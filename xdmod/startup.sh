#!/bin/bash
#cgroup v2 with a private cgroup namespace: systemd needs /sys/fs/cgroup writable
[ -f /sys/fs/cgroup/cgroup.controllers ] && mount -o remount,rw /sys/fs/cgroup 2>/dev/null

exec /lib/systemd/systemd --system --log-level=info --log-target=journal-or-kmsg
