# Simple P4 Throttle App

This app demonstrates configurable throttling in P4 which
tracks frequencies on a per-flow basis and drops packets on flows which
exceed their allotted frequency.

This app also drops ICMP packets by default so as to mitigate ICMP flood attacks.

# Setup

Before setup, ensure you have docker and make installed.

Execute the Following (each in a different shell window or screen)

`make build`

`make start`

`make set-pipeline`

## Populate tables

Execute the following in the P4 Runtime Shell

```
te = table_entry["MyIngress.throttle"](action="MyIngress.throttle_packets")

te.match['do_drop']="0"

te.action['p']="2"

te.action['thresh']="10"

te.insert()

```

The 'thresh' value determines your target frequency threshold at which to start
dropping packets. This value will depend on the influx of packets you expect
for your target device. The do_drop match should is set to false to ignore packets that would
have already been dropped (to save computation time).

## Testing

`docker exec -it p4switch tail -f /tmp/s1/stratum_bmv2.log`

The following will open a new scapy testing session:

`make test`

Then execute something similar to what is below to send packets:

>> packet = Ether()/IP()/TCP()

>> sendp(packet, iface='s1-eth1', count=1000)

Or something more fancy:

```
for i in range(1000):
  sendp(packet, iface='s1-eth1', count=10)

```
