# Developer Build Workflow Deep Dive

This document explains how this project builds, boots, and operates from first setup through daily operations.

It is intentionally detailed and aimed at two audiences:

- Operators who need a reliable runbook.
- Maintainers who need to understand why the scripts and Makefiles behave the way they do.

This file focuses on actual current behavior in this repository as of today, including places where behavior may be surprising.

---

## Section 1 - Reader Guide

### If you are an operator

Read these sections first:

- Section 2 End to end lifecycle summary
- Section 3 setup_1.sh Linux host provisioning
- Section 4 setup_2.sh image preparation
- Section 5 Makefile runtime model
- Section 11 Operational playbooks
- Section 12 Failure catalog and troubleshooting matrix

### If you are a maintainer

Read these sections first:

- Section 6 buildout.sh compose generation internals
- Section 7 Image build pipeline under the hood
- Section 8 Runtime networking and subnet strategy
- Section 9 Windows flow and divergences
- Section 10 Cloud mode deep dive
- Section 13 Maintainer notes and validation strategy

### Source files discussed in this guide

- `docker-scale-out/setup_1.sh`
- `docker-scale-out/setup_2.sh`
- `docker-scale-out/Makefile`
- `docker-scale-out/buildout.sh`
- `docker-scale-out/setup_win.ps1`
- `docker-scale-out/Makefile.win`
- `docker-scale-out/buildout.ps1`
- `docker-scale-out/cloud_monitor.py3`

---

## Section 2 - End to End Lifecycle Summary

### Linux high level lifecycle

1. Run `setup_1.sh`
2. Reboot host
3. Run `setup_2.sh`
4. Use `make` for day to day lifecycle commands

### Windows high level lifecycle

1. Run `setup_win.ps1` as administrator
2. Script installs tools and builds stack
3. Use docker compose and makefile.win commands for lifecycle tasks

### Important behavioral note about setup_2 and make build

Current implementation detail:

- `setup_2.sh` executes `make build`
- `make build` currently maps to `docker compose up --build --remove-orphans -d`
- That means containers are started during `make build`

So if setup_2 was expected to only prepare images and not start services, current Makefile behavior is more aggressive than the setup_2 terminal message suggests.

The script message says next step is `make`, but from an implementation standpoint `make build` has already started services.

This guide documents current behavior, not intended behavior.

---

## Section 3 - setup_1.sh Linux Host Provisioning Deep Dive

File:

- `docker-scale-out/setup_1.sh`

### Design goals of setup_1

- Install prerequisite software for supported Linux families.
- Configure host kernel and Docker daemon for this stack.
- Ensure Docker is enabled and reachable.
- Leave system in a reboot ready state before build stage.

### Main execution order in setup_1

At the bottom of the file, setup_1 executes this sequence:

1. `update_submodules`
2. `check_root`
3. `verify_root_access`
4. `install_packages`
5. `configure_sysctl`
6. `configure_docker`
7. `enable_docker_ipv6`
8. `ensure_docker_running`
9. Print reboot instruction

### update_submodules

Purpose:

- Forces all git submodules to expected state.

Behavior:

- Requires git binary.
- Requires script to run from repo root where `.git` exists.
- Executes:
  - `git submodule update --init --force --remote --recursive`

Why it matters:

- Build contexts and internal assets can live in submodules.
- Missing submodules produces confusing downstream build failures.

### check_root and verify_root_access

Purpose:

- Guarantee privileged operations can run.

Behavior:

- If not root, setup_1 attempts elevation with `sudo` first, then `su`.
- If neither exists, script exits with explicit error.
- `verify_root_access` checks `id -u` equals 0.

Why it matters:

- Script writes under `/etc`, updates package manager state, and modifies system services.

### install_packages

Purpose:

- Install required runtime and build dependencies.

Behavior highlights:

