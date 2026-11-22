#!/bin/bash
#exec 1> >(logger -s -t influxdb-setup) 2>&1

#set up here rather than with DOCKER_INFLUXDB_INIT_MODE: the entrypoint gives up if influxd
#still answers 503 while running its startup migrations, so retry until setup is accepted
until curl -s http://localhost:8086/api/v2/setup | grep -q '"allowed": *false'; do
	influx setup -f -u user -p password -o scaleout -b scaleout -r 1w -t token >/dev/null 2>&1 ||
		sleep 1
done

function pingit {
	influx v1 auth list 1>&2

	echo $?
}

#wait until the daemon is responding
while [ "$(pingit)" != 0 ]; do
	sleep 0.1
done

sleep 2

B=$(while true; do
	influx bucket list 2>/dev/null >/tmp/buckets
	B=$(awk '
	BEGIN { rc = 1 }
	/scaleout/ {
		if (length($1) > 5 && $1 !~ /Error/) {
			print $1; rc = 0
		}
	}
	END {exit rc}
	' </tmp/buckets)
	[ $? -eq 0 ] && echo "$B" && break
	sleep 0.1
done)

echo "Found bucket: $B"

influx v1 dbrp create \
	--db scaleout --rp scaleout \
	--bucket-id $B \
	--default

influx v1 auth create \
	-c default \
	-d "slurm user" \
	--org scaleout \
	--password "password" \
	--username "user" \
	--write-bucket $B \
	--read-bucket $B

influx v1 auth create \
	-c default \
	-d "slurm user" \
	--org scaleout \
	--no-password \
	--username "admin" \
	--write-bucket $B \
	--read-bucket $B
