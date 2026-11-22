# Script parameters
param(
    [string]$Subnet = "10.11",
    [string]$Subnet6 = "2001:db8:1:1::"
)

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
    Write-Host "  - Git for Windows (git and Git Bash)" -ForegroundColor Yellow
    Write-Host "  - GNU make" -ForegroundColor Yellow
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

# Function to refresh PATH after installing packages
function Update-PathFromRegistry {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}

# Function to install a package with winget
function Install-WingetPackage {
    param([string]$Id)
    if (-not (Test-CommandExists winget)) {
        throw "winget is not available. Please install $Id manually and try again."
    }
    Write-Host "Installing $Id using winget..."
    winget install -e --id $Id --accept-source-agreements --accept-package-agreements
    Update-PathFromRegistry
}

# Function to find Git for Windows' bash.exe (not the WSL bash.exe in System32)
function Find-GitBash {
    $candidates = @()
    $git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($git) {
        # git.exe lives in <Git>\cmd or <Git>\mingw64\bin
        $gitDir = Split-Path (Split-Path $git.Source -Parent) -Parent
        $candidates += Join-Path $gitDir "bin\bash.exe"
        $candidates += Join-Path (Split-Path $gitDir -Parent) "bin\bash.exe"
    }
    $candidates += "$env:ProgramFiles\Git\bin\bash.exe", "${env:ProgramFiles(x86)}\Git\bin\bash.exe", "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
    return $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}

# Function to ensure git, Git Bash and GNU make are available; the build runs the Linux Makefile in Git Bash
function Ensure-BuildTools {
    Write-Host "Checking for Git for Windows (git and Git Bash)..."
    if (-not (Test-CommandExists git) -or -not (Find-GitBash)) {
        Install-WingetPackage "Git.Git"
    }
    $script:GitBash = Find-GitBash
    if (-not (Test-CommandExists git) -or -not $script:GitBash) {
        throw "Git for Windows was not found after installation. Install it from https://git-scm.com/download/win and try again."
    }
    Write-Host "Found Git Bash at $script:GitBash" -ForegroundColor Green

    Write-Host "Checking for GNU make..."
    & $script:GitBash -c "command -v make >/dev/null"
    if ($LASTEXITCODE -ne 0) {
        Install-WingetPackage "ezwinports.make"
        & $script:GitBash -c "command -v make >/dev/null"
        if ($LASTEXITCODE -ne 0) {
            throw "GNU make was not found after installation. Run 'winget install ezwinports.make' and try again."
        }
    }
    Write-Host "Found GNU make" -ForegroundColor Green
}

# Function to update git submodules
function Update-Submodules {
    Write-Debug "Starting Update-Submodules function..."
    try {
        Write-Debug "Current directory: $(Get-Location)"
        Write-Debug "Checking for git installation..."
        
        if (-not (Test-CommandExists git)) {
            throw "git not found"
        }

        Write-Debug "Checking for .git directory..."
        if (-not (Test-Path .git)) {
            Write-Error "Error: Not a git repository. Please run this script from the repository root."
            Write-Host "Current directory: $(Get-Location)" -ForegroundColor Red
            Write-Host "Expected .git directory not found" -ForegroundColor Red
            throw "Not a git repository"
        }

        Write-Host "Updating git submodules (shallow clones of pinned versions; first run may take several minutes)..."
        # Some submodules (e.g. openapi-generator) contain paths longer than MAX_PATH
        git config --global core.longpaths true
        Write-Debug "Running git submodule update..."
        # Keep Unix line endings and real symlinks (several sources build only with them); creating symlinks needs admin or Developer Mode
        $checkoutConfig = @("-c", "core.autocrlf=false", "-c", "core.symlinks=true")
        $submoduleArgs = @("--init", "--force", "--recursive", "--checkout", "--depth", "1", "--recommend-shallow", "--single-branch", "--progress")
        # Slurm has src/conmgr/con.c; Windows 11 allows it but git rejects reserved device names unless core.protectNTFS is off
        git -c core.protectNTFS=false @checkoutConfig submodule update @submoduleArgs -- scaleout/src/slurm
        if ($LASTEXITCODE -eq 0) { git -C scaleout/src/slurm config core.protectNTFS false }
        git @checkoutConfig submodule update @submoduleArgs

        if ($LASTEXITCODE -ne 0) {
            Write-Error "Error: Failed to update git submodules. Exit code: $LASTEXITCODE"
            throw "Git submodule update failed"
        }
        # Keep these settings for later checkouts (make build checks out the requested Slurm release), and recreate symlinks that earlier checkouts stored as plain files
        git submodule foreach --recursive --quiet 'git config core.autocrlf false; git config core.symlinks true; if git ls-files -s | grep -q ^120000; then git ls-files -s | grep ^120000 | cut -f2 | git checkout -f --pathspec-from-file=-; fi'
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
            $jqUrl = "https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-windows-amd64.exe"
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

    # Same build as Linux: buildout.sh generates docker-compose.yml, then the Makefile builds the images and starts the cluster
    $env:SUBNET = $Subnet
    $env:SUBNET6 = $Subnet6
    # Stop Git Bash from rewriting container paths such as /bin/bash into Windows paths
    $env:MSYS_NO_PATHCONV = "1"
    # Always regenerate docker-compose.yml from buildout.sh
    Remove-Item "docker-compose.yml" -ErrorAction SilentlyContinue

    Write-Host "Running 'make build' in Git Bash (the first build takes a long time)..." -ForegroundColor Yellow
    & $script:GitBash -c "make build 2>&1"
    if ($LASTEXITCODE -ne 0) {
        throw "make build failed with exit code $LASTEXITCODE"
    }

    Write-Host "`nContainer status:" -ForegroundColor Yellow
    docker compose ps -a --format "{{.Name}}: {{.Status}}"

    Write-Host "Build and deployment completed successfully!" -ForegroundColor Green
}

# Function to handle cleanup on script exit
function Invoke-Cleanup {
    param($ExitCode)
    if ($ExitCode -ne 0) {
        Write-Host "Build failed with exit code $ExitCode" -ForegroundColor Red
        Write-Host "Fix the error above and rerun this script; it resumes from the existing images and volumes." -ForegroundColor Yellow
    }
    exit $ExitCode
}

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

    # Ensure git, Git Bash and GNU make, then update git submodules
    Ensure-BuildTools
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
    Write-Host "1. From Git Bash in this directory:" -ForegroundColor Yellow
    Write-Host "   make bash" -ForegroundColor White
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