- Detects distro from `/etc/os-release`.
- Uses distro specific package manager paths:
  - Debian or Ubuntu path using `apt-get`.
  - Fedora path using `dnf`.
  - RHEL family path using `dnf` plus repo bootstrapping if needed.
  - Suse path using `zypper`.
  - Arch path using `pacman`.

Installed categories include:

- Docker engine or docker package.
- Compose plugin or compose package depending on distro.
- Build toolchain and development headers.
- Utilities such as jq, ssh client, python3, python3-daemon.

Why it matters:

- This project compiles substantial components in image builds, especially under `scaleout` context.

### configure_sysctl

Purpose:

- Set host kernel tunables for high process and networking load expected by this environment.

Behavior:

- Writes `/etc/sysctl.d/99-slurm-docker.conf`.
- Applies changes via `sysctl --system`.

Parameter intent includes:

- TCP backlog and netdev backlog expansion.
- ARP neighbor gc thresholds and timings.
- vm max map count for Elasticsearch.
- inotify and file descriptor limits.

Why it matters:

- Avoids avoidable service instability under container and job load.

### configure_docker

Purpose:

- Configure Docker daemon and systemd cgroup behavior.

Behavior:

- Writes `/etc/docker/daemon.json` with key options.
- Creates `/etc/systemd/system/docker.slice`.
- Creates `/usr/lib/systemd/system/docker.service.d/local.conf`.
- Reloads and restarts docker related units.

Notable daemon settings:

- systemd cgroup driver
- buildkit enabled
- experimental true
- cgroup parent docker.slice
- default cgroup namespace host
- overlay2 storage driver

Why it matters:

- This stack depends on host level cgroup and process semantics that are sensitive to daemon defaults.

### enable_docker_ipv6

Purpose:

- Ensure daemon config includes IPv6 block required for this project networking model.

Behavior:

- Ensures daemon json exists.
- Uses jq merge to set:
  - ipv6 true
  - fixed cidr v6 set to `2001:db8:1::/64`
- Restarts docker service.

Why it matters:

- Generated compose network in this project includes IPv6 allocations.  This was a design decision to make it easier to test IPv6 support.

### ensure_docker_running

Purpose:

- Confirm docker daemon is enabled and active.

Behavior:

- Enables docker service if disabled.
- Attempts to start daemon when not running.
- Handles both systemctl and service based systems.
- Wait loop has bounded retry and clear errors.

Why it matters:

- setup_2 and make build require immediate daemon availability.

### Why reboot is requested after setup_1

Reboot is requested because setup_1 modifies:

- systemd unit definitions
- cgroup and docker service relationships
- kernel tunables

Running setup_2 without reboot may work on some systems, but behavior can be inconsistent when stale daemon state persists.

---

## Section 4 - setup_2.sh Image Preparation and Verification Deep Dive

File:

- `docker-scale-out/setup_2.sh`

### Design goals of setup_2

- Validate privileged environment for build stage.
- Clean stale compose state from prior runs.
- Build image set and verify minimum expected outputs.
- Avoid interactive docker login prompts in user workflow.

### Main execution order

1. `check_root`
2. `verify_root_access`
3. `check_make`
4. `check_docker`
5. `perform_build`
6. `cleanup` trap on error path

### check_make

Purpose:

- Fail early if make is unavailable.

### check_docker

Purpose:

- Ensure docker command exists and daemon is alive.

Behavior:

- Calls `docker info`.
- If daemon unavailable, attempts start via systemctl or service.
- Waits up to 30 seconds for ready state.

### perform_build internals

Current order:

1. Verify `Makefile` exists in current directory.
2. `make clean`
3. `make build`
4. Verify local images exist via `docker image inspect` for:
   - `scaleout`
   - `grafana`

### login behavior in setup_2

Current policy:

- No interactive docker login prompt.
- No user credential prompt in script path.

Observed practical effect:

- If upstream pulls are unauthorized for any reason, build fails with regular compose or registry error messages.

### cleanup trap behavior

`trap cleanup EXIT` is active.

On nonzero exit:

