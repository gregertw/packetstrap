#!/bin/bash

# This simple bash scripts will do just about everything needed to have a helper node for deployment of OKD
#  
# You need to:
#   - Pass your domain name as $1
#   - Pass your subdomain name (and cluster name) as $2
# For example: ./packetstrap.sh demonstr8.net test

# You also need to:
#   - have a ssh key in ~/.ssh/id_rsa.pub 

[[ $# -ne 2 ]] && echo "Please provide 2 arguments" && exit 254

# Create SSH key
ssh-keygen -b 2048 -t rsa -f /root/.ssh/id_rsa -q -N ""

echo "==== Setting variables"
# Pullsecret for OKD
PULLSECRET="{\"auths\":{\"fake\":{\"auth\": \"bar\"}}}"
BASEDOMAIN=$1
METADATANAME=$2
SSHKEY=`cat ~/.ssh/id_rsa.pub`
PUBLICIP=`ip address show dev bond0 |grep bond0 |grep -v bond0:0 |grep inet |awk -F" " '{ print $2}' |awk -F"/" '{print $1}'`

echo "==== create manifests"
mkdir packetinstall
cat <<EOT > packetinstall/install-config.yaml
apiVersion: v1
baseDomain: BASEDOMAIN
compute:
- hyperthreading: Enabled   
  name: worker
  replicas: 0 
controlPlane:
  hyperthreading: Enabled   
  name: master 
  replicas: 3 
metadata:
  name: METADATANAME
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14 
    hostPrefix: 23 
  networkType: OpenShiftSDN
  serviceNetwork: 
  - 172.30.0.0/16
platform:
  none: {} 
fips: false 
pullSecret: 'PULLSECRET'
sshKey: 'SSHKEY'
EOT

sed -i "s/BASEDOMAIN/${BASEDOMAIN}/" packetinstall/install-config.yaml
sed -i "s/METADATANAME/${METADATANAME}/" packetinstall/install-config.yaml
sed -i "s%PULLSECRET%${PULLSECRET}%" packetinstall/install-config.yaml
sed -i "s%SSHKEY%${SSHKEY}%" packetinstall/install-config.yaml

./openshift-install create manifests --dir=packetinstall

sed -i 's/mastersSchedulable: true/mastersSchedulable: false/' packetinstall/manifests/cluster-scheduler-02-config.yml

./openshift-install create ignition-configs --dir=packetinstall


echo "==== Create publicly accessible directory, Copy ignition files, Create iPXE files"

mkdir /var/www/html/packetstrap
cp packetinstall/*.ign /var/www/html/packetstrap/
cp ./binaries/pxe/* /var/www/html/packetstrap/
chmod 644 /var/www/html/packetstrap/*.ign


# Set up bootstrap with fedora-coreos.initramfs.x86_64.img, fedora-coreos.x86_64.iso, fedora-coreos.kernel-x86_64, fedora-coreos.rootfs.x86_64.img, 
# fedora-coreos.metal.x86_64.raw.xz
# Removed coreos.inst.image_url=http://PUBLICIP:8080/packetstrap/fedora-coreos.metal.x86_64.raw.xz
cat <<EOT > /var/www/html/packetstrap/bootstrap.boot
#!ipxe

kernel http://PUBLICIP:8080/packetstrap/fedora-coreos.kernel-x86_64 ip=dhcp rd.neednet=1 ignition.firstboot ignition.platform.id=metal console=ttyS1,115200n8 coreos.inst=yes coreos.inst.install_dev=/dev/sda coreos.inst.ignition_url=http://PUBLICIP:8080/packetstrap/bootstrap.ign coreos.live.rootfs_url=http://PUBLICIP:8080/packetstrap/fedora-coreos.rootfs.x86_64.img systemd.unified_cgroup_hierarchy=0
initrd http://PUBLICIP:8080/packetstrap/fedora-coreos.initramfs.x86_64.img 
boot
EOT

cat <<EOT > /var/www/html/packetstrap/master.boot
#!ipxe

kernel http://PUBLICIP:8080/packetstrap/fedora-coreos.kernel-x86_64 ip=dhcp rd.neednet=1 ignition.firstboot ignition.platform.id=metal console=ttyS1,115200n8 coreos.inst=yes coreos.inst.install_dev=/dev/sda coreos.inst.ignition_url=http://PUBLICIP:8080/packetstrap/master.ign coreos.live.rootfs_url=http://PUBLICIP:8080/packetstrap/fedora-coreos.rootfs.x86_64.img systemd.unified_cgroup_hierarchy=0
initrd http://PUBLICIP:8080/packetstrap/fedora-coreos.initramfs.x86_64.img 
boot
EOT

cat <<EOT > /var/www/html/packetstrap/worker.boot
#!ipxe

kernel http://PUBLICIP:8080/packetstrap/fedora-coreos.kernel-x86_64 ip=dhcp rd.neednet=1 ignition.firstboot ignition.platform.id=metal console=ttyS1,115200n8 coreos.inst=yes coreos.inst.install_dev=/dev/sda coreos.inst.ignition_url=http://PUBLICIP:8080/packetstrap/worker.ign coreos.live.rootfs_url=http://PUBLICIP:8080/packetstrap/fedora-coreos.rootfs.x86_64.img systemd.unified_cgroup_hierarchy=0
initrd http://PUBLICIP:8080/packetstrap/fedora-coreos.initramfs.x86_64.img
boot
EOT


sed -i "s/PUBLICIP/$PUBLICIP/g" /var/www/html/packetstrap/bootstrap.boot
sed -i "s/PUBLICIP/$PUBLICIP/g" /var/www/html/packetstrap/master.boot
sed -i "s/PUBLICIP/$PUBLICIP/g" /var/www/html/packetstrap/worker.boot



echo "==== all done, you can now iPXE servers to:"
echo "       http://${PUBLICIP}:8080/packetstrap/bootstrap.boot" | tee -a iPXE_info.txt
echo "       http://${PUBLICIP}:8080/packetstrap/master.boot" | tee -a iPXE_info.txt
echo "       http://${PUBLICIP}:8080/packetstrap/worker.boot" | tee -a iPXE_info.txt

echo "==== setting path"
export PATH=$PATH:$PWD



