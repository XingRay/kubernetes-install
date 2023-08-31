#!/bin/bash

###################################################
#                     参数设置                     #
###################################################

# 资源规划

etcd_nodes=(
  "k8s-master-01|192.168.0.151"
  "k8s-master-02|192.168.0.152"
  "k8s-master-03|192.168.0.153"
)

k8s_master_nodes=(
	"k8s-master-01|192.168.0.151"
  "k8s-master-02|192.168.0.152"
  "k8s-master-03|192.168.0.153"
)

k8s_worker_nodes=(
  "k8s-worker-01|192.168.0.161"
  "k8s-worker-02|192.168.0.162"
  "k8s-worker-03|192.168.0.163"
)

k8s_control_plane_nodes=(
	"k8s-master-01|192.168.0.151"
)

# 在 k8s-master 中选择一个座位主节点, 其他的作为备用节点
keepalived_master="k8s-master-01"
# 网卡名 使用 ip addr 可以看到
network_interface_name="ens33"
# apiserver使用虚拟ip地址和端口, 要在keepalived中配置转发到 k8s-master 节点上
k8s_apiserver_vip="192.168.0.250"
k8s_apiserver_port="8443"


# k8s pod CIDR
k8s_pod_ip_range="196.16.0.0/16"

# k8s service CIDR
k8s_service_ip_range="10.96.0.0/16"
k8s_service_ip="10.96.0.1"
# coreDns 配置的集群内DNS地址
cluster_dns="10.96.0.10"

# kubelet boostrap 使用的 token
k8s_bootstrap_token_id="c8ad9c"
k8s_bootstrap_token_secret="2e4d610cf3e7426e"


# 工具及安装包的版本, 仅设置版本号, 不要带 "v", 使用的时候会在需要的位置加上 "v"
cfssl_version="1.6.4"
etcd_version="3.5.9"
containerd_version="1.7.5"
cni_plugins_version="1.3.0"
runc_version="1.1.9"
libseccomp_version="2.5.4"
nerdctl_version="1.5.0"
kubernetes_version="1.28.1"
helm_version="3.12.3"
coredns_version="1.26.0"
metrics_server_version="0.6.4"
calico_version="3.26.1"

# 文件路径 
# local_xxx 是执行这个安装脚本的节点上的文件路径, 如果使用相对路径是相对脚本文件的位置
# 本机安装包文件存放路径
local_package_dir="packages"
# 临时目录, 每次脚本会先 ## 清空 ## , 再将安装过程中生成的文件放入这个目录,注意不要指向存有重要数据的目录
local_tmp_dir="tmp"

# remote_xxx 是 k8s 集群中的节点的位置, 文件要先传输过去才能使用
# 远程节点接收文件的基准路径
remote_tmp_dir="/root/tmp"

# 其他参数
# 设置dns列表
dns_server_list="8.8.8.8 114.114.114.114"
# 设置时区
timezone="Asia/Shanghai"
# 设置时间同步服务器
ntp_server="edu.ntp.org.cn"

# 路径及文件名参数, 通常不需要修改
etcd_pki_ca="etcd-ca"
etcd_pki_client="etcd-client"
etcd_pki_dir="/etc/etcd/pki"

k8s_pki_ca="kubernetes-ca"
k8s_pki_etcd_ca="etcd-ca"
k8s_pki_etcd_client="etcd-client"
k8s_pki_kube_apiserver="kube-apiserver"
k8s_pki_service_account="kubernetes-service-account"
k8s_pki_front_proxy_ca="kubebernetes-front-proxy-ca"
k8s_pki_front_proxy_client="kubebernetes-front-proxy-client"


# 工具包本地导出目录
local_tools_save_dir="tools"
# 工具包远程节点临时存放目录
remote_tools_save_dir="/root/tmp/tools"
# ubuntu 22
system_name="jammy"


# 镜像本地导出目录
local_image_save_dir="images"
# 镜像远程节点临时存放目录
remote_image_save_dir="/root/tmp/images"
# 镜像的命名空间
image_namespace=k8s.io

###################################################
#                     参数设置结束                 #
###################################################


# 准备变量

# 安装的工具列表
tools=(
  "psmisc"
  "vim"
  "net-tools"
  "nfs-kernel-server"
  "telnet"
  "lvm2"
  "git"
  "tar"
  "curl"
  "selinux-utils"
  "wget"
  "ipvsadm"
  "ipset"
  "sysstat"
  "conntrack"
  "gnupg2"
  "software-properties-common"
  "apt-transport-https"
  "ca-certificates"
  "ntpdate"
  "gcc"
  "gperf"
  "make"
  "keepalived"
  "haproxy"
  "jq"
)

etcd_hostnames=()
etcd_ips=()
for node in "${etcd_nodes[@]}"; do
  IFS='|' read -r hostname ip <<< "$node"
  etcd_hostnames+=("$hostname")
  etcd_ips+=("$ip")
done

echo "etcd_hostnames"
for name in "${etcd_hostnames[@]}"; do
  echo "$name"
done

echo "etcd_ips:"
for ip in "${etcd_ips[@]}"; do
  echo "$ip"
done

etcd_hostnames_string=${etcd_hostnames[@]}
echo "etcd_hostnames_string:${etcd_hostnames_string}"

etcd_hostnames_string_comma=$(IFS=,; echo "${etcd_hostnames[*]}")
echo "etcd_hostnames_string_comma:${etcd_hostnames_string_comma}"

etcd_ips_string=${etcd_ips[@]}
echo "etcd_ips_string:${etcd_ips_string}"

etcd_ips_string_comma=$(IFS=,; echo "${etcd_ips[*]}")
echo "etcd_ips_string_comma:${etcd_ips_string_comma}"

etcd_urls_string_comma=""
for ip in "${etcd_ips[@]}"; do
  if [ -n "$etcd_urls_string_comma" ]; then
    etcd_urls_string_comma+=","
  fi
  etcd_urls_string_comma+="https://$ip:2379"
done
echo "etcd_urls_string_comma:$etcd_urls_string_comma"



k8s_master_hostnames=()
k8s_master_ips=()
for node in "${k8s_master_nodes[@]}"; do
  IFS='|' read -r hostname ip <<< "$node"
  k8s_master_hostnames+=("$hostname")
  k8s_master_ips+=("$ip")
done

echo "k8s_master_hostnames"
for name in "${k8s_master_hostnames[@]}"; do
  echo "$name"
done

echo "k8s_master_ips:"
for ip in "${k8s_master_ips[@]}"; do
  echo "$ip"
done

k8s_master_hostnames_string=${k8s_master_hostnames[@]}
echo "k8s_master_hostnames_string:${k8s_master_hostnames_string}"

k8s_master_hostnames_string_comma=$(IFS=,; echo "${k8s_master_hostnames[*]}")
echo "k8s_master_hostnames_string_comma:${k8s_master_hostnames_string_comma}"

k8s_master_ips_string=${k8s_master_ips[@]}
echo "k8s_master_ips_string:${k8s_master_ips_string}"

k8s_master_ips_string_comma=$(IFS=,; echo "${k8s_master_ips[*]}")
echo "k8s_master_ips_string_comma:${k8s_master_ips_string_comma}"


k8s_worker_hostnames=()
k8s_worker_ips=()
for node in "${k8s_worker_nodes[@]}"; do
  IFS='|' read -r hostname ip <<< "$node"
  k8s_worker_hostnames+=("$hostname")
  k8s_worker_ips+=("$ip")
done

echo "k8s_worker_hostnames"
for name in "${k8s_worker_hostnames[@]}"; do
  echo "$name"
done

echo "k8s_worker_ips:"
for ip in "${k8s_worker_ips[@]}"; do
  echo "$ip"
done

k8s_worker_hostnames_string=${k8s_worker_hostnames[@]}
echo "k8s_worker_hostnames_string:${k8s_worker_hostnames_string}"

k8s_worker_hostnames_string_comma=$(IFS=,; echo "${k8s_worker_hostnames[*]}")
echo "k8s_worker_hostnames_string_comma:${k8s_worker_hostnames_string_comma}"

k8s_worker_ips_string=${k8s_worker_ips[@]}
echo "k8s_worker_ips_string:${k8s_worker_ips_string}"

k8s_worker_ips_string_comma=$(IFS=,; echo "${k8s_worker_ips[*]}")
echo "k8s_worker_ips_string_comma:${k8s_worker_ips_string_comma}"


tmp_all_k8s_nodes=("${k8s_master_nodes[@]}" "${k8s_worker_nodes[@]}")
k8s_nodes=()
for node in "${tmp_all_k8s_nodes[@]}"; do
  # 判断是否已经保存到 k8s_nodes 中
  if [[ ! " ${k8s_nodes[@]} " =~ " ${node} " ]]; then
    k8s_nodes+=("$node")
  fi
done

k8s_node_hostnames=()
k8s_node_ips=()
for node in "${k8s_nodes[@]}"; do
  IFS='|' read -r hostname ip <<< "$node"
	if [[ ! " ${k8s_node_hostnames[@]} " =~ " ${hostname} " ]]; then
    k8s_node_hostnames+=("$hostname")
  fi
	
  if [[ ! " ${k8s_node_ips[@]} " =~ " ${ip} " ]]; then
    k8s_node_ips+=("$ip")
  fi
done

echo "k8s_node_hostnames"
for name in "${k8s_node_hostnames[@]}"; do
  echo "$name"
done

echo "k8s_node_ips:"
for ip in "${k8s_node_ips[@]}"; do
  echo "$ip"
done

k8s_node_hostnames_string=${k8s_node_hostnames[@]}
echo "k8s_node_hostnames_string:${k8s_node_hostnames_string}"

k8s_node_hostnames_string_comma=$(IFS=,; echo "${k8s_node_hostnames[*]}")
echo "k8s_node_hostnames_string_comma:${k8s_node_hostnames_string_comma}"

k8s_node_ips_string=${k8s_node_ips[@]}
echo "k8s_node_ips_string:${k8s_node_ips_string}"

k8s_node_ips_string_comma=$(IFS=,; echo "${k8s_node_ips[*]}")
echo "k8s_node_ips_string_comma:${k8s_node_ips_string_comma}"


tmp_all_nodes=("${etcd_nodes[@]}" "${k8s_master_nodes[@]}" "${k8s_worker_nodes[@]}" "${k8s_control_plane_nodes[@]}")
cluster_nodes=()
for node in "${tmp_all_nodes[@]}"; do
  # 判断是否已经保存到 cluster_nodes 中
  if [[ ! " ${cluster_nodes[@]} " =~ " ${node} " ]]; then
    cluster_nodes+=("$node")
  fi
done
cluster_node_hostnames=()
cluster_node_ips=()
for node in "${cluster_nodes[@]}"; do
  IFS='|' read -r hostname ip <<< "$node"
  cluster_node_hostnames+=("$hostname")
  cluster_node_ips+=("$ip")
done

echo "cluster_node_hostnames"
for name in "${cluster_node_hostnames[@]}"; do
  echo "$name"
done

echo "cluster_node_ips:"
for ip in "${cluster_node_ips[@]}"; do
  echo "$ip"
done

k8s_control_plane_hostnames=()
k8s_control_plane_ips=()
for node in "${k8s_control_plane_nodes[@]}"; do
  IFS='|' read -r hostname ip <<< "$node"
  k8s_control_plane_hostnames+=("$hostname")
  k8s_control_plane_ips+=("$ip")
done

echo "k8s_control_plane_hostnames"
for name in "${k8s_control_plane_hostnames[@]}"; do
  echo "$name"
done

echo "k8s_control_plane_ips:"
for ip in "${k8s_control_plane_ips[@]}"; do
  echo "$ip"
done


k8s_inner_hostnames=(
  "kubernetes"
  "kubernetes.default"
  "kubernetes.default.svc"
  "kubernetes.default.svc.cluster"
  "kubernetes.default.svc.cluster.local"
)

k8s_inner_hostnames_string=${k8s_inner_hostnames[@]}
echo "k8s_inner_hostnames_string:${k8s_inner_hostnames_string}"

k8s_node_hostnames_string_comma=$(IFS=,; echo "${k8s_inner_hostnames[*]}")
echo "k8s_node_hostnames_string_comma:${k8s_node_hostnames_string_comma}"


k8s_apiserver_url="https://$k8s_apiserver_vip:$k8s_apiserver_port"
echo "k8s_apiserver_url:${k8s_apiserver_url}"


# 下载工具列表
tools_string="${tools[*]}"

