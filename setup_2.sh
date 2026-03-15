#!/bin/bash

# Exit on any error
set -e

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Run a shell command as root only when required
run_as_root() {
    local cmd="$1"
    if [ "$EUID" -eq 0 ]; then
        bash -lc "$cmd"
    elif command_exists sudo; then
        sudo bash -lc "$cmd"
    elif command_exists su; then
        su -c "$cmd" root
    else
        return 1
    fi
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

    if ! docker info >/dev/null 2>&1; then
        local docker_err
        docker_err="$(docker info 2>&1 || true)"

        # If user access is denied, daemon start is not the right fix.
        case "$docker_err" in
            *"permission denied"*|*"Got permission denied"*)
                echo "Error: Current user cannot access the Docker daemon."
                echo "Add this user to the docker group or run docker rootfully, then retry."
                exit 1
                ;;
        esac

        echo "Docker daemon is not running. Attempting to start it..."
        
        # Try to start docker using systemctl if available
        if command_exists systemctl; then
            if ! run_as_root "systemctl start docker"; then
                echo "Error: Failed to start docker daemon using systemctl"
                exit 1
            fi
        # Fallback to service command
        elif command_exists service; then
            if ! run_as_root "service docker start"; then
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
            if [ $attempts -ge 30 ]; then
                echo "Error: Docker daemon failed to start within 30 seconds"
                exit 1
            fi
            sleep 1
        done
        echo "Docker daemon started successfully"
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

    echo "Build completed successfully."
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

# Check prerequisites
check_make
check_docker

# Perform the build
perform_build

# If we get here, everything succeeded
echo "Build process completed successfully!"
echo "Next step: run 'make' to start the cluster."