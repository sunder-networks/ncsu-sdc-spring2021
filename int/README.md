# ncsu-sdc-spring2021
NC State Senior Design Class Spring 2021

### Getting Started
Visual workflow
```
[P4_SRC] -> make build -> PipelineConfig

make start  # remember to navigate to http://localhost:50000 to access switch data like chassis config, and write logs!

New Terminal -> make set-pipeline # Use P4Runtime Shell to set table entries
```

A common workflow in dataplane development begins with source changes `main.p4` , next the source is compiled into a forwarding pipeline config `./build/bmv2/*` in this case. 

The make target `build` can be used to preform this compilation step.
```
~/ncsu-sdc-spring2021/ (main)
$ make build
Compiled Successfully!
pipeline data written to: build/bmv2
~/ncsu-sdc-spring2021/ (main)
$ tree
.
├── LICENSE
├── Makefile
├── README.md
├── build
│   └── bmv2
│       ├── bmv2.json
│       └── p4info.pb.txt
├── main.p4
```


The make target `start` can be used to run stratum_bmv2 switches (software switch dataplanes), and is the primary entrypoint for verification and experiments. 
> Use Ctrl-D to exit
```
~/ncsu-sdc-spring2021/ (main)
$ make start
*** Error setting resource limits. Mininet's performance may be affected.
*** Creating network
*** Adding controller
*** Adding hosts:
h1 h2
*** Adding switches:
s1
*** Adding links:
(h1, s1) (h2, s1)
*** Configuring hosts
h1 h2
*** Starting controller

*** Starting 1 switches
s1 ⚡️ stratum_bmv2 @ 50001

*** Starting CLI:
mininet>
```

A few different types of topologies are possible by default and using the `TOPO` parameter we can drive different topology creations with `make`, the table below enumerates the options and expected values.
| Topology | description |
| --- | --- |
| single | single switch topology with 2 hosts connected (DEFAULT)
| linear,3,2 | straight line of 3 switches with 2 hosts per switch
| tree,2,3 | single root tree with 2 layers of depth and 3 wide fanout, i.e. root switch connects to 3 switches which each have 3 hosts

```
~/ncsu-sdc-spring2021/ (main)
$ make start TOPO=tree,2,3
*** Error setting resource limits. Mininet's performance may be affected.
*** Creating network
*** Adding controller
*** Adding hosts:
h1 h2 h3 h4 h5 h6 h7 h8 h9
*** Adding switches:
s1 s2 s3 s4
*** Adding links:
(s1, s2) (s1, s3) (s1, s4) (s2, h1) (s2, h2) (s2, h3) (s3, h4) (s3, h5) (s3, h6) (s4, h7) (s4, h8) (s4, h9)
*** Configuring hosts
h1 h2 h3 h4 h5 h6 h7 h8 h9
*** Starting controller

*** Starting 4 switches
s1 ⚡️ stratum_bmv2 @ 50001
s2 ⚡️ stratum_bmv2 @ 50002
s3 ⚡️ stratum_bmv2 @ 50003
s4 ⚡️ stratum_bmv2 @ 50004

*** Starting CLI:
mininet>
*** Stopping 0 controllers

*** Stopping 12 links
............
*** Stopping 4 switches
s1 s2 s3 s4
*** Stopping 9 hosts
h1 h2 h3 h4 h5 h6 h7 h8 h9
*** Done
completed in 91.880 seconds
~/ncsu-sdc-spring2021/ (main)
$ make start TOPO=tree,2,2
*** Error setting resource limits. Mininet's performance may be affected.
*** Creating network
*** Adding controller
*** Adding hosts:
h1 h2 h3 h4
*** Adding switches:
s1 s2 s3
*** Adding links:
(s1, s2) (s1, s3) (s2, h1) (s2, h2) (s3, h3) (s3, h4)
*** Configuring hosts
h1 h2 h3 h4
*** Starting controller

*** Starting 3 switches
s1 ⚡️ stratum_bmv2 @ 50001
s2 ⚡️ stratum_bmv2 @ 50002
s3 ⚡️ stratum_bmv2 @ 50003

*** Starting CLI:
mininet>
```

Setting the pipeline will drop you into the p4runtime-sh
```
~/ncsu-sdc-spring2021/ (main)
$ make set-pipeline
*** Welcome to the IPython shell for P4Runtime ***
P4Runtime sh >>> tables
MyIngress.my_ports

P4Runtime sh >>> actions
MyIngress.drop
MyIngress.set_output
NoAction

P4Runtime sh >>> te = table_entry["MyIngress.my_ports"](action="MyIngress.set_output")

P4Runtime sh >>> te.match['ingress_port']="1"
field_id: 1
exact {
  value: "\000\001"
}


P4Runtime sh >>> te.action['p']="2"
param_id: 1
value: "\000\002"


P4Runtime sh >>> te.insert()

P4Runtime sh >>> # if match source port of 1 send to port 2

P4Runtime sh >>> # now insert the reverse rule
```

#### More details and references
The [ForwardingPipelineConfig](https://github.com/p4lang/p4runtime/blob/v1.3.0/proto/p4/v1/p4runtime.proto#L696) message has two fields of interest, p4info and p4_device_config, these fields map to the artifacts `./build/bmv2/p4info.pb.txt` and `./build/bmv2/bmv2.json` respectively. The linked protobuf source code is distributed as part of the open source P4Runtime specification and service definition protobuf files to learn more please check out the documentation available on p4.org/specs .


### Resources
Have this cheatsheet open while coding , reference for p4 syntax https://github.com/p4lang/tutorials/blob/master/p4-cheat-sheet.pdf

