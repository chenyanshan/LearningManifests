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
        - ip addr add 192.168.0.100/24 dev eth1
        - ip link set eth1 up
        - ip addr add 10.0.1.1/24 dev eth2
        - ip link set eth2 up
        - ip route add 10.0.2.0/24 via 192.168.0.200
        - iptables -t nat -A POSTROUTING -s 10.0.0.0/16 ! -d 10.0.0.0/16 -j MASQUERADE

    host1:
        kind: linux
        image: nicolaka/netshoot
        exec:
        # 1. 在宿主机上开启IP转发。
        - sysctl -w net.ipv4.ip_forward=1
        # ⭐️ 新增：开启ARP代理功能，允许为其他接口上的IP进行ARP应答。
        - sysctl -w net.ipv4.conf.all.proxy_arp=1
        - ip addr add 10.0.1.2/24 dev eth1
        - ip link set eth1 up
        - ip route replace default via 10.0.1.1 dev eth1

        # 2. 设置VXLAN接口。
        - ip link add flannel.1 type vxlan id 1 dev eth1 local 10.0.1.2 dstport 4789
        - ip link set dev flannel.1 up

        # 3. 设置连接本地Pod的网桥。
        - brctl addbr cni0
        - ip addr add 172.16.0.1/24 dev cni0
        - ip link set dev cni0 up
        - brctl addif cni0 pod1_veth_piar
        - ip link set dev pod1_veth_piar up

        # 4. 添加到对端Pod子网的路由。
        - ip route add 172.16.1.0/24 dev flannel.1

        # 5. 添加静态FDB条目，用于引导广播（如初始ARP请求）。
        - bridge fdb append to 00:00:00:00:00:00 dst 10.0.2.2 dev flannel.1

    pod1:
        kind: linux
        image: nicolaka/netshoot
        exec:
        - ip addr add 172.16.0.2/24 dev eth1
        - ip link set eth1 up
        - ip route replace default via 172.16.0.1 dev eth1

    gw2:
        kind: linux
        image: nicolaka/netshoot
        exec:
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
        exec:
        # 1. 在宿主机上开启IP转发。
        - sysctl -w net.ipv4.ip_forward=1
        # ⭐️ 新增：开启ARP代理功能。
        - sysctl -w net.ipv4.conf.all.proxy_arp=1
        - ip addr add 10.0.2.2/24 dev eth1
        - ip link set eth1 up
        - ip route replace default via 10.0.2.1 dev eth1

        # 2. 设置VXLAN接口。
        - ip link add flannel.1 type vxlan id 1 dev eth1 local 10.0.2.2 dstport 4789
        - ip link set dev flannel.1 up

        # 3. 设置连接本地Pod的网桥。
        - brctl addbr cni0
        - ip addr add 172.16.1.1/24 dev cni0
        - ip link set dev cni0 up
        - brctl addif cni0 pod2_veth_piar
        - ip link set dev pod2_veth_piar up

        # 4. 添加到对端Pod子网的路由。
        - ip route add 172.16.0.0/24 dev flannel.1

        # 5. 添加指向另一台宿主机的静态FDB条目。
        - bridge fdb append to 00:00:00:00:00:00 dst 10.0.1.2 dev flannel.1

    pod2:
        kind: linux
        image: nicolaka/netshoot
        exec:
        - ip addr add 172.16.1.2/24 dev eth1
        - ip link set eth1 up
        - ip route replace default via 172.16.1.1 dev eth1

  links:
     - endpoints: ["gw1:eth1", "gw2:eth1"]
     - endpoints: ["gw1:eth2", "host1:eth1"]
     - endpoints: ["gw2:eth2", "host2:eth1"]
     - endpoints: ["host1:pod1_veth_piar", "pod1:eth1"]
     - endpoints: ["host2:pod2_veth_piar", "pod2:eth1"]

EOF

# 步骤 2: 清理任何先前的同名部署并部署新的拓扑
echo "--- Destroying any existing lab: simple-vxlan-lab ---"
sudo clab destroy -t clab.yaml --cleanup
echo "--- Deploying lab: simple-vxlan-lab ---"
sudo clab deploy -t clab.yaml