#!/bin/bash

set -v

sudo clab destroy -t clab.yaml --cleanup

brctl addbr switch
ip link set switch up

cat <<EOF > clab.yaml && clab deploy -t clab.yaml
name: host-gw-lab
topology:
  nodes:
    # 模拟连接所有主机的二层交换机 (底层网络)
    switch:
        kind: bridge

    host1:
        kind: linux
        image: nicolaka/netshoot
        network-mode: none
        exec:
        - sysctl -w net.ipv4.ip_forward=1

        - ip addr add 192.168.0.100/24 dev veth-paic1
        - ip link set veth-paic1 up

        # 设置 Pod 连接宿主机的网桥
        - brctl addbr cni0
        - ip addr add 10.0.1.1/24 dev cni0
        - ip link set cni0 up

        # 把 Pod 的 vveth-paic-pair 网卡挂载到 cni0 上。
        - ip link set pod1-veth-paic master cni0
        - ip link set pod1-veth-paic up

        # host-gw 核心路由: 告诉 host1 如何到达 host2 上的 Pod 网络
        - ip route add 10.0.2.0/24 via 192.168.0.200

        # NAT 规则, 用于 Pod 访问外部网络 (可选)
        - iptables -t nat -A POSTROUTING -s 10.0.0.0/16 ! -d 10.0.0.0/16 -j MASQUERADE

    pod1:
        kind: linux
        image: nicolaka/netshoot
        network-mode: none
        exec:
        # Pod 自己的 IP
        - ip addr add 10.0.1.2/24 dev veth-paic1
        - ip link set veth-paic1 up
        # 将默认网关指向其宿主 host1
        - ip route replace default via 10.0.1.1
    
    host2:
        kind: linux
        image: nicolaka/netshoot
        network-mode: none
        exec:
        - sysctl -w net.ipv4.ip_forward=1

        - ip addr add 192.168.0.200/24 dev veth-paic1
        - ip link set veth-paic1 up

        # 设置 Pod 连接宿主机的网桥
        - brctl addbr cni0
        - ip addr add 10.0.2.1/24 dev cni0
        - ip link set cni0 up

        # 把 Pod 的 vveth-paic-pair 网卡挂载到 cni0 上。
        - ip link set pod2-veth-paic master cni0
        - ip link set pod2-veth-paic up

        # host-gw 核心路由: 告诉 host1 如何到达 host2 上的 Pod 网络
        - ip route add 10.0.1.0/24 via 192.168.0.100

        # NAT 规则, 用于 Pod 访问外部网络 (可选)
        - iptables -t nat -A POSTROUTING -s 10.0.0.0/16 ! -d 10.0.0.0/16 -j MASQUERADE

    pod2:
      kind: linux
      image: nicolaka/netshoot
      network-mode: none
      exec:
      - ip addr add 10.0.2.2/24 dev veth-paic1
      - ip link set veth-paic1 up
      # 将默认网关指向其宿主 host2
      - ip route replace default via 10.0.2.1

  links:
     # 将 host1 和 host2 连接到交换机上
     - endpoints: ["host1:veth-paic1", "switch:veth-paic1"]
     - endpoints: ["host2:veth-paic1", "switch:veth-paic2"]
     # 将 pod 连接到 host
     - endpoints: ["host1:pod1-veth-paic", "pod1:veth-paic1"]
     - endpoints: ["host2:pod2-veth-paic", "pod2:veth-paic1"]

EOF

sudo clab deploy -t clab.yaml


