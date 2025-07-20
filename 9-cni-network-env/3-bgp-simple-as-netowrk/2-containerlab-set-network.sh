#!/bin/bash

set -v

sudo clab destroy -t clab.yaml --cleanup

brctl addbr leaf01-br
ip link set leaf01-br up

brctl addbr leaf02-br
ip link set leaf02-br up


cat <<EOF > clab.yaml && clab deploy -t clab.yaml
name: cilium-bgp
mgmt:
  ipv4-subnet: 172.16.100.0/24
topology:
  nodes:
    # 模拟连接所有主机的二层交换机 (底层网络)
    leaf01-br:
        kind: bridge

    leaf02-br:
        kind: bridge

    spine01:
      kind: linux
      image: hihihiai/vyos:1.5-stream-2025-Q1-generic-amd64
      cmd: /sbin/init
      binds:
        - /lib/modules:/lib/modules
        - ./vyos-boot-conf/spine01-config.boot:/opt/vyatta/etc/config/config.boot

    spine02:
      kind: linux
      image: hihihiai/vyos:1.5-stream-2025-Q1-generic-amd64
      cmd: /sbin/init
      binds:
        - /lib/modules:/lib/modules
        - ./vyos-boot-conf/spine02-config.boot:/opt/vyatta/etc/config/config.boot

    leaf01:
      kind: linux
      image: hihihiai/vyos:1.5-stream-2025-Q1-generic-amd64
      cmd: /sbin/init
      binds:
        - /lib/modules:/lib/modules
        - ./vyos-boot-conf/leaf01-config.boot:/opt/vyatta/etc/config/config.boot

    leaf02:
      kind: linux
      image: hihihiai/vyos:1.5-stream-2025-Q1-generic-amd64
      cmd: /sbin/init
      binds:
        - /lib/modules:/lib/modules
        - ./vyos-boot-conf/leaf02-config.boot:/opt/vyatta/etc/config/config.boot

    control-plane:
      kind: linux
      image: nicolaka/netshoot
      network-mode: container:cilium-bgp-control-plane
      exec:
        - ip addr add 10.0.5.11/24 dev net0
        - ip route replace default via 10.0.5.1

    worker:
      kind: linux
      image: nicolaka/netshoot
      network-mode: container:cilium-bgp-worker
      exec:
        - ip addr add 10.0.5.12/24 dev net0
        - ip route replace default via 10.0.5.1

    worker2:
      kind: linux
      image: nicolaka/netshoot
      network-mode: container:cilium-bgp-worker2
      exec:
        - ip addr add 10.0.10.11/24 dev net0
        - ip route replace default via 10.0.10.1

    worker3:
      kind: linux
      image: nicolaka/netshoot
      network-mode: container:cilium-bgp-worker3
      exec:
        - ip addr add 10.0.10.12/24 dev net0
        - ip route replace default via 10.0.10.1

  links:
   - endpoints: [control-plane:net0, leaf01-br:leaf01-br-eth1]
   - endpoints: [worker:net0, leaf01-br:leaf01-br-eth2]
   - endpoints: [worker2:net0, leaf02-br:leaf02-br-eth1]
   - endpoints: [worker3:net0, leaf02-br:leaf02-br-eth2]

   - endpoints: [leaf01:eth2, spine01:eth1]
   - endpoints: [leaf01:eth3, spine02:eth2]
   - endpoints: [leaf01:eth1, leaf01-br:leaf01-br-eth3]

   - endpoints: [leaf02:eth2, spine02:eth1]
   - endpoints: [leaf02:eth3, spine01:eth2]
   - endpoints: [leaf02:eth1, leaf02-br:leaf02-br-eth3]
EOF

sudo clab deploy -t clab.yaml


