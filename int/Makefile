# Boilerplate 
SHELL := bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c
.DELETE_ON_ERROR:
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules

# Docker images
COMPILER_IMAGE := p4lang/p4c@sha256:0d71bf89866409148ce06ee90eb1630547ade68fffa62d1af626d33b9f64bebe
MININET_IMAGE := gcr.io/hotbox-sunos/mn@sha256:1ba5430f6fdfcf8e45893b4dd30e3757e68c8d3e242b5214833abc62d40dcbd4
MININET_DEBUG_IMAGE := gcr.io/hotbox-sunos/mn@sha256:f04cd7eb7ca1e5e6928261c7589a820d076cde2352a82e74cbf848758962c244
SCAPY_IMAGE := gcr.io/hotbox-sunos/scapy@sha256:c501873575bac0049a42b02496e760318404ea31821d663cea210035d3d590b3
# Source helper
P4_SRC := $(wildcard *.p4)

# USER VARIABLES ***************
TOPO = single
# possible values are 
#   single
#   linear,#Switches,#hosts
#   tree,#Switches,#hosts
LOG = debug
# possible values are
#   debug
#   warn
# USER VARIABLES ***************

start: clean build
	@docker rm -f  p4switch 2>/dev/null || true
ifeq ($(LOG),debug)
	@echo "running switch in debug mode"
	@exec docker run -it  -p 50000-50030:50000-50030 --rm --privileged --name p4switch ${MININET_DEBUG_IMAGE} --topo ${TOPO}
else
	@exec docker run -it  -p 50000-50030:50000-50030 --rm --privileged --name p4switch ${MININET_IMAGE} --topo ${TOPO}
endif


build: build/bmv2/p4info.pb.txt
build/bmv2/p4info.pb.txt: $(P4_SRC)
	@[ -d build/bmv2 ] || mkdir -p build/bmv2
	docker run -it --rm -w /src -v ${PWD}:/src \
	   ${COMPILER_IMAGE} \
	   p4c-bm2-ss --arch v1model -o /src/$(@D)/bmv2.json --p4runtime-files /src/$@ ${P4_SRC}
	@echo "Compiled Successfully!"
	@echo "pipeline data written to: $(@D)"

test: build
	@docker run -it -v ${PWD}:/src -w /src --rm --net=container:p4switch ${SCAPY_IMAGE} bash
clean:
	@rm -rf build

TARGET_PORT=50001
set-pipeline: build/bmv2/p4info.pb.txt
	@docker run -it --rm -v ${PWD}/build/bmv2:/p4 -w /p4 --net=container:p4switch p4lang/p4runtime-sh --grpc-addr 127.0.0.1:${TARGET_PORT} --device-id 1 --election 0,1 --config /p4/p4info.pb.txt,/p4/bmv2.json

.PHONY: build clean test start