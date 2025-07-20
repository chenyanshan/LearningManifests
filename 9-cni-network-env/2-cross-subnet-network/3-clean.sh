#!/bin/bash



clab destroy -t cross-subnet-clab.yaml  --cleanup
kind delete clusters cross-subnet

ip link set clab-br1 down
brctl delbr clab-br1

ip link set clab-br2 down
brctl delbr clab-br2
