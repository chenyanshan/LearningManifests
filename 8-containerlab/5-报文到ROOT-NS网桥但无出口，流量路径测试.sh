#!/bin/bash

set -v


cat <<EOF> clab.yaml | clab deploy -t clab.yaml -
name: basic-bridge-lab
topology:
  nodes:
    host1:
      kind: linux
      image: nicolaka/netshoot
      exec:
      - sysctl -w net.ipv4.ip_forward=1 
      - ip addr add 192.168.1.2/24 dev eth0
      - ip link set eth0 up

      # 新增一个网桥
      - brctl addbr base_br
      - ip link set base_br up

      # 配置一个 eth 和 host2 关联
      - ip link set eth_to_br up
      - brctl addif base_br eth_to_br


    host2:
        kind: linux
        image: nicolaka/netshoot
        exec:
        - ip addr add 192.168.1.3/24 dev eth1 # 给接口 eth0 配 IP (与 router 的 eth1 同网段)
        - ip link set eth1 up                 # 启动接口 eth0

  links:
     - endpoints: ["host1:eth_to_br", "host2:eth1"]

EOF