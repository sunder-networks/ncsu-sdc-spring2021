# Boilerplate
SHELL := bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c
.DELETE_ON_ERROR:
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules

# Docker images
COMPILER_IMAGE := opennetworking/p4c@sha256:bbc894835ad2057373fca9a5ba92a28c891328a39a88848a35aba44f7f3a7cda
MININET_IMAGE := gcr.io/hotbox-sunos/mn@sha256:f849ad2d24ad6e176e4f0b268163d3ff1198a62c7b18381ddb224fd609585dc4
MININET_DEBUG_IMAGE := gcr.io/hotbox-sunos/mn@sha256:92eb52a35fa7a9e5ab8f2f5c22c59d37de4ec3b235a3c6fc8bfd150dd696121c
SCAPY_IMAGE := ehlers/scapy@sha256:24527af82bde12bcd2fbeffe1ca8859300419d336ed717e41688235e64f14069
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
	   p4c-bm2-ss --arch v1model -o /src/$(@D)/bmv2.json  --p4runtime-files /src/$@ ${P4_SRC}
	@echo "Compiled Successfully!"
	@echo "pipeline data written to: $(@D)"

test: build
	@docker run -it --rm --net=container:p4switch ${SCAPY_IMAGE} scapy
clean:
	@rm -rf build

TARGET_PORT=50001
set-pipeline: build/bmv2/p4info.pb.txt
	@docker run -it --rm -v ${PWD}/build/bmv2:/p4 -w /p4 --net=container:p4switch p4lang/p4runtime-sh --grpc-addr 127.0.0.1:${TARGET_PORT} --device-id 1 --election 0,1 --config /p4/p4info.pb.txt,/p4/bmv2.json

.PHONY: build clean test start
