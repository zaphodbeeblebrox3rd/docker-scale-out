# Slurm docker-scale-out
Docker compose cluster for Slurm training

> All packages and prerequisite configuration for Debian or RHEL-family Linux distros can be performed by running setup_1.sh.  It might even work on Suse or Arch although further testing is needed.  After rebooting, run setup_2.sh to finish the image build, then run make to start the containers.

>This is not for production use, it is not to be installed on a production server, and it should be on a dedicated VM or test machine to avoid conflicts with other services.
{ .is-info }

## Requirements
- Root access (for running setup scripts and Docker)
- **Memory:** Minimum 12 GB RAM (16 GB or more recommended for a full stack with Elasticsearch, Slurm, and all services)
- **Disk:** At least 30 GB free space for container images, build artifacts, and volumes
- **CPU architecture:** x86_64 (amd64) or arm64 (aarch64)

## Basic Architecture of the cluster

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
  * Admin Console: http://127.0.0.1:8083/
  * User: admin
  * Password: password

## Quick Start
This is built to set up quickly and to use easily afterwards

### Initial Setup
- Run `setup_1.sh`
- Reboot
- Run `setup_2.sh`

### Run the cluster
```
make
```

### Open a shell to a login node or other container
```
make bash
make HOST=login bash
```

## Automated Setup on Windows
Linux is recommended but it is possible to use Windows. Run the setup_win powershell script.
```
./setup_win.ps1
```

## Managing the cluster
Beyond just starting the cluster, you may want to stop it or rebuild it from time to time while tinkering with it.

### Stop the cluster
```
make stop
```

### Reverse all runtime changes
```
make clean
```

### Remove all images
```
make uninstall
```


## Custom Nodes

Custom node lists may be provided by setting NODELIST to point to a file
containing list of nodes for the cluster or modifying the default generated
"nodelist" file in the scaleout directory.

The node list follows the following format with one node per line:
> ${HOSTNAME} ${CLUSTERNAME} ${IPv4} ${IPv6}

Example line:
> node00 scaleout 10.11.5.0 2001:db8:1:1::5:0

Note that the service nodes can not be changed and will always be placed into
the following subnets:
> ${SUBNET}.1.0/24
> ${SUBNET6}1:0/122

## Multiple Instances
Each cluster must have a unique class B subnet.

Default IPv4 is SUBNET="10.11".
Default IPv6 is SUBNET6="2001:db8:1:1::".

## Custom Slurm version

To specify an explicit version of Slurm to be compiled and installed:
> export SLURM_RELEASE=slurm-$version

Make sure to call `make clean` after to invalidate all the caches with the
prior release.

### To build images

```
git submodule update --init --force --remote --recursive
make build
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

If you see `unauthorized` or `authentication required` during image pulls, treat that as an environment or registry-access issue. The user setup flow does not perform `docker login` and expects public image access.

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

## How to disable building xdmod container

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

When this happens, fewer jobs must be run as this a kernel limitation.
