#!/bin/bash
set -v # 显示执行的命令


brctl addbr underlay_net
#ifconfig br0 up
ip link set underlay_net up


# ip link add vxlan100 type vxlan id 100 dev eth1 remote 192.168.100.2 dstport 4789
#   vxlan100:        你想要创建的 VXLAN 接口的名称。
#   type vxlan:      指定接口类型为 VXLAN。
#   id 100:          设置 VXLAN 网络标识符 (VNI) 为 100。
#                    同一 VXLAN 网络中的所有 VTEP 必须使用相同的 VNI。
#   dev eth0:        指定用于 VXLAN 封装的底层物理网络接口。
#                    VXLAN 报文将通过此接口的 IP 地址（192.168.1.10）发送。
#   remote 192.168.2.2: 指定对端 VTEP (主机 B) 的 IP 地址。
#                        对于 BUM (Broadcast, Unknown Unicast, Multicast) 流量，
#                        如果不知道目标 MAC 在哪里，数据包将被单播到这个远程 IP。
#                        在多于两个 VTEP 的单播模式中，你可能需要配置多个远程对等体
#                        或使用多播。
#   dstport 4789:    指定 VXLAN 使用的 UDP 目标端口。IANA 分配的默认端口是 4789。
#                    两端必须一致。


# 步骤 1: 创建 clab.yaml 文件
cat <<EOF > clab_simple_vxlan.yaml
name: simple-vxlan-lab
topology:
  nodes:
    underlay_net: # 用一个网桥节点来模拟共享的底层 L2 网络
      kind: bridge

    host1:
      kind: linux
      image: nicolaka/netshoot # 使用包含网络工具的镜像
      exec:
      - sysctl -w net.ipv4.ip_forward=1 
      - ip addr add 192.168.100.1/24 dev eth1
      - ip link set eth1 up
      - ip link add vxlan100 type vxlan id 100 dev eth1 remote 192.168.100.2 dstport 4789
      #- ip addr add 10.1.1.1/24 dev vxlan100
      - ip link set vxlan100 up
      - echo "--- host1 创建内部网桥 (br_h1_vxlan) ---"
      - brctl addbr br_h1_vxlan # 需要 image 中包含 bridge-utils
      - ip link set br_h1_vxlan up

      - echo "--- host1 将 vxlan100 添加到 br_h1_vxlan ---"
      - brctl addif br_h1_vxlan vxlan100

      - echo "--- host1 配置并将 eth_to_br0 添加到 br_h1_vxlan ---"
      - ip link set eth_to_br0 up # 这个接口由 clab link 创建
      - brctl addif br_h1_vxlan eth_to_br0

      - echo "--- host1 为 br_h1_vxlan 分配 Overlay IP ---"
      #- ip addr add 10.10.1.1/24 dev vxlan100 # pod1 的 Overlay 网关 IP
      - ip addr add 10.1.1.1/24 dev br_h1_vxlan
      - ip -d link show vxlan100
      - ip addr show br_h1_vxlan


    pod1:
        kind: linux
        image: nicolaka/netshoot
        exec:
        - ip addr add 10.1.1.3/24 dev eth1
        - ip link set eth1 up
        - ip route replace default via 10.1.1.1 


    host2:
      kind: linux
      image: nicolaka/netshoot
      exec:
      - sysctl -w net.ipv4.ip_forward=1 
      - ip addr add 192.168.100.2/24 dev eth1
      - ip link set eth1 up
      - ip link add vxlan100 type vxlan id 100 dev eth1 remote 192.168.100.1 dstport 4789
      #- ip addr add 10.1.1.2/24 dev vxlan100
      - ip link set vxlan100 up

      - echo "--- host2 创建内部网桥 (br_h2_vxlan) ---"
      - brctl addbr br_h2_vxlan # 需要 image 中包含 bridge-utils
      - ip link set br_h2_vxlan up

      - echo "--- host2 将 vxlan100 添加到 br_h2_vxlan ---"
      - brctl addif br_h2_vxlan vxlan100

      - echo "--- host2 配置并将 eth_to_br1 添加到 br_h2_vxlan ---"
      - ip link set eth_to_br1 up # 这个接口由 clab link 创建
      - brctl addif br_h2_vxlan eth_to_br1

      - echo "--- host2 为 br_h2_vxlan 分配 Overlay IP ---"
      - ip addr add 10.1.1.2/24 dev br_h2_vxlan
      - ip -d link show vxlan100
      - ip addr show br_h2_vxlan


    pod2:
        kind: linux
        image: nicolaka/netshoot
        exec:
        - ip addr add 10.1.1.4/24 dev eth1
        - ip link set eth1 up
        - ip route replace default via 10.1.1.2


  links:
    - endpoints: ["underlay_net:h1_port", "host1:eth1"] # 将 host1:eth1 连接到底层网络
    - endpoints: ["underlay_net:h2_port", "host2:eth1"] # 将 host2:eth1 连接到底层网络

    # Overlay 网络连接 (通过网桥节点)
    # host1 通过 eth_to_br0 连接到 br0
    - endpoints: ["host1:eth_to_br0", "pod1:eth1"]

    # host2 通过 eth_to_br1 连接到 br1
    - endpoints: ["host2:eth_to_br1", "pod2:eth1"]

EOF

# 步骤 2: 清理任何先前的同名部署并部署新的拓扑
echo "--- Destroying any existing lab: simple-vxlan-lab ---"
sudo clab destroy -t clab_simple_vxlan.yaml --cleanup

echo "--- Deploying lab: simple-vxlan-lab ---"
sudo clab deploy -t clab_simple_vxlan.yaml