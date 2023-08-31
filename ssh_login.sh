#!/bin/bash

cluster_node_ips=(
  "192.168.0.151"
  "192.168.0.152"
  "192.168.0.153"
  "192.168.0.161"
  "192.168.0.162"
  "192.168.0.163"
)

for ip in "${cluster_node_ips[@]}"; do
  ssh-copy-id $ip
done