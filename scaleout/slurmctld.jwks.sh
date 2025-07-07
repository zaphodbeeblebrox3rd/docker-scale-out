#!/bin/bash
#Grab JWKS from keycloak

[ {DISABLE_KEYCLOAK} ] && echo "Skipping populating jwks.json" && exit 0

while [ 1 ]
do
	curl -s "http://{SUBNET}.1.23:8080/realms/master/protocol/openid-connect/certs" > /etc/slurm/jwks.json
	if [ $? -eq 0 -a -s /etc/slurm/jwks.json ]
	then
		keys=$(jq '.keys | length' /etc/slurm/jwks.json)
		if [ $? -eq 0 ] && [[ "$keys" =~ ^[[:digit:]]+$ ]] && [ "$keys" -gt 0 ]
		then
			echo "Downloaded JWKS"
			break
		else
			echo "Retrying JWKS download"
			unlink /etc/slurm/jwks.json
		fi
	fi
done

exit 0
