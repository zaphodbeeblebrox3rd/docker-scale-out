#!/bin/bash
#cgroup v2 with a private cgroup namespace: systemd needs /sys/fs/cgroup writable
[ -f /sys/fs/cgroup/cgroup.controllers ] && mount -o remount,rw /sys/fs/cgroup 2>/dev/null
#cgroup v1: Docker 25+ mounts the read-only /sys/fs/cgroup bind recursively, so make the controllers writable again for systemd
[ ! -f /sys/fs/cgroup/cgroup.controllers ] && awk '$5 ~ "^/sys/fs/cgroup/." && / - cgroup2? / {print $5}' /proc/self/mountinfo |
	xargs -r -n1 mount -o remount,bind,rw 2>/dev/null

exec /lib/systemd/systemd --system --log-level=info --log-target=journal-or-kmsg
