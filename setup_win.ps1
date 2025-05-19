# Exit on any error
$ErrorActionPreference = "Stop"

# Enable detailed error output
$DebugPreference = "Continue"
$VerbosePreference = "Continue"

# Store the original working directory and script path
$script:OriginalLocation = Get-Location
$script:ScriptPath = $MyInvocation.MyCommand.Path
if (-not $script:ScriptPath) {
    $script:ScriptPath = $PSCommandPath
}

# Initialize exit code
$script:ExitCode = 0

# Function to keep window open
function Keep-WindowOpen {
    Write-Host "`nPress any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# Function to check if running as administrator and self-elevate if needed
function Test-Administrator {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "This script needs to be run as Administrator. Attempting to elevate privileges..." -ForegroundColor Yellow
        
        # Create a new process with elevated privileges
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"Set-Location '$script:OriginalLocation'; & '$script:ScriptPath'`""
        $psi.Verb = "runas"
        $psi.UseShellExecute = $true
        $psi.WorkingDirectory = $script:OriginalLocation
        
        try {
            $process = [System.Diagnostics.Process]::Start($psi)
            $process.WaitForExit()
            exit $process.ExitCode
        }
        catch {
            Write-Error "Failed to elevate privileges. Please run PowerShell as Administrator and try again."
            exit 1
        }
    }
    Write-Host "Running with administrator privileges" -ForegroundColor Green
}

# Global error handler
$ErrorActionPreference = "Stop"
trap {
    Write-Host "`nAn error occurred:" -ForegroundColor Red
    Write-Host "Error Message: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Line Number: $($_.InvocationInfo.Line)" -ForegroundColor Red
    Write-Host "Script Name: $($_.InvocationInfo.ScriptName)" -ForegroundColor Red
    Write-Host "Stack Trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    Keep-WindowOpen
    exit 1
}

# Now that all functions are defined, we can use them
Write-Debug "Changed to directory: $(Get-Location)"
Set-Location $script:OriginalLocation

# Function to verify administrator access
function Test-AdminAccess {
    try {
        $null = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        Write-Host "Successfully verified administrator privileges"
    }
    catch {
        Write-Error "Error: Cannot verify administrator access"
        exit 1
    }
}

# Function to check if a command exists
function Test-CommandExists {
    param([string]$Command)
    Write-Debug "Checking if command exists: $Command"
    $exists = [bool](Get-Command $Command -ErrorAction SilentlyContinue)
    Write-Debug "Command exists: $exists"
    return $exists
}

# Function to list out all packages that will be installed
function List-Packages {
    Write-Host "`nThe following packages will be installed:" -ForegroundColor Yellow
    Write-Host "  - Docker Desktop" -ForegroundColor Yellow
    Write-Host "  - Python 3.11" -ForegroundColor Yellow
    Write-Host "  - jq" -ForegroundColor Yellow
    Write-Host "  - Visual Studio Build Tools 2022" -ForegroundColor Yellow
    
    do {
        $response = Read-Host "`nDo you want to continue with the installation? (y/n)"
        $response = $response.ToLower()
    } while ($response -notin @('y', 'n', 'yes', 'no'))
    
    if ($response -in @('n', 'no')) {
        Write-Host "`nInstallation cancelled by user." -ForegroundColor Red
        exit 0
    }
    
    Write-Host "`nProceeding with installation..." -ForegroundColor Green
}

# Function to check if Visual Studio Build Tools is installed
function Test-VisualStudioBuildTools {
    Write-Debug "Checking for Visual Studio Build Tools installation..."
    
    # Check common installation paths
    $vsPaths = @(
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\BuildTools"
    )
    
    foreach ($path in $vsPaths) {
        if (Test-Path $path) {
            Write-Debug "Found Visual Studio Build Tools at: $path"
            return $true
        }
    }
    
    # Check using vswhere if available
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $vsInstallations = & $vswhere -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($vsInstallations) {
            Write-Debug "Found Visual Studio Build Tools using vswhere"
            return $true
        }
    }
    
    Write-Debug "Visual Studio Build Tools not found"
    return $false
}

