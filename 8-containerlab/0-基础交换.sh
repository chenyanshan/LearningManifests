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
        network-mode: none
        exec:
        - ip addr add 10.0.0.10/24 dev eth1 
        - ip link set eth1 up
        - ip route add default via 10.0.0.1 dev eth1

    host2:
        kind: linux
        # 使用一个完整的 Ubuntu 镜像
        image: nicolaka/netshoot
        network-mode: none
        exec:
        - ip addr add 10.0.0.11/24 dev eth1 
        - ip link set eth1 up
        - ip route add default via 10.0.0.1 dev eth1
        - echo "nameserver 223.5.5.5" > /etc/resolv.conf
        - ping -c 1 www.baidu.com
        - apk add nginx
        - nginx

  links:
     - endpoints: ["br0:eth1", "host1:eth1"]
     - endpoints: ["br0:eth2", "host2:eth1"]

EOF

sudo clab destroy -t clab.yaml --cleanup

sudo clab deploy -t clab.yaml

ip addr add 10.0.0.1/24 dev br0
sysctl -w net.ipv4.ip_forward=1
iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -j MASQUERADE