packages=(
  "cfssl_${cfssl_version}_linux_amd64|https://github.com/cloudflare/cfssl/releases/download/v${cfssl_version}/cfssl_${cfssl_version}_linux_amd64"

  "cfssljson_${cfssl_version}_linux_amd64|https://github.com/cloudflare/cfssl/releases/download/v${cfssl_version}/cfssljson_${cfssl_version}_linux_amd64"
  
  "etcd-v${etcd_version}-linux-amd64.tar.gz|https://github.com/etcd-io/etcd/releases/download/v${etcd_version}/etcd-v${etcd_version}-linux-amd64.tar.gz"
  
  "containerd-${containerd_version}-linux-amd64.tar.gz|https://github.com/containerd/containerd/releases/download/v${containerd_version}/containerd-${containerd_version}-linux-amd64.tar.gz"
	
	"cni-plugins-linux-amd64-v${cni_plugins_version}.tgz|https://github.com/containernetworking/plugins/releases/download/v${cni_plugins_version}/cni-plugins-linux-amd64-v${cni_plugins_version}.tgz"
    
	"runc-v${runc_version}.amd64|https://github.com/opencontainers/runc/releases/download/v${runc_version}/runc.amd64"
	
  "libseccomp-${libseccomp_version}.tar.gz|https://github.com/seccomp/libseccomp/releases/download/v${libseccomp_version}/libseccomp-${libseccomp_version}.tar.gz"

  "nerdctl-${nerdctl_version}-linux-amd64.tar.gz|https://github.com/containerd/nerdctl/releases/download/v${nerdctl_version}/nerdctl-${nerdctl_version}-linux-amd64.tar.gz"

  "kubernetes-server-${kubernetes_version}-linux-amd64.tar.gz|https://dl.k8s.io/v${kubernetes_version}/kubernetes-server-linux-amd64.tar.gz"
  
  "helm-v${helm_version}-linux-amd64.tar.gz|https://get.helm.sh/helm-v${helm_version}-linux-amd64.tar.gz"
  
  "coredns-${coredns_version}.tgz|https://github.com/coredns/helm/releases/download/coredns-${coredns_version}/coredns-${coredns_version}.tgz"

  # https://docs.projectcalico.org/manifests/calico.yaml
  "calico-v${calico_version}.yaml|https://raw.githubusercontent.com/projectcalico/calico/v${calico_version}/manifests/calico.yaml"
  
  "metrics-server-v${metrics_server_version}_high-availability-1.21+.yaml|https://github.com/kubernetes-sigs/metrics-server/releases/download/v${metrics_server_version}/high-availability-1.21+.yaml"
)

echo "###############################"
echo "#             start           #"
echo "###############################"

echo "###############################"
echo "#  set env for cluster node   #"
echo "###############################"

# 设置 hostname
echo "set hostname"
for node in "${cluster_nodes[@]}"; do
  IFS='|' read -r hostname ip <<< "$node"
  echo "set hostname as $hostname in $ip"
  ssh "root@$ip" "hostnamectl set-hostname $hostname"
done

# 将ip host 信息添加到 /etc/hosts 文件
# 生成要添加到 /etc/hosts 的内容
echo "set hosts"
for node_info in "${cluster_nodes[@]}"; do
    IFS='|' read -r hostname ip <<< "$node_info"
    hosts_content="$ip $hostname"
	
	for remote_ip in "${cluster_node_ips[@]}"; do
		ssh "root@$remote_ip" "grep -Fq \"${hosts_content}\" /etc/hosts || echo -e \"$hosts_content\" >> /etc/hosts"
	done
	
	grep -Fq "${hosts_content}" /etc/hosts || echo -e "${hosts_content}" >> /etc/hosts
done
echo "set hosts finished"

# hello
echo "hello"
for node in "${cluster_node_hostnames[@]}"; do
  ssh "root@$node" "echo \"hello from $node\""
done
echo "hello finished"


# 更新系统
echo "update and upgrade"
for node in "${cluster_node_hostnames[@]}"; do
	(
		echo "update and upgrade in $node"
		ssh "root@$node" "apt update && apt upgrade -y"
	) &    
done
wait
echo "update and upgrade finished"


# 安装工具
echo "install tools"
for node in "${cluster_node_hostnames[@]}"; do
	(
		echo "install tools in ${node}, tools:${tools_string}"
		ssh "root@$node" "apt install -y ${tools_string}"
	) &
done
wait
echo "install tools finished"


# 修改DNS
echo "set dns server"
file_name="/etc/systemd/resolved.conf"
file_append_content="[Resolve]\nDNS=${dns_server_list}"

# Loop through the remote nodes
for node in "${cluster_node_hostnames[@]}"; do
  # Check if the file exists
  ssh "root@$node" "[ -e $file_name ]"
  if [ $? -eq 0 ]; then
    # Check if content exists in the file
    ssh "root@$node" "grep -q '^$file_append_content' $file_name"
    if [ $? -ne 0 ]; then
      # Append content to the file
      ssh "root@$node" "echo '$file_append_content' >> $file_name"
      echo "Added $file_append_content to $file_name on $node_name"
    else
      echo "$file_append_content already exists in $file_name on $node_name"
    fi
  else
    # Create the file and write content to it
    ssh "root@$node" "echo '$file_append_content' > $file_name"
    echo "Created $file_name with $file_append_content on $node_name"
  fi
done


# 设置时区
echo "set timezone"
for node in "${cluster_node_hostnames[@]}"; do
	(
		echo "set timezone to ${timezone} in $node"
		ssh "root@$node" "timedatectl set-timezone ${timezone}"
		# ntp 同步时钟
		ssh "root@$node" "ntpdate ${ntp_server}"
	) &    
done
wait


echo "#######################################"
echo "#   check install package and tools   #"
echo "#######################################"

# 下载安装包
echo "download packages"
for package in "${packages[@]}"; do
  IFS='|' read -r filename remote_url <<< "$package"
  
  # 检查本地是否存在文件
  if [ ! -f "${local_package_dir}/$filename" ]; then
    echo "file $filename not exists, downloading..."
    wget "$remote_url" -O "${local_package_dir}/$filename"
    if [ $? -eq 0 ]; then
      echo "download finished"
    else
      echo "download failed"
    fi
  else
    echo "$filename exists, skip downloading"
  fi
done
echo "download packages finished"


echo "###############################"
echo "#    set env for k8s node     #"
echo "###############################"

# 关闭selinux
echo "disable selinux"
file_name="/etc/selinux/config"
file_append_content="SELINUX=disabled"

# Loop through the remote nodes
for node in "${k8s_node_hostnames[@]}"; do
  # Check if the file exists
  ssh "root@$node" "[ -e $file_name ]"
  if [ $? -eq 0 ]; then
    # Check if content exists in the file
    ssh "root@$node" "grep -q '^$file_append_content' $file_name"
    if [ $? -ne 0 ]; then
      # Append content to the file
      ssh "root@$node" "echo '$file_append_content' >> $file_name"
      echo "Added $file_append_content to $file_name on $node_name"
    else
      echo "$file_append_content already exists in $file_name on $node_name"
    fi
  else
    # Create the file and write content to it
    ssh "root@$node" "echo '$file_append_content' > $file_name"
    echo "Created $file_name with $file_append_content on $node_name"
  fi
done


# 关闭交换分区
echo "swap off"
for node in "${k8s_node_hostnames[@]}"; do
  echo "swap off in $node"
  ssh "root@$node" "swapoff -a && sysctl -w vm.swappiness=0"
  ssh "root@$node" "sed -i '/^\/swap.img/ s/^/#/' /etc/fstab"
done


# 修改资源限制
echo "set ulimit"
ulimit -SHn 65535
file_name="/etc/security/limits.conf"
file_append_content="
* soft nofile 655360
* hard nofile 131072
* soft nproc 655350
* hard nproc 655350
* soft memlock unlimited
* hard memlock unlimited
"

# Loop through the remote nodes
for node in "${k8s_node_hostnames[@]}"; do
  # Check if the file exists
  ssh "root@$node" "[ -e $file_name ]"
  if [ $? -eq 0 ]; then
    # Check if content exists in the file
    ssh "root@$node" "grep -Fq '^$file_append_content' $file_name"
    if [ $? -ne 0 ]; then
      # Append content to the file
      ssh "root@$node" "echo '$file_append_content' >> $file_name"
      echo "Added $file_append_content to $file_name on $node_name"
    else
      echo "$file_append_content already exists in $file_name on $node_name"
    fi
  else
    # Create the file and write content to it
    ssh "root@$node" "echo '$file_append_content' > $file_name"
    echo "Created $file_name with $file_append_content on $node_name"
  fi
done



# 启用 ipvs
echo "enable ipvs"
file_name="/etc/modules-load.d/ipvs.conf"
file_append_content="
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
nf_conntrack
ip_tables
ip_set
xt_set
ipt_set
ipt_rpfilter
ipt_REJECT
ipip
"

# Loop through the remote nodes
for node in "${k8s_node_hostnames[@]}"; do
  # Check if the file exists
  ssh "root@$node" "[ -e $file_name ]"
  if [ $? -eq 0 ]; then
    # Check if content exists in the file
    ssh "root@$node" "grep -Fq '^$file_append_content' $file_name"
    if [ $? -ne 0 ]; then
      # Append content to the file
      ssh "root@$node" "echo '$file_append_content' >> $file_name"
      echo "Added $file_append_content to $file_name on $node_name"
      ssh "root@$node" "systemctl restart systemd-modules-load.service"
    else
      echo "$file_append_content already exists in $file_name on $node_name"
    fi
  else
    # Create the file and write content to it
    ssh "root@$node" "echo '$file_append_content' > $file_name"
    echo "Created $file_name with $file_append_content on $node_name"
    ssh "root@$node" "systemctl restart systemd-modules-load.service"
  fi
done


# 修改内核参数
echo "update kernal param for kubernetes"
file_name="/etc/sysctl.d/k8s.conf"
file_append_content="
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
fs.may_detach_mounts = 1
vm.overcommit_memory=1
vm.panic_on_oom=0
fs.inotify.max_user_watches=89100
fs.file-max=52706963
fs.nr_open=52706963
net.netfilter.nf_conntrack_max=2310720

net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl =15
net.ipv4.tcp_max_tw_buckets = 36000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_orphans = 327680
net.ipv4.tcp_orphan_retries = 3
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.ip_conntrack_max = 65536
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.tcp_timestamps = 0
net.core.somaxconn = 16384

net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.lo.disable_ipv6 = 0
net.ipv6.conf.all.forwarding = 1
"

# Loop through the remote nodes
for node in "${k8s_node_hostnames[@]}"; do
  # Check if the file exists
  ssh "root@$node" "[ -e $file_name ]"
  if [ $? -eq 0 ]; then
    # Check if content exists in the file
    ssh "root@$node" "grep -Fq '^$file_append_content' $file_name"
    if [ $? -ne 0 ]; then
      # Append content to the file
      ssh "root@$node" "echo '$file_append_content' >> $file_name"
      echo "Added $file_append_content to $file_name on $node_name"
      ssh "root@$node" "sysctl --system"
    else
        echo "$file_append_content already exists in $file_name on $node_name"
    fi
  else
    # Create the file and write content to it
    ssh "root@$node" "echo '$file_append_content' > $file_name"
    echo "Created $file_name with $file_append_content on $node_name"
    ssh "root@$node" "sysctl --system"
  fi
done



echo "###############################"
echo "#  start install modules      #"
echo "###############################"

