#!/bin/bash

# Exit on any error
set -e

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if make is installed
check_make() {
    if ! command_exists make; then
        echo "Error: make is not installed. Please run setup_1.sh first."
        exit 1
    fi
}

# Function to check if docker is running and attempt to start it if not
check_docker() {
    if ! command_exists docker; then
        echo "Error: docker is not installed. Please run setup_1.sh first."
        exit 1
    fi

    if ! docker info > /dev/null 2>&1; then
        echo "Docker daemon is not running. Attempting to start it..."
        
        # Try to start docker using systemctl if available
        if command_exists systemctl; then
            if ! systemctl start docker; then
                echo "Error: Failed to start docker daemon using systemctl"
                exit 1
            fi
        # Fallback to service command
        elif command_exists service; then
            if ! service docker start; then
                echo "Error: Failed to start docker daemon using service"
                exit 1
            fi
        else
            echo "Error: Could not start docker daemon. Please start it manually and try again."
            exit 1
        fi

        # Wait for docker to be ready
        echo "Waiting for docker daemon to be ready..."
        local attempts=0
        while ! docker info > /dev/null 2>&1; do
            attempts=$((attempts + 1))
            if [ $attempts -gt 30 ]; then
                echo "Error: Docker daemon failed to start within 30 seconds"
                exit 1
            fi
            sleep 1
        done
        echo "Docker daemon started successfully"
    fi
}

# Function to check and handle Docker login
check_docker_login() {
    echo "Checking Docker login status..."
    
    # First check if we can build the scaleout image
    echo "Attempting to build scaleout image..."
    if ! make build >/dev/null 2>&1; then
        echo "Docker login required. Please enter your Docker Hub credentials:"
        
        # Prompt for username
        read -p "Docker Hub Username: " docker_username
        if [ -z "$docker_username" ]; then
            echo "Error: Username cannot be empty"
            return 1
        fi
        
        # Prompt for password (hidden)
        read -s -p "Docker Hub Password: " docker_password
        echo
        if [ -z "$docker_password" ]; then
            echo "Error: Password cannot be empty"
            return 1
        fi
        
        # Attempt to login
        echo "Logging in to Docker Hub..."
        if ! echo "$docker_password" | docker login -u "$docker_username" --password-stdin; then
            echo "Error: Docker login failed"
            return 1
        fi
        
        # Try building again after login
        echo "Attempting to build scaleout image again..."
        if ! make build >/dev/null 2>&1; then
            echo "Error: Login successful but unable to build scaleout image"
            echo "Please verify you have access to the required repositories"
            return 1
        fi
        
        echo "Docker login successful and verified"
    else
        echo "Docker login verified with scaleout image build"
    fi
}

# Function to perform the build
perform_build() {
    echo "Starting build process..."

    # Check if we're in the correct directory
    if [ ! -f "Makefile" ]; then
        echo "Error: Makefile not found. Please run this script from the repository root."
        exit 1
    fi

    # Check Docker login status
    if ! check_docker_login; then
        echo "Error: Docker login is required to proceed with the build"
        exit 1
    fi

    # Clean any previous build artifacts
    echo "Cleaning previous build artifacts..."
    make clean

    # Build the images
    echo "Building Docker images..."
    if ! make build; then
        echo "Error: Failed to build Docker images"
        exit 1
    fi

    # Verify images were built successfully
    echo "Verifying Docker images..."
    local required_images=("scaleout" "grafana")
    local missing_images=0

    for image in "${required_images[@]}"; do
        if ! docker image inspect "$image" >/dev/null 2>&1; then
            echo "Error: Required image '$image' was not built successfully"
            missing_images=1
        fi
    done

    if [ $missing_images -eq 1 ]; then
        echo "Error: Some required images are missing. Please check the build output for errors."
        exit 1
    fi

    # Start the cluster
    echo "Starting the cluster..."
    if ! make; then
        echo "Error: Failed to start the cluster"
        exit 1
    fi

    echo "Build and deployment completed successfully!"
}

# Function to handle cleanup on script exit
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "Build failed with exit code $exit_code"
        echo "Attempting to clean up..."
        make clean
    fi
    exit $exit_code
}

# Set up cleanup trap
trap cleanup EXIT

# Main execution
echo "Starting build process..."

# Check and elevate privileges if needed
check_root "$@"

# Verify we have root access
verify_root_access

# Check prerequisites
check_make
check_docker

# Perform the build
perform_build

# If we get here, everything succeeded
echo "Build process completed successfully!"
echo "You can now access the cluster using the URLs provided in the README." 