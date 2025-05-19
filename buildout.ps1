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
        [int]$NodesCount = 9,
        [string]$SlurmBenchmark = "",
        [string]$Federation = ""
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
        if (Test-Path $Nodelist) {
            Remove-Item $Nodelist -Force
        }
        0..$NodesCount | ForEach-Object {
            $i = $_
            ("node{0:D2} cluster ${Subnet}.5.$($i + 10) ${Subnet6}5:$($i + 10)" -f $i)
        } | Set-Content $Nodelist
    }
}

# Function to generate hosts file
function Generate-HostsFile {
    param(
        [string]$Nodelist
    )

    if (Test-Path "scaleout/hosts.nodes") {
        Remove-Item "scaleout/hosts.nodes" -Force
    }

    if (Test-Path $Nodelist) {
        Get-Content $Nodelist | ForEach-Object {
            $name, $cluster, $ip4, $ip6 = $_ -split '\s+'
            if ($ip4) { "$ip4 $name" | Add-Content "scaleout/hosts.nodes" }
            if ($ip6) { "$ip6 $name" | Add-Content "scaleout/hosts.nodes" }
        }
    }
    else {
        Write-Host "Warning: Nodelist file not found at $Nodelist" -ForegroundColor Yellow
    }
}

# Function to generate host list for docker-compose
function Get-HostList {
    $hosts = @()
    
    # Add standard hosts using template
    $hosts += "db:${Subnet}.1.3"
    $hosts += "db6:${Subnet6}1:3"
    $hosts += "slurmdbd:${Subnet}.1.2"
    $hosts += "slurmdbd6:${Subnet6}1:2"
    $hosts += "login:${Subnet}.1.5"
    $hosts += "login6:${Subnet6}1:5"
    $hosts += "rest:${Subnet}.1.6"
    $hosts += "rest6:${Subnet6}1:6"
    $hosts += "proxy:${Subnet}.1.7"
    $hosts += "proxy6:${Subnet6}1:7"
    $hosts += "es01:${Subnet}.1.15"
    $hosts += "es016:${Subnet6}1:15"
    $hosts += "es02:${Subnet}.1.16"
    $hosts += "es026:${Subnet6}1:16"
    $hosts += "es03:${Subnet}.1.17"
    $hosts += "es036:${Subnet6}1:17"
    $hosts += "kibana:${Subnet}.1.18"
    $hosts += "kibana6:${Subnet6}1:18"
    $hosts += "influxdb:${Subnet}.1.19"
    $hosts += "influxdb6:${Subnet6}1:19"
    $hosts += "grafana:${Subnet}.1.20"
    $hosts += "grafana6:${Subnet6}1:20"
    $hosts += "open-ondemand:${Subnet}.1.21"
    $hosts += "open-ondemand6:${Subnet6}1:21"
    $hosts += "xdmod:${Subnet}.1.22"
    $hosts += "xdmod6:${Subnet6}1:22"
    $hosts += "keycloak:${Subnet}.1.23"
    $hosts += "keycloak6:${Subnet6}1:23"

    if ($Federation) {
        $c_sub = 5
        $Federation.Split() | ForEach-Object {
            $c = $_
            $hosts += "${c}-mgmtnode:${Subnet}.${c_sub}.1"
            $hosts += "${c}-mgmtnode6:${Subnet6}${c_sub}:1"
            $hosts += "${c}-mgmtnode2:${Subnet}.${c_sub}.2"
            $hosts += "${c}-mgmtnode26:${Subnet6}${c_sub}:2"
            $c_sub++
        }
    }
    else {
        $hosts += "mgmtnode:${Subnet}.1.1"
        $hosts += "mgmtnode6:${Subnet6}1:1"
        $hosts += "mgmtnode2:${Subnet}.1.4"
        $hosts += "mgmtnode26:${Subnet6}1:4"
    }

    return $hosts
}

