#!/bin/bash

# Exit on any error
set -e

# Function to update git submodules
update_submodules() {
    if ! command_exists git; then
        echo "Error: git is not installed. Please install git first."
        exit 1
    fi

    if [ ! -d .git ]; then
        echo "Error: Not a git repository. Please run this script from the repository root."
        exit 1
    fi

    echo "Updating git submodules..."
    git submodule update --init --force --remote --recursive
    if [ $? -ne 0 ]; then
        echo "Error: Failed to update git submodules"
        exit 1
    fi
    echo "Git submodules updated successfully"
}

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "This script needs to be run as root to perform system-wide changes."
        echo "Attempting to elevate privileges..."
        
        # Check if sudo is available
        if command_exists sudo; then
            echo "Using sudo to elevate privileges..."
            exec sudo "$0" "$@"
        # Check if su is available
        elif command_exists su; then
            echo "Using su to elevate privileges..."
            exec su -c "$0 $*" root
        else
            echo "Error: Neither sudo nor su is available."
            echo "Please run this script as root manually."
            exit 1
        fi
    fi
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to get distribution information
get_distro_info() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID $VERSION_ID"
    else
        echo "unknown"
    fi
}

# Function to verify root access
verify_root_access() {
    if ! command_exists id; then
        echo "Error: Cannot verify root access"
        exit 1
    fi

    if [ "$(id -u)" -ne 0 ]; then
        echo "Error: Failed to obtain root privileges"
        exit 1
    fi

    echo "Successfully obtained root privileges"
}

