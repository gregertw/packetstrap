#!/bin/bash

# This simple bash scripts will bootstrap a CentOS7 with OS installs in prep for OKD install
#  

# You also need to:
#   - have a ssh key in ~/.ssh/id_rsa.pub 

# Create SSH key
ssh-keygen -b 2048 -t rsa -f /root/.ssh/id_rsa -q -N ""

echo "==== Setting variables"
SSHKEY=`cat ~/.ssh/id_rsa.pub`
PUBLICIP=`ip address show dev bond0 |grep bond0 |grep -v bond0:0 |grep inet |awk -F" " '{ print $2}' |awk -F"/" '{print $1}'`

echo "==== clean up yum and repo setup"
yum clean all
yum install yum-utils -y
yum install firewalld -y

service firewalld start

echo "==== setup firewall"
firewall-cmd --add-port=80/tcp
firewall-cmd --add-port=443/tcp
firewall-cmd --add-port=8080/tcp
firewall-cmd --add-port=8088/tcp
firewall-cmd --add-port=6443/tcp
firewall-cmd --add-port=22623/tcp
firewall-cmd --add-port=2376/tcp
firewall-cmd --add-port=9000/tcp
firewall-cmd --add-port=2376/udp
firewall-cmd --add-port=111/tcp
firewall-cmd --add-port=662/tcp
firewall-cmd --add-port=875/tcp
firewall-cmd --add-port=892/tcp
firewall-cmd --add-port=2049/tcp
firewall-cmd --add-port=32803/tcp
firewall-cmd --add-port=111/udp
firewall-cmd --add-port=662/udp
firewall-cmd --add-port=875/udp
firewall-cmd --add-port=892/udp
firewall-cmd --add-port=2049/udp
firewall-cmd --add-port=32803/udp
firewall-cmd --runtime-to-permanent
firewall-cmd --reload

echo "==== install and configure nfs"
yum install nfs-utils -y
echo "/mnt/data *(rw,sync,no_wdelay,no_root_squash,insecure)" >> /etc/exports

#This is a terrible idea
mkdir /mnt/data
chmod -R 777 /mnt/data


service nfs start
exportfs

echo "==== install and configure haproxy"
yum install haproxy -y
cat <<EOT > /etc/haproxy/haproxy.cfg
defaults
	mode                	http
	log                 	global
	option              	httplog
	option              	dontlognull
	option forwardfor   	except 127.0.0.0/8
	option              	redispatch
	retries             	3
	timeout http-request	10s
	timeout queue       	1m
	timeout connect     	10s
	timeout client      	300s
	timeout server      	300s
	timeout http-keep-alive 10s
	timeout check       	10s
	maxconn             	20000

# Useful for debugging, dangerous for production
listen stats
	bind :9000
	mode http
	stats enable
	stats uri /

frontend openshift-api-server
	bind *:6443
	default_backend openshift-api-server
	mode tcp
	option tcplog

backend openshift-api-server
	balance source
	mode tcp
	server master-0 MASTER0IP:6443 check
	server master-1 MASTER1IP:6443 check
	server master-2 MASTER2IP:6443 check
        server bootstrap BOOTSTRAPIP:6443 check

frontend machine-config-server
	bind *:22623
	default_backend machine-config-server
	mode tcp
	option tcplog

backend machine-config-server
	balance source
	mode tcp
        server master-0 MASTER0IP:22623 check
        server master-1 MASTER1IP:22623 check
        server master-2 MASTER2IP:22623 check
        server bootstrap BOOTSTRAPIP:22623 check

frontend ingress-http
	bind *:80
	default_backend ingress-http
	mode tcp
	option tcplog

backend ingress-http
	balance source
	mode tcp
	server worker-0 WORKER0IP:80 check
	server worker-1 WORKER1IP:80 check

frontend ingress-https
	bind *:443
	default_backend ingress-https
	mode tcp
	option tcplog

backend ingress-https
	balance source
	mode tcp
	server worker-0 WORKER0IP:443 check
	server worker-1 WORKER1IP:443 check
EOT


echo "==== install and configure apache"
yum install httpd -y
sed -i 's/Listen 80/Listen 8080/' /etc/httpd/conf/httpd.conf
echo "apache is setup" > /var/www/html/test
service httpd start

echo "==== get okd install, client, and COS images"
mkdir binaries
pushd binaries
wget https://github.com/openshift/okd/releases/download/4.5.0-0.okd-2020-10-03-012432/openshift-client-linux-4.5.0-0.okd-2020-10-03-012432.tar.gz
mv openshift-client-linux-4.5.0-0.okd-2020-10-03-012432.tar.gz openshift-client.tar.gz
wget https://github.com/openshift/okd/releases/download/4.5.0-0.okd-2020-10-03-012432/openshift-install-linux-4.5.0-0.okd-2020-10-03-012432.tar.gz
mv openshift-install-linux-4.5.0-0.okd-2020-10-03-012432.tar.gz openshift-install.tar.gz

mkdir pxe
pushd pxe
# Get fedora-coreos.initramfs.x86_64.img, fedora-coreos.x86_64.iso, fedora-coreos.kernel-x86_64, fedora-coreos.rootfs.x86_64.img, 
# fedora-coreos.metal.x86_64.raw.xz
wget https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/32.20200923.3.0/x86_64/fedora-coreos-32.20200923.3.0-live-initramfs.x86_64.img
mv fedora-coreos-32.20200923.3.0-live-initramfs.x86_64.img fedora-coreos.initramfs.x86_64.img
wget https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/32.20200923.3.0/x86_64/fedora-coreos-32.20200923.3.0-live.x86_64.iso
mv fedora-coreos-32.20200923.3.0-live.x86_64.iso fedora-coreos.x86_64.iso
wget https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/32.20200923.3.0/x86_64/fedora-coreos-32.20200923.3.0-live-kernel-x86_64
mv fedora-coreos-32.20200923.3.0-live-kernel-x86_64 fedora-coreos.kernel-x86_64
# CoreOS now requires rootfs image to boot
wget https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/32.20200923.3.0/x86_64/fedora-coreos-32.20200923.3.0-live-rootfs.x86_64.img
mv fedora-coreos-32.20200923.3.0-live-rootfs.x86_64.img fedora-coreos.rootfs.x86_64.img
wget https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/32.20200923.3.0/x86_64/fedora-coreos-32.20200923.3.0-metal.x86_64.raw.xz
mv fedora-coreos-32.20200923.3.0-metal.x86_64.raw.xz fedora-coreos.metal.x86_64.raw.xz

popd
popd

tar -xvzf ./binaries/openshift-install.tar.gz
tar -xvzf ./binaries/openshift-client.tar.gz

echo "OS upgrades, firewall, haproxy, and apache, as well as OKD packages installed."