# PowerShell version of buildout.sh
param(
    [string]$Subnet = "10.11",
    [string]$Subnet6 = "2001:db8:1:1::",
    [string]$Nodelist = "scaleout/nodelist",
    [string]$SlurmBenchmark = "",
    [string]$Federation = ""
)

# Function to generate node list
function Generate-NodeList {
    param(
        [int]$NodesCount = 9
    )

    if ($Federation) {
        $c_sub = 5
        if (Test-Path $Nodelist) {
            Remove-Item $Nodelist -Force
        }
        
        $Federation.Split() | ForEach-Object {
            $c = $_
            0..$NodesCount | ForEach-Object {
                $i = $_
                "$(("{0}-node{1:D2}" -f $c, $i)) $c ${Subnet}.${c_sub}.$($i + 10) ${Subnet6}${c_sub}:$($i + 10)"
            } | Add-Content $Nodelist
            $c_sub++
        }
    }
    else {
        # Generate list of nodes
        0..$NodesCount | ForEach-Object {
            $i = $_
            "{0} cluster ${Subnet}.5.$($i + 10) ${Subnet6}5:$($i + 10)"
        } | Set-Content $Nodelist
    }
}

# Function to generate hosts file
function Generate-HostsFile {
    if (Test-Path "scaleout/hosts.nodes") {
        Remove-Item "scaleout/hosts.nodes" -Force
    }

    Get-Content $Nodelist | ForEach-Object {
        $name, $cluster, $ip4, $ip6 = $_ -split '\s+'
        if ($ip4) { "$ip4 $name" | Add-Content "scaleout/hosts.nodes" }
        if ($ip6) { "$ip6 $name" | Add-Content "scaleout/hosts.nodes" }
    }
}

# Generate host list for docker-compose
function Get-HostList {
    $hosts = @{}
    
    # Add standard hosts
    $hosts["db"] = "${Subnet}.1.3"
    $hosts["db6"] = "${Subnet6}1:3"
    $hosts["slurmdbd"] = "${Subnet}.1.2"
    $hosts["slurmdbd6"] = "${Subnet6}1:2"
    $hosts["login"] = "${Subnet}.1.5"
    $hosts["login6"] = "${Subnet6}1:5"
    $hosts["rest"] = "${Subnet}.1.6"
    $hosts["rest6"] = "${Subnet6}1:6"
    $hosts["proxy"] = "${Subnet}.1.7"
    $hosts["proxy6"] = "${Subnet6}1:7"
    $hosts["es01"] = "${Subnet}.1.15"
    $hosts["es016"] = "${Subnet6}1:15"
    $hosts["es02"] = "${Subnet}.1.16"
    $hosts["es026"] = "${Subnet6}1:16"
    $hosts["es03"] = "${Subnet}.1.17"
    $hosts["es036"] = "${Subnet6}1:17"
    $hosts["kibana"] = "${Subnet}.1.18"
    $hosts["kibana6"] = "${Subnet6}1:18"
    $hosts["influxdb"] = "${Subnet}.1.19"
    $hosts["influxdb6"] = "${Subnet6}1:19"
    $hosts["grafana"] = "${Subnet}.1.20"
    $hosts["grafana6"] = "${Subnet6}1:20"
    $hosts["open-ondemand"] = "${Subnet}.1.21"
    $hosts["open-ondemand6"] = "${Subnet6}1:21"
    $hosts["xdmod"] = "${Subnet}.1.22"
    $hosts["xdmod6"] = "${Subnet6}1:22"
    $hosts["keycloak"] = "${Subnet}.1.23"
    $hosts["keycloak6"] = "${Subnet6}1:23"

    if ($Federation) {
        $c_sub = 5
        $Federation.Split() | ForEach-Object {
            $c = $_
            $hosts["${c}-mgmtnode"] = "${Subnet}.${c_sub}.1"
            $hosts["${c}-mgmtnode6"] = "${Subnet6}${c_sub}:1"
            $hosts["${c}-mgmtnode2"] = "${Subnet}.${c_sub}.2"
            $hosts["${c}-mgmtnode26"] = "${Subnet6}${c_sub}:2"
            $c_sub++
        }
    }
    else {
        $hosts["mgmtnode"] = "${Subnet}.1.1"
        $hosts["mgmtnode6"] = "${Subnet6}1:1"
        $hosts["mgmtnode2"] = "${Subnet}.1.4"
        $hosts["mgmtnode26"] = "${Subnet6}1:4"
    }

    return $hosts
}

