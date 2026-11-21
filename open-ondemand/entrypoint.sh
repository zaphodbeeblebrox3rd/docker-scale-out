#!/bin/bash

#
# /home must be mounted in order to add users with correct UIDs
#
getent group bedrock >/dev/null || groupadd -g 1005 bedrock
touch /etc/httpd/.htpasswd
cd /home || exit
for i in *; do
	[ -d "/home/$i" ] || continue
	TUID=$(stat -c %u "/home/$i")
	htpasswd -b /etc/httpd/.htpasswd "$i" password
	id "$i" >/dev/null 2>&1 || /usr/sbin/useradd -M -u "$TUID" -c "$i" -g users -G bedrock "$i"
done

#
# Clone over SSH config
#
for i in ssh_config ssh_host_ecdsa_key ssh_host_ecdsa_key.pub ssh_host_ed25519_key ssh_host_ed25519_key.pub ssh_host_rsa_key ssh_host_rsa_key.pub ssh_known_hosts sshd_config; do
	ln -nfs /etc/shared-ssh/$i /etc/ssh/$i
done

exec /usr/sbin/httpd -DFOREGROUND
