#!/bin/bash

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
# 需要获取其所依赖包的包
libs="${tools[*]}"

logfile="tools_install.log"
ret=""
function getDepends()
{
   echo "fileName is" $1>>$logfile
   # use tr to del < >
   ret=`apt-cache depends $1 | grep Depends |cut -d: -f2 |tr -d "<>"`
   echo $ret|tee  -a $logfile
}

for ip in "${etcd_ips[@]}"; do
  if [ -n "$etcd_urls_string_comma" ]; then
    libs+=","
  fi
  libs+="https://$ip:2379"
done

# download libs dependen. deep in 3
i=0
while [ $i -lt 3 ] ;
do
    let i++
    echo $i
    # download libs
    newlist=" "
    for j in $libs
    do
        added="$(getDepends $j)"
        newlist="$newlist $added"
        apt install $added --reinstall -d -y
    done

    libs=$newlist
done

# 创建源信息
apt install dpkg-dev
cp -r /var/cache/apt/archives/*.deb /data/ubuntu/ 
dpkg-scanpackages . /dev/null | gzip > /data/ubuntu/Packages.gz -r

# 拷贝包到内网机器上
scp -r ubuntu/ root@192.168.0.31:
scp -r ubuntu/ root@192.168.0.32:
scp -r ubuntu/ root@192.168.0.33:
scp -r ubuntu/ root@192.168.0.34:
scp -r ubuntu/ root@192.168.0.35:

# 在内网机器上配置apt源
vim /etc/apt/sources.list
cat /etc/apt/sources.list
deb file:////root/ ubuntu/

# 安装deb包
apt install ./*.deb