- Prints build failed with exit code.
- Executes `make clean` to reduce partial broken state.

Why this matters:

- Prevents subsequent runs from inheriting half created compose resources.

### Current behavioral nuance with startup

setup_2 prints:

- Build process completed successfully
- Next step run make to start cluster

But implementation calls `make build`, and in this Makefile `build` runs compose up with build and detached flags. So services are effectively started during build.

If you want strict build without start behavior, Makefile build target semantics must change.

---

## Section 5 - Makefile Runtime Model

File:

- `docker-scale-out/Makefile`

### Key variables

- `HOST` default `login`
- `BUILD` default `up --build --remove-orphans -d`
- `DC` auto chooses:
  - `docker compose` if available
  - else `docker-compose`
- `SUBNET` default `10.11`
- `SUBNET6` default `2001:db8:1:1::`

### Compose command selection detail

Current detection line:

- `docker compose version >/dev/null 2>&1 && echo docker compose || echo docker-compose`

This avoids shell redirection issues seen in some docker compat wrappers.

### Generated compose file rule

Target:

- `./docker-compose.yml: buildout.sh`

Command:

- `bash buildout.sh > ./docker-compose.yml`

Implication:

- Many make commands regenerate compose when missing.
- Behavior can drift if environment vars changed between runs.

### Target deep dive

#### default target

- `default: ./docker-compose.yml run`
- Running plain `make` means compose generation plus run target.

#### build

- Depends on generated compose file.
- Runs `$(DC) --ansi=never --progress=plain $(BUILD)`.
- With default BUILD value this means up with build in detached mode.

#### run

- Runs `$(DC) up --remove-orphans -d`
- Start existing services and create missing containers from current compose.

#### stop

- Runs `$(DC) down`
- Stops and removes containers and network resources tracked by compose project.

#### clean

- If compose file exists:
  - kill
  - down remove orphans with short timeout and volumes
  - unlink generated compose file
- Removes cloud_socket file if present.

#### uninstall

- Down with `--rmi all --remove-orphans -t1 -v`
- Followed by `$(DC) rm -v`
- Intended for aggressive local cleanup.

#### nocache

- Temporarily sets BUILD to `build --no-cache` path then executes build target.

#### cloud

- Creates cloud_socket
- Regenerates compose with `CLOUD=1`
- Launches cloud monitor process
- Cleans cloud artifacts when monitor exits

#### bash

- `$(DC) exec $(HOST) /bin/bash`
- Default host is login container.
- Override with `make HOST=node01 bash` etc.

#### test-build

- Clean nodelist and prior state.
- Build images and stack.
- Exec `/usr/local/bin/test-build.sh` in target host.
- Cleans generated artifacts after test path.

---

## Section 6 - buildout.sh Compose Generation Internals

File:

- `docker-scale-out/buildout.sh`

### Core role

buildout.sh is not just a helper.

It is the primary source of truth for runtime topology because it generates full compose yaml dynamically from environment and repository state.

### Initial dynamic values

- `CACHE_DESTROYER` from concatenated `scaleout/patch.d/*.patch` hash.
- `SLURM_RELEASE` default `master`.
- `DISTRO` default `docker.io/library/almalinux:8`.
- `SUBNET` default `10.11`.
- `SUBNET6` default `2001:db8:1:1::`.
- `NODELIST` default `scaleout/nodelist`.

### Port exposure behavior

When subnet is default 10.11, script exposes host ports for services such as:

- Elasticsearch 9200
- Kibana 5601
- Proxy 8080
- Grafana 3000
- Open OnDemand 8081
- XDMoD 8082
- Keycloak 8083

When SUBNET is changed from default, many host port publishes are disabled to reduce collisions between multiple instances.

### Node list generation behavior

If nodelist is empty or benchmark mode is set:

- Single cluster mode generates node00 through node09 by default.
- Benchmark mode increases node count to 100.
- Federation mode generates per cluster node names like clustername-nodeNN.