# 清理本地的临时目录
echo "clean dirs in local and cluster nodes"
mkdir -p ${local_tmp_dir}
rm -rf ${local_tmp_dir}/*

# 清理集群节点的临时目录
for node in "${cluster_node_hostnames[@]}"; do
  ssh "root@$node" "mkdir -p ${remote_tmp_dir}"
  ssh "root@$node" "rm -rf ${remote_tmp_dir}/*"
done

# 安装 containerd
echo "###############################"
echo "#    install contained        #"
echo "###############################"

mkdir ${local_tmp_dir}/containerd
rm -rf mkdir ${local_tmp_dir}/containerd/*

echo "clean containerd"
for node in "${k8s_node_hostnames[@]}"; do
  ssh "root@$node" "systemctl is-active containerd.service && systemctl stop containerd.service"
  ssh "root@$node" "[ -f /etc/systemd/system/containerd.service ] && rm /etc/systemd/system/containerd.service"
done

# 将 containerd 安装包分发到所有的 k8s 节点
echo "copying contained install package to k8s nodes"

for node in "${k8s_node_hostnames[@]}"; do
  echo "copy containerd install package to ${node} "
  ssh root@${node} "mkdir -p ${remote_tmp_dir}/containerd"
  ssh root@${node} "rm -rf ${remote_tmp_dir}/containerd/*"
  scp ${local_package_dir}/containerd-${containerd_version}-linux-amd64.tar.gz root@${node}:${remote_tmp_dir}/containerd/containerd-${containerd_version}-linux-amd64.tar.gz
  ssh "root@$node" "tar -xzvf ${remote_tmp_dir}/containerd/containerd-${containerd_version}-linux-amd64.tar.gz -C /usr/local"
done

# 配置 containerd 所需的模块
file_name="/etc/modules-load.d/containerd.conf"
file_content="
modprobe
overlay
br_netfilter
"
for node in "${k8s_node_hostnames[@]}"; do
  ssh "root@$node" "echo '$file_content' > ${file_name}"
	# 加载模块
	ssh "root@$node" "systemctl restart systemd-modules-load.service"
done


# 配置 containerd 所需的内核
file_name="/etc/sysctl.d/99-kubernetes-cri.conf"
file_content="
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
"
for node in "${k8s_node_hostnames[@]}"; do
  ssh "root@$node" "echo '$file_content' > ${file_name}"
	# 加载模块
	ssh "root@$node" "sysctl --system"
done


# 生成并修改containerd配置文件
tar -zxvf ${local_package_dir}/containerd-${containerd_version}-linux-amd64.tar.gz -C ${local_tmp_dir}/containerd
${local_tmp_dir}/containerd/bin/containerd config default > ${local_tmp_dir}/containerd/config.toml
# 修改
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' ${local_tmp_dir}/containerd/config.toml
sed -i "s#config_path\ \=\ \"\"#config_path\ \=\ \"/etc/containerd/certs.d\"#g" ${local_tmp_dir}/containerd/config.toml
sed -i "s|registry.k8s.io/pause:3.8|registry.k8s.io/pause:3.9|"  ${local_tmp_dir}/containerd/config.toml
# 发送到 k8s 的所有节点
for node in "${k8s_node_hostnames[@]}"; do
  ssh root@$node "mkdir -p /etc/containerd"
  ssh root@$node "[ -f /etc/containerd/config.toml ] && rm /etc/containerd/config.toml"
  scp ${local_tmp_dir}/containerd/config.toml root@$node:/etc/containerd/config.toml
done

# 在本机生成镜像仓库代理配置文件
mkdir -p ${local_tmp_dir}/containerd/certs.d 
rm -rf ${local_tmp_dir}/containerd/certs.d/*

# docker hub镜像加速
mkdir -p ${local_tmp_dir}/containerd/certs.d/docker.io
cat > ${local_tmp_dir}/containerd/certs.d/docker.io/hosts.toml << EOF
server = "https://docker.io"
[host."https://dockerproxy.com"]
  capabilities = ["pull", "resolve"]

[host."https://docker.m.daocloud.io"]
  capabilities = ["pull", "resolve"]

[host."https://reg-mirror.qiniu.com"]
  capabilities = ["pull", "resolve"]

[host."https://registry.docker-cn.com"]
  capabilities = ["pull", "resolve"]

[host."http://hub-mirror.c.163.com"]
  capabilities = ["pull", "resolve"]

EOF

# registry.k8s.io镜像加速
mkdir -p ${local_tmp_dir}/containerd/certs.d/registry.k8s.io
tee ${local_tmp_dir}/containerd/certs.d/registry.k8s.io/hosts.toml << 'EOF'
server = "https://registry.k8s.io"

[host."https://k8s.m.daocloud.io"]
  capabilities = ["pull", "resolve", "push"]
EOF

# docker.elastic.co镜像加速
mkdir -p ${local_tmp_dir}/containerd/certs.d/docker.elastic.co
tee ${local_tmp_dir}/containerd/certs.d/docker.elastic.co/hosts.toml << 'EOF'
server = "https://docker.elastic.co"

[host."https://elastic.m.daocloud.io"]
  capabilities = ["pull", "resolve", "push"]
EOF

# gcr.io镜像加速
mkdir -p ${local_tmp_dir}/containerd/certs.d/gcr.io
tee ${local_tmp_dir}/containerd/certs.d/gcr.io/hosts.toml << 'EOF'
server = "https://gcr.io"

[host."https://gcr.m.daocloud.io"]
  capabilities = ["pull", "resolve", "push"]
EOF

# ghcr.io镜像加速
mkdir -p ${local_tmp_dir}/containerd/certs.d/ghcr.io
tee ${local_tmp_dir}/containerd/certs.d/ghcr.io/hosts.toml << 'EOF'
server = "https://ghcr.io"

[host."https://ghcr.m.daocloud.io"]
  capabilities = ["pull", "resolve", "push"]
EOF

# k8s.gcr.io镜像加速
mkdir -p ${local_tmp_dir}/containerd/certs.d/k8s.gcr.io
tee ${local_tmp_dir}/containerd/certs.d/k8s.gcr.io/hosts.toml << 'EOF'
server = "https://k8s.gcr.io"

[host."https://k8s-gcr.m.daocloud.io"]
  capabilities = ["pull", "resolve", "push"]
EOF

# mcr.m.daocloud.io镜像加速
mkdir -p ${local_tmp_dir}/containerd/certs.d/mcr.microsoft.com
tee ${local_tmp_dir}/containerd/certs.d/mcr.microsoft.com/hosts.toml << 'EOF'
server = "https://mcr.microsoft.com"

[host."https://mcr.m.daocloud.io"]
  capabilities = ["pull", "resolve", "push"]
EOF

# nvcr.io镜像加速
mkdir -p ${local_tmp_dir}/containerd/certs.d/nvcr.io
tee ${local_tmp_dir}/containerd/certs.d/nvcr.io/hosts.toml << 'EOF'
server = "https://nvcr.io"

[host."https://nvcr.m.daocloud.io"]
  capabilities = ["pull", "resolve", "push"]
EOF

# quay.io镜像加速
mkdir -p ${local_tmp_dir}/containerd/certs.d/quay.io
tee ${local_tmp_dir}/containerd/certs.d/quay.io/hosts.toml << 'EOF'
server = "https://quay.io"

[host."https://quay.m.daocloud.io"]
  capabilities = ["pull", "resolve", "push"]
EOF

# registry.jujucharms.com镜像加速
mkdir -p ${local_tmp_dir}/containerd/certs.d/registry.jujucharms.com
tee ${local_tmp_dir}/containerd/certs.d/registry.jujucharms.com/hosts.toml << 'EOF'
server = "https://registry.jujucharms.com"

[host."https://jujucharms.m.daocloud.io"]
  capabilities = ["pull", "resolve", "push"]
EOF

# rocks.canonical.com镜像加速
mkdir -p ${local_tmp_dir}/containerd/certs.d/rocks.canonical.com
tee ${local_tmp_dir}/containerd/certs.d/rocks.canonical.com/hosts.toml << 'EOF'
server = "https://rocks.canonical.com"

[host."https://rocks-canonical.m.daocloud.io"]
  capabilities = ["pull", "resolve", "push"]
EOF

# 将containerd的镜像仓库代理配置文件发送到各个节点
for node in "${k8s_node_hostnames[@]}"; do
	ssh "root@$node" "mkdir -p /etc/containerd/certs.d"
  echo "copying contained repository proxy settings file to $node"
  scp -r ${local_tmp_dir}/containerd/certs.d/* root@$node:/etc/containerd/certs.d/
done

# https://github.com/containerd/containerd/blob/main/docs/getting-started.md
# download the containerd.service unit file from 
# https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
# into /usr/local/lib/systemd/system/containerd.service

# 配置 containerd.service
file_name="/usr/lib/systemd/system/containerd.service"
file_content="
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target local-fs.target

[Service]
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/local/bin/containerd
Type=notify
Delegate=yes
KillMode=process
Restart=always
RestartSec=5
LimitNPROC=infinity
LimitCORE=infinity
LimitNOFILE=infinity
TasksMax=infinity
OOMScoreAdjust=-999

[Install]
WantedBy=multi-user.target
"
for node in "${k8s_node_hostnames[@]}"; do
  ssh "root@$node" "echo '${file_content}' > ${file_name}"
done

# installing CNI plugins
echo "installing CNI plugins"
for node in "${k8s_node_hostnames[@]}"; do
  echo "installing CNI plugins for ${node}"
  ssh root@${node} "mkdir -p /opt/cni/bin"
  ssh root@${node} "rm -rf /opt/cni/bin/*"
  ssh root@${node} "mkdir -p ${remote_tmp_dir}/cni-plugins"
  ssh root@${node} "rm -rf ${remote_tmp_dir}/cni-plugins/*"
  scp ${local_package_dir}/cni-plugins-linux-amd64-v${cni_plugins_version}.tgz root@${node}:${remote_tmp_dir}/cni-plugins/cni-plugins-linux-amd64-v${cni_plugins_version}.tgz
  ssh root@${node} "tar -xzvf ${remote_tmp_dir}/cni-plugins/cni-plugins-linux-amd64-v${cni_plugins_version}.tgz -C /opt/cni/bin"
  echo "installing cni-plugins for ${node} finished"
done
echo "installing CNI plugins finished"

# 创建 cni plugins 配置文件
cat > ${local_tmp_dir}/containerd/10-containerd-net.conflist << EOF
{
  "cniVersion": "1.0.0",
  "name": "containerd-net",
  "plugins": [
    {
      "type": "bridge",
      "bridge": "cni0",
      "isGateway": true,
      "ipMasq": true,
      "promiscMode": true,
      "ipam": {
        "type": "host-local",
        "ranges": [
          [{
            "subnet": "10.88.0.0/16"
          }],
          [{
            "subnet": "2001:4860:4860::/64"
          }]
        ],
        "routes": [
          { "dst": "0.0.0.0/0" },
          { "dst": "::/0" }
        ]
      }
    },
    {
      "type": "portmap",
      "capabilities": {"portMappings": true}
    }
  ]
}
EOF
for node in "${k8s_node_hostnames[@]}"; do
  ssh "root@$node" "mkdir -p /etc/cni/net.d"
  scp ${local_tmp_dir}/containerd/10-containerd-net.conflist root@$node:/etc/cni/net.d/10-containerd-net.conflist
done

# install libseccomp
echo "installing libseccomp"
# 先安装依赖工具
for node in "${k8s_node_hostnames[@]}"; do
  (
    ssh root@${node} "apt install -y gcc make gperf"
  ) &
done
wait

for node in "${k8s_node_hostnames[@]}"; do
  echo "installing libseccomp for ${node}"
  ssh root@${node} "mkdir -p ${remote_tmp_dir}/libseccomp"
  ssh root@${node} "rm -rf ${remote_tmp_dir}/libseccomp/*"
  scp ${local_package_dir}/libseccomp-${libseccomp_version}.tar.gz root@${node}:${remote_tmp_dir}/libseccomp/libseccomp-${libseccomp_version}.tar.gz
  
  ssh root@${node} "tar -zxvf ${remote_tmp_dir}/libseccomp/libseccomp-${libseccomp_version}.tar.gz -C ${remote_tmp_dir}/libseccomp/"
  ssh root@${node} "cd ${remote_tmp_dir}/libseccomp/libseccomp-${libseccomp_version} && ./configure --disable-dependency-tracking && make && make install"
  echo "installing libseccomp for ${node} finished"
done
echo "installing libseccomp finished"

# installing runc
echo "installing runc"
for node in "${k8s_node_hostnames[@]}"; do
  echo "installing runc for ${node}"
  ssh root@${node} "mkdir -p ${remote_tmp_dir}/runc"
  ssh root@${node} "rm -rf ${remote_tmp_dir}/runc/*"
  scp ${local_package_dir}/runc-v${runc_version}.amd64 root@${node}:${remote_tmp_dir}/runc/runc-v${runc_version}.amd64
  ssh root@${node} "install -m 755 ${remote_tmp_dir}/runc/runc-v${runc_version}.amd64 /usr/local/sbin/runc"
  echo "installing runc for ${node} finished"
done
echo "installing runc finished"


# 启动containerd.service
for node in "${k8s_node_hostnames[@]}"; do
  ssh "root@$node" "systemctl daemon-reload"
  ssh "root@$node" "systemctl enable --now containerd.service"
done

# 安装 nerdctl
echo "install nerdctl"
for node in "${k8s_node_hostnames[@]}"; do
  echo "install nerdctl for $node"
  ssh "root@$node" "mkdir -p ${remote_tmp_dir}/nerdctl"
  ssh "root@$node" "rm -rf ${remote_tmp_dir}/nerdctl/*"
  scp ${local_package_dir}/nerdctl-${nerdctl_version}-linux-amd64.tar.gz root@$node:${remote_tmp_dir}/nerdctl/nerdctl-${nerdctl_version}-linux-amd64.tar.gz
  ssh "root@$node" "tar -xzvf ${remote_tmp_dir}/nerdctl/nerdctl-${nerdctl_version}-linux-amd64.tar.gz -C /usr/local/bin"
done
echo "install nerdctl finished"


# 如果本机存在预先导出的镜像则将镜像发送至各个节点, 导入镜像
if [ -d "${local_image_save_dir}" ]; then
  echo "send images to k8s-nodes"
  for node in "${k8s_node_hostnames[@]}"; do
    ssh "root@${node}" "mkdir -p ${remote_image_save_dir}"
    ssh "root@${node}" "rm -rf ${remote_image_save_dir}/*"

    echo "cpoying images to ${node}"
    scp "${local_image_save_dir}"/* "root@${node}:${remote_image_save_dir}/"
    
    for filename in $(ls ${local_image_save_dir}); do
      echo "load ${remote_image_save_dir}/${filename} in ${node}"
      ssh "root@${node}" "nerdctl load --namespace=${image_namespace} -i ${remote_image_save_dir}/${filename}"
    done
    echo "load images on ${node} finished"
  done
  
fi
echo "load images finished"


##################################
#     安装 cfssl cfssljson       #
##################################

echo "install cfssl cfssljson to local node"
cp ${local_package_dir}/cfssl_${cfssl_version}_linux_amd64 /usr/local/bin/cfssl
cp ${local_package_dir}/cfssljson_${cfssl_version}_linux_amd64 /usr/local/bin/cfssljson
chmod +x /usr/local/bin/cfssl /usr/local/bin/cfssljson
echo "install cfssl cfssljson to local node finished"



##########################
#        安装 etcd       #
##########################

# 准备 etcd 安装过程使用的临时目录
mkdir -p ${local_tmp_dir}/etcd
rm -rf ${local_tmp_dir}/etcd/*

# 准备 etcd 可执行文件目录
mkdir -p ${local_tmp_dir}/etcd/bin
rm -rf ${local_tmp_dir}/etcd/bin/*

for node in "${etcd_hostnames[@]}"; do
  ssh root@${node} "mkdir -p /etc/etcd"
  ssh root@${node} "rm -rf /etc/etcd/*"
done


tar -zxvf ${local_package_dir}/etcd-v${etcd_version}-linux-amd64.tar.gz -C ${local_tmp_dir}/etcd/bin
echo "copying etcd etcdctl"
for node in "${etcd_hostnames[@]}"; do
  echo "copying etcd etcdctl to $node"
  ssh root@${node} "systemctl is-active etcd.service && systemctl stop etcd.service"
  ssh root@${node} "[ -f /usr/local/bin/etcd ] && rm /usr/local/bin/etcd"
  ssh root@${node} "[ -f /usr/local/bin/etcdctl ] && rm /usr/local/bin/etcdctl"

  # 将可执行文件发送到所有的etcd节点 /usr/local/bin/ 目录下
  scp ${local_tmp_dir}/etcd/bin/etcd-v${etcd_version}-linux-amd64/etcd root@$node:/usr/local/bin/
  scp ${local_tmp_dir}/etcd/bin/etcd-v${etcd_version}-linux-amd64/etcdctl root@$node:/usr/local/bin/
  echo "copying etcd etcdctl to $node finished"
done
echo "copying etcd etcdctl finished"

# 生成 etcd 使用的证书
echo "generate ectd pki"

# 存放证书配置
mkdir -p ${local_tmp_dir}/etcd/etcd-pki-config
rm -rf ${local_tmp_dir}/etcd/etcd-pki-config/*

# 存放生成的证书
mkdir -p ${local_tmp_dir}/etcd/etcd-pki
rm -rf ${local_tmp_dir}/etcd/etcd-pki/*

# 生成 etcd pki 配置, 对各种 Profile 进行参数设置
cat > ${local_tmp_dir}/etcd/etcd-pki-config/etcd-pki-config.json << EOF 
{
  "signing": {
    "default": {
      "expiry": "876000h"
    },
    "profiles": {
      "kubernetes": {
        "usages": [
            "signing",
            "key encipherment",
            "server auth",
            "client auth"
        ],
        "expiry": "876000h"
      }
    }
  }
}
EOF

# 生成 etcd ca 证书的申请书
cat > ${local_tmp_dir}/etcd/etcd-pki-config/${etcd_pki_ca}-csr.json  << EOF 
{
  "CN": "etcd",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "Beijing",
      "L": "Beijing",
      "O": "etcd",
      "OU": "Etcd Security"
    }
  ],
  "ca": {
    "expiry": "876000h"
  }
}
EOF

# 生成 etcd ca 证书
cfssl gencert -initca ${local_tmp_dir}/etcd/etcd-pki-config/${etcd_pki_ca}-csr.json | cfssljson -bare ${local_tmp_dir}/etcd/etcd-pki/${etcd_pki_ca}


# 生成 etcd 客户端证书的申请书
cat > ${local_tmp_dir}/etcd/etcd-pki-config/${etcd_pki_client}-csr.json << EOF 
{
  "CN": "etcd",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "Beijing",
      "L": "Beijing",
      "O": "etcd",
      "OU": "Etcd Security"
    }
  ]
}
EOF

cfssl gencert \
-ca=${local_tmp_dir}/etcd/etcd-pki/${etcd_pki_ca}.pem \
-ca-key=${local_tmp_dir}/etcd/etcd-pki/${etcd_pki_ca}-key.pem \
-config=${local_tmp_dir}/etcd/etcd-pki-config/etcd-pki-config.json \
-hostname=127.0.0.1,${etcd_hostnames_string_comma},${etcd_ips_string_comma} \
-profile=kubernetes \
${local_tmp_dir}/etcd/etcd-pki-config/${etcd_pki_client}-csr.json | cfssljson -bare ${local_tmp_dir}/etcd/etcd-pki/${etcd_pki_client}

# 将 etcd 的证书发送到 etcd 节点
for node in "${etcd_hostnames[@]}"; do
  ssh "root@$node" "mkdir -p ${etcd_pki_dir}"
  ssh "root@$node" "rm -rf ${etcd_pki_dir}/*"
  for file in ${etcd_pki_ca}-key.pem ${etcd_pki_ca}.pem ${etcd_pki_client}-key.pem ${etcd_pki_client}.pem; do
    scp ${local_tmp_dir}/etcd/etcd-pki/${file} root@$node:${etcd_pki_dir}/${file};
  done
done


# 创建保存 etcd 配置文件的目录
mkdir -p ${local_tmp_dir}/etcd/etcd-config
rm -rf ${local_tmp_dir}/etcd/etcd-config/*


initial_cluster=""
for node in "${etcd_nodes[@]}"; do
    IFS='|' read -ra node_info <<< "$node"
    node_name="${node_info[0]}"
    node_ip="${node_info[1]}"
    
    if [ -n "$initial_cluster" ]; then
        initial_cluster+=","
    fi
    initial_cluster+="$node_name=https://$node_ip:2380"
done


echo "generate etcd conf file"
for node in "${etcd_nodes[@]}"; do
  IFS='|' read -ra node_info <<< "$node"
  node_name="${node_info[0]}"
  node_ip="${node_info[1]}"
  
  cat > ${local_tmp_dir}/etcd/etcd-config/${node_name}-config.yaml << EOF
name: '${node_name}'
data-dir: /var/lib/etcd
wal-dir: /var/lib/etcd/wal
snapshot-count: 5000
heartbeat-interval: 100
election-timeout: 1000
quota-backend-bytes: 0
listen-peer-urls: 'https://${node_ip}:2380'
listen-client-urls: 'https://${node_ip}:2379,http://127.0.0.1:2379'
max-snapshots: 3
max-wals: 5
cors:
initial-advertise-peer-urls: 'https://${node_ip}:2380'
advertise-client-urls: 'https://${node_ip}:2379'
discovery:
discovery-fallback: 'proxy'
discovery-proxy:
discovery-srv:
initial-cluster: '${initial_cluster}'
initial-cluster-token: 'etcd-k8s-cluster'
initial-cluster-state: 'new'
strict-reconfig-check: false
enable-v2: true
enable-pprof: true
proxy: 'off'
proxy-failure-wait: 5000
proxy-refresh-interval: 30000
proxy-dial-timeout: 1000
proxy-write-timeout: 5000
proxy-read-timeout: 0
client-transport-security:
  cert-file: '${etcd_pki_dir}/${etcd_pki_client}.pem'
  key-file: '${etcd_pki_dir}/${etcd_pki_client}-key.pem'
  client-cert-auth: true
  trusted-ca-file: '${etcd_pki_dir}/${etcd_pki_ca}.pem'
  auto-tls: true
peer-transport-security:
  cert-file: '${etcd_pki_dir}/${etcd_pki_client}.pem'
  key-file: '${etcd_pki_dir}/${etcd_pki_client}-key.pem'
  peer-client-cert-auth: true
  trusted-ca-file: '${etcd_pki_dir}/${etcd_pki_ca}.pem'
  auto-tls: true
debug: false
log-package-levels:
log-outputs: [default]
force-new-cluster: false
EOF
    
  echo "etcd configuration file ${local_tmp_dir}/etcd/etcd-config/${node_name}-config.yaml created for $node_name"
done
echo "generate etcd conf file finished"


# 将配置文件发送到对应的etcd节点, 并保存为 ${etcd_conf_dir}/ 如/etc/etcd/conf/etcd-config.yml
echo "copying etcd conf file"
for node in "${etcd_hostnames[@]}"; do
  echo "copying etcd conf file for $node"
  ssh "root@$node" "mkdir -p /etc/etcd/conf"
  ssh "root@$node" "rm -rf /etc/etcd/conf/*"
  scp ${local_tmp_dir}/etcd/etcd-config/${node}-config.yaml root@$node:/etc/etcd/conf/etcd-config.yml
  echo "copying etcd conf file for $node finished"
done
echo "copying etcd conf file finished"


cat > ${local_tmp_dir}/etcd/etcd.service << EOF
[Unit]
Description=Etcd Service
Documentation=https://coreos.com/etcd/docs/latest/
After=network.target

[Service]
Type=notify
ExecStart=/usr/local/bin/etcd --config-file=/etc/etcd/conf/etcd-config.yml
Restart=on-failure
RestartSec=10
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
Alias=etcd3.service
EOF


# 将配置文件发送到对应的etcd节点, 并保存为 /etc/etcd/etcd.config.yml
echo "copying etcd.service and start etcd.service"
for node in "${etcd_hostnames[@]}"; do
  ssh root@${node} "[ -f /usr/lib/systemd/system/etcd.service ] && rm /usr/lib/systemd/system/etcd.service"
  scp ${local_tmp_dir}/etcd/etcd.service root@$node:/usr/lib/systemd/system/etcd.service
done

# 启动 etcd.service
echo "start etcd.service"
for node in "${etcd_hostnames[@]}"; do
  (
    echo "start etcd.service for ${node}"
    ssh "root@$node" "systemctl daemon-reload"
    ssh "root@$node" "systemctl enable --now etcd.service"
  ) &
done
wait
echo "start etcd.service finished"



echo ########################################
echo #    install haproxy and keepalived    #
echo ########################################
# 在 k8s-master 节点上安装 haproxy keepalived 
echo "start installing keepalived haproxy"
for node in "${k8s_master_hostnames[@]}"; do
  echo "start installing keepalived haproxy for ${node}"
  ssh "root@$node" "apt install -y keepalived haproxy"
done

mkdir -p ${local_tmp_dir}/haproxy
rm -rf ${local_tmp_dir}/haproxy/*

for node in "${k8s_master_hostnames[@]}"; do
    ssh root@$node "mkdir -p /etc/haproxy"
done

server_list=""
for node in "${k8s_master_nodes[@]}"; do
    IFS='|' read -ra node_info <<< "$node"
    node_name="${node_info[0]}"
    node_ip="${node_info[1]}"
    server_list+=" server $node_name $node_ip:6443 check"$'\n'
done

cat >${local_tmp_dir}/haproxy/haproxy.cfg<<EOF
global
 maxconn 2000
 ulimit-n 16384
 log 127.0.0.1 local0 err
 stats timeout 30s

defaults
 log global
 mode http
 option httplog
 timeout connect 5000
 timeout client 50000
 timeout server 50000
 timeout http-request 15s
 timeout http-keep-alive 15s


frontend monitor-in
 bind *:33305
 mode http
 option httplog
 monitor-uri /monitor

frontend k8s-master
 bind 0.0.0.0:${k8s_apiserver_port}
 bind 127.0.0.1:${k8s_apiserver_port}
 mode tcp
 option tcplog
 tcp-request inspect-delay 5s
 default_backend k8s-master


backend k8s-master
 mode tcp
 option tcplog
 option tcp-check
 balance roundrobin
 default-server inter 10s downinter 5s rise 2 fall 2 slowstart 60s maxconn 250 maxqueue 256 weight 100
# server  k8s-master01  192.168.0.151:6443 check
# server  k8s-master02  192.168.0.152:6443 check
# server  k8s-master03  192.168.0.153:6443 check
${server_list}
EOF

# 将生成的配置文件发送到所有的 k8s-master 节点并保存为 /etc/haproxy/haproxy.cfg
for node in "${k8s_master_hostnames[@]}"; do
    echo "copying haproxy.cfg to $node"
    ssh root@$node "[ -f /etc/haproxy/haproxy.cfg ] && rm /etc/haproxy/haproxy.cfg"
    scp ${local_tmp_dir}/haproxy/haproxy.cfg root@$node:/etc/haproxy/haproxy.cfg
done


# 生成 keepalived 配置文件
mkdir ${local_tmp_dir}/keepalived
rm -rf mkdir ${local_tmp_dir}/keepalived/*

for node in "${k8s_master_hostnames[@]}"; do
    ssh root@$node "mkdir -p /etc/keepalived"
done

# 生成健康检查脚本
cat > ${local_tmp_dir}/keepalived/check_apiserver.sh << EOF
#!/bin/bash

err=0
for k in \$(seq 1 3)
do
    check_code=\$(pgrep haproxy)
    if [[ \$check_code == "" ]]; then
        err=\$(expr \$err + 1)
        sleep 1
        continue
    else
        err=0
        break
    fi
done

if [[ \$err != "0" ]]; then
    echo "systemctl stop keepalived"
    /usr/bin/systemctl stop keepalived
    exit 1
else
    exit 0
fi
EOF

# 将健康检查脚本复制到 master 节点
for node in "${k8s_master_hostnames[@]}"; do
    echo "copying check_apiserver.sh to $node"
    ssh root@$node "[ -f /etc/keepalived/check_apiserver.sh ] && rm /etc/keepalived/check_apiserver.sh"
    scp ${local_tmp_dir}/keepalived/check_apiserver.sh root@$node:/etc/keepalived/check_apiserver.sh
    ssh root@$node "chmod +x /etc/keepalived/check_apiserver.sh"
done

mkdir -p ${local_tmp_dir}/keepalived/conf
rm -rf ${local_tmp_dir}/keepalived/conf/*

# 为每个节点创建 _keepalived.conf
for node in "${k8s_master_nodes[@]}"; do
  IFS='|' read -ra node_info <<< "$node"
  node_name="${node_info[0]}"
  node_ip="${node_info[1]}"
  
  state="MASTER"
  priority="100"
  if [ "$node_name" == "$keepalived_master" ]; then
    state="MASTER"
    priority="100"
  else
    state="BACKUP"
    priority=$(( (RANDOM % 10 + 1) * 10 ))
  fi

  cat > ${local_tmp_dir}/keepalived/conf/${node_name}_keepalived.conf << EOF
! Configuration File for keepalived

global_defs {
  router_id LVS_DEVEL
}
vrrp_script chk_apiserver {
  script "/etc/keepalived/check_apiserver.sh"
  interval 5 
  weight -5
  fall 2
  rise 1
}
vrrp_instance VI_1 {
  state ${state}
  # network_interface_name: ip addr
  interface ${network_interface_name} 
  mcast_src_ip ${node_ip}
  virtual_router_id 51
  priority ${priority}
  nopreempt
  advert_int 2
  authentication {
      auth_type PASS
      auth_pass K8SHA_KA_AUTH
  }
  virtual_ipaddress {
      ${k8s_apiserver_vip}
  }
  track_script {
    chk_apiserver 
  } 
}
EOF
done

# 将配置文件发送到所有 k8s-master 节点
# 配置文件并保存为 /etc/keepalived/keepalived.conf
# 健康检查脚本保存为 /etc/keepalived/check_apiserver.sh , 并需要添加执行权限
echo "copy keepalived.conf"
for node in "${k8s_master_hostnames[@]}"; do
    echo "copying keepalived.conf to $node"
    ssh root@${node} "[ -f /etc/keepalived/keepalived.conf ] && rm /etc/keepalived/keepalived.conf"
    scp ${local_tmp_dir}/keepalived/conf/${node}_keepalived.conf root@$node:/etc/keepalived/keepalived.conf
done
echo "copy keepalived.conf finished"

# 启动服务
for node in "${k8s_master_hostnames[@]}"; do
  ssh root@$node "systemctl daemon-reload"
  
  ssh root@$node "systemctl enable --now haproxy.service"
  ssh root@$node "systemctl restart haproxy.service"
  
  ssh root@$node "systemctl enable --now keepalived.service"
  ssh root@$node "systemctl restart keepalived.service"
done



echo #################################
echo #  start installing kubernetes  #
echo #################################
# k8s组件配置

# 所有 k8s 节点执行
for node in "${k8s_node_hostnames[@]}"; do
    ssh $node "mkdir -p /var/log/kubernetes"
    ssh $node "rm -rf /var/log/kubernetes/*"

    ssh $node "mkdir -p /etc/kubernetes"
    ssh $node "rm -rf /etc/kubernetes/*"

    ssh $node "mkdir -p /etc/kubernetes/pki"
    ssh $node "mkdir -p /etc/kubernetes/conf"
    ssh $node "mkdir -p /etc/kubernetes/manifests"
done

# 创建目录保存 kubernetes 可执行文件
mkdir -p ${local_tmp_dir}/kubernetes
rm -rf ${local_tmp_dir}/kubernetes/*

mkdir -p ${local_tmp_dir}/kubernetes/bin
rm -rf ${local_tmp_dir}/kubernetes/bin/*

# 解压到临时目录
tar -zxvf ${local_package_dir}/kubernetes-server-${kubernetes_version}-linux-amd64.tar.gz --strip-components=3 -C ${local_tmp_dir}/kubernetes/bin kubernetes/server/bin/kube{let,ctl,-apiserver,-controller-manager,-scheduler,-proxy}

# 将 kubectl 可执行文件复制到本机的 /usr/local/bin/kubectl , 用于下面生成k8s组件的配置文件
cp ${local_tmp_dir}/kubernetes/bin/kubectl /usr/local/bin/kubectl

# 创建保存 kubernetes 生成证书的配置的目录
mkdir -p ${local_tmp_dir}/kubernetes/kubernetes-pki-config
rm -rf ${local_tmp_dir}/kubernetes/kubernetes-pki-config/*

# 创建保存 kubernetes 证书的目录
mkdir -p ${local_tmp_dir}/kubernetes/kubernetes-pki
rm -rf ${local_tmp_dir}/kubernetes/kubernetes-pki/*

# 创建保存 kubernetes 配置文件的目录
mkdir -p ${local_tmp_dir}/kubernetes/kubernetes-config
rm -rf ${local_tmp_dir}/kubernetes/kubernetes-config/*

# 创建保存 kubernetes service 配置文件目录
mkdir -p ${local_tmp_dir}/kubernetes/kubernetes-service
rm -rf ${local_tmp_dir}/kubernetes/kubernetes-service/*

# 创建保存 kubernetes 资源配置文件目录
mkdir -p ${local_tmp_dir}/kubernetes/kubernetes-resource
rm -rf ${local_tmp_dir}/kubernetes/kubernetes-resource/*

# 生成 kubernetes pki 配置文件, 设置各种 profile 参数
cat > ${local_tmp_dir}/kubernetes/kubernetes-pki-config/kubernetes-pki-config.json << EOF 
{
  "signing": {
    "default": {
      "expiry": "876000h"
    },
    "profiles": {
      "kubernetes": {
        "usages": [
            "signing",
            "key encipherment",
            "server auth",
            "client auth"
        ],
        "expiry": "876000h"
      }
    }
  }
}
EOF

# 生成 k8s-ca 申请书
cat > ${local_tmp_dir}/kubernetes/kubernetes-pki-config/${k8s_pki_ca}-csr.json   << EOF 
{
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "Beijing",
      "L": "Beijing",
      "O": "Kubernetes",
      "OU": "Kubernetes-manual"
    }
  ],
  "ca": {
    "expiry": "876000h"
  }
}
EOF

# 申城 k8s ca 证书
cfssl gencert -initca ${local_tmp_dir}/kubernetes/kubernetes-pki-config/${k8s_pki_ca}-csr.json | cfssljson -bare ${local_tmp_dir}/kubernetes/kubernetes-pki/${k8s_pki_ca}

# 将 k8s ca 证书公钥发给所有 k8s 节点
for node in "${k8s_node_hostnames[@]}"; do
  scp ${local_tmp_dir}/kubernetes/kubernetes-pki/${k8s_pki_ca}.pem root@${node}:/etc/kubernetes/pki/${k8s_pki_ca}.pem
  scp ${local_tmp_dir}/kubernetes/kubernetes-pki/${k8s_pki_ca}-key.pem root@${node}:/etc/kubernetes/pki/${k8s_pki_ca}-key.pem
done

# 生成apiserver聚合证书
# 生成 front-proxy ca 申请书
cat > ${local_tmp_dir}/kubernetes/kubernetes-pki-config/${k8s_pki_front_proxy_ca}-csr.json  << EOF 
{
  "CN": "kubernetes",
  "key": {
     "algo": "rsa",
     "size": 2048
  },
  "ca": {
    "expiry": "876000h"
  }
}
EOF
# 生成 front-proxy ca 证书
cfssl gencert -initca ${local_tmp_dir}/kubernetes/kubernetes-pki-config/${k8s_pki_front_proxy_ca}-csr.json | cfssljson -bare ${local_tmp_dir}/kubernetes/kubernetes-pki/${k8s_pki_front_proxy_ca}
# 将 front-proxy ca 证书公钥发给所有 k8s-master 节点
for node in "${k8s_node_hostnames[@]}"; do
  scp ${local_tmp_dir}/kubernetes/kubernetes-pki/${k8s_pki_front_proxy_ca}.pem root@${node}:/etc/kubernetes/pki/${k8s_pki_front_proxy_ca}.pem
  scp ${local_tmp_dir}/kubernetes/kubernetes-pki/${k8s_pki_front_proxy_ca}-key.pem root@${node}:/etc/kubernetes/pki/${k8s_pki_front_proxy_ca}-key.pem
done


# 生成 front-proxy 客户端证书
cat > ${local_tmp_dir}/kubernetes/kubernetes-pki-config/${k8s_pki_front_proxy_client}-csr.json  << EOF 
{
  "CN": "front-proxy-client",
  "key": {
     "algo": "rsa",
     "size": 2048
  }
}
EOF

# 生成 front-proxy 客户端证书
cfssl gencert \
-ca=${local_tmp_dir}/kubernetes/kubernetes-pki/${k8s_pki_front_proxy_ca}.pem   \
-ca-key=${local_tmp_dir}/kubernetes/kubernetes-pki/${k8s_pki_front_proxy_ca}-key.pem   \
-config=${local_tmp_dir}/kubernetes/kubernetes-pki-config/kubernetes-pki-config.json \
-profile=kubernetes \
${local_tmp_dir}/kubernetes/kubernetes-pki-config/${k8s_pki_front_proxy_client}-csr.json | cfssljson -bare ${local_tmp_dir}/kubernetes/kubernetes-pki/${k8s_pki_front_proxy_client}

# 将 front-proxy 客户端证书发给所有 k8s-master 节点
for node in "${k8s_node_hostnames[@]}"; do
  scp ${local_tmp_dir}/kubernetes/kubernetes-pki/${k8s_pki_front_proxy_client}.pem root@${node}:/etc/kubernetes/pki/${k8s_pki_front_proxy_client}.pem
  scp ${local_tmp_dir}/kubernetes/kubernetes-pki/${k8s_pki_front_proxy_client}-key.pem root@${node}:/etc/kubernetes/pki/${k8s_pki_front_proxy_client}-key.pem
done


# 创建 ServiceAccount Key
# 生成私钥
openssl genrsa -out ${local_tmp_dir}/kubernetes/kubernetes-pki/${k8s_pki_service_account}.key 2048
# 生成公钥
openssl rsa -in ${local_tmp_dir}/kubernetes/kubernetes-pki/${k8s_pki_service_account}.key -pubout -out ${local_tmp_dir}/kubernetes/kubernetes-pki/${k8s_pki_service_account}.pub
# 将 service-account 密钥对发送到所有 k8s-master 节点
for node in "${k8s_node_hostnames[@]}"; do
  scp ${local_tmp_dir}/kubernetes/kubernetes-pki/${k8s_pki_service_account}.key root@${node}:/etc/kubernetes/pki/${k8s_pki_service_account}.key
  scp ${local_tmp_dir}/kubernetes/kubernetes-pki/${k8s_pki_service_account}.pub root@${node}:/etc/kubernetes/pki/${k8s_pki_service_account}.pub
done


echo ######################################
echo #      install kube-apiserver        #
echo ######################################

# 复制 kube-apiserver 可执行文件到所有 k8s-master 节点
echo "stop kube-apiserver.service"
for node in "${k8s_master_hostnames[@]}"; do
  echo "stop kube-apiserver.service for $node"
  ssh root@${node} "systemctl is-active kube-apiserver.service && systemctl stop kube-apiserver.serivce"
done
echo "stop kube-apiserver finished"

echo "copying kube-apiserver"
for node in "${k8s_master_hostnames[@]}"; do
  echo "copying kube-apiserver to $node"
  ssh root@${node} "[ -f /usr/local/bin/kube-apiserver ] && rm /usr/local/bin/kube-apiserver"
  scp ${local_tmp_dir}/kubernetes/bin/kube-apiserver root@$node:/usr/local/bin/kube-apiserver
done
echo "copying kube-apiserver finished"

# 生成 apiserver 证书
cat > ${local_tmp_dir}/kubernetes/kubernetes-pki-config/kube-apiserver-csr.json << EOF 
{
  "CN": "kube-apiserver",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "Beijing",
      "L": "Beijing",
      "O": "Kubernetes",
      "OU": "Kubernetes-manual"
    }
  ]
}
EOF


# k8s_service_ip="10.96.0.1"
# k8s_apiserver_vip="192.168.0.250"
# k8s_node_ips_string_comma="192.168.0.151,192.168.0.152,192.168.0.153,192.168.0.161,192.168.0.162,192.168.0.163"
cfssl gencert \
-ca=${local_tmp_dir}/kubernetes/kubernetes-pki/${k8s_pki_ca}.pem \
-ca-key=${local_tmp_dir}/kubernetes/kubernetes-pki/${k8s_pki_ca}-key.pem \
-config=${local_tmp_dir}/kubernetes/kubernetes-pki-config/kubernetes-pki-config.json \
-hostname=$k8s_service_ip,$k8s_apiserver_vip,127.0.0.1,${k8s_node_hostnames_string_comma},${k8s_node_ips_string_comma} \
-profile=kubernetes \
${local_tmp_dir}/kubernetes/kubernetes-pki-config/kube-apiserver-csr.json | cfssljson -bare ${local_tmp_dir}/kubernetes/kubernetes-pki/kube-apiserver

# 将 kube-apiserver 证书发送到所有 k8s-master 节点
echo "copying kube-apiserver pki to k8s-master for kube-apiserver"
for node in "${k8s_master_hostnames[@]}"; do
  echo "copying kube-apiserver pki to k8s-master for kube-apiserver for $node"
  for file in kube-apiserver.pem kube-apiserver-key.pem; do
    ssh root@$node "[ -f /etc/kubernetes/pki/$file ] && rm /etc/kubernetes/pki/$file"
    scp ${local_tmp_dir}/kubernetes/kubernetes-pki/$file root@$node:/etc/kubernetes/pki/$file
  done
done

# kube-apiserver 要访问 etcd 集群, 需要加载 etcd 的证书, 复制 etcd 证书到 k8s-master 节点
echo "copying etcd pki to k8s-master for kube-apiserver"
for node in "${k8s_master_hostnames[@]}"; do
  echo "copying etcd pki to k8s-master for kube-apiserver for $node"
  scp ${local_tmp_dir}/etcd/etcd-pki/${etcd_pki_ca}.pem root@$node:/etc/kubernetes/pki/${k8s_pki_etcd_ca}.pem
  scp ${local_tmp_dir}/etcd/etcd-pki/${etcd_pki_client}.pem root@$node:/etc/kubernetes/pki/${k8s_pki_etcd_client}.pem
  scp ${local_tmp_dir}/etcd/etcd-pki/${etcd_pki_client}-key.pem root@$node:/etc/kubernetes/pki/${k8s_pki_etcd_client}-key.pem
done

# 创建 kube-apiserver.service
for node in "${k8s_master_nodes[@]}"; do
    IFS='|' read -ra node_info <<< "$node"
    node_name="${node_info[0]}"
    node_ip="${node_info[1]}"
  
  cat > ${local_tmp_dir}/kubernetes/kubernetes-service/${node_name}-kube-apiserver.service << EOF
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes
After=network.target

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
--v=2 \\
--allow-privileged=true \\
--bind-address=0.0.0.0 \\
--secure-port=6443 \\
--advertise-address=$node_ip \\
--service-cluster-ip-range=${k8s_service_ip_range} \\
--service-node-port-range=30000-32767 \\
--etcd-servers=${etcd_urls_string_comma} \\
--etcd-cafile=/etc/kubernetes/pki/${k8s_pki_etcd_ca}.pem \\
--etcd-certfile=/etc/kubernetes/pki/${k8s_pki_etcd_client}.pem \\
--etcd-keyfile=/etc/kubernetes/pki/${k8s_pki_etcd_client}-key.pem \\
--client-ca-file=/etc/kubernetes/pki/${k8s_pki_ca}.pem \\
--tls-cert-file=/etc/kubernetes/pki/kube-apiserver.pem \\
--tls-private-key-file=/etc/kubernetes/pki/kube-apiserver-key.pem \\
--kubelet-client-certificate=/etc/kubernetes/pki/kube-apiserver.pem \\
--kubelet-client-key=/etc/kubernetes/pki/kube-apiserver-key.pem \\
--service-account-key-file=/etc/kubernetes/pki/${k8s_pki_service_account}.pub \\
--service-account-signing-key-file=/etc/kubernetes/pki/${k8s_pki_service_account}.key \\
--service-account-issuer=https://kubernetes.default.svc.cluster.local \\
--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname \\
--enable-admission-plugins=NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,DefaultTolerationSeconds,NodeRestriction,ResourceQuota \\
--authorization-mode=Node,RBAC \\
--enable-bootstrap-token-auth=true \\
--requestheader-client-ca-file=/etc/kubernetes/pki/${k8s_pki_front_proxy_ca}.pem \\
--proxy-client-cert-file=/etc/kubernetes/pki/${k8s_pki_front_proxy_client}.pem \\
--proxy-client-key-file=/etc/kubernetes/pki/${k8s_pki_front_proxy_client}-key.pem \\
--requestheader-allowed-names=aggregator \\
--requestheader-group-headers=X-Remote-Group \\
--requestheader-extra-headers-prefix=X-Remote-Extra- \\
--requestheader-username-headers=X-Remote-User \\
--enable-aggregator-routing=true
Restart=on-failure
RestartSec=10s
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
done

# 将配置文件 ${node_name}-kube-apiserver.service 复制到所有 k8s-master 节点, 并保存为 /usr/lib/systemd/system/kube-apiserver.service
# 启动 kube-apiserver 服务
for node in "${k8s_master_hostnames[@]}"; do
  scp ${local_tmp_dir}/kubernetes/kubernetes-service/${node}-kube-apiserver.service root@${node}:/usr/lib/systemd/system/kube-apiserver.service
  ssh root@$node "systemctl daemon-reload"
  ssh root@$node "systemctl enable --now kube-apiserver.service"
	ssh "root@$node" "systemctl restart kube-apiserver.service"
done



echo #####################################
echo #  install kube-controller-manager  #
echo #####################################

# 复制 kube-controller-manager 可执行文件到所有 k8s-master 节点
echo "stop kube-controller-manager.service"
for node in "${k8s_master_hostnames[@]}"; do
  echo "stop kube-controller-manager.service for $node"
  ssh root@${node} "systemctl is-active kube-controller-manager.service && systemctl stop kube-controller-manager.serivce"
done
echo "stop kube-controller-manager finished"

echo "copying kube-controller-manager"
for node in "${k8s_master_hostnames[@]}"; do
  echo "copying kube-controller-manager to $node"
  ssh root@${node} "[ -f /usr/local/bin/kube-controller-manager ] && rm /usr/local/bin/kube-controller-manager"
  scp ${local_tmp_dir}/kubernetes/bin/kube-controller-manager root@$node:/usr/local/bin/kube-controller-manager
done
echo "copying kube-controller-manager finished"

# 生成 kube-controller-manager 证书申请书
cat > ${local_tmp_dir}/kubernetes/kubernetes-pki-config/kube-controller-manager-csr.json << EOF 
{
  "CN": "system:kube-controller-manager",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "Beijing",
      "L": "Beijing",
      "O": "system:kube-controller-manager",
      "OU": "Kubernetes-manual"
    }
  ]
}
EOF

# 生成 kube-controller-manager 证书
cfssl gencert \
-ca=${local_tmp_dir}/kubernetes/kubernetes-pki/${k8s_pki_ca}.pem \
-ca-key=${local_tmp_dir}/kubernetes/kubernetes-pki/${k8s_pki_ca}-key.pem \
-config=${local_tmp_dir}/kubernetes/kubernetes-pki-config/kubernetes-pki-config.json \
-profile=kubernetes \
${local_tmp_dir}/kubernetes/kubernetes-pki-config/kube-controller-manager-csr.json | cfssljson -bare ${local_tmp_dir}/kubernetes/kubernetes-pki/kube-controller-manager

# 将 kube-controller-manager 证书复制到所有 k8s-master 节点
#for node in "${k8s_master_hostnames[@]}"; do
  #scp ${local_tmp_dir}/kubernetes/kubernetes-pki/kube-controller-manager.pem root@${node}:/etc/kubernetes/pki/kube-controller-manager.pem
  #scp ${local_tmp_dir}/kubernetes/kubernetes-pki/kube-controller-manager-key.pem root@${node}:/etc/kubernetes/pki/kube-controller-manager-key.pem
#done


# 生成 kube-controller-manager 配置文件 kube-controller-manager.kubeconfig
# k8s_apiserver_url=https://192.168.0.250:8443
kubectl config set-cluster kubernetes \
--certificate-authority=${local_tmp_dir}/kubernetes/kubernetes-pki/${k8s_pki_ca}.pem \
--embed-certs=true \
--server=${k8s_apiserver_url} \
--kubeconfig=${local_tmp_dir}/kubernetes/kubernetes-config/kube-controller-manager.kubeconfig

kubectl config set-context system:kube-controller-manager@kubernetes \
--cluster=kubernetes \
--user=system:kube-controller-manager \
--kubeconfig=${local_tmp_dir}/kubernetes/kubernetes-config/kube-controller-manager.kubeconfig

kubectl config set-credentials system:kube-controller-manager \
--client-certificate=${local_tmp_dir}/kubernetes/kubernetes-pki/kube-controller-manager.pem \
--client-key=${local_tmp_dir}/kubernetes/kubernetes-pki/kube-controller-manager-key.pem \
--embed-certs=true \
--kubeconfig=${local_tmp_dir}/kubernetes/kubernetes-config/kube-controller-manager.kubeconfig

kubectl config use-context system:kube-controller-manager@kubernetes \
--kubeconfig=${local_tmp_dir}/kubernetes/kubernetes-config/kube-controller-manager.kubeconfig

for node in "${k8s_master_hostnames[@]}"; do
  scp ${local_tmp_dir}/kubernetes/kubernetes-config/kube-controller-manager.kubeconfig root@${node}:/etc/kubernetes/conf/kube-controller-manager.kubeconfig
done


# 配置 kube-controller-manager.service
# 不使用ipv6 删除参数 --node-cidr-mask-size-ipv6=120
cat > ${local_tmp_dir}/kubernetes/kubernetes-service/kube-controller-manager.service << EOF

[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes
After=network.target

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\
      --v=2 \\
      --bind-address=0.0.0.0 \\
      --root-ca-file=/etc/kubernetes/pki/${k8s_pki_ca}.pem \\
      --cluster-signing-cert-file=/etc/kubernetes/pki/${k8s_pki_ca}.pem \\
      --cluster-signing-key-file=/etc/kubernetes/pki/${k8s_pki_ca}-key.pem \\
      --service-account-private-key-file=/etc/kubernetes/pki/${k8s_pki_service_account}.key \\
      --kubeconfig=/etc/kubernetes/conf/kube-controller-manager.kubeconfig \\
      --leader-elect=true \\
      --use-service-account-credentials=true \\
      --node-monitor-grace-period=40s \\
      --node-monitor-period=5s \\
      --controllers=*,bootstrapsigner,tokencleaner \\
      --allocate-node-cidrs=true \\
      --service-cluster-ip-range=${k8s_service_ip_range} \\
      --cluster-cidr=${k8s_pod_ip_range} \\
      --node-cidr-mask-size-ipv4=24 \\
      --requestheader-client-ca-file=/etc/kubernetes/pki/${k8s_pki_front_proxy_ca}.pem

Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target

EOF

# 将配置文件 kube-controller-manager.service 复制到所有 k8s-master 节点, 
# 并保存为 /usr/lib/systemd/system/kube-controller-manager.service
for node in "${k8s_master_hostnames[@]}"; do
  scp ${local_tmp_dir}/kubernetes/kubernetes-service/kube-controller-manager.service root@${node}:/usr/lib/systemd/system/kube-controller-manager.service
    
done

# 启动 kube-controller-manager 服务
for node in "${k8s_master_hostnames[@]}"; do
  ssh root@$node "systemctl daemon-reload"
  ssh root@$node "systemctl enable --now kube-controller-manager.service"
	ssh "root@$node" "systemctl restart kube-controller-manager.service"
done



echo #####################################
echo #     install kube-scheduler        #
echo #####################################

# 复制 kube-scheduler 可执行文件到所有 k8s-master 节点
echo "stop kube-scheduler.service"
for node in "${k8s_master_hostnames[@]}"; do
  echo "stop kube-scheduler.service for $node"
  ssh root@${node} "systemctl is-active kube-scheduler.service && systemctl stop kube-scheduler.serivce"
done
echo "stop kube-scheduler finished"

echo "copying kube-scheduler"
for node in "${k8s_master_hostnames[@]}"; do
  echo "copying kube-scheduler to $node"
  ssh root@${node} "[ -f /usr/local/bin/kube-scheduler ] && rm /usr/local/bin/kube-scheduler"
  scp ${local_tmp_dir}/kubernetes/bin/kube-scheduler root@$node:/usr/local/bin/kube-scheduler
done
echo "copying kube-scheduler finished"

# 生成 kube-scheduler 的证书申请书
cat > ${local_tmp_dir}/kubernetes/kubernetes-pki-config/kube-scheduler-csr.json << EOF 
{
  "CN": "system:kube-scheduler",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "Beijing",
      "L": "Beijing",
      "O": "system:kube-scheduler",
      "OU": "Kubernetes-manual"
    }
  ]
}
EOF

# 生成 kube-scheduler 的证书
cfssl gencert \
-ca=${local_tmp_dir}/kubernetes/kubernetes-pki/${k8s_pki_ca}.pem \
-ca-key=${local_tmp_dir}/kubernetes/kubernetes-pki/${k8s_pki_ca}-key.pem \
-config=${local_tmp_dir}/kubernetes/kubernetes-pki-config/kubernetes-pki-config.json \
-profile=kubernetes \
${local_tmp_dir}/kubernetes/kubernetes-pki-config/kube-scheduler-csr.json | cfssljson -bare ${local_tmp_dir}/kubernetes/kubernetes-pki/kube-scheduler



#生成 kube-scheduler.kubeconfig
# 生成 scheduler 配置文件
kubectl config set-cluster kubernetes \
--certificate-authority=${local_tmp_dir}/kubernetes/kubernetes-pki/${k8s_pki_ca}.pem \
--embed-certs=true \
--server=$k8s_apiserver_url \
--kubeconfig=${local_tmp_dir}/kubernetes/kubernetes-config/kube-scheduler.kubeconfig

kubectl config set-credentials system:kube-scheduler \
--client-certificate=${local_tmp_dir}/kubernetes/kubernetes-pki/kube-scheduler.pem \
--client-key=${local_tmp_dir}/kubernetes/kubernetes-pki/kube-scheduler-key.pem \
--embed-certs=true \
--kubeconfig=${local_tmp_dir}/kubernetes/kubernetes-config/kube-scheduler.kubeconfig

kubectl config set-context system:kube-scheduler@kubernetes \
--cluster=kubernetes \
--user=system:kube-scheduler \
--kubeconfig=${local_tmp_dir}/kubernetes/kubernetes-config/kube-scheduler.kubeconfig

kubectl config use-context system:kube-scheduler@kubernetes \
--kubeconfig=${local_tmp_dir}/kubernetes/kubernetes-config/kube-scheduler.kubeconfig

# 把配置文件 kube-scheduler.kubeconfig 复制到所有 k8s-master 节点
echo "copying kube-scheduler.kubeconfig to k8s-master nodes"
for node in "${k8s_master_hostnames[@]}"; do
  echo "copying kube-scheduler.kubeconfig to ${node}"
  scp ${local_tmp_dir}/kubernetes/kubernetes-config/kube-scheduler.kubeconfig root@${node}:/etc/kubernetes/kube-scheduler.kubeconfig
done
echo "copying kube-scheduler.kubeconfig to k8s-master nodes finished"


# 配置kube-scheduler.service
cat > ${local_tmp_dir}/kubernetes/kubernetes-service/kube-scheduler.service << EOF

[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes
After=network.target

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\
      --v=2 \\
      --bind-address=0.0.0.0 \\
      --leader-elect=true \\
      --kubeconfig=/etc/kubernetes/kube-scheduler.kubeconfig

Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

# 将配置文件 kube-scheduler.service 复制到所有 k8s-master 节点
# 并保存为 /usr/lib/systemd/system/kube-scheduler.service
# 启动 kube-scheduler 服务
for node in "${k8s_master_hostnames[@]}"; do
  scp ${local_tmp_dir}/kubernetes/kubernetes-service/kube-scheduler.service root@${node}:/usr/lib/systemd/system/kube-scheduler.service
done

# 启动 kube-controller-manager 服务
for node in "${k8s_master_hostnames[@]}"; do
  ssh root@$node "systemctl daemon-reload"
  ssh root@$node "systemctl enable --now kube-scheduler.service"
	ssh "root@$node" "systemctl restart kube-scheduler.service"
done


echo #####################################
echo #        install kubelet            #
echo #####################################

# 复制 kubelet 可执行文件到所有 k8s 节点
echo "stop kubelet.service"
for node in "${k8s_node_hostnames[@]}"; do
  echo "stop kubelet.service for $node"
  ssh root@${node} "systemctl is-active kubelet.service && systemctl stop kubelet.serivce"
done
echo "stop kubelet.service finished"

echo "copying kubelet"
for node in "${k8s_node_hostnames[@]}"; do
  echo "copying kubelet to $node"
  ssh root@${node} "[ -f /usr/local/bin/kubelet ] && rm /usr/local/bin/kubelet"
  scp ${local_tmp_dir}/kubernetes/bin/kubelet root@$node:/usr/local/bin/kubelet
done
echo "copying kubelet finished"

# 创建 bootstrap-kubelet.kubeconfig
# TLS Bootstrapping配置
# /etc/kubernetes/conf/bootstrap-kubelet.kubeconfig
kubectl config set-cluster kubernetes \
--certificate-authority=${local_tmp_dir}/kubernetes/kubernetes-pki/${k8s_pki_ca}.pem \
--embed-certs=true \
--server=${k8s_apiserver_url} \
--kubeconfig=${local_tmp_dir}/kubernetes/kubernetes-config/bootstrap-kubelet.kubeconfig

kubectl config set-credentials tls-bootstrap-token-user \
--token=${k8s_bootstrap_token_id}.${k8s_bootstrap_token_secret} \
--kubeconfig=${local_tmp_dir}/kubernetes/kubernetes-config/bootstrap-kubelet.kubeconfig

kubectl config set-context tls-bootstrap-token-user@kubernetes \
--cluster=kubernetes \
--user=tls-bootstrap-token-user \
--kubeconfig=${local_tmp_dir}/kubernetes/kubernetes-config/bootstrap-kubelet.kubeconfig

kubectl config use-context tls-bootstrap-token-user@kubernetes \
--kubeconfig=${local_tmp_dir}/kubernetes/kubernetes-config/bootstrap-kubelet.kubeconfig


for node in "${k8s_node_hostnames[@]}"; do
    scp ${local_tmp_dir}/kubernetes/kubernetes-config/bootstrap-kubelet.kubeconfig root@${node}:/etc/kubernetes/conf/bootstrap-kubelet.kubeconfig
done


# kubelet.kubeconfig 自动生成


# 创建 kubelet-conf.yml
# /etc/kubernetes/conf/kubelet-conf.yml
cat > ${local_tmp_dir}/kubernetes/kubernetes-config/kubelet-conf.yml <<EOF
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
address: 0.0.0.0
port: 10250
readOnlyPort: 10255
authentication:
  anonymous:
    enabled: false
  webhook:
    cacheTTL: 2m0s
    enabled: true
  x509:
    clientCAFile: /etc/kubernetes/pki/${k8s_pki_ca}.pem
authorization:
  mode: Webhook
  webhook:
    cacheAuthorizedTTL: 5m0s
    cacheUnauthorizedTTL: 30s
cgroupDriver: systemd
cgroupsPerQOS: true
clusterDNS:
- ${cluster_dns}
clusterDomain: cluster.local
containerLogMaxFiles: 5
containerLogMaxSize: 10Mi
contentType: application/vnd.kubernetes.protobuf
cpuCFSQuota: true
cpuManagerPolicy: none
cpuManagerReconcilePeriod: 10s
enableControllerAttachDetach: true
enableDebuggingHandlers: true
enforceNodeAllocatable:
- pods
eventBurst: 10
eventRecordQPS: 5
evictionHard:
  imagefs.available: 15%
  memory.available: 100Mi
  nodefs.available: 10%
  nodefs.inodesFree: 5%
evictionPressureTransitionPeriod: 5m0s
failSwapOn: true
fileCheckFrequency: 20s
hairpinMode: promiscuous-bridge
healthzBindAddress: 127.0.0.1
healthzPort: 10248
httpCheckFrequency: 20s
imageGCHighThresholdPercent: 85
imageGCLowThresholdPercent: 80
imageMinimumGCAge: 2m0s
iptablesDropBit: 15
iptablesMasqueradeBit: 14
kubeAPIBurst: 10
kubeAPIQPS: 5
makeIPTablesUtilChains: true
maxOpenFiles: 1000000
maxPods: 110
nodeStatusUpdateFrequency: 10s
oomScoreAdj: -999
podPidsLimit: -1
registryBurst: 10
registryPullQPS: 5
# resolvConf: /etc/resolv.conf
# coreDns loop : https://blog.csdn.net/xdbrcisco/article/details/117442590
resolvConf: /run/systemd/resolve/resolv.conf
rotateCertificates: true
runtimeRequestTimeout: 2m0s
serializeImagePulls: true
staticPodPath: /etc/kubernetes/manifests
streamingConnectionIdleTimeout: 4h0m0s
syncFrequency: 1m0s
volumeStatsAggPeriod: 1m0s
EOF
# kubernetes-config/kubelet-conf.yml -> /etc/kubernetes/conf/kubelet-conf.yml
for node in "${k8s_node_hostnames[@]}"; do
    scp ${local_tmp_dir}/kubernetes/kubernetes-config/kubelet-conf.yml root@$node:/etc/kubernetes/conf/kubelet-conf.yml
done


# 生成 kubelet.service 文件
cat > ${local_tmp_dir}/kubernetes/kubernetes-service/kubelet.service << EOF
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet \\
--bootstrap-kubeconfig=/etc/kubernetes/conf/bootstrap-kubelet.kubeconfig  \\
--kubeconfig=/etc/kubernetes/conf/kubelet.kubeconfig \\
--config=/etc/kubernetes/conf/kubelet-conf.yml \\
--container-runtime-endpoint=unix:///run/containerd/containerd.sock  \\
--node-labels=node.kubernetes.io/node=

[Install]
WantedBy=multi-user.target
EOF

# 复制 kubelet.service 到所有 k8s 节点
for node in "${k8s_node_hostnames[@]}"; do
  scp ${local_tmp_dir}/kubernetes/kubernetes-service/kubelet.service root@$node:/usr/lib/systemd/system/kubelet.service
done

# 清除旧文件
for node in "${k8s_node_hostnames[@]}"; do
  ssh root@$node "mkdir -p /var/lib/kubelet"
  ssh root@$node "rm -rf /var/lib/kubelet/*"
	ssh root@$node "mkdir -p /etc/systemd/system/kubelet.service.d"
  ssh root@$node "rm -rf /etc/systemd/system/kubelet.service.d/*"
done

# 启动 kubelet.service
for node in "${k8s_node_hostnames[@]}"; do
  ssh root@$node "systemctl daemon-reload"
  ssh root@$node "systemctl enable --now kubelet.service"
done




echo #####################################
echo #        install kube-proxy         #
echo #####################################

# 复制 kube-proxy 可执行文件到所有 k8s 节点
echo "stop kube-proxy.service"
for node in "${k8s_node_hostnames[@]}"; do
  echo "stop kube-proxy.service for $node"
  ssh root@${node} "systemctl is-active kube-proxy.service && systemctl stop kube-proxy.serivce"
done
echo "stop kube-proxy.service finished"

echo "copying kube-proxy"
for node in "${k8s_node_hostnames[@]}"; do
  echo "copying kube-proxy to $node"
  ssh root@${node} "[ -f /usr/local/bin/kube-proxy ] && rm /usr/local/bin/kube-proxy"
  scp ${local_tmp_dir}/kubernetes/bin/kube-proxy root@$node:/usr/local/bin/kube-proxy
done
echo "copying kube-proxy finished"


# 创建 kube-proxy 证书
cat > ${local_tmp_dir}/kubernetes/kubernetes-pki-config/kube-proxy-csr.json << EOF 
{
  "CN": "system:kube-proxy",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "Beijing",
      "L": "Beijing",
      "O": "system:kube-proxy",
      "OU": "Kubernetes-manual"
    }
  ]
}
EOF

cfssl gencert \
-ca=${local_tmp_dir}/kubernetes/kubernetes-pki/${k8s_pki_ca}.pem \
-ca-key=${local_tmp_dir}/kubernetes/kubernetes-pki/${k8s_pki_ca}-key.pem \
-config=${local_tmp_dir}/kubernetes/kubernetes-pki-config/kubernetes-pki-config.json \
-profile=kubernetes \
${local_tmp_dir}/kubernetes/kubernetes-pki-config/kube-proxy-csr.json | cfssljson -bare ${local_tmp_dir}/kubernetes/kubernetes-pki/kube-proxy


# 创建 /etc/kubernetes/conf/kube-proxy.kubeconfig
kubectl config set-cluster kubernetes \
--certificate-authority=${local_tmp_dir}/kubernetes/kubernetes-pki/${k8s_pki_ca}.pem \
--embed-certs=true \
--server=${k8s_apiserver_url} \
--kubeconfig=${local_tmp_dir}/kubernetes/kubernetes-config/kube-proxy.kubeconfig

kubectl config set-credentials kube-proxy \
--client-certificate=${local_tmp_dir}/kubernetes/kubernetes-pki/kube-proxy.pem \
--client-key=${local_tmp_dir}/kubernetes/kubernetes-pki/kube-proxy-key.pem \
--embed-certs=true \
--kubeconfig=${local_tmp_dir}/kubernetes/kubernetes-config/kube-proxy.kubeconfig

kubectl config set-context kube-proxy@kubernetes \
--cluster=kubernetes \
--user=kube-proxy \
--kubeconfig=${local_tmp_dir}/kubernetes/kubernetes-config/kube-proxy.kubeconfig

kubectl config use-context kube-proxy@kubernetes \
--kubeconfig=${local_tmp_dir}/kubernetes/kubernetes-config/kube-proxy.kubeconfig

for node in "${k8s_node_hostnames[@]}"; do
    scp ${local_tmp_dir}/kubernetes/kubernetes-config/kube-proxy.kubeconfig root@${node}:/etc/kubernetes/conf/kube-proxy.kubeconfig
done


# 创建 /etc/kubernetes/conf/kube-proxy.yaml
# /etc/kubernetes/kube-proxy.yaml
cat > ${local_tmp_dir}/kubernetes/kubernetes-config/kube-proxy.yaml << EOF
apiVersion: kubeproxy.config.k8s.io/v1alpha1
bindAddress: 0.0.0.0
clientConnection:
  acceptContentTypes: ""
  burst: 10
  contentType: application/vnd.kubernetes.protobuf
  kubeconfig: /etc/kubernetes/conf/kube-proxy.kubeconfig
  qps: 5
clusterCIDR: ${k8s_pod_ip_range}
configSyncPeriod: 15m0s
conntrack:
  max: null
  maxPerCore: 32768
  min: 131072
  tcpCloseWaitTimeout: 1h0m0s
  tcpEstablishedTimeout: 24h0m0s
enableProfiling: false
healthzBindAddress: 0.0.0.0:10256
hostnameOverride: ""
iptables:
  masqueradeAll: false
  masqueradeBit: 14
  minSyncPeriod: 0s
  syncPeriod: 30s
ipvs:
  masqueradeAll: true
  minSyncPeriod: 5s
  scheduler: "rr"
  syncPeriod: 30s
kind: KubeProxyConfiguration
metricsBindAddress: 127.0.0.1:10249
mode: "ipvs"
nodePortAddresses: null
oomScoreAdj: -999
portRange: ""
udpIdleTimeout: 250ms
EOF
# 复制配置文件
# kubernetes-config/kube-proxy.yaml -> /etc/kubernetes/conf/kube-proxy.yaml
for node in "${k8s_node_hostnames[@]}"; do
  scp ${local_tmp_dir}/kubernetes/kubernetes-config/kube-proxy.yaml root@$node:/etc/kubernetes/conf/kube-proxy.yaml
done


cat > ${local_tmp_dir}/kubernetes/kubernetes-service/kube-proxy.service << EOF
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes
After=network.target

[Service]
ExecStart=/usr/local/bin/kube-proxy \\
--config=/etc/kubernetes/conf/kube-proxy.yaml \\
--v=2
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

# 复制 kube-proxy.service 配置文件
echo "copying kube-proxy.service"
for node in "${k8s_node_hostnames[@]}"; do
  echo "copying kube-proxy.service to $node"
  scp ${local_tmp_dir}/kubernetes/kubernetes-service/kube-proxy.service root@$node:/usr/lib/systemd/system/kube-proxy.service
done
echo "copying kube-proxy.service finished"

# 启动 kube-proxy.service
for node in "${k8s_node_hostnames[@]}"; do
  ssh root@$node "systemctl daemon-reload"
  ssh root@$node "systemctl enable --now kube-proxy.service"
done


echo #####################################
echo #         install kubectl           #
echo #####################################

# 复制 kubectl 可执行文件到所有 k8s_control_plane 节点 , kubectl 是 cli 程序,没有服务, 只需要
echo "copying kubectl"
for node in "${k8s_control_plane_hostnames[@]}"; do
  echo "copying kubectl to $node"
  ssh root@${node} "[ -f /usr/local/bin/kubectl ] && rm /usr/local/bin/kubectl"
  scp ${local_tmp_dir}/kubernetes/bin/kubectl root@$node:/usr/local/bin/kubectl
done
echo "copying kubectl finished"

# 生成 admin 的证书申请书
cat > ${local_tmp_dir}/kubernetes/kubernetes-pki-config/admin-csr.json << EOF 
{
  "CN": "admin",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "Beijing",
      "L": "Beijing",
      "O": "system:masters",
      "OU": "Kubernetes-manual"
    }
  ]
}
EOF

# 生成 admin 的证书
cfssl gencert \
-ca=${local_tmp_dir}/kubernetes/kubernetes-pki/${k8s_pki_ca}.pem \
-ca-key=${local_tmp_dir}/kubernetes/kubernetes-pki/${k8s_pki_ca}-key.pem \
-config=${local_tmp_dir}/kubernetes/kubernetes-pki-config/kubernetes-pki-config.json \
-profile=kubernetes \
${local_tmp_dir}/kubernetes/kubernetes-pki-config/admin-csr.json | cfssljson -bare ${local_tmp_dir}/kubernetes/kubernetes-pki/admin


# 生成 admin.kubeconfig 用于操作集群, 复制为操作集群的节点的 /root/.kube/config 文件
kubectl config set-cluster kubernetes \
--certificate-authority=${local_tmp_dir}/kubernetes/kubernetes-pki/${k8s_pki_ca}.pem \
--embed-certs=true \
--server=${k8s_apiserver_url} \
--kubeconfig=${local_tmp_dir}/kubernetes/kubernetes-config/admin.kubeconfig

kubectl config set-credentials kubernetes-admin  \
--client-certificate=${local_tmp_dir}/kubernetes/kubernetes-pki/admin.pem \
--client-key=${local_tmp_dir}/kubernetes/kubernetes-pki/admin-key.pem \
--embed-certs=true \
--kubeconfig=${local_tmp_dir}/kubernetes/kubernetes-config/admin.kubeconfig

kubectl config set-context kubernetes-admin@kubernetes \
--cluster=kubernetes \
--user=kubernetes-admin \
--kubeconfig=${local_tmp_dir}/kubernetes/kubernetes-config/admin.kubeconfig

kubectl config use-context kubernetes-admin@kubernetes \
--kubeconfig=${local_tmp_dir}/kubernetes/kubernetes-config/admin.kubeconfig


# 将 admin.kubeconfig 发送到 control_plane 节点, 保存为 /root/.kube/config , control_plane 节点上安装有 kubelet , 
# 在 control_plane 节点上通过 kubelet 执行命令时会读取 /root/.kube/config 文件中的配置
for node in "${k8s_control_plane_hostnames[@]}"; do
  echo "copying admin.kubeconfig to $node save as /root/.kube/config"
  ssh root@${node} "mkdir -p /root/.kube"
  ssh root@${node} "rm -rf /root/.kube/*"
  scp ${local_tmp_dir}/kubernetes/kubernetes-config/admin.kubeconfig root@${node}:/root/.kube/config
done


# 安装helm
mkdir -p ${local_tmp_dir}/helm
rm -rf ${local_tmp_dir}/helm/*

tar -zxvf ${local_package_dir}/helm-v${helm_version}-linux-amd64.tar.gz -C ${local_tmp_dir}/helm

for node in "${k8s_control_plane_hostnames[@]}"; do
  scp ${local_tmp_dir}/helm/linux-amd64/helm root@${node}:/usr/local/bin/helm
  ssh root@${node} "chmod +x /usr/local/bin/helm"
done


#############################
#    在 k8s 集群中创建资源   #
#############################
mkdir -p ${local_tmp_dir}/kubernetes/kubernetes-resources
rm -rf ${local_tmp_dir}/kubernetes/kubernetes-resources/*

first_k8s_control_plane_node="${k8s_control_plane_hostnames[0]}"
echo "first_k8s_control_plane_node:$first_k8s_control_plane_node"
ssh root@${first_k8s_control_plane_node} "mkdir -p ${remote_tmp_dir}/kubernetes"
ssh root@${first_k8s_control_plane_node} "rm -rf ${remote_tmp_dir}/kubernetes/*"
ssh root@${first_k8s_control_plane_node} "mkdir -p ${remote_tmp_dir}/kubernetes/kubernetes-resource"


cat > ${local_tmp_dir}/kubernetes/kubernetes-resources/bootstrap-secret.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: bootstrap-token-${k8s_bootstrap_token_id}
  namespace: kube-system
type: bootstrap.kubernetes.io/token
stringData:
  description: "The default bootstrap token generated by 'kubelet '."
  token-id: ${k8s_bootstrap_token_id}
  token-secret: ${k8s_bootstrap_token_secret}
  usage-bootstrap-authentication: "true"
  usage-bootstrap-signing: "true"
  auth-extra-groups: system:bootstrappers:default-nodetoken,system:bootstrappers:worker,system:bootstrappers:ingress

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kubelet-bootstrap
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:node-bootstrapper
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: system:bootstrappers:default-node-token

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: node-autoapprove-bootstrap
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:certificates.k8s.io:certificatesigningrequests:nodeclient
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: system:bootstrappers:default-node-token
    
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: node-autoapprove-certificate-rotation
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:certificates.k8s.io:certificatesigningrequests:selfnodeclient
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: system:nodes
  
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:kube-apiserver-to-kubelet
  
rules:
  - apiGroups:
    - ""
    resources:
      - nodes/proxy
      - nodes/stats
      - nodes/log
      - nodes/spec
      - nodes/metrics
    verbs:
      - "*"
      
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:kube-apiserver
  namespace: ""
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-apiserver-to-kubelet
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: kube-apiserver
EOF

scp ${local_tmp_dir}/kubernetes/kubernetes-resources/bootstrap-secret.yaml root@${first_k8s_control_plane_node}:${remote_tmp_dir}/kubernetes/kubernetes-resource/bootstrap-secret.yaml
ssh root@${first_k8s_control_plane_node} "kubectl apply -f ${remote_tmp_dir}/kubernetes/kubernetes-resource/bootstrap-secret.yaml"



cat > ${local_tmp_dir}/kubernetes/kubernetes-resources/bootstrap-account.yaml << EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system-anonymous-as-cluster-admin
subjects:
- kind: User
  name: system:anonymous
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system-bootstrap-${k8s_bootstrap_token_id}-as-cluster-admin
subjects:
- kind: User
  name: system:bootstrap:${k8s_bootstrap_token_id}
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF

scp ${local_tmp_dir}/kubernetes/kubernetes-resources/bootstrap-account.yaml root@${first_k8s_control_plane_node}:${remote_tmp_dir}/kubernetes/kubernetes-resource/bootstrap-account.yaml
ssh root@${first_k8s_control_plane_node} "kubectl apply -f ${remote_tmp_dir}/kubernetes/kubernetes-resource/bootstrap-account.yaml"


apt install -y jq

remote_host=${first_k8s_control_plane_node}
remote_user="root"

# 获取指定 Pod 中所有容器的就绪状态
is_pod_containers_ready() {
  local namespace="$1"
  local pod_name="$2"
  
  ssh "$remote_user"@"$remote_host" "kubectl get pod -n '$namespace' '$pod_name' -o json" | \
    jq -r '.status.containerStatuses[] | select(.ready != true) | .name'
}

# 检查指定命名空间下的所有 pod 的容器就绪状态
check_namespace_pods() {
  local namespace="$1"
  
  pod_list=$(ssh "$remote_user"@"$remote_host" "kubectl get pods -n '$namespace' --no-headers -o custom-columns=':metadata.name'")

  all_pods_ready=true

  for pod in $pod_list; do
    not_ready_containers=$(is_pod_containers_ready "$namespace" "$pod")
    if [ -n "$not_ready_containers" ]; then
      all_pods_ready=false
      echo "Not all containers in pod $pod are ready"
      break
    fi
  done
}

# 检查指定命名空间下的所有 pod 是否就绪
check_all_pods_ready_in_namespace() {
  local namespace="$1"
  
  while true; do
    check_namespace_pods "$namespace"
    
    if [ "$all_pods_ready" = true ]; then
      ssh "$remote_user"@"$remote_host" 'echo "All pods are ready"'
      break  # 退出循环，继续执行后续任务
    fi
    
    sleep 1  # 等待 1 秒再进行下一次检查
  done
}

# 安装网络插件 calico
cp ${local_package_dir}/calico-v${calico_version}.yaml ${local_tmp_dir}/kubernetes/kubernetes-resources/calico-v${calico_version}-CALICO_IPV4POOL_CIDR.yaml
sed -i "s/# - name: CALICO_IPV4POOL_CIDR/- name: CALICO_IPV4POOL_CIDR/g" ${local_tmp_dir}/kubernetes/kubernetes-resources/calico-v${calico_version}-CALICO_IPV4POOL_CIDR.yaml
sed -i "s|#   value: \"192.168.0.0/16\"|  value: \"196.16.0.0/16\"|g" ${local_tmp_dir}/kubernetes/kubernetes-resources/calico-v${calico_version}-CALICO_IPV4POOL_CIDR.yaml

scp ${local_tmp_dir}/kubernetes/kubernetes-resources/calico-v${calico_version}-CALICO_IPV4POOL_CIDR.yaml root@${first_k8s_control_plane_node}:${remote_tmp_dir}/kubernetes/kubernetes-resource/calico-v${calico_version}-CALICO_IPV4POOL_CIDR.yaml
ssh root@${first_k8s_control_plane_node} "kubectl apply -f ${remote_tmp_dir}/kubernetes/kubernetes-resource/calico-v${calico_version}-CALICO_IPV4POOL_CIDR.yaml"

# 等到 calico 就绪
check_all_pods_ready_in_namespace "kube-system"


# 安装CoreDNS
scp ${local_package_dir}/coredns-${coredns_version}.tgz root@${first_k8s_control_plane_node}:${remote_tmp_dir}/kubernetes/kubernetes-resource/coredns-${coredns_version}.tgz
ssh root@${first_k8s_control_plane_node} "tar -zxvf ${remote_tmp_dir}/kubernetes/kubernetes-resource/coredns-${coredns_version}.tgz -C ${remote_tmp_dir}/kubernetes/kubernetes-resource"

# 修改IP地址
# cd coredns/
# vim values.yaml
# cat values.yaml | grep clusterIP:
# clusterIP: "10.96.0.10"

# 使用ssh执行sed命令在远程服务器上替换文件内容
ssh root@${first_k8s_control_plane_node} "sed -i 's|# clusterIP: \"\"|  clusterIP: \"${cluster_dns}\"|g' ${remote_tmp_dir}/kubernetes/kubernetes-resource/coredns/values.yaml"
ssh root@${first_k8s_control_plane_node} "helm install coredns ${remote_tmp_dir}/kubernetes/kubernetes-resource/coredns/ -n kube-system"

# 等待 coreDns就绪
check_all_pods_ready_in_namespace "kube-system"


# 安装 Metrics Server
cp ${local_package_dir}/metrics-server-v${metrics_server_version}_high-availability-1.21+.yaml ${local_tmp_dir}/kubernetes/kubernetes-resources/metrics-server-v${metrics_server_version}_high-availability-1.21+-updated.yaml

sed -i "/^      - args:$/,/^        - --metric-resolution=15s$/s/^        - --metric-resolution=15s$/\\        - --metric-resolution=15s\\n\\        - --kubelet-insecure-tls\\n\\        - --requestheader-client-ca-file=\\/etc\\/kubernetes\\/pki\\/${k8s_pki_front_proxy_ca}.pem\\n\\        - --requestheader-username-headers=X-Remote-User\\n\\        - --requestheader-group-headers=X-Remote-Group\\n\\        - --requestheader-extra-headers-prefix=X-Remote-Extra-/" "${local_tmp_dir}/kubernetes/kubernetes-resources/metrics-server-v${metrics_server_version}_high-availability-1.21+-updated.yaml"
sed -i '/^        volumeMounts:$/,/^          name: tmp-dir$/s%^          name: tmp-dir$%\          name: tmp-dir\n        - name: ca-ssl\n          mountPath: /etc/kubernetes/pki%' ${local_tmp_dir}/kubernetes/kubernetes-resources/metrics-server-v${metrics_server_version}_high-availability-1.21+-updated.yaml
sed -i '/^      volumes:$/,/^        name: tmp-dir$/s%^        name: tmp-dir$%\        name: tmp-dir\n      - name: ca-ssl\n        hostPath:\n          path: /etc/kubernetes/pki%' ${local_tmp_dir}/kubernetes/kubernetes-resources/metrics-server-v${metrics_server_version}_high-availability-1.21+-updated.yaml

scp ${local_tmp_dir}/kubernetes/kubernetes-resources/metrics-server-v${metrics_server_version}_high-availability-1.21+-updated.yaml root@${first_k8s_control_plane_node}:${remote_tmp_dir}/kubernetes/kubernetes-resource/metrics-server-v${metrics_server_version}_high-availability-1.21+-updated.yaml
ssh root@${first_k8s_control_plane_node} "kubectl apply -f ${remote_tmp_dir}/kubernetes/kubernetes-resource/metrics-server-v${metrics_server_version}_high-availability-1.21+-updated.yaml"

# 等待 Metrics Server 就绪
check_all_pods_ready_in_namespace "kube-system"


echo "###########################################"
echo "   kubernetes cluster install success     #"
echo "###########################################"

watch -n 1 ssh root@${first_k8s_control_plane_node} "kubectl get all -A"