# Function to generate Docker Compose configuration
function Generate-DockerCompose {
    param(
        [string]$Subnet,
        [string]$Subnet6,
        [string]$Nodelist,
        [string]$SlurmBenchmark = "",
        [string]$Federation = ""
    )

    # Generate node list if needed
    if (-not (Test-Path $Nodelist) -or $SlurmBenchmark) {
        Generate-NodeList -NodesCount $NodesCount -SlurmBenchmark $SlurmBenchmark -Federation $Federation
    }

    # Generate hosts file
    Generate-HostsFile -Nodelist $Nodelist

    # Get host list
    $hostList = Get-HostList -Federation $Federation

    # Format hosts for docker-compose
    $formattedHosts = ($hostList | Select-Object -Unique | ForEach-Object {
        "      - `"$_`""
    }) -join "`n"

    # Generate compute node services
    $computeNodes = @()
    if (Test-Path $Nodelist) {
        Get-Content $Nodelist | ForEach-Object {
            $name, $cluster, $ip4, $ip6 = $_ -split '\s+'
            if ($name -match 'node\d+') {
                $computeNodes += @"
  ${name}:
    image: scaleout:latest
    hostname: ${name}
    environment:
      - LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64
    networks:
      internal:
        ipv4_address: "${ip4}"
        ipv6_address: "${ip6}"
    volumes:
      - root-home:/root
      - cluster-etc-slurm:/etc/slurm
      - mail:/var/spool/mail/
      - src:/usr/local/src/
      - ld-so-conf:/etc/ld.so.conf.d
      - /etc/localtime:/etc/localtime:ro
      - /run/
      - /run/lock/
      - /sys/
      - /sys/fs/cgroup/:/sys/fs/cgroup/:ro
      - /sys/fs/cgroup/docker.slice/:/sys/fs/cgroup/docker.slice/:rw
      - /sys/fs/fuse/:/sys/fs/fuse/:rw
      - /tmp/
      - /var/lib/journal
      - ./logs:/var/log/containers
    command: ["bash", "-c", "echo -e '/usr/local/lib\n/usr/local/lib64' > /etc/ld.so.conf.d/usr_local_lib.conf && ldconfig && /sbin/startup.sh"]
    tty: true
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
        compress: "true"
        mode: "non-blocking"
        max-buffer-size: "25m"
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
            }
        }
    }

    # Generate docker-compose.yml content
    $yamlContent = @"
version: '3.8'

services:
$($computeNodes -join "`n")
  db:
    image: sql_server:latest
    build:
      context: ./sql_server
      args:
        SUBNET: "$Subnet"
        SUBNET6: "$Subnet6"
      network: host
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
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
        compress: "true"
        mode: "non-blocking"
        max-buffer-size: "25m"
    extra_hosts:
$formattedHosts

  slurmdbd:
    image: scaleout:latest
    hostname: slurmdbd
    environment:
      - LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64
      - SLURM_FEDERATION_CLUSTER=cluster
    networks:
      internal:
        ipv4_address: "${Subnet}.1.2"
        ipv6_address: "${Subnet6}1:2"
    volumes:
      - root-home:/root
      - cluster-etc-slurm:/etc/slurm
      - mail:/var/spool/mail/
      - src:/usr/local/src/
      - ld-so-conf:/etc/ld.so.conf.d
      - /etc/localtime:/etc/localtime:ro
      - /run/
      - /run/lock/
      - /sys/
      - /sys/fs/cgroup/:/sys/fs/cgroup/:ro
      - /sys/fs/cgroup/docker.slice/:/sys/fs/cgroup/docker.slice/:rw
      - /sys/fs/fuse/:/sys/fs/fuse/:rw
      - /tmp/
      - /var/lib/journal
      - ./logs:/var/log/containers
    command: ["bash", "-c", "echo -e '/usr/local/lib\n/usr/local/lib64' > /etc/ld.so.conf.d/usr_local_lib.conf && ldconfig && /sbin/startup.sh"]
    tty: true
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
        compress: "true"
        mode: "non-blocking"
        max-buffer-size: "25m"
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
      - 'SUBNET=${Subnet}'
      - 'SUBNET6=${Subnet6}'
      - container=docker
      - SLURM_FEDERATION_CLUSTER=cluster
      - LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64
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
      - ld-so-conf:/etc/ld.so.conf.d
      - /etc/localtime:/etc/localtime:ro
      - /run/
      - /run/lock/
      - /sys/
      - /sys/fs/cgroup/:/sys/fs/cgroup/:ro
      - /sys/fs/cgroup/docker.slice/:/sys/fs/cgroup/docker.slice/:rw
      - /sys/fs/fuse/:/sys/fs/fuse/:rw
      - /tmp/
      - /var/lib/journal
      - ./logs:/var/log/containers
    command: ["bash", "-c", "echo -e '/usr/local/lib\n/usr/local/lib64' > /etc/ld.so.conf.d/usr_local_lib.conf && ldconfig && /sbin/startup.sh"]
    tty: true
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
        compress: "true"
        mode: "non-blocking"
        max-buffer-size: "25m"
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
      - 'SUBNET=${Subnet}'
      - 'SUBNET6=${Subnet6}'
      - container=docker
      - SLURM_FEDERATION_CLUSTER=cluster
      - LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64
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
      - ld-so-conf:/etc/ld.so.conf.d
      - /etc/localtime:/etc/localtime:ro
      - /run/
      - /run/lock/
      - /sys/
      - /sys/fs/cgroup/:/sys/fs/cgroup/:ro
      - /sys/fs/cgroup/docker.slice/:/sys/fs/cgroup/docker.slice/:rw
      - /sys/fs/fuse/:/sys/fs/fuse/:rw
      - /tmp/
      - /var/lib/journal
      - ./logs:/var/log/containers
    command: ["bash", "-c", "echo -e '/usr/local/lib\n/usr/local/lib64' > /etc/ld.so.conf.d/usr_local_lib.conf && ldconfig && /sbin/startup.sh"]
    tty: true
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
        compress: "true"
        mode: "non-blocking"
        max-buffer-size: "25m"
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
      - 'SUBNET=${Subnet}'
      - 'SUBNET6=${Subnet6}'
      - container=docker
      - LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64
    hostname: login
    command: ["bash", "-c", "echo \"Debug: Checking munge user/group\" && id munge && getent passwd munge && getent group munge && echo \"Debug: Initial state of /var/log/munge\" && ls -la /var/log/munge || true && echo \"Debug: Parent directory permissions\" && ls -la /var/log/ && echo \"Debug: Creating /var/log/munge\" && rm -rf /var/log/munge && mkdir -p /var/log/munge && echo \"Debug: Setting ownership\" && chown -R munge:munge /var/log/munge && chmod 700 /var/log/munge && echo \"Debug: Final state of /var/log/munge\" && ls -la /var/log/munge && echo \"Debug: Starting munged\" && /usr/local/sbin/munged --num-threads=10 && echo \"Debug: Process context\" && ps aux | grep munged || echo \"No munged process found\" && echo \"Debug: Copying startup script\" && cp /usr/local/src/login.startup.sh /usr/local/src/startup.sh && dos2unix /usr/local/src/startup.sh && chmod +x /usr/local/src/startup.sh && echo \"Debug: Starting main startup script\" && /sbin/startup.sh"]
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
      - ld-so-conf:/etc/ld.so.conf.d
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
      - ./logs:/var/log/containers
      - ./scaleout/login.startup.sh:/usr/local/src/login.startup.sh:ro
    tty: true
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
        compress: "true"
        mode: "non-blocking"
        max-buffer-size: "25m"
    cap_add:
      - SYS_PTRACE
      - SYS_ADMIN
      - MKNOD
      - SYS_NICE
      - SYS_RESOURCE
    security_opt:
      - seccomp:unconfined
      - apparmor:unconfined
    init: true
    extra_hosts:
$formattedHosts

  rest:
    image: scaleout:latest
    hostname: rest
    environment:
      - LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64
    networks:
      internal:
        ipv4_address: "${Subnet}.1.6"
        ipv6_address: "${Subnet6}1:6"
    volumes:
      - etc-ssh:/etc/ssh
      - cluster-etc-slurm:/etc/slurm
      - ld-so-conf:/etc/ld.so.conf.d
      - /etc/localtime:/etc/localtime:ro
      - /run/
      - /run/lock/
      - /sys/
      - /sys/fs/cgroup/:/sys/fs/cgroup/:ro
      - /sys/fs/cgroup/docker.slice/:/sys/fs/cgroup/docker.slice/:rw
      - /sys/fs/fuse/:/sys/fs/fuse/:rw
      - /tmp/
      - /var/lib/journal
      - ./logs:/var/log/containers
    command: ["bash", "-c", "echo -e '/usr/local/lib\n/usr/local/lib64' > /etc/ld.so.conf.d/usr_local_lib.conf && ldconfig && /sbin/startup.sh"]
    tty: true
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
        compress: "true"
        mode: "non-blocking"
        max-buffer-size: "25m"
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
      - 'SUBNET=${Subnet}'
      - 'SUBNET6=${Subnet6}'
      - container=docker
    hostname: proxy
    command: ["bash", "-c", "/usr/sbin/nginx& /usr/sbin/php-fpm83 -F& wait"]
    networks:
      internal:
        ipv4_address: "${Subnet}.1.7"
        ipv6_address: "${Subnet6}1:7"
    volumes:
      - auth:/auth/
      - ./logs:/var/log/containers
    tty: true
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
        compress: "true"
        mode: "non-blocking"
        max-buffer-size: "25m"
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
      - 'SUBNET=${Subnet}'
      - 'SUBNET6=${Subnet6}'
    networks:
      internal:
        ipv4_address: "${Subnet}.1.20"
        ipv6_address: "${Subnet6}1:20"
    volumes:
      - ./logs:/var/log/containers
    ports:
      - 3000:3000
    tty: true
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
        compress: "true"
        mode: "non-blocking"
        max-buffer-size: "25m"
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
      - 'SUBNET=${Subnet}'
      - 'SUBNET6=${Subnet6}'
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
    networks:
      internal:
        ipv4_address: "${Subnet}.1.19"
        ipv6_address: "${Subnet6}1:19"
    volumes:
      - ./logs:/var/log/containers
    tty: true
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
        compress: "true"
        mode: "non-blocking"
        max-buffer-size: "25m"
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
      - 'SUBNET=${Subnet}'
      - 'SUBNET6=${Subnet6}'
      - DEFAULT_SSHHOST=login
    volumes:
      - etc-ssh:/etc/shared-ssh
      - home:/home/
      - ./logs:/var/log/containers
    networks:
      internal:
        ipv4_address: "${Subnet}.1.21"
        ipv6_address: "${Subnet6}1:21"
    ports:
      - 8081:80
    depends_on:
      - "login"
    tty: true
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
        compress: "true"
        mode: "non-blocking"
        max-buffer-size: "25m"
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
      dockerfile: Dockerfile.win
    image: xdmod:latest
    environment:
      - 'SUBNET=${Subnet}'
      - 'SUBNET6=${Subnet6}'
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
      - ./logs:/var/log/containers
    ports:
      - 8082:80
    tty: true
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
        compress: "true"
        mode: "non-blocking"
        max-buffer-size: "25m"
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
    volumes:
      - ./logs:/var/log/containers
    ports:
      - 8083:8080
    tty: true
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
        compress: "true"
        mode: "non-blocking"
        max-buffer-size: "25m"
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
      - 'SUBNET=${Subnet}'
      - 'SUBNET6=${Subnet6}'
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - elastic_data01:/usr/share/elasticsearch/data
      - ./logs:/var/log/containers
    networks:
      internal:
        ipv4_address: "${Subnet}.1.15"
        ipv6_address: "${Subnet6}1:15"
    ports:
      - 9200:9200
    tty: true
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
        compress: "true"
        mode: "non-blocking"
        max-buffer-size: "25m"
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
      - 'SUBNET=${Subnet}'
      - 'SUBNET6=${Subnet6}'
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - elastic_data02:/usr/share/elasticsearch/data
      - ./logs:/var/log/containers
    networks:
      internal:
        ipv4_address: "${Subnet}.1.16"
        ipv6_address: "${Subnet6}1:16"
    tty: true
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
        compress: "true"
        mode: "non-blocking"
        max-buffer-size: "25m"
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
      - 'SUBNET=${Subnet}'
      - 'SUBNET6=${Subnet6}'
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - elastic_data03:/usr/share/elasticsearch/data
      - ./logs:/var/log/containers
    networks:
      internal:
        ipv4_address: "${Subnet}.1.17"
        ipv6_address: "${Subnet6}1:17"
    tty: true
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
        compress: "true"
        mode: "non-blocking"
        max-buffer-size: "25m"
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
    environment:
      - SERVER_NAME=scaleout
      - ELASTICSEARCH_HOSTS=http://es01:9200
      - 'SUBNET=${Subnet}'
      - 'SUBNET6=${Subnet6}'
    networks:
      internal:
        ipv4_address: "${Subnet}.1.18"
        ipv6_address: "${Subnet6}1:18"
    volumes:
      - ./logs:/var/log/containers
    ports:
      - 5601:5601
    depends_on:
      - "es01"
      - "es02"
      - "es03"
    tty: true
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
        compress: "true"
        mode: "non-blocking"
        max-buffer-size: "25m"
    cap_add:
      - SYS_PTRACE
      - SYS_ADMIN
      - MKNOD
      - SYS_NICE
      - SYS_RESOURCE
    security_opt:
      - seccomp:unconfined
      - apparmor:unconfined

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
  ld-so-conf:

networks:
  internal:
    driver: bridge
    driver_opts:
      com.docker.network.bridge.enable_ip_masquerade: 'true'
      com.docker.network.bridge.enable_icc: 'true'
    internal: false
    enable_ipv6: true
    ipam:
      driver: default
      config:
        - subnet: ${Subnet}.0.0/16
        - subnet: ${Subnet6}0/64
"@

    # Create logs directory if it doesn't exist
    if (-not (Test-Path "logs")) {
        New-Item -ItemType Directory -Path "logs" | Out-Null
    }

    # Write the docker-compose.yml file
    $yamlContent | Out-File -FilePath "docker-compose.yml" -Encoding UTF8
    Write-Host "Generated docker-compose.yml" -ForegroundColor Green
}

# Main execution
$NodesCount = if ($SlurmBenchmark) { 100 } else { 9 }

# Generate Docker Compose configuration
Generate-DockerCompose -Subnet $Subnet -Subnet6 $Subnet6 -Nodelist $Nodelist -SlurmBenchmark $SlurmBenchmark -Federation $Federation 