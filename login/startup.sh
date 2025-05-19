#!/bin/bash

# Start SSH service
/usr/sbin/sshd

# Start Slurm daemon
/usr/sbin/slurmd

# Keep container running
tail -f /dev/null 