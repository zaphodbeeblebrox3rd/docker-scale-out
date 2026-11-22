# Slurm docker-scale-out

A Docker Compose Slurm cluster for training, testing, and development: multiple management and compute nodes, slurmdbd, slurmrestd, and a web stack (Open OnDemand, Open XDMoD, Grafana, OpenSearch, Keycloak).

> Not for production. Run it on a dedicated VM or test machine; setup changes host Docker and kernel settings.

## Requirements

- Linux (Debian or RHEL family) with root access; Windows is supported but less tested
- 12 GB RAM minimum, 16 GB+ recommended
- 30 GB free disk
- x86_64 or arm64

## Quick start (Linux)

```bash
git clone --recurse-submodules --shallow-submodules https://github.com/zaphodbeeblebrox3rd/docker-scale-out.git
cd docker-scale-out
./setup_1.sh        # installs packages, configures Docker and sysctls
sudo reboot
./setup_2.sh        # builds the images and starts the cluster
make bash           # shell on the login node
```

From the login node, try `sinfo` and `srun -N2 hostname`. Stop the cluster with `make stop` and start it again with `make`.

## Quick start (Windows)

Run in an elevated PowerShell:

```powershell
.\setup_win.ps1
```

It installs any missing prerequisites (Git for Windows with Git Bash, GNU make, Docker Desktop), then runs the same `make build` as Linux in Git Bash. Later `make` commands work the same as on Linux, from PowerShell or Git Bash.

## Web interfaces

| Service | URL | Login |
|---|---|---|
| Open OnDemand | http://localhost:8081/ | `fred` or `wilma` / `password` |
| Open XDMoD | http://localhost:8082/ | |
| Grafana | http://localhost:3000/ | `admin` / `admin` |
| OpenSearch Dashboards | http://127.0.0.1:5601/ | |
| Keycloak admin | http://127.0.0.1:8083/ | `admin` / `password` |

## Documentation

- [Architecture and services](docs/services.md): nodes, ports, REST API
- [Operating the cluster](docs/operations.md): start, stop, shells, clean, save/load
- [Customization](docs/customization.md): node lists, subnets, Slurm version, feature toggles, federation, cloud mode
- [Building images](docs/building.md): submodules, rebuilds, test builds
- [Troubleshooting](docs/troubleshooting.md): network overlaps, build failures, cgroup limits
- [Developer build workflow](docs/developer-build-workflow.md): how the setup scripts, Makefiles, and compose generator work
