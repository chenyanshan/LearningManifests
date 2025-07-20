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
        #- ip addr add 172.16.0.0/32 dev flannel.1
        - ip route add 172.16.1.0/24 via 172.16.1.1 dev flannel.1 onlink

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
        #- ip addr add 172.16.1.0/32 dev flannel.1
        - ip route add 172.16.0.0/24 via 172.16.0.1 dev flannel.1 onlink

        # 5. 添加指向另一台宿主机的静态FDB条目。
        - bridge fdb append to 00:00:00:00:00:00 dst 10.0.1.2 dev flannel.1
        # 使用组播
        # - ip link add flannel.1 type vxlan id 1 dev eth1 group 239.1.1.1 dstport 4789

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



# 1. Pod1 到 Host1：pod1 (172.16.0.2) 发送一个 ICMP 包给 pod2 (172.16.1.2)。数据包的网关是 host1 上的 cni0 网桥 (172.16.0.1)。
# 2. Host1 路由查询：host1 的内核收到数据包。它查询路由表，发现了这条规则：ip route add 172.16.1.0/24 via 172.16.1.0 dev flannel.1 onlink。目标地址 172.16.1.2 匹配了这条路由。
# 3. 为网关进行 ARP 查询：这条路由规则指定了网关是 172.16.1.0，并且它是通过 flannel.1 接口 onlink（直连）的。因为 flannel.1 是一个虚拟的二层设备，所以内核在创建二层帧之前，必须先找到网关 172.16.1.0 的 MAC 地址。
# 4. 生成 ARP 请求：host1 内核生成一个 ARP 请求：“谁是 172.16.1.0？请告诉 172.16.0.0”（这里的 172.16.0.0 就是 host1 上 flannel.1 接口的 IP）。这个 ARP 请求在二层上是一个广播。
# 5. VXLAN 封装：这个 ARP 请求被发送给 flannel.1 设备。VXLAN 驱动需要将这个广播帧发送给其他的 VTEP 节点。
#    它会查找自己的转发表（FDB），并找到你手动添加的静态条目：bridge fdb append to 00:00:00:00:00:00 dst 10.0.2.2。
#    这条规则告诉驱动，将这个广播 ARP 请求封装成一个单播 UDP 包，然后发往 host2 的 IP (10.0.2.2)。
# 6. Host2 解封装并回应 ARP：host2 收到 UDP 包，识别出是发往 VNI 1 的 VXLAN 流量，于是解封装，并将内部的 ARP 请求交给它自己的 flannel.1 接口。
#                          host2 的内核看到这个 ARP 请求查询的是 172.16.1.0，而这正是它自己 flannel.1 接口的 IP，于是它用自己 flannel.1 的 MAC 地址进行应答。
# 7. 转发 ICMP 包：host1 收到 ARP 应答后，将 host2 的 flannel.1 MAC 地址添加到自己的邻居缓存中。现在，它终于可以转发原始的 ICMP 包了。
#                 内部的数据包现在是 [二层头: src_mac=h1_flannel_mac, dst_mac=h2_flannel_mac] -> [三层头: src_ip=172.16.0.2, dst_ip=172.16.1.2]。
#                 这整个二层帧被 VXLAN 封装后发往 10.0.2.2。
# 8. 送达 Pod2：host2 解封装 ICMP 包，查询 172.16.1.2 的路由，然后通过 cni0 网桥将包转发给 pod2。


# 上面的架构是单播模式，Vxlan 支持组播模式，但是需要底层网络设备支持并配置组播。
# 绝大多数生产环境中（尤其是公有云上），像 Flannel、Calico 等CNI的VXLAN模式都不使用组播。
# 原因是：为了解耦。CNI的设计目标是能运行在任何网络环境上，而要求用户去配置底层网络的组播功能，依赖性太强，不现实。
# 它们是这样做的：用一个集中的控制平面来代替组播。

# flannel： 
# 每个节点上的 flanneld 进程启动后，会向 etcd 注册自己的信息，包括：本节点的公网IP（VTEP IP）、分配到的Pod子网、以及flannel.1接口的MAC地址。
# 同时，每个 flanneld 进程也会**监听（Watch）**etcd 中所有其他节点注册的信息。
# 当 host1 上的 flanneld 从 etcd 中发现了 host2 的信息后，它会直接、动态地在 host1 上配置好到达 host2 所需的路由表和FDB转发表。


# # flanneld 自动在 host1 上执行类似操作
# # 1. 添加到对端Pod子网的路由
# ip route add 172.16.1.0/24 via 172.16.1.0 dev flannel.1 onlink 

# # 2. 添加对端VTEP的ARP和FDB信息
# # ARP: 172.16.1.0 -> host2 flannel.1 MAC
# # FDB: host2 flannel.1 MAC -> host2 IP (VTEP)
# ip neigh add 172.16.1.0 lladdr <host2-flannel-MAC> dev flannel.1
# bridge fdb append <host2-flannel-MAC> dst <host2-IP> dev flannel.1

# 生产级CNI走了一条更具普适性的路线。它放弃了对底层网络组播功能的要求，转而利用 etcd 这样的数据库建立了一个“中央通知系统”。
# 大家把自己的信息报上来，再从系统里获取所有其他人的信息，然后自己动态地、精确地配置好转发表。