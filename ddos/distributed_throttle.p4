/* -*- P4_16 -*- */
#include <core.p4>
#include <v1model.p4>

// allows us to use variable registers
#define V1MODEL_VERSION 20200408

// default threshold at which to start dropping packets
#define FREQ_DROP_THRESHOLD 10000

#define NUM_CELLS 100

#define BLOOM_FILTER_ENTRIES 4096
#define BLOOM_FILTER_BIT_WIDTH 48


/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/

const bit<16> TYPE_IPV4 = 0x0800;
const bit<16> TYPE_IPV6 = 0x86DD;
const bit<16> TYPE_FEED = 0xFEED;
const bit<8>  TYPE_TCP  = 6;
const bit<8>  TYPE_UDP  = 17;

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

header tcp_t{
    bit<16> srcPort;
    bit<16> dstPort;
    bit<32> seqNo;
    bit<32> ackNo;
    bit<4>  dataOffset;
    bit<4>  res;
    bit<1>  cwr;
    bit<1>  ece;
    bit<1>  urg;
    bit<1>  ack;
    bit<1>  psh;
    bit<1>  rst;
    bit<1>  syn;
    bit<1>  fin;
    bit<16> window;
    bit<16> checksum;
    bit<16> urgentPtr;
}

header udp_t {
    bit<16> sport;
    bit<16> dport;
    bit<16> len;
    bit<16> checksum;
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
    bit<8> do_drop;
    bit<48> freq;
    bit<48> last_diff;

    bit<32> register_position_one;
    bit<32> register_position_two;
    bit<48> register_count_one;
    bit<48> register_count_two;
    bit<48> register_freq_one;
    bit<48> register_freq_two;
    bit<48> register_time_one;
    bit<48> register_time_two;

    bit<48> flow_freq;
    bit<48> flow_time;
    bit<8> entry_exists;
}

