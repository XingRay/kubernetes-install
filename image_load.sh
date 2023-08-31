#!/bin/bash
k8s_node_hostnames=(
  "k8s-master-01"
  "k8s-master-02"
  "k8s-master-03"
  "k8s-worker-01"
  "k8s-worker-02"
  "k8s-worker-03"
)

local_image_save_dir="images"
remote_image_save_dir="/root/tmp/images"

for node in "${k8s_node_hostnames[@]}"; do
  ssh "root@${node}" "mkdir -p ${remote_image_save_dir}"
  ssh "root@${node}" "rm -rf ${remote_image_save_dir}/*"

  scp "${local_image_save_dir}"/* "root@${node}:${remote_image_save_dir}/"
  
  ssh "root@${node}" "
    for filename in $(ls '${remote_image_save_dir}'); do
      nerdctl load --namespace='${namespace}' -i '${remote_image_save_dir}/\$filename'
    done
  "
done
