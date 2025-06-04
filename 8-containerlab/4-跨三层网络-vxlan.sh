#!/bin/bash

set -v


cat <<EOF> clab.yaml | clab deploy -t clab.yaml -
name: basic-bridge-lab
topology:
  nodes:
    gw1:
        kind: linux
        image: nicolaka/netshoot
        exec:
        - sysctl -w net.ipv4.ip_forward=1
        - ip addr add 192.168.0.100/24 dev gwnet1
        - ip link set gwnet1 up
        - ip addr add 10.0.1.1/24 dev hostnet1
        - ip link set hostnet1 up
        - ip route add 10.0.2.0/24 via 192.168.0.200
        - iptables -t nat -A POSTROUTING -s 10.0.0.0/16 ! -d 10.0.0.0/16 -j MASQUERADE

    host1:
        kind: linux
        image: nicolaka/netshoot
        exec:
        - ip addr add 10.0.1.2/24 dev eth1
        - ip link set eth1 up
        - ip route replace default via 10.0.1.1
    
    gw2:
        kind: linux
        image: nicolaka/netshoot
        exec:
        - sysctl -w net.ipv4.ip_forward=1
        - ip addr add 192.168.0.200/24 dev gwnet1
        - ip link set gwnet1 up
        - ip addr add 10.0.2.1/24 dev hostnet1
        - ip link set hostnet1 up
        - ip route add 10.0.1.0/24 via 192.168.0.100
        - iptables -t nat -A POSTROUTING -s 10.0.0.0/16 ! -d 10.0.0.0/16 -j MASQUERADE

    host2:
        kind: linux
        image: nicolaka/netshoot
        exec:
        - ip addr add 10.0.2.2/24 dev eth1
        - ip link set eth1 up
        - ip route replace default via 10.0.2.1

  links:
     - endpoints: ["gw1:gwnet1", "gw2:gwnet1"]
     - endpoints: ["gw1:hostnet1", "host1:eth1"]
     - endpoints: ["gw2:hostnet1", "host2:eth1"]

EOF