# Function to update git submodules
function Update-Submodules {
    Write-Debug "Starting Update-Submodules function..."
    try {
        Write-Debug "Current directory: $(Get-Location)"
        Write-Debug "Checking for git installation..."
        
        if (-not (Test-CommandExists git)) {
            Write-Host "Git is not installed. Attempting to install Git..."
            
            if (Test-CommandExists winget) {
                Write-Host "Installing Git using winget..."
                try {
                    Write-Debug "Running winget install for Git..."
                    $wingetOutput = winget install -e --id Git.Git 2>$null
                    Write-Debug "Winget output: $wingetOutput"
                    Write-Debug "Git installation completed"
                }
                catch {
                    Write-Error "Failed to install Git. Error: $($_.Exception.Message)"
                    throw
                }
                
                # Refresh environment variables
                Write-Debug "Refreshing environment variables..."
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
                
                if (-not (Test-CommandExists git)) {
                    Write-Error "Error: Git installation failed. Please install Git manually and try again."
                    throw "Git installation verification failed"
                }
                Write-Host "Git installed successfully"
            }
            else {
                Write-Error "Error: winget is not available. Please install Git manually and try again."
                throw "Winget not available"
            }
        }

        Write-Debug "Checking for .git directory..."
        if (-not (Test-Path .git)) {
            Write-Error "Error: Not a git repository. Please run this script from the repository root."
            Write-Host "Current directory: $(Get-Location)" -ForegroundColor Red
            Write-Host "Expected .git directory not found" -ForegroundColor Red
            throw "Not a git repository"
        }

        Write-Host "Updating git submodules..."
        Write-Debug "Running git submodule update..."
        $gitOutput = git submodule update --init --force --remote --recursive 2>$null
        Write-Debug "Git output: $gitOutput"
        
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Error: Failed to update git submodules. Exit code: $LASTEXITCODE"
            Write-Error "Git output: $gitOutput"
            throw "Git submodule update failed"
        }
        Write-Host "Git submodules updated successfully"
    }
    catch {
        Write-Error "Error in Update-Submodules: $($_.Exception.Message)"
        throw
    }
}

