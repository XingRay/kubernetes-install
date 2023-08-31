#!/bin/bash

cluster_node_hostnames=(
  "k8s-master-01"
  "k8s-master-02"
  "k8s-master-03"
  "k8s-worker-01"
  "k8s-worker-02"
  "k8s-worker-03"
)

remote_tools_save_dir="/root/tmp/tools"
local_tools_save_dir="./tools"

# ubuntu 22
system_name="jammy"

# 检查本地目录是否存在
if [ -d "${local_tools_save_dir}" ]; then
    # 将导出的工具包发送到远程节点离线安装
    for node in "${cluster_node_hostnames[@]}"; do
        # 准备好远程节点临时存放工具安装包的目录
        ssh "root@${node}" "mkdir -p ${remote_tools_save_dir}"
        ssh "root@${node}" "rm -rf ${remote_tools_save_dir}/*"

        # 将安装包发送到各个节点
        scp -r "${local_tools_save_dir}"/* "root@${node}:${remote_tools_save_dir}/"
        # 在内网机器上配置apt源
        ssh "root@${node}" "echo deb [trusted=yes] file://${remote_tools_save_dir}/ ${system_name} main > /etc/apt/sources.list.d/local-tools.list"
        # 安装deb包
        ssh "root@${node}" "apt update && apt install -y ${remote_tools_save_dir}/*.deb"
    done
else
    echo "Local tools directory '${local_tools_save_dir}' not found."
fi
