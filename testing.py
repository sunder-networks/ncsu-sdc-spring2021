from scapy.all import *
import time

class INTP(Packet):
    name = "Custom INT Packet"
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
    print("!~! Output !~!")
    # aout.results[0].show()
    if len(aout.results) > 0:
        rxPkt = aout.results[0]
        # import pdb; pdb.Pdb().set_trace()
        print(rxPkt[UDP].decode_payload_as(INTP))
        rxPkt.show()


if __name__=="__main__":
    test()