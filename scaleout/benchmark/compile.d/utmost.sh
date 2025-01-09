#!/bin/bash

sed -i /etc/slurm/slurm.conf \
	-e 'd/JobComp/' \
	-e 'd/JobAcctGather/' \
	-e 'd/AcctGatherProfileType/' \
	-e 'd/Suspend/' \
	-e 'd/Resume/' \
	-e 'd/cloud/' \
	-e 'd/PrologFlags/' \
	-e 'd/X11Parameters/'

unlink /etc/slurm/acct_gather.conf
unlink /etc/slurm/plugstack.conf

cat <<EOF >> /etc/slurm/slurm.conf
SlurmctldParameters=enable_rpc_queue,enable_job_state_cache
MaxArraySize=1000000
MaxJobCount=1000000
MessageTimeout=100

SlurmdDebug=error
SlurmctldDebug=error
SchedulerParameters=bf_continue,bf_interval=60,bf_max_time=60,bf_resolution=120,defer,max_rpc_cnt=250,sched_interval=10
EOF
