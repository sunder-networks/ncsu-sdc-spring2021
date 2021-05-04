/* -*- P4_16 -*- */
#include <core.p4>
#include <v1model.p4>

// #define SINK_MODE

/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/

const bit<32> NODE_ID = 0xFACADEDA;
const bit<16> TYPE_IPV4 = 0x0800;
const bit<8>  IP_PROTOCOL_TYPE_UDP = 0x11;
const bit<8>  IP_PROTOCOL_TYPE_TCP = 0x06;
const bit<2>  TYPE_INT = 0x1;
const bit<1>  INT_CONTINUE = 0x1;
const bit<1>  INT_TEMINATE = 0x0;
const bit<8>  INT_REP_NO_LIM = 0xFF;

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
    bit<32>   srcAddr;
    bit<32>   dstAddr;
}

header udp_t {
    bit<16>   srcPort;
    bit<16>   dstPort;
    bit<16>   len;
    bit<16>   cksum;
}

header inth_t {
    bit<2>    version;
    bit<1>    append;
    bit<1>    following;
    bit<8>    availCount;
    bit<2>    rsvd;
    bit<9>    ingressPort;
    bit<9>    egressPort;
    bit<48>   ingressTime;
    bit<48>   egressTime;
    bit<32>   nodeID;
}


struct metadata {
    /* empty */
}

struct headers {
    ethernet_t  ethernet;
    ipv4_t      ipv4;
    udp_t       udp;
    inth_t      inth;
    inth_t      newinth;
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
            default: accept;
        }
    }
    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition select(hdr.ipv4.protocol) {
            IP_PROTOCOL_TYPE_UDP: parse_udp;
            default: accept;
        }
    }
    state parse_udp {
        packet.extract(hdr.udp);
        transition select(hdr.udp.dstPort) {
            default: parse_int;
        }
    }
    state parse_int {
        packet.extract(hdr.inth);
        transition select(hdr.inth.following) {
#ifdef SINK_MODE
            INT_CONTINUE: parse_int;
#endif
            default: accept;
        }
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
        // size = 64;
        const entries = {
            (9w1) : set_output(9w2);
            (9w2) : set_output(9w1);
        }
    }

    action ipv4_forward(egressSpec_t p, bit<48> dmac) {
        standard_metadata.egress_spec = p;
        hdr.ethernet.dstAddr = dmac;
        hdr.ipv4.ttl = hdr.ipv4.ttl - 1 ;
    }

    table ipv4_routing {
        key = {
            hdr.ipv4.dstAddr: lpm;
        }
        actions = {
            ipv4_forward;
            drop;
        }
        size = 1024;
    }

    action create_INT() {
        inth_t i = {TYPE_INT,
                  INT_CONTINUE,
                  INT_TEMINATE, 
                  INT_REP_NO_LIM,
                  0,
                  standard_metadata.ingress_port,
                  standard_metadata.egress_spec,
                  standard_metadata.ingress_global_timestamp,
                  0, 
                  NODE_ID};
        if(hdr.inth.isValid()) {
            i.following = INT_CONTINUE;
            if(hdr.inth.availCount != INT_REP_NO_LIM) {
                i.availCount = hdr.inth.availCount - 1;
            }
        }
        hdr.newinth = i;
    }

    table debug {
        key = {
            hdr.newinth.version: exact;
            hdr.newinth.append: exact;
            hdr.newinth.following: exact;
            hdr.newinth.availCount: exact;
            hdr.newinth.rsvd: exact;
            hdr.newinth.ingressPort: exact;
            hdr.newinth.egressPort: exact;
            hdr.newinth.ingressTime: exact;
            hdr.newinth.nodeID: exact;
        }
        actions = {
        }
        size = 64;
    }
    
    apply {
        my_ports.apply();
        if (hdr.ipv4.isValid()){
            ipv4_routing.apply();
        }
#ifndef SINK_MODE
        if (!hdr.inth.isValid() || (hdr.inth.append == INT_CONTINUE && hdr.inth.availCount != 0)) {
            create_INT();
        }
#endif

        debug.apply();
    }
}

/*************************************************************************
****************  E G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata) {

    action update_INT() {
        hdr.newinth.egressTime = standard_metadata.egress_global_timestamp;
        hdr.newinth.setValid();
    }

    table debug_egress {
        key = {
            hdr.newinth.egressTime: exact;
        }
        actions = {
        }
        size = 64;
    }

    apply { 
#ifndef SINK_MODE
        if (!hdr.inth.isValid() || (hdr.inth.append == INT_CONTINUE && hdr.inth.availCount != 0)) {
            update_INT();
        }
#endif

        debug_egress.apply();      
     }
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
        packet.emit(hdr.udp);
#ifndef SINK_MODE
        packet.emit(hdr.newinth);
        packet.emit(hdr.inth);
#endif
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