# Main execution
$NodesCount = if ($SlurmBenchmark) { 100 } else { 9 }

# Generate node list if needed
if (-not (Test-Path $Nodelist) -or $SlurmBenchmark) {
    Generate-NodeList -NodesCount $NodesCount
}

# Generate hosts file
Generate-HostsFile

# Get host list
$hosts = Get-HostList

# Generate docker-compose.yml
$slurmBenchmarkArg = if ($SlurmBenchmark) { "        SLURM_BENCHMARK: $SlurmBenchmark" } else { "" }

# Format hosts for YAML
$formattedHosts = $hosts.GetEnumerator() | ForEach-Object { "      - `"$($_.Key):$($_.Value)`"" } | Out-String

$composeContent = @"
networks:
  internal:
    driver: bridge
    driver_opts:
        com.docker.network.bridge.enable_ip_masquerade: 'true'
        com.docker.network.bridge.enable_icc: 'true'
    internal: false
    enable_ipv6: true
    ipam:
      config:
        - subnet: "${Subnet}.0.0/16"
        - subnet: "${Subnet6}/64"

volumes:
  root-home:
  home:
  etc-ssh:
  cluster-etc-slurm:
  slurmctld:
  elastic_data01:
  elastic_data02:
  elastic_data03:
  mail:
  auth:
  xdmod:
  src:
  container-shared:

services:
  db:
    image: sql_server:latest
    build:
      context: ./sql_server
      args:
        SUBNET: "${Subnet}"
        SUBNET6: "${Subnet6}"
    environment:
      - MYSQL_ROOT_PASSWORD=password
      - MYSQL_USER=slurm
      - MYSQL_PASSWORD=password
      - MYSQL_DATABASE=slurm_acct_db
      - SUBNET="${Subnet}"
      - SUBNET6="${Subnet6}"
    hostname: db
    networks:
      internal:
        ipv4_address: "${Subnet}.1.3"
        ipv6_address: "${Subnet6}1:3"
    tty: true
    logging:
      driver: local
    cap_add:
      - SYS_PTRACE
      - SYS_ADMIN
      - MKNOD
      - SYS_NICE
      - SYS_RESOURCE
    security_opt:
      - seccomp:unconfined
      - apparmor:unconfined
    extra_hosts:
$formattedHosts

  slurmdbd:
    build:
      context: ./scaleout
      dockerfile: Dockerfile.win
      args:
        DOCKER_FROM: almalinux:8
        SLURM_RELEASE: master
        DISTRO: almalinux:8
$slurmBenchmarkArg
    image: scaleout:latest
    hostname: slurmdbd
    networks:
      internal:
        ipv4_address: "${Subnet}.1.2"
        ipv6_address: "${Subnet6}1:2"
    volumes:
      - root-home:/root
      - cluster-etc-slurm:/etc/slurm
      - mail:/var/spool/mail/
      - src:/usr/local/src/
      - /etc/localtime:/etc/localtime:ro
      - /run/
      - /run/lock/
      - /sys/
      - /sys/fs/cgroup/:/sys/fs/cgroup/:ro
      - /sys/fs/cgroup/docker.slice/:/sys/fs/cgroup/docker.slice/:rw
      - /sys/fs/fuse/:/sys/fs/fuse/:rw
      - /tmp/
      - /var/lib/journal
    tty: true
    logging:
      driver: local
    cap_add:
      - SYS_PTRACE
      - SYS_ADMIN
      - MKNOD
      - SYS_NICE
      - SYS_RESOURCE
    security_opt:
      - seccomp:unconfined
      - apparmor:unconfined
    depends_on:
      - "db"
    extra_hosts:
$formattedHosts

  mgmtnode:
    image: scaleout:latest
    environment:
      - SUBNET="${Subnet}"
      - SUBNET6="${Subnet6}"
      - container=docker
      - SLURM_FEDERATION_CLUSTER=cluster
    hostname: mgmtnode
    networks:
      internal:
        ipv4_address: "${Subnet}.1.1"
        ipv6_address: "${Subnet6}1:1"
    volumes:
      - root-home:/root
      - home:/home/
      - slurmctld:/var/spool/slurm
      - etc-ssh:/etc/ssh
      - cluster-etc-slurm:/etc/slurm
      - mail:/var/spool/mail/
      - auth:/auth/
      - xdmod:/xdmod/
      - src:/usr/local/src/
      - /etc/localtime:/etc/localtime:ro
      - /run/
      - /run/lock/
      - /sys/
      - /sys/fs/cgroup/:/sys/fs/cgroup/:ro
      - /sys/fs/cgroup/docker.slice/:/sys/fs/cgroup/docker.slice/:rw
      - /sys/fs/fuse/:/sys/fs/fuse/:rw
      - /tmp/
      - /var/lib/journal
    tty: true
    logging:
      driver: local
    cap_add:
      - SYS_PTRACE
      - SYS_ADMIN
      - MKNOD
      - SYS_NICE
      - SYS_RESOURCE
    security_opt:
      - seccomp:unconfined
      - apparmor:unconfined
    depends_on:
      - "slurmdbd"
    extra_hosts:
$formattedHosts

  mgmtnode2:
    image: scaleout:latest
    environment:
      - SUBNET="${Subnet}"
      - SUBNET6="${Subnet6}"
      - container=docker
      - SLURM_FEDERATION_CLUSTER=cluster
    hostname: mgmtnode2
    networks:
      internal:
        ipv4_address: "${Subnet}.1.4"
        ipv6_address: "${Subnet6}1:4"
    volumes:
      - root-home:/root
      - etc-ssh:/etc/ssh
      - cluster-etc-slurm:/etc/slurm
      - home:/home/
      - slurmctld:/var/spool/slurm
      - mail:/var/spool/mail/
      - src:/usr/local/src/
      - /etc/localtime:/etc/localtime:ro
      - /run/
      - /run/lock/
      - /sys/
      - /sys/fs/cgroup/:/sys/fs/cgroup/:ro
      - /sys/fs/cgroup/docker.slice/:/sys/fs/cgroup/docker.slice/:rw
      - /sys/fs/fuse/:/sys/fs/fuse/:rw
      - /tmp/
      - /var/lib/journal
    tty: true
    logging:
      driver: local
    cap_add:
      - SYS_PTRACE
      - SYS_ADMIN
      - MKNOD
      - SYS_NICE
      - SYS_RESOURCE
    security_opt:
      - seccomp:unconfined
      - apparmor:unconfined
    depends_on:
      - "slurmdbd"
      - "mgmtnode"
    extra_hosts:
$formattedHosts

  login:
    image: scaleout:latest
    environment:
      - SUBNET="${Subnet}"
      - SUBNET6="${Subnet6}"
      - container=docker
    hostname: login
    networks:
      internal:
        ipv4_address: "${Subnet}.1.5"
        ipv6_address: "${Subnet6}1:5"
    volumes:
      - root-home:/root
      - etc-ssh:/etc/ssh
      - cluster-etc-slurm:/etc/slurm
      - home:/home/
      - slurmctld:/var/spool/slurm
      - mail:/var/spool/mail/
      - src:/usr/local/src/
      - /var/lib/containers
      - /dev/fuse:/dev/fuse:rw
      - container-shared:/srv/containers
      - /etc/localtime:/etc/localtime:ro
      - /run/
      - /run/lock/
      - /sys/
      - /sys/fs/cgroup/:/sys/fs/cgroup/:ro
      - /sys/fs/cgroup/docker.slice/:/sys/fs/cgroup/docker.slice/:rw
      - /sys/fs/fuse/:/sys/fs/fuse/:rw
      - /tmp/
      - /var/lib/journal
    tty: true
    logging:
      driver: local
    cap_add:
      - SYS_PTRACE
      - SYS_ADMIN
      - MKNOD
      - SYS_NICE
      - SYS_RESOURCE
    security_opt:
      - seccomp:unconfined
      - apparmor:unconfined
    extra_hosts:
$formattedHosts

  rest:
    hostname: rest
    image: scaleout:latest
    networks:
      internal:
        ipv4_address: "${Subnet}.1.6"
        ipv6_address: "${Subnet6}1:6"
    volumes:
      - etc-ssh:/etc/ssh
      - cluster-etc-slurm:/etc/slurm
      - /etc/localtime:/etc/localtime:ro
      - /run/
      - /run/lock/
      - /sys/
      - /sys/fs/cgroup/:/sys/fs/cgroup/:ro
      - /sys/fs/cgroup/docker.slice/:/sys/fs/cgroup/docker.slice/:rw
      - /sys/fs/fuse/:/sys/fs/fuse/:rw
      - /tmp/
      - /var/lib/journal
    tty: true
    logging:
      driver: local
    cap_add:
      - SYS_PTRACE
      - SYS_ADMIN
      - MKNOD
      - SYS_NICE
      - SYS_RESOURCE
    security_opt:
      - seccomp:unconfined
      - apparmor:unconfined
    depends_on:
      - "mgmtnode"
    extra_hosts:
$formattedHosts

  proxy:
    build:
      context: ./proxy
    image: proxy:latest
    environment:
      - SUBNET="${Subnet}"
      - SUBNET6="${Subnet6}"
      - container=docker
    hostname: proxy
    command: ["bash", "-c", "/usr/sbin/nginx& /usr/sbin/php-fpm83 -F& wait"]
    networks:
      internal:
        ipv4_address: "${Subnet}.1.7"
        ipv6_address: "${Subnet6}1:7"
    volumes:
      - auth:/auth/
      - /dev/log:/dev/log
    tty: true
    logging:
      driver: local
    cap_add:
      - SYS_PTRACE
      - SYS_ADMIN
      - MKNOD
      - SYS_NICE
      - SYS_RESOURCE
    security_opt:
      - seccomp:unconfined
      - apparmor:unconfined
    ports:
      - 8080:8080
    depends_on:
      - "rest"
    extra_hosts:
$formattedHosts

  grafana:
    image: grafana:latest
    build:
      context: ./grafana
    environment:
      - SUBNET="${Subnet}"
      - SUBNET6="${Subnet6}"
    volumes:
      - /dev/log:/dev/log
    networks:
      internal:
        ipv4_address: "${Subnet}.1.20"
        ipv6_address: "${Subnet6}1:20"
    ports:
      - 3000:3000
    tty: true
    logging:
      driver: local
    cap_add:
      - SYS_PTRACE
      - SYS_ADMIN
      - MKNOD
      - SYS_NICE
      - SYS_RESOURCE
    security_opt:
      - seccomp:unconfined
      - apparmor:unconfined

  influxdb:
    build:
      context: ./influxdb
    image: influxdb
    command: ["bash", "-c", "/setup.sh & source /entrypoint.sh"]
    environment:
      - SUBNET="${Subnet}"
      - SUBNET6="${Subnet6}"
      - DOCKER_INFLUXDB_INIT_MODE=setup
      - DOCKER_INFLUXDB_INIT_USERNAME=user
      - DOCKER_INFLUXDB_INIT_PASSWORD=password
      - DOCKER_INFLUXDB_INIT_ORG=scaleout
      - DOCKER_INFLUXDB_INIT_BUCKET=scaleout
      - DOCKER_INFLUXDB_INIT_RETENTION=1w
      - DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=token
      - DOCKER_INFLUXDB_INIT_USER_ID=
      - INFLUXDB_DATA_QUERY_LOG_ENABLED=true
      - INFLUXDB_REPORTING_DISABLED=false
      - INFLUXDB_HTTP_LOG_ENABLED=true
      - INFLUXDB_CONTINUOUS_QUERIES_LOG_ENABLED=true
      - LOG_LEVEL=debug
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - /dev/log:/dev/log
    networks:
      internal:
        ipv4_address: "${Subnet}.1.19"
        ipv6_address: "${Subnet6}1:19"
    tty: true
    logging:
      driver: local
    cap_add:
      - SYS_PTRACE
      - SYS_ADMIN
      - MKNOD
      - SYS_NICE
      - SYS_RESOURCE
    security_opt:
      - seccomp:unconfined
      - apparmor:unconfined

  open-ondemand:
    build:
      context: ./open-ondemand
    image: open-ondemand
    environment:
      - SUBNET="${Subnet}"
      - SUBNET6="${Subnet6}"
      - DEFAULT_SSHHOST=login
    volumes:
      - /dev/log:/dev/log
      - etc-ssh:/etc/shared-ssh
      - home:/home/
    networks:
      internal:
        ipv4_address: "${Subnet}.1.21"
        ipv6_address: "${Subnet6}1:21"
    depends_on:
      - "login"
    ports:
      - 8081:80
    tty: true
    logging:
      driver: local
    cap_add:
      - SYS_PTRACE
      - SYS_ADMIN
      - MKNOD
      - SYS_NICE
      - SYS_RESOURCE
    security_opt:
      - seccomp:unconfined
      - apparmor:unconfined

  xdmod:
    build:
      context: ./xdmod
    image: xdmod:latest
    environment:
      - SUBNET="${Subnet}"
      - SUBNET6="${Subnet6}"
      - container=docker
    hostname: xdmod
    command: ["/sbin/startup.sh"]
    networks:
      internal:
        ipv4_address: "${Subnet}.1.22"
        ipv6_address: "${Subnet6}1:22"
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - /run/
      - /run/lock/
      - /sys/
      - /sys/fs/cgroup/:/sys/fs/cgroup/:ro
      - /sys/fs/cgroup/docker.slice/:/sys/fs/cgroup/docker.slice/:rw
      - /sys/fs/fuse/:/sys/fs/fuse/:rw
      - /tmp/
      - /var/lib/journal
      - xdmod:/xdmod/
    ports:
      - 8082:80
    tty: true
    logging:
      driver: local
    cap_add:
      - SYS_PTRACE
      - SYS_ADMIN
      - MKNOD
      - SYS_NICE
      - SYS_RESOURCE
    security_opt:
      - seccomp:unconfined
      - apparmor:unconfined
    extra_hosts:
$formattedHosts

  keycloak:
    image: keycloak:latest
    build:
      context: ./keycloak
    environment:
      - KC_BOOTSTRAP_ADMIN_USERNAME=admin
      - KC_BOOTSTRAP_ADMIN_PASSWORD=password
    hostname: keycloak
    networks:
      internal:
        ipv4_address: "${Subnet}.1.23"
        ipv6_address: "${Subnet6}1:23"
    ports:
      - 8083:8080
    tty: true
    logging:
      driver: local
    cap_add:
      - SYS_PTRACE
      - SYS_ADMIN
      - MKNOD
      - SYS_NICE
      - SYS_RESOURCE
    security_opt:
      - seccomp:unconfined
      - apparmor:unconfined

  es01:
    image: docker.elastic.co/elasticsearch/elasticsearch-oss:7.10.1
    environment:
      - node.name=es01
      - cluster.name=scaleout
      - discovery.seed_hosts=es02,es03
      - cluster.initial_master_nodes=es01,es02,es03
      - bootstrap.memory_lock=true
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
      - SUBNET="${Subnet}"
      - SUBNET6="${Subnet6}"
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - elastic_data01:/usr/share/elasticsearch/data
      - /dev/log:/dev/log
    networks:
      internal:
        ipv4_address: "${Subnet}.1.15"
        ipv6_address: "${Subnet6}1:15"
    ports:
      - 9200:9200
    tty: true
    logging:
      driver: local
    cap_add:
      - SYS_PTRACE
      - SYS_ADMIN
      - MKNOD
      - SYS_NICE
      - SYS_RESOURCE
    security_opt:
      - seccomp:unconfined
      - apparmor:unconfined

  es02:
    image: docker.elastic.co/elasticsearch/elasticsearch-oss:7.10.1
    environment:
      - node.name=es02
      - cluster.name=scaleout
      - discovery.seed_hosts=es01,es03
      - cluster.initial_master_nodes=es01,es02,es03
      - bootstrap.memory_lock=true
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
      - SUBNET="${Subnet}"
      - SUBNET6="${Subnet6}"
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - elastic_data02:/usr/share/elasticsearch/data
      - /dev/log:/dev/log
    networks:
      internal:
        ipv4_address: "${Subnet}.1.16"
        ipv6_address: "${Subnet6}1:16"
    tty: true
    logging:
      driver: local
    cap_add:
      - SYS_PTRACE
      - SYS_ADMIN
      - MKNOD
      - SYS_NICE
      - SYS_RESOURCE
    security_opt:
      - seccomp:unconfined
      - apparmor:unconfined

  es03:
    image: docker.elastic.co/elasticsearch/elasticsearch-oss:7.10.1
    environment:
      - node.name=es03
      - cluster.name=scaleout
      - discovery.seed_hosts=es01,es02
      - cluster.initial_master_nodes=es01,es02,es03
      - bootstrap.memory_lock=true
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
      - SUBNET="${Subnet}"
      - SUBNET6="${Subnet6}"
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - elastic_data03:/usr/share/elasticsearch/data
      - /dev/log:/dev/log
    networks:
      internal:
        ipv4_address: "${Subnet}.1.17"
        ipv6_address: "${Subnet6}1:17"
    tty: true
    logging:
      driver: local
    cap_add:
      - SYS_PTRACE
      - SYS_ADMIN
      - MKNOD
      - SYS_NICE
      - SYS_RESOURCE
    security_opt:
      - seccomp:unconfined
      - apparmor:unconfined

  kibana:
    image: docker.elastic.co/kibana/kibana-oss:7.10.1
    volumes:
      - /dev/log:/dev/log
    environment:
      - SERVER_NAME=scaleout
      - ELASTICSEARCH_HOSTS=http://es01:9200
      - SUBNET="${Subnet}"
      - SUBNET6="${Subnet6}"
    networks:
      internal:
        ipv4_address: "${Subnet}.1.18"
        ipv6_address: "${Subnet6}1:18"
    ports:
      - 5601:5601
    depends_on:
      - "es01"
      - "es02"
      - "es03"
    tty: true
    logging:
      driver: local
    cap_add:
      - SYS_PTRACE
      - SYS_ADMIN
      - MKNOD
      - SYS_NICE
      - SYS_RESOURCE
    security_opt:
      - seccomp:unconfined
      - apparmor:unconfined
"@

# Add compute nodes
0..$NodesCount | ForEach-Object {
    $i = $_
    $nodeName = "node{0:D2}" -f $i
    $ipv6Suffix = $i + 10
    $nodeContent = @"

  ${nodeName}:
    image: scaleout:latest
    environment:
      - SUBNET="${Subnet}"
      - SUBNET6="${Subnet6}"
      - container=docker
      - SLURM_FEDERATION_CLUSTER=cluster
    hostname: ${nodeName}
    networks:
      internal:
        ipv4_address: "${Subnet}.5.$($i + 10)"
        ipv6_address: "${Subnet6}5:${ipv6Suffix}"
    volumes:
      - root-home:/root
      - etc-ssh:/etc/ssh
      - cluster-etc-slurm:/etc/slurm
      - home:/home/
      - mail:/var/spool/mail/
      - src:/usr/local/src/
      - container-shared:/srv/containers
      - /etc/localtime:/etc/localtime:ro
      - /run/
      - /run/lock/
      - /sys/
      - /sys/fs/cgroup/:/sys/fs/cgroup/:ro
      - /sys/fs/cgroup/docker.slice/:/sys/fs/cgroup/docker.slice/:rw
      - /sys/fs/fuse/:/sys/fs/fuse/:rw
      - /tmp/
      - /var/lib/journal
    ulimits:
      nproc:
        soft: 65535
        hard: 65535
      nofile:
        soft: 131072
        hard: 131072
      memlock:
        soft: -1
        hard: -1
    tty: true
    logging:
      driver: local
    cap_add:
      - SYS_PTRACE
      - SYS_ADMIN
      - MKNOD
      - SYS_NICE
      - SYS_RESOURCE
    security_opt:
      - seccomp:unconfined
      - apparmor:unconfined
    depends_on:
      - "mgmtnode"
    extra_hosts:
$formattedHosts
"@
    $composeContent += $nodeContent
}

# Write docker-compose.yml
$composeContent | Set-Content "docker-compose.yml"

# Output the generated YAML for debugging
Write-Host "Generated docker-compose.yml content:"
Write-Host $composeContent 