### Hosts file generation

- Recreates `scaleout/hosts.nodes` from nodelist entries.
- Adds both ipv4 and ipv6 mappings when available.

### Host alias payload

buildout creates an `extra_hosts` block that maps service names to static IPs.

Important detail:

- Linux buildout uses same hostname label for ipv4 and ipv6 mapping lines.
- Windows buildout diverges and often uses separate ipv6 alias suffixes.

### cgroup mount strategy

Script checks cgroup v2 marker `/sys/fs/cgroup/cgroup.controllers`.

- If missing, emits one mount strategy.
- If present, emits cgroup v2 aware mount strategy including docker.slice path mount.

This is one of the most environment sensitive portions of runtime setup.

### Service blocks generated

Primary service families generated include:

- database service db from sql_server context
- core scaleout image consumer services
  - slurmdbd
  - mgmtnode and mgmtnode2 or federation variants
  - login
  - rest
  - compute nodes from nodelist
  - cloud service when CLOUD env is set
- ingress and support services
  - proxy
  - keycloak
  - open-ondemand
  - influxdb
  - grafana
  - xdmod optionally
- elastic stack components
  - es01 es02 es03
  - kibana

### Build versus image semantics in generated compose

Many custom services include both:

- `image` tag name
- `build` context

This allows compose build workflow to construct local tags while still referencing named images.

### Cache invalidation with CACHE_DESTROYER

`slurmdbd` build args include `CACHE_DESTROYER`.

Because CACHE_DESTROYER depends on patch files under `scaleout/patch.d`, modifying any patch changes the arg and invalidates downstream docker layer cache paths for that stage.

### Feature toggles

- `DISABLE_XDMOD` removes xdmod service block.
- `FEDERATION` creates multi cluster topology names and volumes.
- `CLOUD` adds cloud service plus cloud socket bind mounts.
- `SLURM_BENCHMARK` increases node count and changes build args.

---

## Section 7 - Image Build Pipeline Under the Hood

### Entry points into builds

Linux common paths:

- `make build`
- `make`
- `setup_2.sh` because it executes make build

Windows common paths:

- `setup_win.ps1` Start-Build function
- `make -f Makefile.win build`

### Build contexts and resulting local image tags

From current buildout output and contexts:

- `scaleout:latest` from `./scaleout`
- `sql_server:latest` from `./sql_server`
- `proxy:latest` from `./proxy`
- `keycloak:latest` from `./keycloak`
- `xdmod:latest` from `./xdmod`
- `open-ondemand` from `./open-ondemand`
- `influxdb` from `./influxdb`
- `grafana` from `./grafana`

Pulled upstream images include:

- docker.elastic.co elasticsearch oss 7.10.1
- docker.elastic.co kibana oss 7.10.1
- base images required by each Dockerfile

### Why pull access denied messages may appear before local build succeeds

In compose workflows with image plus build directives, compose may attempt to resolve image references before or alongside build operations depending on provider behavior.

In logs this can look like:

- pull access denied for local tag
- then later build phase begins

This is noisy but not always fatal.

Fatal build failure happens only when a required build step fails, such as patch apply errors in Dockerfile stages.

### Example of fatal build stage failure class

A known class is invalid patch format consumed by:

- `git apply valgrind.patch`

If patch lacks diff headers, build fails even if other images build successfully.

### Buildx and multi arch note

Current default local workflow is architecture native local build.

There is no built in cross platform buildx publish workflow in main Linux Makefile.

If maintainers want reproducible multi arch publishing, this should live in separate developer specific automation and not user setup scripts.

---

## Section 8 - Runtime Networking and Subnet Strategy

### Default network model

Generated compose creates internal bridge network with:

- ipv4 subnet `10.11.0.0/16`
- ipv6 subnet `2001:db8:1:1::/64`

Services get mostly static ip assignments under these ranges.

### Why subnet collisions occur

Common causes:

- Another compose project already owns same subnet.
- Previous failed run left network artifacts.
- Running with mixed privilege context created parallel engine namespaces.

### Mixed privilege context pitfall

If setup runs under sudo and later make runs without sudo in a docker compat podman environment, resources can appear inconsistent:

- One context has running containers
- Other context tries to create same network and fails

### Practical subnet override usage

You can override per command:

- `SUBNET=10.50 SUBNET6=2001:db8:50:1:: make`

You can also export variables in shell before make usage.

### Restart and cleanup for overlap errors

Typical recovery sequence:

1. `make clean`
2. `docker network prune -f`
3. restart docker daemon when needed
4. run with alternate SUBNET if host has persistent overlap

### Compose provider considerations with podman wrappers

When docker command is a podman wrapper, compose provider messages may indicate external provider fallback.

This is not automatically broken but can change behavior in:

- network lifecycle
- log formatting
- auth token acquisition logs

---

## Section 9 - Windows Flow and Divergences

Files:

- `docker-scale-out/setup_win.ps1`
- `docker-scale-out/Makefile.win`
- `docker-scale-out/buildout.ps1`

### Windows setup entry behavior

setup_win performs:

- admin elevation checks
- package display and installation path via winget and installers
- submodule update
- docker desktop startup and readiness checks
- build path invocation
- compose up to start cluster

### Non interactive auth stance on Windows

Current setup_win does not prompt for docker login.

Auth related pull failures raise explicit error guidance indicating user setup does not perform docker login and expects accessible public images.

### Notable function inventory in setup_win

- Keep-WindowOpen
- Test-Administrator
- Test-AdminAccess
- Test-CommandExists
- List-Packages
- Test-VisualStudioBuildTools
- Update-Submodules
- Install-RequiredPackages
- Test-DockerRunning
- Configure-Docker
- Ensure-DockerRunning
- Start-DockerDesktop
- Start-Build
- Invoke-Cleanup
- Connect-ToHost

### make alias behavior in setup_win

At end of script, setup_win sets:

- `Set-Alias -Name make -Value Connect-ToHost -Force`

This impacts current powershell session behavior.

Implication:

- Typing make afterward may invoke connect helper rather than gnu make command depending on shell context.

### Makefile.win model

- default all target is build then up
- build runs buildout.ps1 then docker compose build
- verify enforces required generated and source files
- up runs docker compose up -d and displays status
- down and clean targets manage lifecycle and generated files

### buildout.ps1 divergence from buildout.sh

Windows compose generator uses powershell logic and writes compose file directly.

Differences include:

- host alias naming often appends ipv6 suffix markers like db6
- parameterized powershell functions for nodelist and hosts generation
- no Linux style cloud monitor integration path

### Windows cloud mode gap

Linux has `make cloud` and cloud_monitor path using unix socket.

Windows flow currently has no equivalent cloud mode orchestration in makefile.win.

---

## Section 10 - Cloud Mode Deep Dive

Files:

- `docker-scale-out/Makefile`
- `docker-scale-out/buildout.sh`
- `docker-scale-out/cloud_monitor.py3`
- `docker-scale-out/scaleout/resume.node.sh`
- `docker-scale-out/scaleout/suspend.node.sh`

### make cloud sequence

1. remove stale `cloud_socket`
2. create `cloud_socket`
3. regenerate compose with `CLOUD=1`
4. run `python3 ./cloud_monitor.py3 "$(DC)"`
5. cleanup socket and compose on monitor exit

### buildout cloud specific behavior

When CLOUD set:

- defines CLOUD_MOUNTS bind mount from host cloud_socket to `/run/cloud_socket`
- emits cloud service using scaleout image
- includes CLOUD env for service

### cloud monitor behavior

cloud_monitor uses unix socket `cloud_socket` and tracks active cloud nodes.

It invokes compose scale operations such as:

- `up --scale cloud=N --no-recreate -d`

It also responds to messages like:

- start node
- stop node
- whoami queries

### slurm integration hints