# Function to install required packages
function Install-RequiredPackages {
    Write-Debug "Starting Install-RequiredPackages function..."
    Write-Host "Installing required packages..."

    if (Test-CommandExists winget) {
        Write-Host "Using winget to install packages..."
        
        try {
            # Check if Docker Desktop is already installed
            $dockerPath = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
            if (Test-Path $dockerPath) {
                Write-Host "Docker Desktop is already installed" -ForegroundColor Green
            } else {
                # Install Docker Desktop
                Write-Debug "Installing Docker Desktop..."
                $dockerOutput = winget install -e --id Docker.DockerDesktop 2>$null
                Write-Debug "Docker Desktop installation output: $dockerOutput"
                if ($LASTEXITCODE -ne 0) {
                    # Check if the error is because Docker is already installed
                    if ($dockerOutput -match "Found an existing package already installed") {
                        Write-Host "Docker Desktop is already installed" -ForegroundColor Green
                    } else {
                        throw "Docker Desktop installation failed with exit code $LASTEXITCODE"
                    }
                }
            }
            
            # Install Python
            Write-Debug "Installing Python..."
            $pythonOutput = winget install -e --id Python.Python.3.11 2>$null
            Write-Debug "Python installation output: $pythonOutput"
            if ($LASTEXITCODE -ne 0) {
                # Check if Python is already installed
                if ($pythonOutput -match "Found an existing package already installed") {
                    Write-Host "Python is already installed" -ForegroundColor Green
                } else {
                    throw "Python installation failed with exit code $LASTEXITCODE"
                }
            }
            
            # Install jq manually
            Write-Debug "Installing jq..."
            $jqUrl = "https://github.com/stedolan/jq/releases/download/jq-1.6/jq-win64.exe"
            $jqPath = "$env:ProgramFiles\jq\jq.exe"
            $jqDir = "$env:ProgramFiles\jq"
            
            # Create jq directory if it doesn't exist
            if (-not (Test-Path $jqDir)) {
                Write-Debug "Creating jq directory..."
                New-Item -ItemType Directory -Path $jqDir -Force | Out-Null
            }
            
            # Download jq if not already present
            if (-not (Test-Path $jqPath)) {
                Write-Debug "Downloading jq..."
                Invoke-WebRequest -Uri $jqUrl -OutFile $jqPath
            } else {
                Write-Host "jq is already installed" -ForegroundColor Green
            }
            
            # Add jq to PATH if not already present
            $currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
            if (-not $currentPath.Contains($jqDir)) {
                Write-Debug "Adding jq to PATH..."
                [Environment]::SetEnvironmentVariable("Path", "$currentPath;$jqDir", "Machine")
                $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine")
            }
            
            # Install build tools if not already installed
            Write-Debug "Checking Visual Studio Build Tools installation..."
            if (-not (Test-VisualStudioBuildTools)) {
                Write-Host "Installing Visual Studio Build Tools 2022..." -ForegroundColor Yellow
                $vsInstall = winget install -e --id Microsoft.VisualStudio.2022.BuildTools --accept-source-agreements --accept-package-agreements 2>$null
                Write-Debug "Visual Studio Build Tools installation output: $vsInstall"
                
                if ($LASTEXITCODE -ne 0) {
                    # Check if Build Tools are already installed
                    if ($vsInstall -match "Found an existing package already installed") {
                        Write-Host "Visual Studio Build Tools is already installed" -ForegroundColor Green
                    } else {
                        throw "Visual Studio Build Tools installation failed with exit code $LASTEXITCODE"
                    }
                }
                Write-Host "Visual Studio Build Tools installation completed" -ForegroundColor Green
            } else {
                Write-Host "Visual Studio Build Tools is already installed" -ForegroundColor Green
            }

            # Refresh environment variables after installations
            Write-Debug "Refreshing environment variables..."
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        }
        catch {
            Write-Error "Failed to install packages. Error: $($_.Exception.Message)"
            Write-Error "Installation output: $($_.Exception.Message)"
            throw
        }
    }
    else {
        Write-Error "winget not found. Please install the following manually:"
        Write-Error "- Docker Desktop"
        Write-Error "- Python 3.11"
        Write-Error "- jq"
        Write-Error "- Visual Studio Build Tools 2022"
        exit 1
    }

    # Verify installations
    Write-Host "Verifying installations..."
    $requiredCommands = @("docker", "python", "jq")
    foreach ($cmd in $requiredCommands) {
        Write-Debug "Checking installation of $cmd..."
        try {
            # Try to get the command path first
            $cmdPath = Get-Command $cmd -ErrorAction Stop
            Write-Debug "Found $cmd at: $($cmdPath.Source)"
            
            # Then try to get the version
            $version = Invoke-Expression "$cmd --version" 2>$null
            Write-Debug "$cmd version: $version"
            
            if ($LASTEXITCODE -ne 0) {
                throw "$cmd installation verification failed. Exit code: $LASTEXITCODE"
            }
            Write-Host "$cmd is installed successfully" -ForegroundColor Green
        }
        catch {
            Write-Error "Error: Failed to verify $cmd installation"
            Write-Error "Error details: $($_.Exception.Message)"
            Write-Error "Please ensure $cmd is properly installed and available in your PATH"
            Write-Error "Current PATH: $env:Path"
            throw
        }
    }
}

# Function to verify Docker is running and accessible
function Test-DockerRunning {
    Write-Debug "Verifying Docker is running and accessible..."
    
    try {
        # Check if Docker is responding to commands using PowerShell native commands
        $dockerInfo = & docker info
        if ($?) {
            Write-Debug "Docker is running and accessible"
            return $true
        }

        Write-Debug "Docker info check failed"
        return $false
    }
    catch {
        Write-Debug "Error checking Docker status: $($_.Exception.Message)"
        return $false
    }
}

