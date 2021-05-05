/* -*- P4_16 -*- */
#include <core.p4>
#include <v1model.p4>

#define FREQ_DROP_THRESHOLD 100

/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/

const bit<16> TYPE_IPV4 = 0x0800;
const bit<16> TYPE_IPV6 = 0x86DD;

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

/*************************************************************************
*********************** S T R U C T S  ***********************************
*************************************************************************/

struct metadata {
    bit<8> do_drop;
    bit<48> freq;
    bit<48> last_diff;
}

struct headers {
    ethernet_t   ethernet;
    ipv4_t   ipv4;
}

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

    register<bit<48>>(64) global_freq_r;
    register<bit<48>>(64) last_time_r;

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
    action throttle_packets(egressSpec_t p, bit<48> thresh) {

        // Standard forwarding
        standard_metadata.egress_spec = p;
        hdr.ipv4.ttl = hdr.ipv4.ttl - 1;

        // read timestamp off header
        bit<48> current_time = standard_metadata.ingress_global_timestamp;

        // temp scope variables
        bit<48> global_freq;
        bit<48> last_time;
        bit<48> time_diff;
        // keep track of old global state in case we need to revert
        bit<48> old_time;
        bit<48> old_freq;

        // Read state from registers
        global_freq_r.read(global_freq, 0);
        last_time_r.read(last_time, 0);
        global_freq_r.read(old_freq, 0);
        last_time_r.read(old_time, 0);

        // update running frequency and time registers
        time_diff = (current_time - last_time);
        global_freq = (global_freq + 2);

        // Approximation of division based on time difference
        if(time_diff < 100){
            global_freq = global_freq << 1;
        } else if(time_diff < 1000){
          global_freq = (global_freq + 1);
        } else if(time_diff < 100000) {
            global_freq = global_freq >> 1;
        } else if(time_diff < 1000000) {
            global_freq = global_freq >> 2;
        } else if(time_diff < 10000000) {
            global_freq = global_freq >> 3;
        } else if(time_diff < 100000000) {
            global_freq = global_freq >> 4;
        } else {
            global_freq = global_freq >> 5;
        }

        // Values are added to metadata for debug purposes
        meta.last_diff = time_diff;
        meta.freq = global_freq;

        // check if new frequency value is beyond threshold
        if(global_freq >= thresh){
            // if at or above threshold, mark packet for drop
            meta.do_drop = 1;

            // if throttling has occurred, do not persist working state (use old values instead)
            global_freq = old_freq;
            current_time = old_time;
        }

        // Persist state in registers
        global_freq_r.write(0, global_freq);
        last_time_r.write(0, current_time);

    }

    // Table to hold throttle configuration with threshold value
    // Could be extended to set different threshold frequencies based on packet values
    table throttle {
        key = {
            meta.do_drop: exact;
        }
        actions = {
            throttle_packets;
        }
        default_action = throttle_packets(2,1000);
        size = 1024;
    }

    // Simple table: if a packet do_drop metadata = 1 => drop it!
    // Could be extended to let by certain types of packets (high priority?)
    table drop_table {
        key = {
            meta.do_drop: exact;
        }
        actions = {
            drop;
        }
    }

    // Table used to print useful debug values - feel free to remove for production
    table debug {
        key = {
            meta.do_drop: exact;
            meta.last_diff: exact;
            meta.freq: exact;
            hdr.ipv4.srcAddr: exact;
        }
        actions = {
            drop;
        }
        size = 64;
    }

    apply {
        my_ports.apply();
        throttle.apply();
        drop_table.apply();
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
