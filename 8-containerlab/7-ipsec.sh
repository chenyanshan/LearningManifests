#!/bin/bash
set -v


# SPI_ID="0x$(head -c 4 /dev/urandom | od -A n -t x4 | tr -d ' ')"
# AUTH_KEY="0x$(openssl rand -hex 16)"
# ENC_KEY="0x$(openssl rand -hex 16)"
# 来回 spi $SPI_ID reqid $SPI_ID 可以一致



cat <<EOF> clab.yaml
name: ipsec-demo
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
        - brctl addbr cni0
        - ip addr add 172.16.1.1/24 dev cni0
        - ip link set dev cni0 up
        - brctl addif cni0 pod1_veth_piar
        - ip link set dev pod1_veth_piar up

        # --- IPsec 配置 for host1 ---
        # ↓↓↓ [已注释] 定义 出站 (从本地到远端) 的 SA 规则
        # - ip xfrm state add \
        #     src 10.0.1.2 \        # 源隧道IP (本地公网IP)
        #     dst 10.0.2.2 \        # 目标隧道IP (对端公网IP)
        #     proto esp \
        #     # echo "0x$(head -c 4 /dev/urandom | od -A n -t x4 | tr -d ' ')"
        #     spi 0x9ba69051 \
        #     # echo "0x$(head -c 4 /dev/urandom | od -A n -t x4 | tr -d ' ')"
        #     reqid 0x9ba69051 \
        #     mode tunnel \
        #     # echo "0x$(openssl rand -hex 16)"
        #     auth md5 0xed0b35c8ac0763c89e5327cd6fac8d54 \ # 使用 MD5 算法进行认证，后面是认证密钥
        #     # echo "0x$(openssl rand -hex 16)"
        #     enc aes 0x80d1b8e777d1a63bedf5710aaed93cf5    # 使用 AES 算法进行加密，后面是加密密钥
        # 合并为单行命令:
        # 这是分离模式
        - ip xfrm state add src 10.0.1.2 dst 10.0.2.2 proto esp spi 0x9ba69051 reqid 0x9ba69051 mode tunnel auth md5 0xed0b35c8ac0763c89e5327cd6fac8d54 enc aes 0x80d1b8e777d1a63bedf5710aaed93cf5
       # - ip xfrm state add src 10.0.1.2 dst 10.0.2.2 proto esp spi $ID reqid $ID mode tunnel aead 'rfc4106(gcm(aes))' $KEY 128

        # ↓↓↓ [已注释] 定义 入站 (从远端到本地) 的 SA 规则
        # - ip xfrm state add \
        #     src 10.0.2.2 \        # (修正) 源隧道IP (对端公网IP)
        #     dst 10.0.1.2 \        # (修正) 目标隧道IP (本地公网IP)
        #     proto esp \
        #     spi 0xabcde123 \      # (修正) 入站SPI/REQID应与出站不同，且与对端的出站规则匹配
        #     reqid 0xabcde123 \
        #     mode tunnel \
        #     auth md5 0xed0b35c8ac0763c89e5327cd6fac8d54 \
        #     enc aes 0x80d1b8e777d1a63bedf5710aaed93cf5
        # 合并为单行命令 (注意: 入站SA的源/目标IP已修正，并假设使用不同的SPI/REQID和密钥，这些需要与host2的出站规则匹配):
        # 来回一致也没关系
        - ip xfrm state add src 10.0.2.2 dst 10.0.1.2 proto esp spi 0xf2a13b9c reqid 0xf2a13b9c mode tunnel auth md5 0x1a2b3c4d5e6f78901234567890abcdef enc aes 0xfedcba9876543210fedcba9876543210

        # ↓↓↓ [已注释] 定义 出站 策略：什么流量需要被加密发送出去
        # - ip xfrm policy add \
        #     src 172.16.1.0/24 \   # (修正) 源地址 (本地私有网络)
        #     dst 172.16.2.0/24 \   # (修正) 目标地址 (远程私有网络)
        #     dir out \
        #     tmpl src 10.0.1.2 dst 10.0.2.2 \
        #     proto esp reqid 0x9ba69051 mode tunnel
        # 合并为单行命令 (修正了网络地址为/24网段):
        - ip xfrm policy add src 172.16.1.0/24 dst 172.16.2.0/24 dir out tmpl src 10.0.1.2 dst 10.0.2.2 proto esp reqid 0x9ba69051 mode tunnel

        # ↓↓↓ [已注释] 定义 入站/转发 策略 (修正: dir in 和 fwd 的源/目标地址应相反)
        # - ip xfrm policy add \
        #     src 172.16.2.0/24 \   # (修正) 源地址 (远程私有网络)
        #     dst 172.16.1.0/24 \   # (修正) 目标地址 (本地私有网络)
        #     dir in \
        #     tmpl src 10.0.2.2 dst 10.0.1.2 \
        #     proto esp reqid 0xf2a13b9c mode tunnel
        # - ip xfrm policy add \
        #     src 172.16.2.0/24 \   # (修正) 源地址 (远程私有网络)
        #     dst 172.16.1.0/24 \   # (修正) 目标地址 (本地私有网络)
        #     dir fwd \
        #     tmpl src 10.0.2.2 dst 10.0.1.2 \
        #     proto esp reqid 0xf2a13b9c mode tunnel
        # 合并为单行命令:
        - ip xfrm policy add src 172.16.2.0/24 dst 172.16.1.0/24 dir in tmpl src 10.0.2.2 dst 10.0.1.2 proto esp reqid 0xf2a13b9c mode tunnel
        - ip xfrm policy add src 172.16.2.0/24 dst 172.16.1.0/24 dir fwd tmpl src 10.0.2.2 dst 10.0.1.2 proto esp reqid 0xf2a13b9c mode tunnel

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
        - brctl addbr cni0
        - ip addr add 172.16.2.1/24 dev cni0
        - ip link set dev cni0 up
        - brctl addif cni0 pod2_veth_piar
        - ip link set dev pod2_veth_piar up
        
        # --- IPsec 配置 for host2 ---
        # ↓↓↓ [已注释] 定义 出站 (从本地到远端) 的 SA 规则 (对应 host1 的入站)
        # - ip xfrm state add \
        #     src 10.0.2.2 \
        #     dst 10.0.1.2 \
        #     proto esp \
        #     spi 0xf2a13b9c \
        #     reqid 0xf2a13b9c \
        #     mode tunnel \
        #     auth md5 0x1a2b3c4d5e6f78901234567890abcdef \
        #     enc aes 0xfedcba9876543210fedcba9876543210
        # 合并为单行命令 (SPI/密钥必须与host1的入站规则完全匹配):
        - ip xfrm state add src 10.0.2.2 dst 10.0.1.2 proto esp spi 0xf2a13b9c reqid 0xf2a13b9c mode tunnel auth md5 0x1a2b3c4d5e6f78901234567890abcdef enc aes 0xfedcba9876543210fedcba9876543210

        # ↓↓↓ [已注释] 定义 入站 (从远端到本地) 的 SA 规则 (对应 host1 的出站)
        # - ip xfrm state add \
        #     src 10.0.1.2 \
        #     dst 10.0.2.2 \
        #     proto esp \
        #     spi 0x9ba69051 \
        #     reqid 0x9ba69051 \
        #     mode tunnel \
        #     auth md5 0xed0b35c8ac0763c89e5327cd6fac8d54 \
        #     enc aes 0x80d1b8e777d1a63bedf5710aaed93cf5
        # 合并为单行命令 (SPI/密钥必须与host1的出站规则完全匹配):
        - ip xfrm state add src 10.0.1.2 dst 10.0.2.2 proto esp spi 0x9ba69051 reqid 0x9ba69051 mode tunnel auth md5 0xed0b35c8ac0763c89e5327cd6fac8d54 enc aes 0x80d1b8e777d1a63bedf5710aaed93cf5

        # ↓↓↓ [已注释] 定义 出站 策略 (对应 host1 的入站/转发策略)
        # - ip xfrm policy add \
        #     src 172.16.2.0/24 \
        #     dst 172.16.1.0/24 \
        #     dir out \
        #     tmpl src 10.0.2.2 dst 10.0.1.2 \
        #     proto esp reqid 0xf2a13b9c mode tunnel
        # 合并为单行命令:
        - ip xfrm policy add src 172.16.2.0/24 dst 172.16.1.0/24 dir out tmpl src 10.0.2.2 dst 10.0.1.2 proto esp reqid 0xf2a13b9c mode tunnel

        # ↓↓↓ [已注释] 定义 入站/转发 策略 (对应 host1 的出站策略)
        # - ip xfrm policy add \
        #     src 172.16.1.0/24 \
        #     dst 172.16.2.0/24 \
        #     dir in \
        #     tmpl src 10.0.1.2 dst 10.0.2.2 \
        #     proto esp reqid 0x9ba69051 mode tunnel
        # - ip xfrm policy add \
        #     src 172.16.1.0/24 \
        #     dst 172.16.2.0/24 \
        #     dir fwd \
        #     tmpl src 10.0.1.2 dst 10.0.2.2 \
        #     proto esp reqid 0x9ba69051 mode tunnel
        # 合并为单行命令:
        - ip xfrm policy add src 172.16.1.0/24 dst 172.16.2.0/24 dir in tmpl src 10.0.1.2 dst 10.0.2.2 proto esp reqid 0x9ba69051 mode tunnel
        - ip xfrm policy add src 172.16.1.0/24 dst 172.16.2.0/24 dir fwd tmpl src 10.0.1.2 dst 10.0.2.2 proto esp reqid 0x9ba69051 mode tunnel

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



