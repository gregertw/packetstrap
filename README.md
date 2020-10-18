# Adapted from James Labocki

Original scripts from James Labocki at https://github.com/jameslabocki/packetstrap/

## Deploying OKD 4.5 on Packet
You need:

 - SSH keys configured in Packet
 - A domain registered in AWS Route53 (feel free to use your favorite DNS service)
 - Access to OpenShift subscriptions

 You will want to deploy "On Demand" server types for all servers deployed.

First, deploy the following:

 - x1.small.x86 ($0.40/hour)
 - Operating System = CentOS 7

This node will act as our “helper”. This is not to be confused with the bootstrap node for deploying OKD. We will deploy that later. The “helper” will be where we run the os-strap.sh and okd-strap.sh scripts to get everything ready to go.

## Get the helper ready

Once x1.small.x86 is up and running ssh to it and:
Install git:
```
sudo yum install git
```

Then check out the repo:
```
git clone https://github.com/gregertw/packetstrap.git
```

You don't need a pull-secret for OKD.

Make sure you are in the dir above packetstrap/ (sub-dirs will be created) and run ./os-strap.sh.

Now you have all the binaries needed. The okd-strap.sh file assumes your public IP NIC is named bond0 in the iPXE boot info. 
If not, edit okd-strap.sh to use the correct NIC. If you only have one NIC, you can remove bond0: and just use ip=dhcp.

After that, run the okd-strap.sh script and pass it two arguments:

 - The domain name (demonstr8.net below)
 - The sub-domain name and/or cluster name (test below)

```
# ./okd-strap.sh demonstr8.net test
```

This will take a little bit to run and it does a lot of things. In the end, if everything worked you should see this:

```
==== create manifests
INFO Consuming Install Config from target directory
WARNING Making control-plane schedulable by setting MastersSchedulable to true for Scheduler cluster settings
INFO Consuming Worker Machines from target directory
INFO Consuming Openshift Manifests from target directory
INFO Consuming OpenShift Install (Manifests) from target directory
INFO Consuming Common Manifests from target directory
INFO Consuming Master Machines from target directory
==== Create publicly accessible directory, Copy ignition files, Create iPXE files
==== all done, you can now iPXE servers to:
http://147.75.199.131:8080/packetstrap/bootstrap.boot
http://147.75.199.131:8080/packetstrap/master.boot
http://147.75.199.131:8080/packetstrap/worker.boot
```


Your IP address will be different of course. As you can see, you are provided with the iPXE boot URLs for the bootstrap, master, and worker nodes. 

## Bootstrapping OKD servers

You now have the load balancer (haproxy), the helper apache server, the images, as well as the configurations. It's time to load Fedora CoreOS
and the right software config on the bootstrap, master, and worker nodes.

Now you can boot the following in Packet console (choose your own server type):

 - bootstrap – c3.medium.x86 – custom iPXE – use the bootstrap.boot URL above

### A note on iPXE boot

The iPXE boot will pull the images from the helper node, configure the system with the ignition file and install the boot image.

Typically, the process includes loading the images, rebooting, installing the partitions and configuring the system, rebooting, load Fedora CoreOS,
and install the OKD config, and ... rebooting. This takes quite a bit of time. 

NOTE!!! The Packet out-of-band console will not be able to show anything once the server has booted into Fedora CoreOS.

### Bootstrapping masters and workers

Once you have an IP address for the bootstrap node, you need to configure DNS for api-int.<sub-domain>.<domain>, e.g. api-int.okd.mydomain.com. 
This is because the ignition files for master and worker nodes references the DNS domain name.

Once the DNS resolution is verified working, you can continue bootstrapping:

 - master0 – c3.medium.x86 – custom iPXE – use the master.boot URL above
 - master1 – c3.medium.x86 – custom iPXE – use the master.boot URL above
 - master2 – c3.medium.x86 – custom iPXE – use the master.boot URL above
 - worker1 – s3.xlarge.x86 – custom iPXE – use the worker.boot URL above
 - worker2 – s3.xlarge.x86 – custom iPXE – use the worker.boot URL above

In AM6, the c3.medium server is a Dell PowerEdge R6515.

As those boot, you’ll need to get those IP addresses into your favourite DNS and also change haproxy to have the right IP addresses.

## Finalise config on helper

Then it will reboot. Once it's up and running, you should be able to ssh into the server using the core users and the created key:

```
ssh core@a.b.c.d
```

For editing haproxy you can just edit the values in the fixhaproxy.sh and run the script.

```
# vi fixhaproxy.sh
<assign IP addresses>
# ./fixhaproxy.sh
```

Now you can connect to your helper node on http://a.b.c.d:9000/ and look at haproxy status as the servers are coming up.

## Bootstrap OKD

If everything worked, the bootstrap server and masters should start building an OKD cluster.

Use this to monitor to bootstrap:

```
# ./openshift-install --dir=packetinstall wait-for bootstrap-complete --log-level=info 
INFO Waiting up to 20m0s for the Kubernetes API at https://api.test.demonstr8.net:6443&#8230;
```

It should look like this if it succeeds:

```
# ./openshift-install --dir=packetinstall wait-for bootstrap-complete --log-level=info
INFO Waiting up to 20m0s for the Kubernetes API at https://api.test.demonstr8.net:6443... 
INFO API v1.17.1 up                               
INFO Waiting up to 40m0s for bootstrapping to complete... 
INFO It is now safe to remove the bootstrap resources 
```

Once it returns you can remove the bootstrap server (or comment it out) from /etc/haproxy/haproxy.cfg and restart haproxy.

```
# vi /etc/haproxy/haproxy.cfg
 <comment out bootstrap node>
# systemctl restart haproxy.service
```

Then you can source your kubeconfig and be on your way.

```
# export KUBECONFIG=/root/packetinstall/auth/kubeconfig
# ./oc whoami
```

You can get the nodes and see that the masters are there.

```
# ./oc get nodes
```

The workers will not be there because you need to approve their Certificate Signining Requests (CSR).

```
# ./oc get csr
```

You can approve the pending requests quickly like this.

```
# ./oc get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}' | xargs ./oc adm certificate approve
```

Now you should be able to point your browser at the OpenShift console located at https://console-openshift-console.apps.test.demonstr8.net/ where test = cluster name and demonstr8.net = basedomain or $2 and $3 from your packetstrap.sh command at the start.

If you want to enable an image registry quickly you can do that by running imageregistry.sh. Note that this is not meant for production use as it uses local storage.

```
# ./imageregistry.sh
```

If you want to create some persistent volumes you can run the persistentvolumes.sh script. It will create four persistent volumes on the NFS directory that is exported from the helper node.

```
# ./persistentvolumes.sh
```

Now you can download the [RHEL 8.1 guest image](https://access.redhat.com/downloads/content/479/ver=/rhel---8/8.1/x86_64/product-software), upload it to /var/www/html on the helper node and get to deploying some VMs on [OpenShift Virtualization](https://docs.openshift.com/container-platform/4.4/welcome/index.html)!
