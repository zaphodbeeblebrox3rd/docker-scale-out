#!/bin/bash
#only configure once
[ -f /var/run/slurmdbd.startup ] && exit 0

touch /var/log/slurmdbd.log
chown slurm:slurm /var/log/slurmdbd.log

date > /var/run/slurmdbd.startup

exit 0
