#!/bin/bash

kubectl taint nodes $(kubectl get nodes -o name | grep control-plane) node-role.kubernetes.io/control-plane:NoSchedule-
kubectl get nodes -o wide

helm repo add cilium https://helm.cilium.io/ > /dev/null 2>&1
helm repo update > /dev/null 2>&1


# --set bgpControlPlane.enabled=true 启用 BPG 策略。
# --set autoDirectNodeRoutes=true 如果你的所有 Kubernetes 节点都连接在同一个交换机上（或者在同一个VLAN里，可以相互直接通信而无需经过路由器），那么就打开这个功能。
helm install cilium cilium/cilium --version 1.17.4 --namespace kube-system --set operator.replicas=1 \
  --set routingMode=native --set ipv4NativeRoutingCIDR="10.1.0.0/16" --set autoDirectNodeRoutes=true \
  --set debug.enabled=true --set debug.verbose=datapath --set monitorAggregation=none \
  --set ipam.mode=kubernetes \
  --set bgpControlPlane.enabled=true

# 3. wait all pods ready
kubectl wait --timeout=100s --for=condition=Ready=true pods --all -A

# 4. cilium status
kubectl -nkube-system exec -it ds/cilium -- cilium status
kubectl get crds | grep ciliumbgppeeringpolicies.cilium.io



cat <<EOF | kubectl apply -f -
apiVersion: "cilium.io/v2alpha1"
kind: CiliumBGPPeeringPolicy
metadata:
  name: "as100"
spec:
  # 这个策略应用到哪些Kubernetes节点上。
  nodeSelector: {}
  virtualRouters:
    - localASN: 100 # 这些Worker节点所在的 ASN
      # 导出您想宣告的Pod CIDR。必须设置。
      exportPodCIDR: true
      # 配置 BGP 路由反射器
      neighbors:
        - peerAddress: "10.0.1.1/24" # BGP RR 的IP地址
          peerASN: 100
EOF