suspend and resume scripts under scaleout call socat against `/run/cloud_socket` so control plane can modify cloud worker count based on scheduler activity.

---

## Section 11 - Operational Playbooks

### Playbook A first run Linux recommended path

1. Ensure repository is cloned.
2. Run:

```bash
chmod +x setup_1.sh setup_2.sh
./setup_1.sh
```

3. Reboot host.
4. Run:

```bash
./setup_2.sh
```

5. Validate whether services already started by make build in your current Makefile semantics.
6. If services are not up, run:

```bash
make
```

7. Check container status:

```bash
docker compose ps
```

### Playbook B daily start and stop

Start:

```bash
make
```

Stop:

```bash
make stop
```

Hard reset runtime artifacts:

```bash
make clean
```

### Playbook C open shell in default login node

```bash
make bash
```

Specific node:

```bash
make HOST=node01 bash
```

### Playbook D rebuild without cache

```bash
make nocache
```

### Playbook E remove all local project images and volumes

```bash
make uninstall
```

### Playbook F after reboot

1. Ensure docker service is up.
2. Run `make`.
3. If subnet conflict appears, run recovery steps in troubleshooting matrix.

### Playbook G custom subnet run

```bash
SUBNET=10.52 SUBNET6=2001:db8:52:1:: make
```

Use this when default subnet collides with existing networks.

### Playbook H cloud mode lifecycle

```bash
make clean
make cloud
```

Cloud mode runs foreground monitor process.

Stop with ctrl c and then cleanup.

---

## Section 12 - Failure Catalog and Troubleshooting Matrix

This section lists symptoms, likely causes, diagnostics, and remediations.

### Case 1 docker daemon not running in setup scripts

Symptom:

- setup_2 reports docker daemon is not running.

Likely cause:

- docker service disabled or failed to start.

Diagnostics:

- `docker info`
- `systemctl status docker`

Remediation:

- start docker service
- re run setup_2

### Case 2 missing make command

Symptom:

- setup_2 exits with make not installed.

Likely cause:

- setup_1 incomplete or failed package install.

Diagnostics:

- `which make`

Remediation:

- rerun setup_1 and inspect package manager logs.

### Case 3 subnet already used on host

Symptom:

- compose network create fails with subnet overlap.

Likely cause:

- existing network occupying 10.11.0.0 slash 16.

Diagnostics:

- `docker network ls`
- `docker network inspect <network>`

Remediation:

- `make clean`
- `docker network prune -f`
- use alternate `SUBNET` and `SUBNET6`

### Case 4 pull access denied for local image names

Symptom:

- compose logs show pull access denied for `scaleout:latest` and similar names.

Likely cause:

- compose attempts pull before local build resolution.

Diagnostics:

- inspect full build logs for whether build phase starts after pull warnings.

Remediation:

- if build continues, treat as warning noise.
- if build aborts, inspect first true dockerfile failure below pull lines.

### Case 5 patch apply failure during scaleout image build

Symptom:

- `git apply` fails in Dockerfile stage.

Likely cause:

- malformed patch file format.

Diagnostics:

- inspect patch file under `scaleout`.
- run local apply check in matching source tree when possible.

Remediation:

- convert patch to valid unified diff with file headers.

### Case 6 docker compose provider mismatch in compat environments

Symptom:

- banner indicating external compose provider.
- inconsistent behavior across runs.

Likely cause:

- docker command wraps podman and delegates compose externally.

Diagnostics:

- `which docker`
- `docker --version`
- `docker compose version`
- `which docker-compose`

Remediation:

- keep privilege context consistent.
- avoid mixing sudo and non sudo compose lifecycle for same project.

### Case 7 setup_2 succeeds but user does not see containers in current context

Symptom:

- setup logs indicate containers running.
- current shell shows none.

Likely cause:

- setup run under sudo or different engine context than current shell.

Diagnostics:

- check `docker ps` in same privilege context used by setup.

Remediation:

