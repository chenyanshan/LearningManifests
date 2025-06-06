#!/bin/bash
set -v
cat <<EOF> clab.yaml | clab deploy -t clab.yaml -
name: basic-bridge-lab1
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
        - ip link add vxlan100 type vxlan id 100 dev eth1 remote 10.0.2.2 dstport 4789
        - ip link set dev vxlan100 up
        - brctl addbr vxlan_br
        - ip link set dev vxlan_br up
        - ip addr add 172.16.0.1/24 dev vxlan_br
        - brctl addif vxlan_br eth_to_br0
        - brctl addif vxlan_br vxlan100
        - ip link set dev eth_to_br0 up
    pod1:
        kind: linux
        image: nicolaka/netshoot
        exec:
        - ip addr add 172.16.0.3/24 dev eth1
        - ip link set eth1 up
        - ip route replace default via 172.16.0.1
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
        - ip link add vxlan100 type vxlan id 100 dev eth1 remote 10.0.1.2 dstport 4789
        - ip link set dev vxlan100 up
        - brctl addbr vxlan_br
        - ip link set dev vxlan_br up
        - ip addr add 172.16.0.2/24 dev vxlan_br
        - brctl addif vxlan_br eth_to_br0
        - brctl addif vxlan_br vxlan100
        - ip link set dev eth_to_br0 up
    pod2:
        kind: linux
        image: nicolaka/netshoot
        exec:
        - ip addr add 172.16.0.4/24 dev eth1
        - ip link set eth1 up
        - ip route replace default via 172.16.0.2
  links:
     - endpoints: ["gw1:gwnet1", "gw2:gwnet1"]
     - endpoints: ["gw1:hostnet1", "host1:eth1"]
     - endpoints: ["gw2:hostnet1", "host2:eth1"]
     - endpoints: ["host1:eth_to_br0", "pod1:eth1"]
     - endpoints: ["host2:eth_to_br0", "pod2:eth1"]
EOF

# 步骤 2: 清理任何先前的同名部署并部署新的拓扑
echo "--- Destroying any existing lab: simple-vxlan-lab ---"
sudo clab destroy -t clab.yaml --cleanup
echo "--- Deploying lab: simple-vxlan-lab ---"
sudo clab deploy -t clab.yaml