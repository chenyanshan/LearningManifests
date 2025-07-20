#!/bin/bash
set -v

# apt install wireguard-tools

wg_peerA_private_key=`wg genkey`
wg_peerB_private_key=`wg genkey`

cat <<EOF> clab.yaml
name: wireguard-demo
mgmt:
  ipv4-subnet: 172.100.100.0/24

topology:
  nodes:
    gw1:
        kind: linux
        image: nicolaka/netshoot
        exec:
        - sysctl -w net.ipv6.conf.all.disable_ipv6=1
        - sysctl -w net.ipv6.conf.default.disable_ipv6=1
        - sysctl -w net.ipv6.conf.lo.disable_ipv6=1
        - sysctl -w net.ipv4.ip_forward=1
        - ip addr add 192.168.0.100/24 dev eth1
        - ip link set eth1 up
        - ip addr add 10.0.1.1/24 dev eth2
        - ip link set eth2 up
        - ip route add 10.0.2.0/24 via 192.168.0.200
        - iptables -t nat -A POSTROUTING -s 10.0.0.0/16 ! -d 10.0.0.0/16 -j MASQUERADE

    host1:
        kind: linux
        image: nicolaka/netshoot
        network-mode: none
        exec:
        - sysctl -w net.ipv6.conf.all.disable_ipv6=1
        - sysctl -w net.ipv6.conf.default.disable_ipv6=1
        - sysctl -w net.ipv6.conf.lo.disable_ipv6=1
        - sysctl -w net.ipv4.ip_forward=1
        - ip addr add 10.0.1.2/24 dev eth1
        - ip link set eth1 up
        - ip route replace default via 10.0.1.1 dev eth1

        - echo ${wg_peerA_private_key} > privatre
        - ip link add dev gw0 type wireguard
        - ip addr add 172.16.1.0/32 dev gw0
        - wg set wg0 private-key ./private
        - ip link set wg0 up
        - wg set gw0 peer ${wg_peerB_private_key} allowed-ips 172.16.2.0/24 endpoint 10.0.2.2:51820

        - brctl add cni0
        - ip addr add 172.16.1.1/24 dev gw0
        - brctl addif cni0 up
        - brctl addif cni0 pod1_veth_piar
        - ip link set dev pod1_veth_piar up

    pod1:
        kind: linux
        image: nicolaka/netshoot
        network-mode: none
        exec:
        - sysctl -w net.ipv6.conf.all.disable_ipv6=1
        - sysctl -w net.ipv6.conf.default.disable_ipv6=1
        - sysctl -w net.ipv6.conf.lo.disable_ipv6=1
        - ip addr add 172.16.1.2/24 dev eth1
        - ip link set eth1 up
        - ip route replace default via 172.16.1.1 dev eth1

    gw2:
        kind: linux
        image: nicolaka/netshoot
        exec:
        - sysctl -w net.ipv6.conf.all.disable_ipv6=1
        - sysctl -w net.ipv6.conf.default.disable_ipv6=1
        - sysctl -w net.ipv6.conf.lo.disable_ipv6=1
        - sysctl -w net.ipv4.ip_forward=1
        - ip addr add 192.168.0.200/24 dev eth1
        - ip link set eth1 up
        - ip addr add 10.0.2.1/24 dev eth2
        - ip link set eth2 up
        - ip route add 10.0.1.0/24 via 192.168.0.100
        - iptables -t nat -A POSTROUTING -s 10.0.0.0/16 ! -d 10.0.0.0/16 -j MASQUERADE

    host2:
        kind: linux
        image: nicolaka/netshoot
        network-mode: none
        exec:
        - sysctl -w net.ipv6.conf.all.disable_ipv6=1
        - sysctl -w net.ipv6.conf.default.disable_ipv6=1
        - sysctl -w net.ipv6.conf.lo.disable_ipv6=1
        - sysctl -w net.ipv4.ip_forward=1
        - ip addr add 10.0.2.2/24 dev eth1
        - ip link set eth1 up
        - ip route replace default via 10.0.2.1 dev eth1

        - echo ${wg_peerB_private_key} > privatre
        - ip link add dev gw0 type wireguard
        - ip addr add 172.16.2.0/32 dev gw0
        - wg set wg0 private-key ./private
        - ip link set wg0 up
        - wg set gw0 peer ${wg_peerA_private_key} allowed-ips 172.16.1.0/24 endpoint 10.0.2.2:51820

        - brctl add cni0
        - ip addr add 172.16.2.1/24 dev gw0
        - brctl addif cni0 up
        - brctl addif cni0 pod2_veth_piar
        - ip link set dev pod2_veth_piar up

    pod2:
        kind: linux
        image: nicolaka/netshoot
        network-mode: none
        exec:
        - sysctl -w net.ipv6.conf.all.disable_ipv6=1
        - sysctl -w net.ipv6.conf.default.disable_ipv6=1
        - sysctl -w net.ipv6.conf.lo.disable_ipv6=1
        - ip addr add 172.16.2.2/24 dev eth1
        - ip link set eth1 up
        - ip route replace default via 172.16.2.1 dev eth1

  links:
    - endpoints: ["gw1:eth1", "gw2:eth1"]
    - endpoints: ["gw1:eth2", "host1:eth1"]
    - endpoints: ["gw2:eth2", "host2:eth1"]
    - endpoints: ["host1:pod1_veth_piar", "pod1:eth1"]
    - endpoints: ["host2:pod2_veth_piar", "pod2:eth1"]
EOF

# 步骤 2: 清理任何先前的同名部署并部署新的拓扑
sudo clab destroy -t clab.yaml --cleanup

sudo clab deploy -t clab.yaml




