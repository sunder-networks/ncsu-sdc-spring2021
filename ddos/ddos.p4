/* -*- P4_16 -*- */
#include <core.p4>
#include <v1model.p4>

#define FREQ_DROP_THRESHOLD 100

/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/

const bit<16> TYPE_IPV4 = 0x0800;
const bit<16> TYPE_IPV6 = 0x86DD;
const bit<16> TYPE_FEED = 0xFEED;

typedef bit<9>  egressSpec_t;

header ethernet_t {
    bit<48>   dstAddr;
    bit<48>   srcAddr;
    bit<16>   etherType;
}

header ipv4_t {
    bit<4>    version;
    bit<4>    ihl;
    bit<8>    diffserv;
    bit<16>   totalLen;
    bit<16>   identification;
    bit<3>    flags;
    bit<13>   fragOffset;
    bit<8>    ttl;
    bit<8>    protocol;
    bit<16>   hdrChecksum;
    bit<32> srcAddr;
    bit<32> dstAddr;
}

header instrinsic_metadata_t {
    bit<48> ingress_global_timestamp;
    bit<48> egress_global_timestamp;
    bit<16> mcast_grp;
    bit<16> egress_rid;
}

header throttle_t {
    bit<48> running_freq;
    bit<8> do_drop;
}

/*************************************************************************
*********************** S T R U C T S  ***********************************
*************************************************************************/

struct freq_entry {
    bit<32> srcAddr;
    bit<32> dstAddr;
    bit<32> freq;
    bit<48> ingress_time;
}

struct metadata {
    instrinsic_metadata_t instrinsic_metadata;
}

struct headers {
    ethernet_t   ethernet;
    ipv4_t   ipv4;
    throttle_t throttle;
}

/*************************************************************************
*********************** R E G I S T E R S  *******************************
*************************************************************************/


/*************************************************************************
*********************** P A R S E R  ***********************************
*************************************************************************/

parser MyParser(packet_in packet,
                out headers hdr,
                inout metadata meta,
                inout standard_metadata_t standard_metadata) {

    state start {
        transition parse_ethernet;
    }

    state parse_ethernet {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            TYPE_IPV4: parse_ipv4;
            // TYPE_IPV6: parse_ipv6;
            default: accept;
        }
    }
    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition accept;
    }

}

/*************************************************************************
************   C H E C K S U M    V E R I F I C A T I O N   *************
*************************************************************************/

control MyVerifyChecksum(inout headers hdr, inout metadata meta) {
    apply {  }
}

/*************************************************************************
**************  I N G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyIngress(inout headers hdr,
                  inout metadata meta,
                  inout standard_metadata_t standard_metadata) {

    register<bit<48>>(1) global_freq_r;
    register<bit<48>>(1) last_time_r;

    action drop() {
        mark_to_drop(standard_metadata);
    }

    action set_output(egressSpec_t p) {
        standard_metadata.egress_spec = p;
    }

    table my_ports {
        key = {
            standard_metadata.ingress_port: exact;
        }
        actions = {
            set_output;
            drop;
        }
        size = 64;
    }


    /*
        Work In Progress - there are elements of this that don't work yet!

        Updates global frequency and time values for ALL incoming packets and drops packets
            while frequency is above predefined threshold

        This is a proof of concept for a more robust throttling and eventually DDOS
            detection algorithm.
    */
    action throttle_packets(egressSpec_t p, bit<48> dmac) {

        // Standard forwarding
        standard_metadata.egress_spec = p;
        hdr.ethernet.dstAddr = dmac;
        hdr.ipv4.ttl = hdr.ipv4.ttl - 1;

        // read timestamp off header
        bit<48> current_time = standard_metadata.ingress_global_timestamp;

        // read global register values
        bit<48> global_freq;
        bit<48> last_time;
        bit<48> time_diff;

        global_freq_r.read(global_freq, 0);
        last_time_r.read(last_time, 0);

        // update running frequency and time registers
        time_diff = (current_time - last_time);
        global_freq = (global_freq + 1);

        if(time_diff < 10){
            global_freq = global_freq * 2;
        } else if(time_diff < 100) {
            global_freq = global_freq / 2;
        } else if(time_diff < 1000) {
            global_freq = global_freq / 4;
        } else if(time_diff < 10000) {
            global_freq = global_freq / 8;
        } else if(time_diff < 100000) {
            global_freq = global_freq / 16;
        }

        global_freq_r.write((bit<32>) global_freq, 0);
        last_time_r.write((bit<32>)last_time, 0);

        // check if new frequency value is beyond threshold
        if(global_freq > FREQ_DROP_THRESHOLD){
            // if above threshold, mark packet for drop
            hdr.throttle.do_drop = 1;
        }

    }

    table throttle {
        key = {
            hdr.ipv4.srcAddr: lpm;
        }
        actions = {
            throttle_packets;
        }
        size = 1024;
    }

    table debug {
        key = {
            hdr.ipv4.srcAddr: exact;
            hdr.throttle.running_freq: exact;
            hdr.throttle.do_drop: exact;
        }
        actions = {
            drop;
        }
        size = 64;
    }

    apply {
        my_ports.apply();
        if (hdr.ipv4.isValid()){
            throttle.apply();
        }
        debug.apply();
    }
}

/*************************************************************************
****************  E G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata) {
    /*
       The egress_port of a packet MUST be selected during INGRESS processing,
       and egress processing is NOT allowed to change it.

        https://p4.org/p4-spec/docs/PSA-v1.1.0.html#appendix-rationale-egress
    */
    apply {  }
}

/*************************************************************************
*************   C H E C K S U M    C O M P U T A T I O N   **************
*************************************************************************/

control MyComputeChecksum(inout headers hdr, inout metadata meta) {
     apply { }
}


/*************************************************************************
***********************  D E P A R S E R  *******************************
*************************************************************************/

control MyDeparser(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.ipv4);
    }
}

/*************************************************************************
***********************  S W I T C H  *******************************
*************************************************************************/

V1Switch(
MyParser(),
MyVerifyChecksum(),
MyIngress(),
MyEgress(),
MyComputeChecksum(),
MyDeparser()
) main;