# Function to configure Docker
function Configure-Docker {
    Write-Debug "Starting Configure-Docker function..."
    Write-Host "Configuring Docker..."

    # Check if Docker is running and responding
    if (Test-DockerRunning) {
        Write-Host "Docker is already running and responding" -ForegroundColor Green
        return
    }

    # Only restart if Docker is not responding
    Write-Debug "Docker is not responding, attempting to restart..."
    try {
        Stop-Process -Name "Docker Desktop" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
        Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"
        Write-Debug "Docker Desktop restarted successfully"
    }
    catch {
        Write-Error "Failed to restart Docker Desktop. Error: $($_.Exception.Message)"
        exit 1
    }
}

# Function to ensure Docker is running
function Ensure-DockerRunning {
    Write-Debug "Starting Ensure-DockerRunning function..."
    Write-Host "Ensuring Docker is running..."

    # Check if Docker Desktop is installed
    $dockerPath = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    if (-not (Test-Path $dockerPath)) {
        Write-Error "Docker Desktop not found at expected location: $dockerPath"
        exit 1
    }

    # Check if Docker is already running
    if (Test-DockerRunning) {
        Write-Host "Docker is already running and responding" -ForegroundColor Green
        return
    }

    # Start Docker Desktop if not running
    Write-Host "Docker Desktop is not running. Starting it..." -ForegroundColor Yellow
    try {
        Start-Process $dockerPath
        Write-Debug "Docker Desktop started"
    }
    catch {
        Write-Error "Failed to start Docker Desktop. Error: $($_.Exception.Message)"
        exit 1
    }
    
    # Wait for Docker to be ready with improved retry logic
    Write-Debug "Waiting for Docker to be ready..."
    $attempts = 0
    $maxAttempts = 60  # 60 seconds timeout
    $success = $false
    
    while ($attempts -lt $maxAttempts -and -not $success) {
        if (Test-DockerRunning) {
            $success = $true
            Write-Host "Docker is responding to commands" -ForegroundColor Green
            break
        }
        
        $attempts++
        Write-Debug "Waiting for Docker to initialize... Attempt ${attempts} of ${maxAttempts}"
        
        # If we've waited 10 seconds and Docker still isn't responding, try restarting it
        if ($attempts -eq 10) {
            Write-Host "Docker is not responding after 30 seconds. Attempting to restart Docker Desktop..." -ForegroundColor Yellow
            Stop-Process -Name "Docker Desktop" -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 5
            Start-Process $dockerPath
            $attempts = 0  # Reset attempts after restart
        }
        
        Start-Sleep -Seconds 3
    }
    
    if (-not $success) {
        Write-Error "Docker Desktop failed to initialize within $maxAttempts seconds"
        Write-Host "Please check Docker Desktop status and try again"
        exit 1
    }
}

# Function to check and handle Docker login
function Test-DockerLogin {
    Write-Host "Checking Docker login status..."
    
    # First check if we're already logged in
    try {
        $loginStatus = Invoke-Expression "docker info" | Select-String "Username"
        if ($loginStatus) {
            Write-Host "Already logged in to Docker Hub" -ForegroundColor Green
            return $true
        }
    }
    catch {
        Write-Debug "Docker info check failed: $($_.Exception.Message)"
    }
    
    # If not logged in, prompt for credentials
    Write-Host "Docker login required. Please enter your Docker Hub credentials:"
    
    # Prompt for username
    $dockerUsername = Read-Host "Docker Hub Username"
    if ([string]::IsNullOrEmpty($dockerUsername)) {
        Write-Error "Error: Username cannot be empty"
        return $false
    }
    
    # Prompt for password (hidden)
    $dockerPassword = Read-Host "Docker Hub Password" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($dockerPassword)
    $dockerPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    
    if ([string]::IsNullOrEmpty($dockerPassword)) {
        Write-Error "Error: Password cannot be empty"
        return $false
    }
    
    # Attempt to login
    Write-Host "Logging in to Docker Hub..."
    try {
        $loginOutput = $dockerPassword | Invoke-Expression "docker login -u $dockerUsername --password-stdin" | Out-String
        Write-Debug "Docker login output: $loginOutput"
        
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Error: Docker login failed"
            Write-Error "Login output: $loginOutput"
            return $false
        }
        
        Write-Host "Docker login successful" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Error: Docker login failed"
        Write-Error "Error details: $($_.Exception.Message)"
        return $false
    }
}

