/* -*- P4_16 -*- */
#include <core.p4>
#include <v1model.p4>

/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/

const bit<32> NODE_ID = 0xA5;
const bit<16> TYPE_IPV4 = 0x0800;
const bit<2>  TYPE_INT = 0x1;
const bit<1>  INT_LIST = 0x0;
const bit<1>  INT_TEMINATE = 0x1;

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

header inth_t {
    bit<2>    version;
    bit<1>    append;
    bit<1>    following;
    bit<4>    availCount;
    bit<6>    rsvd;
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
    inth_t      inth;
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
                  INT_TEMINATE,
                  INT_TEMINATE, 
                  0,
                  0,
                  standard_metadata.ingress_port,
                  standard_metadata.egress_port,
                  standard_metadata.ingress_global_timestamp,
                  0, 
                  NODE_ID};
        hdr.inth = i;
    }
    
    apply {
        my_ports.apply();
        if (hdr.ipv4.isValid()){
            ipv4_routing.apply();
        }
        create_INT();
    }
}

/*************************************************************************
****************  E G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata) {

    action update_INT() {
        hdr.inth.egressTime = standard_metadata.egress_global_timestamp;
    }

    apply { 
        update_INT();        
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
        packet.emit(hdr.inth);
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