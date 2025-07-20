#!/bin/bash


clab destroy -t l2-network-clab.yaml  --cleanup
kind delete clusters l2-network

ip link set l2-network-br down
brctl delbr l2-network-br