# Function to start Docker Desktop
function Start-DockerDesktop {
    Write-Debug "Attempting to start Docker Desktop..."
    
    $dockerPaths = @(
        "C:\Program Files\Docker\Docker\Docker Desktop.exe",
        "${env:ProgramFiles}\Docker\Docker\Docker Desktop.exe",
        "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe"
    )

    $dockerPath = $dockerPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    
    if (-not $dockerPath) {
        Write-Error "Docker Desktop not found in expected locations"
        return $false
    }

    try {
        Start-Process $dockerPath
        Write-Host "Docker Desktop starting..." -ForegroundColor Yellow
        
        # Wait for Docker to be ready
        $attempts = 0
        $maxAttempts = 60
        while ($attempts -lt $maxAttempts) {
            if (Test-DockerRunning) {
                Write-Host "Docker Desktop started successfully" -ForegroundColor Green
                return $true
            }
            $attempts++
            Write-Debug "Waiting for Docker to start... Attempt ${attempts} of ${maxAttempts}"
            Start-Sleep -Seconds 1
        }
        
        Write-Error "Docker Desktop failed to start within $maxAttempts seconds"
        return $false
    }
    catch {
        Write-Error "Failed to start Docker Desktop: $($_.Exception.Message)"
        return $false
    }
}