- standardize lifecycle commands to one context.

### Case 8 cloud mode not scaling as expected

Symptom:

- cloud nodes do not scale with scheduler events.

Likely cause:

- cloud_socket mount missing or monitor not running.

Diagnostics:

- verify `cloud_socket` exists on host.
- verify monitor process active.
- inspect resume and suspend script connectivity.

Remediation:

- rerun `make cloud`.
- confirm CLOUD generated compose includes socket bind mounts.

### Case 9 windows build passes verify but runtime commands confusing

Symptom:

- powershell make command not behaving as expected.

Likely cause:

- setup_win alias overrides make command in active session.

Diagnostics:

- check powershell alias list for make.

Remediation:

- use explicit `make.exe` or remove alias in current session.

### Case 10 cgroups hard limit reached

Symptom:

- slurm errors mention no space left on device for cgroup creation.

Likely cause:

- kernel total cgroup limit exhausted.

Diagnostics:

- inspect host cgroup usage and active jobs.

Remediation:

- reduce active job scale or number of simultaneous stack instances.

---

## Section 13 - Maintainer Notes and Validation Strategy

### Primary control points for behavior changes

- Host provisioning and daemon tuning
  - `setup_1.sh`
- Build stage and post build messaging
  - `setup_2.sh`
- Runtime lifecycle semantics
  - `Makefile`
- Topology and compose generation
  - `buildout.sh`
- Windows equivalents
  - `setup_win.ps1`
  - `Makefile.win`
  - `buildout.ps1`

### Side effects to consider before changing defaults

If you change Makefile build semantics:

- setup_2 behavior changes immediately because it calls `make build`.
- quick start instructions must be updated at same time.
- failure handling and verification assumptions may need adjustment.

If you change subnet defaults:

- documentation and ssh examples may need updates.
- saved environment overrides may conflict with previous runs.

If you change compose provider detection:

- verify behavior in docker native and podman compat shells.

### Recommended maintainer validation checklist

After any workflow change, validate these in order.

1. `bash -n setup_1.sh`
2. `bash -n setup_2.sh`
3. Run setup_2 on a clean host context.
4. Confirm no interactive docker login prompt appears.
5. Confirm make targets still align with README instructions.
6. Run `make stop`, `make clean`, `make` cycle.
7. Validate cloud mode with `make cloud` if touched.
8. Validate Windows paths if setup_win, buildout.ps1, or Makefile.win changed.

### Documentation synchronization checklist

When behavior changes, update all of these:

- `README.md` user facing quick start
- this deep dive file
- setup script terminal success messages
- any troubleshooting callouts tied to changed behavior

---

## Appendix A - Key Commands Reference

### Linux

```bash
./setup_1.sh
# reboot
./setup_2.sh
make
make stop
make clean
make uninstall
make bash
make HOST=node01 bash
make nocache
make cloud
```

### Windows

```powershell
.\setup_win.ps1
make -f Makefile.win build
make -f Makefile.win up
make -f Makefile.win down
make -f Makefile.win clean
```

---

## Appendix B - Environment Variables That Matter Most

### Runtime and topology

- `SUBNET`
- `SUBNET6`
- `NODELIST`
- `FEDERATION`
- `DISABLE_XDMOD`
- `CLOUD`

### Build behavior

- `SLURM_RELEASE`
- `SLURM_BENCHMARK`
- `BUILD` in Makefile context

### Operational implications

- Changing these values changes generated compose content.
- Regenerate compose by rerunning make targets that depend on buildout.

---

## Appendix C - Known Ambiguities and Current Truth

This section records current behavior that can surprise readers.

1. setup_2 says run make next, but it calls make build and current build target starts services.
2. compose may emit pull denied messages even when local build proceeds successfully.
3. podman docker compatibility wrappers can split context between user and sudo execution paths.
4. windows setup sets make alias in current powershell session.

Documenting these explicitly prevents operator confusion and reduces repeated troubleshooting loops.

