#!/bin/bash

cluster_node_hostnames=(
  "k8s-master-01"
  "k8s-master-02"
  "k8s-master-03"
  "k8s-worker-01"
  "k8s-worker-02"
  "k8s-worker-03"
)

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

log_filename="tools_install.log"
log_dir="log"

export_dir="./tools"

# 需要获取其所依赖包的包
libs="${tools[@]}"

ret=""
function getDepends() {
   echo "fileName is" $1 >> ${log_dir}/${log_filename}
   # use tr to del < >
   ret=$(apt-cache depends "$1" | grep Depends | cut -d: -f2 | tr -d "<>")
   echo $ret | tee -a $logfile
}

echo "###################"
echo "#      start      #"
echo "###################"

# 创建源信息
apt update
apt install dpkg-dev

mkdir -p "${export_dir}"
rm -rf "${export_dir}"/*

mkdir -p "${log_dir}"
rm -rf "${log_dir}"/*

# download libs dependen. deep in 3
i=0
while [ $i -lt 3 ]; do
  let i++
  echo $i
  # download libs
  newlist=" "
  for j in "${libs[@]}"; do
    added=$(getDepends "$j")
    newlist="$newlist $added"
    apt install $added --reinstall -d -y
  done

  libs=$newlist
done

cp -r /var/cache/apt/archives/*.deb "$export_dir"/
dpkg-scanpackages "$export_dir" /dev/null | gzip > "$export_dir"/Packages.gz -r

# 复制 Packages.gz 到导出目录
cp "$export_dir"/Packages.gz "$export_dir"/Packages.gz
