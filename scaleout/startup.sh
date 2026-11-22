#!/bin/bash

# Add hosts in the not crazy slow manner
cat /etc/hosts.nodes >>/etc/hosts

#cgroup v1: Docker 25+ mounts the read-only /sys/fs/cgroup bind recursively, so make the controllers writable again for systemd
[ ! -f /sys/fs/cgroup/cgroup.controllers ] && awk '$5 ~ "^/sys/fs/cgroup/." && / - cgroup2? / {print $5}' /proc/self/mountinfo |
	xargs -r -n1 mount -o remount,bind,rw 2>/dev/null

#ensure the systemd cgroup directory exists for enroot
awk -F: '$2 ~ /systemd/ {printf "/sys/fs/cgroup/systemd/%s", $3}' /proc/self/cgroup |
	xargs mkdir -p

#systemd user@.service handles on normal nodes
for i in arnold bambam barney betty chip dino edna fred gazoo pebbles wilma; do
	uid=$(id -u $i)
	mkdir -p /run/user/${uid}/local
	mkdir -p /run/user/${uid}/enroot/{runtime,cache,data,tmp}
	chmod 0700 -R /run/user/${uid}/{local,enroot}
	chown -R $i:users /run/user/${uid}/enroot
	chown $i:users /run/user/$uid
done

ls /usr/lib/systemd/system/slurm*.service | while read s; do
	#We must set the cluster environment variable for all services since systemd drops it for the services
	mkdir -p ${s}.d
	echo -e "[Service]\nEnvironment=SLURM_FEDERATION_CLUSTER=${SLURM_FEDERATION_CLUSTER}\n" >${s}.d/cluster.conf
done

#cgroup v2 with a private cgroup namespace: systemd needs /sys/fs/cgroup writable
[ -f /sys/fs/cgroup/cgroup.controllers ] && mount -o remount,rw /sys/fs/cgroup 2>/dev/null

#start systemd
exec /lib/systemd/systemd --system --log-level=info --crash-reboot --log-target=console