# Function to perform the build
function Start-Build {
    Write-Host "Starting build process..." -ForegroundColor Cyan

    # First verify Docker is running
    if (-not (Test-DockerRunning)) {
        Write-Host "Docker is not running. Attempting to start Docker Desktop..." -ForegroundColor Yellow
        if (-not (Start-DockerDesktop)) {
            Write-Error "Failed to start Docker Desktop. Please start it manually and try again."
            exit 1
        }
    }

    # Check if we're in the correct directory
    Write-Host "Checking for Makefile.win..." -ForegroundColor Yellow
    if (-not (Test-Path "Makefile.win")) {
        Write-Error "Error: Makefile.win not found. Please run this script from the repository root."
        Write-Host "Current directory: $(Get-Location)" -ForegroundColor Red
        exit 1
    }
    Write-Host "Makefile.win found successfully" -ForegroundColor Green

    # Clean any previous build artifacts
    Write-Host "Cleaning previous build artifacts..." -ForegroundColor Yellow
    try {
        # Clean up files directly
        if (Test-Path "scaleout\nodelist") {
            Write-Host "Removing nodelist..." -ForegroundColor Gray
            Remove-Item "scaleout\nodelist" -Force
        }
        if (Test-Path "scaleout\hosts.nodes") {
            Write-Host "Removing hosts.nodes..." -ForegroundColor Gray
            Remove-Item "scaleout\hosts.nodes" -Force
        }
        Write-Host "Clean completed successfully" -ForegroundColor Green
    }
    catch {
        Write-Error "Error during cleanup: $($_.Exception.Message)"
        # Don't exit here, continue with the build
    }

    # Build the images
    Write-Host "Building Docker images..." -ForegroundColor Yellow
    try {
        Write-Host "Running build command..." -ForegroundColor Gray
        
        # First, let's check if we have the required files
        Write-Host "Checking required files..." -ForegroundColor Gray
        $requiredFiles = @(
            "scaleout/Dockerfile",
            "Makefile.win"
        )
        
        $missingFiles = @()
        foreach ($file in $requiredFiles) {
            Write-Host "Checking for $file..." -ForegroundColor Gray
            if (-not (Test-Path $file)) {
                $missingFiles += $file
                Write-Host "Missing: $file" -ForegroundColor Red
            } else {
                Write-Host "Found: $file" -ForegroundColor Green
            }
        }
        
        if ($missingFiles.Count -gt 0) {
            Write-Error "The following required files are missing:"
            foreach ($file in $missingFiles) {
                Write-Error "  - $file"
            }
            Write-Error "Please ensure all required files are present in the correct locations."
            Write-Error "Current directory: $(Get-Location)"
            throw "Missing required files"
        }
        
        # Run the build command with detailed output
        Write-Host "Executing build command..." -ForegroundColor Gray
        Write-Host "Current directory: $(Get-Location)" -ForegroundColor Yellow
        Write-Host "Directory contents:" -ForegroundColor Yellow
        Get-ChildItem -Force | Format-Table Name, Length, LastWriteTime
        
        # Execute make command and capture output
        $process = Start-Process -FilePath "make" -ArgumentList "-f", "Makefile.win", "build" -NoNewWindow -Wait -PassThru -RedirectStandardOutput "make_output.txt" -RedirectStandardError "make_error.txt"
        
        # Read and display the output
        if (Test-Path "make_output.txt") {
            Write-Host "`nBuild command standard output:" -ForegroundColor Gray
            Get-Content "make_output.txt" | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
        }
        
        if (Test-Path "make_error.txt") {
            Write-Host "`nBuild command error output:" -ForegroundColor Red
            Get-Content "make_error.txt" | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        }
        
        # Clean up temporary files
        Remove-Item "make_output.txt" -ErrorAction SilentlyContinue
        Remove-Item "make_error.txt" -ErrorAction SilentlyContinue
        
        if ($process.ExitCode -ne 0) {
            Write-Error "Build command failed with exit code $($process.ExitCode)"
            
            # Check for common issues
            $errorContent = if (Test-Path "make_error.txt") { Get-Content "make_error.txt" -Raw } else { "" }
            if ($errorContent -match "permission denied") {
                Write-Error "Permission denied error detected. Please ensure you have the necessary permissions."
            }
            elseif ($errorContent -match "no such file") {
                Write-Error "Missing file error detected. Please ensure all required files are present."
            }
            elseif ($errorContent -match "network") {
                Write-Error "Network error detected. Please check your internet connection and Docker network settings."
            }
            elseif ($errorContent -match "authentication required" -or $errorContent -match "unauthorized") {
                Write-Host "Docker login required for this operation..." -ForegroundColor Yellow
                if (Test-DockerLogin) {
                    Write-Host "Retrying build after successful login..." -ForegroundColor Yellow
                    $process = Start-Process -FilePath "make" -ArgumentList "-f", "Makefile.win", "build" -NoNewWindow -Wait -PassThru -RedirectStandardOutput "make_output.txt" -RedirectStandardError "make_error.txt"
                    if ($process.ExitCode -ne 0) {
                        throw "Build failed even after Docker login"
                    }
                } else {
                    throw "Docker login failed"
                }
            }
            
            throw "Build command failed with exit code $($process.ExitCode)"
        }
        
        Write-Host "Build completed successfully" -ForegroundColor Green
    }
    catch {
        Write-Error "Error: Failed to build Docker images"
        Write-Error "Error details: $($_.Exception.Message)"
        Write-Host "`nCurrent directory: $(Get-Location)" -ForegroundColor Yellow
        Write-Host "Directory contents:" -ForegroundColor Yellow
        Get-ChildItem -Force | Format-Table Name, Length, LastWriteTime
        exit 1
    }

    # Verify images were built successfully
    Write-Host "Verifying Docker images..." -ForegroundColor Yellow
    $requiredImages = @("scaleout", "grafana")
    $missingImages = $false

    foreach ($image in $requiredImages) {
        Write-Host "Checking for image: $image" -ForegroundColor Gray
        try {
            $imageInfo = Invoke-Expression "docker image inspect $image" | Out-String
            Write-Host "Image $image found successfully" -ForegroundColor Green
            Write-Host "Image details: $imageInfo" -ForegroundColor Gray
        }
        catch {
            Write-Error "Error: Required image '$image' was not built successfully"
            Write-Error "Docker inspect output: $imageInfo"
            $missingImages = $true
        }
    }

    if ($missingImages) {
        Write-Error "Error: Some required images are missing. Please check the build output for errors."
        Write-Host "Available Docker images:" -ForegroundColor Yellow
        docker images
        exit 1
    }

    # Start the cluster
    Write-Host "Starting the cluster..." -ForegroundColor Yellow
    try {
        Write-Host "Running make command..." -ForegroundColor Gray
        
        # First verify docker-compose.yml exists
        if (-not (Test-Path "docker-compose.yml")) {
            Write-Error "Error: docker-compose.yml not found. The build process may have failed."
            throw "Missing docker-compose.yml"
        }
        
        # Show docker-compose.yml contents for debugging
        Write-Host "`nContents of docker-compose.yml:" -ForegroundColor Yellow
        Get-Content "docker-compose.yml" | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
        
        # Run make and capture both output and error streams
        Write-Host "`nExecuting make up command..." -ForegroundColor Yellow
        
        # First try to run docker compose directly to see if it works
        Write-Host "`nTesting docker compose directly..." -ForegroundColor Yellow
        Write-Host "Running: docker compose ps" -ForegroundColor Gray
        $composeTest = Invoke-Expression "docker compose ps" | Out-String
        Write-Host "Docker compose test output:" -ForegroundColor Gray
        Write-Host $composeTest
        
        # Check Docker status before proceeding
        Write-Host "`nChecking Docker status before make up..." -ForegroundColor Yellow
        Write-Host "Running: docker info" -ForegroundColor Gray
        $dockerStatus = Invoke-Expression "docker info" | Out-String
        Write-Host "Docker info:" -ForegroundColor Gray
        Write-Host $dockerStatus
        
        # Now try the make command with detailed output
        Write-Host "`nRunning make up..." -ForegroundColor Yellow
        Write-Host "Current directory: $(Get-Location)" -ForegroundColor Gray
        Write-Host "`nRunning: make -f Makefile.win up" -ForegroundColor Gray
        
        # Run make up and capture output
        $makeOutput = Invoke-Expression "make -f Makefile.win up" | Out-String
        Write-Host "Make command output:" -ForegroundColor Gray
        Write-Host $makeOutput
        
        # Check if containers are running
        Write-Host "`nVerifying container status..." -ForegroundColor Yellow
        $runningContainers = Invoke-Expression 'docker ps --format "{{.Names}}: {{.Status}}"' | Out-String
        Write-Host "Running containers:" -ForegroundColor Green
        Write-Host $runningContainers
        
        # If we get here, the command was successful
        Write-Host "Cluster started successfully" -ForegroundColor Green
    }
    catch {
        Write-Error "Error: Failed to start the cluster"
        Write-Error "Error details: $($_.Exception.Message)"
        
        # Additional diagnostic information
        Write-Host "`nDiagnostic Information:" -ForegroundColor Yellow
        Write-Host "Docker version:" -ForegroundColor Gray
        docker version
        Write-Host "`nDocker info:" -ForegroundColor Gray
        docker info
        Write-Host "`nDocker compose version:" -ForegroundColor Gray
        docker compose version
        Write-Host "`nCurrent directory:" -ForegroundColor Gray
        Get-Location
        Write-Host "`nDirectory contents:" -ForegroundColor Gray
        Get-ChildItem -Force | Format-Table Name, Length, LastWriteTime
        
        # Show the actual error output
        Write-Host "`nMake command output:" -ForegroundColor Red
        Write-Host $makeOutput
        
        exit 1
    }

    Write-Host "Build and deployment completed successfully!" -ForegroundColor Green
}

