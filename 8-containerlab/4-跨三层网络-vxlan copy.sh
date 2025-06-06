#!/bin/bash
set -v
cat <<EOF> clab.yaml | clab deploy -t clab.yaml -
name: flannel-vxlan
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
        - ip link set eth0 down
        - ip link delete eth0

    host1:
        kind: linux
        image: nicolaka/netshoot
        exec:
        - sysctl -w net.ipv4.ip_forward=1
        - ip addr add 10.0.1.2/24 dev eth1
        - ip link set eth1 up
        - ip route replace default via 10.0.1.1 dev eth1

        # 设置 vxlan 网卡
        - ip link add flannel.1 type vxlan id 1 dev eth1 local 10.0.1.2 dstport 4789
        - ip addr add 172.16.0.0/32 dev flannel.1
        - ip link set dev flannel.1 up

        # 设置 Pod 和宿主机连接的网桥
        - brctl addbr cni0
        - ip link set dev cni0 up
        - ip addr add 172.16.0.1/24 dev cni0
        - brctl addif cni0 pod1_veth_piar
        - brctl addif cni0 flannel.1
        - ip link set dev pod1_veth_piar up

        - ip route add 172.16.0.0/24 dev cni0
        - ip route add 172.16.1.0/24 dev flannel.1
        - bridge fdb append to 00:00:00:00:00:00 dst 10.0.2.2 dev flannel.1
        - ip link set eth0 down
        - ip link delete eth0

    pod1:
        kind: linux
        image: nicolaka/netshoot
        exec:
        - ip addr add 172.16.0.2/24 dev eth1
        - ip route add 172.16.0.0/16 via 172.16.0.1 dev eth1
        - ip link set eth1 up
        - ip route replace default via 172.16.0.1 dev eth1
        - ip link set eth0 down
        - ip link delete eth0

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
        - ip link set eth0 down
        - ip link delete eth0

    host2:
        kind: linux
        image: nicolaka/netshoot
        exec:
        - sysctl -w net.ipv4.ip_forward=1
        - ip addr add 10.0.2.2/24 dev eth1
        - ip link set eth1 up
        - ip route replace default via 10.0.2.1 dev eth1

        # 设置 vxlan 网卡
        - ip link add flannel.1 type vxlan id 1 dev eth1 local 10.0.2.2 dstport 4789
        - ip addr add 172.16.1.0/32 dev flannel.1
        - ip link set dev flannel.1 up

        # 设置 Pod 和宿主机连接的网桥
        - brctl addbr cni0
        - ip link set dev cni0 up
        - ip addr add 172.16.1.1/24 dev cni0
        - brctl addif cni0 flannel.1
        - brctl addif cni0 pod2_veth_piar
        - ip link set dev pod2_veth_piar up

        - ip route add 172.16.1.0/24 dev cni0
        - ip route add 172.16.0.0/24 dev flannel.1
        - bridge fdb append to 00:00:00:00:00:00 dst 10.0.1.2 dev flannel.1
        - ip link set eth0 down
        - ip link delete eth0

    pod2:
        kind: linux
        image: nicolaka/netshoot
        exec:
        - ip addr add 172.16.1.2/24 dev eth1
        - ip route add 172.16.0.0/16 via 172.16.1.1 dev eth1
        - ip link set eth1 up
        - ip route replace default via 172.16.1.1 dev eth1
        - ip link set eth0 down
        - ip link delete eth0

  links:
     - endpoints: ["gw1:gwnet1", "gw2:gwnet1"]
     - endpoints: ["gw1:hostnet1", "host1:eth1"]
     - endpoints: ["gw2:hostnet1", "host2:eth1"]
     - endpoints: ["host1:pod1_veth_piar", "pod1:eth1"]
     - endpoints: ["host2:pod2_veth_piar", "pod2:eth1"]
EOF

# 步骤 2: 清理任何先前的同名部署并部署新的拓扑
echo "--- Destroying any existing lab: simple-vxlan-lab ---"
sudo clab destroy -t clab.yaml --cleanup
echo "--- Deploying lab: simple-vxlan-lab ---"
sudo clab deploy -t clab.yaml