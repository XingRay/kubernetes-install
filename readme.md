<center>
    <h1>kubernetes install</h1>
</center>
os : ubuntu 22 server

kubernetes: 1.28.1



1 create vms for kubernetes cluster

2 create a installer-node or select one form kubernetes cluster nodes

2 set open-ssh , allow root remote login

3 download this shell scripts on installer-node

4 modify shell script parameters

5 allow ssh login

```
chmod +x ssh_login.sh && ./ssh_login.sh
```

6 execute installer script

```
chmod +x k8s_install.sh && ./k8s_install.sh
```

