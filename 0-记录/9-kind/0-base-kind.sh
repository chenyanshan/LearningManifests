#!/bin/bash

set -v

# 1. create kubernetes cluster
cat <<EOF> kind.yaml | kind create cluster --image=kindest/node:v1.33.1 --config kind.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: KubeletConfiguration
    cgroupDriver: systemd
- role: worker
networking:
  disableDefaultCNI: true # 禁用 kindnetd
  podSubnet: "10.0.0.0/16" # CNI 插件可能需要的 Pod 子网

EOF

kubectl get nodes -o wide


# 2. helm add cilium repo
helm repo add cilium https://helm.cilium.io/ > /dev/null 2>&1
helm repo update > /dev/null 2>&1


kubectl create ns cilium

# 3. helm install cilium
#
# Direct Route (hostgw) 配置(--set tunnel=disabled --set autoDirectNodeRoutes=true --set ipv4NativeRoutingCIDR="10.0.0.0/8")
# Debug 配置: --set debug.enabled=true --set debug.verbose=datapath --set monitorAggregation=none
# ipam.mode=cluster-pool
helm install cilium cilium/cilium --version 1.14 --namespace cilium --set operator.replicas=1 \
  --set tunnel=disabled --set autoDirectNodeRoutes=true --set ipv4NativeRoutingCIDR="10.0.0.0/8" \
  --set debug.enabled=true --set debug.verbose=datapath --set monitorAggregation=none \
  --set ipam.mode=cluster-pool


# 传统 hostgw 模式，和 calico 之类没什么区别。
# Value tunnel was deprecated in Cilium 1.14 in favor of routingMode and tunnelProtocol, and has been removed.
helm install cilium cilium/cilium --version 1.17.4 --namespace cilium --set operator.replicas=1 \
  --set routingMode=native --set autoDirectNodeRoutes=true --set ipv4NativeRoutingCIDR="10.0.0.0/8" \
  --set debug.enabled=true --set debug.verbose=datapath --set monitorAggregation=none \
  --set ipam.mode=cluster-pool

# ipam: cluster-pool（或由 Operator 管理的 cluster-pool）： 如果 Cilium 的 IPAM模式设置为 cluster-pool，Cilium 会从一个或多个在其自身配置中定义的全局地址池
#（例如通过 clusterPoolIPv4PodCIDRList 或 Helm 中的 ipam.operator.clusterPoolIPv4PodCIDRList 参数指定）
# 中为集群中所有节点上的 Pod 分配 IP 地址。在这种模式下，Cilium 分配 IP 时不一定严格使用 Node.Spec.PodCIDR 字段中由 kube-controller-manager 分配给该节点的 CIDR。它会使用自己管理的、可能更大的全局地址池。

# 设置 ipam.mode=cluster-pool 会导致实际分配 ip 与 kubernetes controller-manager 分配 ip 不一致，导致 describe node 和真实的不一致。


# 默认 vxlan 模式
helm install cilium cilium/cilium --version 1.17.4 --namespace cilium --set operator.replicas=1 

# 不使用 kube-proxy
# 选项 --set kubeProxyReplacement=strict
# --set kubeProxyReplacement=true
# "disable", "partial", "strict"

# strict： 
# Cilium 全面接管： Cilium 会利用其 eBPF (Extended Berkeley Packet Filter) 数据平面来实现 Kubernetes Service 的负载均衡、网络地址转换 (NAT)、以及其他所有历史上由 kube-proxy (通常通过 iptables 或 IPVS 模式) 处理的网络功能。
# 1. 性能提升： eBPF 通常比 iptables 或 IPVS 在处理网络数据包时有更低的延迟和更高的吞吐量。
# 2. 更高效的负载均衡： Cilium 的 eBPF 负载均衡器可以实现更优化的服务路由。
# 3. 源 IP 保留： 在某些情况下，更容易实现源 IP 地址的保留。
# 4. 减少系统开销： 消除了 kube-proxy 进程及其管理的 iptables 规则带来的开销。

# partial (部分替换)：
# Cilium 会尝试在 Socket 层（当 Pod 发起连接时）或 TC (Traffic Control) 层进行负载均衡，这比 iptables 更早介入，效率更高。
# kube-proxy 仍然需要运行，因为它可能还需要处理某些 Cilium 没有完全覆盖的场景，或者确保所有类型的 Service 都能按预期工作，尤其是在一些复杂的配置下。
# 

# kubectl exec -it cilium-1d8xg -- bash
# cilium service list
# cilium bpf map
# cilium map list 
# cilium status
# bpftool net show


# Host Routing , SNAT , 使用 EBPF
# Cilium 会根据配置（例如 ipv4NativeRoutingCIDR 或 clusterPoolIPv4PodCIDRList 来判断哪些是集群内部的 Pod IP）来决定哪些出向流量需要进行地址伪装。通常，目标地址不在 Pod CIDR 范围内的流量，并且源 IP 是 Pod IP 的，会被伪装。 
# --set bpf.masquerade=true 

# cilium status

# cilium config viewer




cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: net-pod1
spec:
  nodeName: cilium-control-plane # 直接指定节点名称
  containers:
  - name: nettool
    image: nicolaka/netshoot
    command: ["/bin/sh", "-c"]
    args: ["sleep 365d"]
---
apiVersion: v1
kind: Pod
metadata:
  name: net-pod2
spec:
  nodeName: cilium-worker # 直接指定节点名称
  containers:
  - name: nettool
    image: nicolaka/netshoot
    command: ["/bin/sh", "-c"]
    args: ["sleep 365d"]
---
apiVersion: v1
kind: Pod
metadata:
  name: net-pod3
spec:
  nodeName: cilium-worker # 直接指定节点名称
  containers:
  - name: nettool
    image: nicolaka/netshoot
    command: ["/bin/sh", "-c"]
    args: ["sleep 365d"]
EOF