# Function to handle cleanup on script exit
function Invoke-Cleanup {
    param($ExitCode)
    if ($ExitCode -ne 0) {
        Write-Host "Build failed with exit code $ExitCode" -ForegroundColor Red
        Write-Host "Attempting to clean up..." -ForegroundColor Yellow
        try {
            $cleanupOutput = make -f Makefile.win clean 2>$null
            Write-Host "Cleanup output: $cleanupOutput" -ForegroundColor Gray
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Cleanup failed with exit code $LASTEXITCODE"
            }
        }
        catch {
            Write-Error "Error during cleanup: $($_.Exception.Message)"
            Write-Error "Cleanup output: $cleanupOutput"
        }
    }
    exit $ExitCode
}

# Function to handle 'make host' command
function Connect-ToHost {
    param(
        [string]$HostName
    )
    
    $containerName = "docker-scale-out-${HostName}-1"
    
    # Check if container exists
    $container = docker ps -a --filter "name=$containerName" --format "{{.Names}}"
    if (-not $container) {
        Write-Error "Container for host '$HostName' not found. Available containers:"
        docker ps --format "{{.Names}}"
        return
    }
    
    # Check if container is running
    $status = docker ps --filter "name=$containerName" --format "{{.Status}}"
    if (-not $status) {
        Write-Error "Container $containerName is not running. Current status:"
        docker ps -a --filter "name=$containerName" --format "{{.Names}}: {{.Status}}"
        return
    }
    
    # Connect to the container
    Write-Host "Connecting to $containerName..." -ForegroundColor Green
    docker exec -it $containerName bash
}

