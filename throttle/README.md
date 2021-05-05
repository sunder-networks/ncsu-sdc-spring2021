# Simple P4 Throttle App

This app demonstrates simple, configurable throttling in P4
using a global running frequency calculation.

# Setup

Before setup, ensure you have docker and make installed.

## Setup docker

`docker-compose up -d`

## Populate tables

`make set-pipeline`

Execute the following in the P4 Runtime Shell:

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

The 'thresh' value determines your target frequency threshold at which to start
dropping packets. This value will depend on the influx of packets you expect
for your target device.

## Testing

The command below will

`docker exec -it throttle_p4switch_1 tail -f /tmp/s1/stratum_bmv2.log`

Start make test to open a scapy session:

`make test`

Then execute something like what is shown below:

>> packet = Ether()/TCP()/IP()

>> sendp(packet, iface='s1-eth1', count=1000)

## Grafana Dashboard

Visit: localhost:3000

Username: admin

Password: admin

Add data Source
- url: http://influxdb:8086
- name: telegraf

Add json config as dashboard