# Function to install packages based on distribution
install_packages() {
    local distro_info
    distro_info=$(get_distro_info)
    local distro_id=${distro_info%% *}
    local version_id=${distro_info#* }

    echo "Detected distribution: $distro_id $version_id"

    # Common build dependencies
    local build_deps="gcc g++ make cmake autoconf automake libtool m4 git"
    # Common development libraries
    local dev_libs="libssl-dev libmariadb-dev libmariadb-dev-compat libmunge-dev libhwloc-dev libpam0g-dev libreadline-dev libncurses5-dev liblz4-dev libzstd-dev libjson-c-dev libjwt-dev libhttp-parser-dev libcurl4-openssl-dev libyaml-dev"
    # Common system utilities
    local sys_utils="wget curl unzip tar gzip bzip2 xz-utils"

    case "$distro_id" in
        "ubuntu"|"debian")
            apt-get update
            apt-get install -y \
                docker.io \
                docker-compose-plugin \
                ssh \
                jq \
                python3 \
                python3-daemon \
                $build_deps \
                $dev_libs \
                $sys_utils
            ;;
        "fedora")
            dnf install -y \
                docker \
                docker-compose \
                openssh-clients \
                jq \
                python3 \
                python3-daemon \
                gcc \
                gcc-c++ \
                make \
                cmake \
                autoconf \
                automake \
                libtool \
                m4 \
                git \
                openssl-devel \
                mariadb-devel \
                munge-devel \
                hwloc-devel \
                pam-devel \
                readline-devel \
                ncurses-devel \
                lz4-devel \
                libzstd-devel \
                json-c-devel \
                libjwt-devel \
                http-parser-devel \
                libcurl-devel \
                libyaml-devel \
                wget \
                curl \
                unzip \
                tar \
                gzip \
                bzip2 \
                xz
            systemctl enable docker
            systemctl start docker
            ;;
        "centos"|"rhel"|"rocky"|"almalinux"|"ol")
            # For RHEL family distributions
            if command_exists dnf; then
                # Modern RHEL-based systems (RHEL 8+, CentOS 8+, Rocky Linux, AlmaLinux)
                dnf install -y \
                    docker \
                    docker-compose \
                    openssh-clients \
                    jq \
                    python3 \
                    python3-daemon \
                    gcc \
                    gcc-c++ \
                    make \
                    cmake \
                    autoconf \
                    automake \
                    libtool \
                    m4 \
                    git \
                    openssl-devel \
                    mariadb-devel \
                    munge-devel \
                    hwloc-devel \
                    pam-devel \
                    readline-devel \
                    ncurses-devel \
                    lz4-devel \
                    libzstd-devel \
                    json-c-devel \
                    libjwt-devel \
                    http-parser-devel \
                    libcurl-devel \
                    libyaml-devel \
                    wget \
                    curl \
                    unzip \
                    tar \
                    gzip \
                    bzip2 \
                    xz
            else
                # Legacy RHEL-based systems (RHEL 7, CentOS 7)
                yum install -y yum-utils
                yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
                yum install -y \
                    docker-ce \
                    docker-ce-cli \
                    containerd.io \
                    docker-compose-plugin \
                    openssh-clients \
                    jq \
                    python3 \
                    python3-daemon \
                    gcc \
                    gcc-c++ \
                    make \
                    cmake \
                    autoconf \
                    automake \
                    libtool \
                    m4 \
                    git \
                    openssl-devel \
                    mariadb-devel \
                    munge-devel \
                    hwloc-devel \
                    pam-devel \
                    readline-devel \
                    ncurses-devel \
                    lz4-devel \
                    libzstd-devel \
                    json-c-devel \
                    libjwt-devel \
                    http-parser-devel \
                    libcurl-devel \
                    libyaml-devel \
                    wget \
                    curl \
                    unzip \
                    tar \
                    gzip \
                    bzip2 \
                    xz
            fi
            systemctl enable docker
            systemctl start docker
            ;;
        "opensuse"|"suse")
            zypper install -y \
                docker \
                docker-compose \
                openssh \
                jq \
                python3 \
                python3-daemon \
                gcc \
                gcc-c++ \
                make \
                cmake \
                autoconf \
                automake \
                libtool \
                m4 \
                git \
                libopenssl-devel \
                mariadb-devel \
                munge-devel \
                hwloc-devel \
                pam-devel \
                readline-devel \
                ncurses-devel \
                liblz4-devel \
                libzstd-devel \
                json-c-devel \
                libjwt-devel \
                http-parser-devel \
                libcurl-devel \
                libyaml-devel \
                wget \
                curl \
                unzip \
                tar \
                gzip \
                bzip2 \
                xz
            systemctl enable docker
            systemctl start docker
            ;;
        "arch")
            pacman -S --noconfirm \
                docker \
                docker-compose \
                openssh \
                jq \
                python \
                python-daemon \
                gcc \
                make \
                cmake \
                autoconf \
                automake \
                libtool \
                m4 \
                git \
                openssl \
                mariadb-libs \
                munge \
                hwloc \
                pam \
                readline \
                ncurses \
                lz4 \
                zstd \
                json-c \
                libjwt \
                http-parser \
                curl \
                libyaml \
                wget \
                unzip \
                tar \
                gzip \
                bzip2 \
                xz
            systemctl enable docker
            systemctl start docker
            ;;
        *)
            echo "Unsupported distribution: $distro_id"
            echo "Please install the following packages manually:"
            echo "- docker"
            echo "- docker-compose"
            echo "- openssh"
            echo "- jq"
            echo "- python3"
            echo "- python3-daemon"
            echo "- build tools (gcc, make, cmake, etc.)"
            echo "- development libraries (openssl, mariadb, munge, etc.)"
            echo "- system utilities (wget, curl, etc.)"
            exit 1
            ;;
    esac

    # Verify installations
    echo "Verifying installations..."
    for cmd in docker docker-compose ssh jq python3 gcc make cmake git; do
        if ! command_exists "$cmd"; then
            echo "Error: $cmd installation failed"
            exit 1
        fi
    done
}

