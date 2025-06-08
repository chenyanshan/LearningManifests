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
        # 1. 在宿主机上开启IP转发。
        - sysctl -w net.ipv4.ip_forward=1
        # ⭐️ 新增：开启ARP代理功能，允许为其他接口上的IP进行ARP应答。
        # 如果没有这个，当 ARP 报文被解开的时候，报文位于宿主机上面。
        # 然后宿主机就会将其丢弃。
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
        network-mode: none
        exec:
        - sysctl -w net.ipv6.conf.all.disable_ipv6=1
        - sysctl -w net.ipv6.conf.default.disable_ipv6=1
        - sysctl -w net.ipv6.conf.lo.disable_ipv6=1
        - ip addr add 172.16.0.2/24 dev eth1
        - ip link set eth1 up
        - ip route replace default via 172.16.0.1 dev eth1

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
        network-mode: none
        exec:
        - sysctl -w net.ipv6.conf.all.disable_ipv6=1
        - sysctl -w net.ipv6.conf.default.disable_ipv6=1
        - sysctl -w net.ipv6.conf.lo.disable_ipv6=1
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



# Pod1 -> Pod2 全流程。
# 1. Pod -> CNI0 忽略。
# 2. Pod1 to Pod2 ICMP 报文 -> CNI0 -> host1网络协议栈。
# 3. Host1 查看目标是 172.16.1.0/24 ，就把报文丢给了 flannel.1 网卡。
# 4. flannel.1 不知道 172.16.1.2 是谁，就通过 ARP 报文进行广播。源 mac 为 flannel.1 mac 。
# 5. ARP 报文通过 fdb 中配置，发送给了【其他】vxlan 节点。（这里没有其他节点）
# 5. host2 收到了 vxlan 报文，送给了 flannel.1 解开报文。
# 6. host2 从 flannel.1 收到谁是 172.16.1.2 ARP 报文。
# 因为其开启了 ARP proxy，所以它知道 172.16.1.2 它能转发到达。所以 host2 通过 flannel.1 响应了 ARP 报文。
# 7. host1 收到了响应报文，172.16.1.2 的 mac 是 host2 flannel.1 的 mac 。
# 8. 最终 flannel.1 封装了报文发出： 
# 最里层：ICMP request
# 封装： SrcIP:Pod1IP, DstIP: Pod2IP, SrcMac: Host1FlannelMac, DstMac: Host2FlannelMac
# Vxlan 封装: Host1 -> Host2:4789
# 9. Host2 收到报文，转给 flannel 解开，然后发现 DstIP 为 Pod2IP， 通过路由转发给了 Pod2 。
# 10. Pod2 以同样路径把 ICMP Reply 返回给了 Pod1 