struct headers {
    ethernet_t   ethernet;
    ipv4_t   ipv4;
    tcp_t   tcp;
    udp_t   udp;
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
        transition select(hdr.ipv4.protocol) {
            TYPE_TCP: parse_tcp;
            TYPE_UDP: parse_udp;
            default: accept;
        }
    }

    state parse_tcp {
        packet.extract(hdr.tcp);
        transition accept;
    }
    state parse_udp {
        packet.extract(hdr.udp);
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

    // Elements that make up our Invertible Bloom Lookup Table (IBLT)
    register<bit<BLOOM_FILTER_BIT_WIDTH>>(BLOOM_FILTER_ENTRIES) bloom_count;
    register<bit<BLOOM_FILTER_BIT_WIDTH>>(BLOOM_FILTER_ENTRIES) bloom_freq;
    register<bit<BLOOM_FILTER_BIT_WIDTH>>(BLOOM_FILTER_ENTRIES) bloom_time;

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

    action find_slot(){

    }

    // gets stored frequency data about the current packet's flow
    action get_flow_info(){
        // First hash of bloom filter using crc16
        hash(meta.register_position_one, HashAlgorithm.crc16, (bit<48>)0, {hdr.ipv4.srcAddr,
                                                     hdr.ipv4.dstAddr,
                                                     hdr.tcp.srcPort,
                                                     hdr.tcp.dstPort,
                                                     hdr.ipv4.protocol},
                                                     (bit<48>)BLOOM_FILTER_ENTRIES);
        // Second hash of bloom filter using crc32
        hash(meta.register_position_two, HashAlgorithm.crc32, (bit<48>)0, {hdr.ipv4.srcAddr,
                                                     hdr.ipv4.dstAddr,
                                                     hdr.tcp.srcPort,
                                                     hdr.tcp.dstPort,
                                                     hdr.ipv4.protocol},
                                                     (bit<48>)BLOOM_FILTER_ENTRIES);

       // read all bloom filter values into metadata
       bloom_count.read(meta.register_count_one, meta.register_position_one);
       bloom_count.read(meta.register_count_two, meta.register_position_two);
       // read time differences
       bloom_time.read(meta.register_time_one, meta.register_position_one);
       bloom_time.read(meta.register_time_two, meta.register_position_two);
       // read running frequencies
       bloom_freq.read(meta.register_freq_one, meta.register_position_one);
       bloom_freq.read(meta.register_freq_two, meta.register_position_two);

       // pre-set values
       meta.entry_exists = 1;
       meta.flow_time = 0;
       meta.flow_freq = 0;

       // At least one entry must have a count of 1 to give us valid data
       if(meta.register_count_one == 0 || meta.register_count_two == 0){
           meta.entry_exists = 0;
       }
       else if(meta.register_count_one == 1){
           meta.flow_time = meta.register_time_one;
           meta.flow_freq = meta.register_freq_one;
       }
       else if(meta.register_count_two == 1){
           meta.flow_time = meta.register_time_two;
           meta.flow_freq = meta.register_freq_two;
       }

       // temporarily remove the entries (to be added back in the update)
      bloom_count.write(meta.register_position_one, meta.register_count_one - (bit<48>) meta.entry_exists);
      bloom_count.write(meta.register_position_two, meta.register_count_two - (bit<48>) meta.entry_exists);

      meta.register_time_one = meta.register_time_one - meta.flow_time;
      meta.register_time_two = meta.register_time_two - meta.flow_time;

      meta.register_freq_one = meta.register_freq_one - meta.flow_freq;
      meta.register_freq_two = meta.register_freq_two - meta.flow_freq;

      // now, we mark that the entry exists (whether it was new or not, so that we can see if it is valid in later steps)
      meta.entry_exists = 1;
      if(meta.register_count_one > 1 && meta.register_count_two > 1){
          // if both slots were filled, we should make a note that these registers are not valid
          // the entry_exists flag gets repurposed as a valid indicator
          meta.entry_exists = 0;
      }

      // If either of them are a valid hit, set them to zero so that the dec is cancelled out
      if(meta.register_count_one == 1){
          meta.register_count_one = 0;
      }
      if(meta.register_count_two == 1){
          meta.register_count_two = 0;
      }

    }

    action update_flow_info(){

        // First hash of bloom filter using crc16 - hash the flow's 5-tuple
        hash(meta.register_position_one, HashAlgorithm.crc16, (bit<48>)0, {hdr.ipv4.srcAddr,
                                                     hdr.ipv4.dstAddr,
                                                     hdr.tcp.srcPort,
                                                     hdr.tcp.dstPort,
                                                     hdr.ipv4.protocol},
                                                     (bit<48>)BLOOM_FILTER_ENTRIES);
        // Second hash of bloom filter using crc32 - hash the flow's 5-tuple
        hash(meta.register_position_two, HashAlgorithm.crc32, (bit<48>)0, {hdr.ipv4.srcAddr,
                                                     hdr.ipv4.dstAddr,
                                                     hdr.tcp.srcPort,
                                                     hdr.tcp.dstPort,
                                                     hdr.ipv4.protocol},
                                                     (bit<48>)BLOOM_FILTER_ENTRIES);

       // Whether its new or not, we always need to add back the entry, so this is valid!
       bloom_count.write(meta.register_position_one, meta.register_count_one + (bit<48>)meta.entry_exists);
       bloom_count.write(meta.register_position_two, meta.register_count_two + (bit<48>)meta.entry_exists);

       bloom_time.write(meta.register_position_one, meta.register_time_one + meta.flow_time);
       bloom_time.write(meta.register_position_two, meta.register_time_two + meta.flow_time);

       bloom_freq.write(meta.register_position_one, meta.register_freq_one + meta.flow_freq);
       bloom_freq.write(meta.register_position_two, meta.register_freq_two + meta.flow_freq);
    }

    /*
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
        global_freq = meta.flow_freq;
        last_time = meta.flow_time;
        old_freq = meta.flow_freq;
        old_time = meta.flow_time;

        // update running frequency and time registers
        time_diff = (current_time - last_time);
        global_freq = (global_freq + 2);

        // Approximation of division based on time difference
        // TODO - improve this to be more adaptive so as to prevent runaway situations
        if(time_diff < 100){
            global_freq = global_freq << 1;
        } else if(time_diff < 1000){
          //no-op
        } else if(time_diff < 10000) {
            global_freq = global_freq >> 1;
        } else if(time_diff < 100000) {
            global_freq = global_freq >> 2;
        } else if(time_diff < 1000000) {
            global_freq = global_freq >> 3;
        } else if(time_diff < 10000000) {
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
        meta.flow_freq = global_freq;
        meta.flow_time = current_time;

    }

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

    table drop_table {
        key = {
            meta.do_drop: exact;
        }
        actions = {
            drop;
        }
        const entries = {
            (8w1): drop();
        }
    }

    table debug {
        key = {
            meta.do_drop: exact;
            meta.last_diff: exact;
            meta.flow_time: exact;
            meta.freq: exact;
            meta.flow_freq: exact;
            meta.register_position_one: exact;
            meta.register_position_two: exact;
            meta.register_count_one: exact;
            meta.register_count_two: exact;
            meta.register_time_one: exact;
            meta.register_time_two: exact;
            meta.register_freq_one: exact;
            meta.register_freq_two: exact;
            meta.entry_exists: exact;
            hdr.ipv4.srcAddr: exact;
        }
        actions = {
            drop;
        }
        size = 64;
    }

    apply {
        my_ports.apply();
        if (hdr.ipv4.isValid()){
             get_flow_info();
             throttle.apply();
             update_flow_info();
             drop_table.apply();
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
