#!/bin/bash

# save
image_list=(
  "registry.k8s.io/pause:3.9"
  "calico/cni:v3.26.1"
  "calico/node:v3.26.1"
  "calico/kube-controllers:v3.26.1"
  "registry.k8s.io/metrics-server/metrics-server:v0.6.4"
  "coredns/coredns:1.11.1"
)

namespace="k8s.io"
local_image_save_dir="images"

mkdir -p "${local_image_save_dir}"
rm -rf "${local_image_save_dir}"/*

for image in "${image_list[@]}"; do
  IFS=':' read -ra image_info <<< "$image"
  repo="${image_info[0]//\//-}"  # Replace '/' with '-'
  tag="${image_info[1]}"

  nerdctl pull --namespace="${namespace}" "${image}"

  filename="${repo}_${tag}.tar"
  nerdctl save --namespace="${namespace}" "${image}" -o "${local_image_save_dir}/${filename}"
done
