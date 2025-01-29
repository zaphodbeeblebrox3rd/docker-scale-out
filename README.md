# slurm-docker-scaleout
Docker compose cluster for testing Slurm

## Prerequisites
  * docker (25.x.x+ with cgroupsv2 or 24.x.x with cgroupsv1)
    * IPv6 must be configured in docker: https://docs.docker.com/config/daemon/ipv6/
  * docker-compose-plugin v2.18.1+
  * ssh (client)
  * jq
  * python3
    * python3-daemon

## Changes needed in sysctl.conf:
```
net.ipv4.tcp_max_syn_backlog=4096
net.core.netdev_max_backlog=1000
net.core.somaxconn=15000

# Force gc to clean-up quickly
net.ipv4.neigh.default.gc_interval = 3600

# Set ARP cache entry timeout
net.ipv4.neigh.default.gc_stale_time = 3600

# Setup DNS threshold for arp
net.ipv4.neigh.default.gc_thresh3 = 8096
net.ipv4.neigh.default.gc_thresh2 = 4048
net.ipv4.neigh.default.gc_thresh1 = 1024

# Increase map count for elasticsearch
vm.max_map_count=262144

# Avoid running out of file descriptors
fs.file-max=10000000
fs.inotify.max_user_instances=65535
fs.inotify.max_user_watches=1048576

#Request kernel max number of cgroups
fs.inotify.max_user_instances=65535
```

## Docker configuration required with cgroupsv2

Make sure the host machine is running CgroupV2 and not hybrid mode:
	https://slurm.schedmd.com/faq.html#cgroupv2

Add these settings to the docker configuration: /etc/docker/daemon.json
```
{
  "exec-opts": [
    "native.cgroupdriver=systemd"
  ],
  "features": {
    "buildkit": true
  },
  "experimental": true,
  "cgroup-parent": "docker.slice",
  "default-cgroupns-mode": "host",
  "storage-driver": "overlay2"
}
```

Configure systemd to allow docker to run in it's own slice to avoid systemd
conflicting with it:

/etc/systemd/system/docker.slice:
```
[Unit]
Description=docker slice
Before=slices.target
[Slice]
CPUAccounting=true
MemoryAccounting=true
Delegate=yes
```

/usr/lib/systemd/system/docker.service.d/local.conf:
```
[Service]
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
Delegate=yes
```

Activate the changes:
```
systemctl daemon-reload
systemctl restart docker.slice docker
```

## Basic Architecture

Maria Database Node:
  * db

Slurm Management Nodes:
  * mgmtnode
  * mgmtnode2
  * slurmdbd

Compute Nodes:
  * node[00-09]

Login Nodes:
  * login

Nginx Proxy node:
 * proxy

Rest API Nodes:
  * rest

Kibana (Only supports IPv4):
  * View http://127.0.0.1:5601/

Elasticsearch:
  * View http://localhost:9200/

Grafana:
  * View http://localhost:3000/
  * User: admin
  * Password: admin

Open On-Demand:
  * View http://localhost:8081/
  * User: {user name - "fred" or "wilma"}
  * Password: password

Open XDMoD:
  * View http://localhost:8082/

Proxy:
  * Auth REST API http://localhost:8080/auth
  * Query REST API http://localhost:8080/slurm/

Keycloak
  * Admin Console: http://localhost:8083/
  * User: admin
  * Password: password

## Multiple Instances
Each cluster must have a unique class B subnet.

Default IPv4 is SUBNET="10.11".
Default IPv6 is SUBNET6="2001:db8:1:1::".

## Custom Nodes

Custom node lists may be provided by setting NODELIST to point to a file
containing list of nodes for the cluster or modifing the default generated
"nodelist" file in the scaleout directory.

The node list follows the following format with one node per line:
> ${HOSTNAME} ${CLUSTERNAME} ${IPv4} ${IPv6}

Example line:
> node00 scaleout 10.11.5.0 2001:db8:1:1::5:0

Note that the service nodes can not be changed and will always be placed into
the following subnets:
> ${SUBNET}.1.0/24
> ${SUBNET6}1:0/122

## Custom Slurm version

To specify an explicit version of Slurm to be compiled and installed:
> export SLURM_RELEASE=slurm-$version

Make sure to call `make clean` after to invalidate all the caches with the
prior release.

## To build images

```
git submodule update --init --force --remote --recursive
make build
```

## To run:

```
make
```

## To build and run in Cloud mode:

```
make clean
make cloud
```

Note: cloud mode will run in the foreground.

## To build without caching:

```
make nocache
```

## To stop:

```
make stop
```

## To reverse all changes:

```
make clean
```

## To remove all images:

```
make uninstall
```

## To control:

```
make bash
make HOST=node1 bash
```

## To login via ssh
```
ssh-keygen -f "/home/$(whoami)/.ssh/known_hosts" -R "10.11.1.5" 2>/dev/null
ssh -o StrictHostKeyChecking=no -l fred 10.11.1.5 -X #use 'password'
```

## Federation Mode

Federation mode will create multiple Slurm clusters with nodes and slurmctld
daemons. Other nodes will be shared, such as login and slurmdbd.

To create multiple federation clusters:
```
export FEDERATION="taco burrito quesadilla"
echo "FederationParameters=fed_display" >> scaleout/slurm/slurm.conf
truncate -s0 scaleout/nodelist
make clean
make build
make
```

Configure Slurm for multiple federation clusters:
```
make HOST=quesadilla-mgmtnode bash
sacctmgr add federation scaleout clusters=taco,burrito,quesadilla
```

### Activate Federation mode in Slurm

Notify slurmdbd to use federation after building cluster:
```
export FEDERATION="taco burrito quesadilla"
make HOST=taco-mgmtnode bash
sacctmgr add federation scaleout cluster=taco,burrito,quesadilla
```

### Deactivate to Federation mode

```
export FEDERATION="taco burrito quesadilla"
make uninstall
truncate -s0 scaleout/nodelist
```

## Caveats

The number of CPU threads on the host are multiplied by the number of nodes. Do not attempt to use computationally intensive applications.

## Docker work-arounds:

```
ERROR: Pool overlaps with other one on this address space
```
or
```
failed to prepare ${HASH}: max depth exceeded
ERROR: Service 'slurmdbd' failed to build : Build failed
```
Call this:
```
make clean
docker network prune -f
sudo systemctl restart docker
```

## To save all images to ./scaleout.tar

```
make save
```

## To load saved copy of all images

```
make load
```

## To test building

```
git submodule update --init --force --remote --recursive
make test-build
```

## How to trigger manual xdmod data dump:

```
make HOST=scaleout_mgmtnode_1 bash
bash /etc/cron.hourly/dump_xdmod.sh
exit
make bash
exec bash /etc/cron.hourly/dump_xdmod.sh
make HOST=xdmod bash
sudo -u xdmod -- /usr/bin/xdmod-shredder -r scaleout -f slurm -i /xdmod/data.csv
sudo -u xdmod -- /usr/bin/xdmod-ingestor
exit
```

## How to disable buidling xdmod container

This is will only disable attempts to build and start the container.

```
export DISABLE_XDMOD=1
```

## Maxing out kernel cgroups total

The Linux kernel has a hard limit of 65535 cgroups total. Stacking large number
of jobs or scaleout instances may result in the following error:

```
error: proctrack_g_create: No space left on device
```

When this happens, fewers jobs must be run as this a kernel limitation.
