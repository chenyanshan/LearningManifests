#!/bin/bash

set -v

brctl addbr br0
#ifconfig br0 up
ip link set br0 up

cat <<EOF> clab.yaml | clab deploy -t clab.yaml -
name: basic-bridge-lab
topology:
  nodes:
    br0:
        kind: bridge

    host1:
        kind: linux
        image: nicolaka/netshoot
        exec:
        - ip addr add 192.168.1.2/24 dev eth1 # 给接口 eth0 配 IP (与 router 的 eth1 同网段)
        - ip link set eth1 up                 # 启动接口 eth0

    host2:
        kind: linux
        image: nicolaka/netshoot
        exec:
        - ip addr add 192.168.1.3/24 dev eth1 # 给接口 eth0 配 IP (与 router 的 eth1 同网段)
        - ip link set eth1 up                 # 启动接口 eth0

  links:
     - endpoints: ["br0:eth1", "host1:eth1"]
     - endpoints: ["br0:eth2", "host2:eth1"]

EOF