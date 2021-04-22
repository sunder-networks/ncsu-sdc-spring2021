## Populate tables

Execute the following in the P4 Runtime Shell

```
te = table_entry["MyIngress.throttle"](action="MyIngress.throttle_packets")

te.match['do_drop']="0"

te.action['p']="2"

te.action['thresh']="10"

te.insert()

te = table_entry["MyIngress.drop_table"](action="MyIngress.drop")

te.match['do_drop']="1"

te.insert()
```

## Testing

`docker exec -it p4switch tail -f /tmp/s1/stratum_bmv2.log`

`make test`

>> packet = Ether()/IP()/TCP()

>> sendp(packet, iface='s1-eth1', count=1000)