# Function to configure sysctl
configure_sysctl() {
    cat > /etc/sysctl.d/99-slurm-docker.conf << EOF
net.ipv4.tcp_max_syn_backlog=4096
net.core.netdev_max_backlog=1000
net.core.somaxconn=15000

# Force gc to clean-up quickly
net.ipv4.neigh.default.gc_interval = 3600

# Set ARP cache entry timeout
net.ipv4.neigh.default.gc_stale_time = 3600

# Setup DNS threshold for arp
net.ipv4.neigh.default.gc_thresh3 = 8096
net.ipv4.neigh.default.gc_thresh2 = 4048
net.ipv4.neigh.default.gc_thresh1 = 1024

# Increase map count for elasticsearch
vm.max_map_count=262144

# Avoid running out of file descriptors
fs.file-max=10000000
fs.inotify.max_user_instances=65535
fs.inotify.max_user_watches=1048576

#Request kernel max number of cgroups
fs.inotify.max_user_instances=65535
EOF

    # Apply sysctl settings
    sysctl --system
}

# Function to configure Docker for cgroupsv2
configure_docker() {
    # Create docker daemon config
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << EOF
{
  "exec-opts": [
    "native.cgroupdriver=systemd"
  ],
  "features": {
    "buildkit": true
  },
  "experimental": true,
  "cgroup-parent": "docker.slice",
  "default-cgroupns-mode": "host",
  "storage-driver": "overlay2"
}
EOF

    # Create docker slice unit file
    cat > /etc/systemd/system/docker.slice << EOF
[Unit]
Description=docker slice
Before=slices.target
[Slice]
CPUAccounting=true
MemoryAccounting=true
Delegate=yes
EOF

    # Create docker service override
    mkdir -p /usr/lib/systemd/system/docker.service.d
    cat > /usr/lib/systemd/system/docker.service.d/local.conf << EOF
[Service]
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
Delegate=yes
EOF

    # Reload systemd and restart docker
    systemctl daemon-reload
    systemctl restart docker.slice docker
}

# Function to enable IPv6 in Docker
enable_docker_ipv6() {
    if [ ! -f /etc/docker/daemon.json ]; then
        echo "{}" > /etc/docker/daemon.json
    fi

    # Add IPv6 configuration to existing daemon.json
    jq '. + {"ipv6": true, "fixed-cidr-v6": "2001:db8:1::/64"}' /etc/docker/daemon.json > /tmp/daemon.json
    mv /tmp/daemon.json /etc/docker/daemon.json

    # Restart docker to apply changes
    systemctl restart docker
}

# Function to ensure Docker is enabled and running
ensure_docker_running() {
    echo "Ensuring Docker is enabled and running..."

    # Enable Docker to start on boot
    if command_exists systemctl; then
        if ! systemctl is-enabled docker > /dev/null 2>&1; then
            echo "Enabling Docker to start on boot..."
            systemctl enable docker
        fi
    fi

    # Check if Docker is running
    if ! docker info > /dev/null 2>&1; then
        echo "Starting Docker daemon..."
        if command_exists systemctl; then
            systemctl start docker
        elif command_exists service; then
            service docker start
        else
            echo "Error: Could not start docker daemon. Please start it manually after reboot."
            return 1
        fi

        # Wait for Docker to be ready
        echo "Waiting for Docker daemon to be ready..."
        local attempts=0
        while ! docker info > /dev/null 2>&1; do
            attempts=$((attempts + 1))
            if [ $attempts -gt 30 ]; then
                echo "Warning: Docker daemon failed to start within 30 seconds"
                echo "Docker will be started automatically after reboot"
                return 0
            fi
            sleep 1
        done
        echo "Docker daemon started successfully"
    else
        echo "Docker daemon is already running"
    fi
}

# Main execution
echo "Starting setup..."

# Update git submodules first
update_submodules

# Check and elevate privileges if needed
check_root "$@"

# Verify we have root access
verify_root_access

# Install required packages
echo "Installing required packages..."
install_packages

# Configure sysctl
echo "Configuring sysctl settings..."
configure_sysctl

# Configure Docker for cgroupsv2
echo "Configuring Docker for cgroupsv2..."
configure_docker

# Enable IPv6 in Docker
echo "Enabling IPv6 in Docker..."
enable_docker_ipv6

# Ensure Docker is enabled and running
ensure_docker_running

echo "Setup completed successfully!"
echo "Please reboot your system to ensure all changes take effect prior to running setup_2.sh" 