#host2:~# ip x p
#src 172.16.1.0/24 dst 172.16.2.0/24
#	dir fwd priority 0
#	tmpl src 10.0.1.2 dst 10.0.2.2
#		proto esp reqid 2611384401 mode tunnel
#src 172.16.1.0/24 dst 172.16.2.0/24
#	dir in priority 0
#	tmpl src 10.0.1.2 dst 10.0.2.2
#		proto esp reqid 2611384401 mode tunnel
#src 172.16.2.0/24 dst 172.16.1.0/24
#	dir out priority 0
#	tmpl src 10.0.2.2 dst 10.0.1.2
#		proto esp reqid 4070652828 mode tunnel
#host2:~# ip x s
#src 10.0.1.2 dst 10.0.2.2
#	proto esp spi 0x9ba69051 reqid 2611384401 mode tunnel
#	replay-window 0
#	auth-trunc hmac(md5) 0xed0b35c8ac0763c89e5327cd6fac8d54 96
#	enc cbc(aes) 0x80d1b8e777d1a63bedf5710aaed93cf5
#	anti-replay context: seq 0x0, oseq 0x0, bitmap 0x00000000
#	sel src 0.0.0.0/0 dst 0.0.0.0/0
#src 10.0.2.2 dst 10.0.1.2
#	proto esp spi 0xf2a13b9c reqid 4070652828 mode tunnel
#	replay-window 0
#	auth-trunc hmac(md5) 0x1a2b3c4d5e6f78901234567890abcdef 96
#	enc cbc(aes) 0xfedcba9876543210fedcba9876543210
#	anti-replay context: seq 0x0, oseq 0x3, bitmap 0x00000000
#	sel src 0.0.0.0/0 dst 0.0.0.0/0