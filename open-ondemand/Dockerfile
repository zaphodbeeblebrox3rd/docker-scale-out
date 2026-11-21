FROM docker.io/library/almalinux:9
RUN dnf -y install https://yum.osc.edu/ondemand/4.2/ondemand-release-web-4.2-1.el9.noarch.rpm epel-release dnf-plugins-core && \
	dnf config-manager --set-enabled crb && \
	dnf -y module enable ruby:3.3 nodejs:22 && \
	dnf -y install ondemand httpd-tools openssh-clients sudo util-linux procps-ng && \
	dnf clean all && \
	rm -f /etc/httpd/conf.d/ssl.conf
COPY ood_portal.yml /etc/ood/config/ood_portal.yml
COPY scaleout.yaml /etc/ood/config/clusters.d/scaleout.yml
RUN /opt/ood/ood-portal-generator/sbin/update_ood_portal --force
COPY entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh

RUN mkdir -p /usr/local/bin/
COPY sbatch scancel scontrol squeue /usr/local/bin/
RUN chmod 0755 /usr/local/bin/{sbatch,scancel,scontrol,squeue}

EXPOSE 80
CMD ["/entrypoint.sh"]
