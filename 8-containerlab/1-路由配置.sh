#!/bin/bash

set -v


cat <<EOF> clab.yaml | clab deploy -t clab.yaml -
name: basic-bridge-lab
topology:
  nodes:
    gw0:
        kind: linux
        image: nicolaka/netshoot
        exec:
        - sysctl -w net.ipv4.ip_forward=1
        - ip addr add 192.168.1.1/24 dev eth1
        - ip link set eth1 up                 # 启动接口 eth0
        - ip addr add 192.168.2.1/24 dev eth2
        - ip link set eth2 up                 # 启动接口 eth0
        # 出去外部设置。
        - iptables -t nat -A POSTROUTING -s 192.168.0.0/16 -j MASQUERADE

    host1:
        kind: linux
        image: nicolaka/netshoot
        exec:
        - ip addr add 192.168.1.2/24 dev eth1 # 给接口 eth0 配 IP (与 router 的 eth1 同网段)
        - ip link set eth1 up                 # 启动接口 eth0
        - ip route replace default via 192.168.1.1

    host2:
        kind: linux
        image: nicolaka/netshoot
        exec:
        - ip addr add 192.168.2.2/24 dev eth1 # 给接口 eth0 配 IP (与 router 的 eth1 同网段)
        - ip link set eth1 up                 # 启动接口 eth0
        - ip route replace default via 192.168.2.1

  links:
     - endpoints: ["gw0:eth1", "host1:eth1"]
     - endpoints: ["gw0:eth2", "host2:eth1"]

EOF