# Add alias for make host command
Set-Alias -Name make -Value Connect-ToHost -Force

# Main execution
try {
    Write-Host "Starting setup process..." -ForegroundColor Cyan
    Write-Host "Current directory: $(Get-Location)" -ForegroundColor Yellow
    Write-Host "PowerShell version: $($PSVersionTable.PSVersion)" -ForegroundColor Yellow
    Write-Host "OS version: $([System.Environment]::OSVersion)" -ForegroundColor Yellow

    # Check administrator privileges
    Test-Administrator
    Test-AdminAccess

    # List packages and get user confirmation
    List-Packages

    # Update git submodules
    Update-Submodules

    # Install required packages
    Install-RequiredPackages

    # Configure and ensure Docker is running
    Configure-Docker
    Ensure-DockerRunning

    # Perform the build
    Start-Build

    # If we get here, everything succeeded
    Write-Host "`nSetup process completed successfully!" -ForegroundColor Green
    
    # Display connection instructions
    Write-Host "`nTo connect to the login node, you can use either of these methods:" -ForegroundColor Cyan
    Write-Host "1. Using the 'make' command:" -ForegroundColor Yellow
    Write-Host "   make login" -ForegroundColor White
    Write-Host "2. Using Docker directly:" -ForegroundColor Yellow
    Write-Host "   docker exec -it docker-scale-out-login-1 bash" -ForegroundColor White
    Write-Host "`nNote: The login node is accessible at:" -ForegroundColor Cyan
    Write-Host "   - IPv4: ${Subnet}.1.5" -ForegroundColor White
    Write-Host "   - IPv6: ${Subnet6}1:5" -ForegroundColor White
    Write-Host "   - Hostname: login" -ForegroundColor White
    
    $script:ExitCode = 0
    Keep-WindowOpen
}
catch {
    Write-Host "`nAn error occurred during setup:" -ForegroundColor Red
    Write-Host "Error Message: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Error Type: $($_.Exception.GetType().FullName)" -ForegroundColor Red
    Write-Host "Line Number: $($_.InvocationInfo.Line)" -ForegroundColor Red
    Write-Host "Script Name: $($_.InvocationInfo.ScriptName)" -ForegroundColor Red
    Write-Host "Stack Trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    $script:ExitCode = 1
    Keep-WindowOpen
}
finally {
    Write-Host "`nPerforming final cleanup..." -ForegroundColor Yellow
    try {
        Invoke-Cleanup -ExitCode $script:ExitCode
    }
    catch {
        Write-Host "Error during cleanup: $($_.Exception.Message)" -ForegroundColor Red
    }
} 