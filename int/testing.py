from scapy.all import *
import time

class INTP(Packet):
    name = "\u001b[100mCustom INT Header\u001b[40m"
    fields_desc = [
        BitField("version", 0, 2),
        BitField("append", 0, 1),
        BitField("following", 0, 1),
        BitField("available count", 0, 8),
        BitField("reserved", 0, 2),
        BitField("ingress port", 0, 9),
        BitField("egress port", 0, 9),
        BitField("ingress time", 0, 48),
        BitField("egress time", 0, 48),
        BitField("node ID", 0, 32),
    ]

    def guess_payload_class(self, payload):
        return INTP

def test():
    ain = AsyncSniffer(iface="s1-eth1")
    aout = AsyncSniffer(iface="s1-eth2")
    ain.start()
    aout.start()
    sendp(Ether()/IP()/UDP(), iface="s1-eth1")
    
    # To stop the sniffer and show summary
    time.sleep(1)
    ain.stop()
    aout.stop()
    print("!~! Input !~!")
    ain.results[0].show()
    print("!~! Source Output !~!")
    rxPkt = aout.results[0]
    if len(aout.results) > 0:
        rxPkt[UDP].decode_payload_as(INTP)
        print("\u001b[36m")
        rxPkt.show()
        print("\u001b[0m")
    wrpcap("int1.cap", rxPkt)

    aout2 = AsyncSniffer(iface="s1-eth2")
    aout2.start()
    sendp(rxPkt, iface="s1-eth1")
    
    # To stop the sniffer and show summary
    time.sleep(1)
    aout2.stop()
    print("!~! Transit Output !~!")
    if len(aout.results) > 0:
        rxPkt = aout2.results[0]
        rxPkt[UDP].decode_payload_as(INTP)
        rxPkt[INTP].decode_payload_as(INTP)
        print("\u001b[95m")
        rxPkt.show()
        print("\u001b[0m")
        wrpcap("int2.cap", rxPkt)

def test2():
    aout = AsyncSniffer(iface="s1-eth2")
    int2 = rdpcap("int2.cap")

    aout.start()
    sendp(int2, iface="s1-eth1")
    time.sleep(1)
    aout.stop()
    aout.results[0].show()



if __name__=="__main__":
    test()
    # test2()
