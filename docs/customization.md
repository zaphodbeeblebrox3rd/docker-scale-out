# Customization

[Back to README](../README.md)

Most options are environment variables read when `docker-compose.yml` is generated. After changing one, run `make clean` and then `make build` (or `make`) so the compose file and images are regenerated.

## Custom node list

Set `NODELIST` to a file with one node per line, or edit the generated `scaleout/nodelist`:

```
${HOSTNAME} ${CLUSTERNAME} ${IPv4} ${IPv6}
```

Example:

```
node00 scaleout 10.11.5.0 2001:db8:1:1::5:0
```

Service nodes cannot be moved; they always use `${SUBNET}.1.0/24` and `${SUBNET6}1:0/122`.

## Subnets and multiple instances

Each cluster on the same host needs its own class B subnet. Defaults are `SUBNET=10.11` and `SUBNET6=2001:db8:1:1::`.

```bash
SUBNET=10.52 SUBNET6=2001:db8:52:1:: make
```

## Slurm version

```bash
export SLURM_RELEASE=slurm-<version>
make clean   # invalidates caches built for the previous release
make build
```

## Feature toggles

Set any of these before building to skip a component:

| Variable | Effect |
|---|---|
| `DISABLE_KEYCLOAK=1` | Do not build or start Keycloak; also skips populating `/etc/slurm/jwks.json` |
| `DISABLE_XDMOD=1` | Do not build or start the XDMoD container |
| `DISABLE_PYXIS=1` | Do not build enroot and pyxis from source |
| `DISABLE_GNU_PARALLEL=1` | Do not build GNU parallel from source (workaround when its mirror is down) |
| `DISABLE_DEVELOPER=1` | Build Slurm and other sources in release mode instead of developer/debug mode |
| `DISABLE_GPU=1` | Do not add the `gpu01` node even when the host has an NVIDIA GPU; see [GPUs](GPU.md) |
| `DISABLE_CLOUD_NODES=1` | Leave the `cloud` nodes and partition out of `slurm.conf`; always set on Windows |

## Federation mode

Federation creates several Slurm clusters, each with its own nodes and slurmctld. The login node and slurmdbd are shared.

Create the clusters:

```bash
export FEDERATION="taco burrito quesadilla"
echo "FederationParameters=fed_display" >> scaleout/slurm/slurm.conf
truncate -s0 scaleout/nodelist
make clean
make build
make
```

Register the federation in slurmdbd:

```bash
make HOST=taco-mgmtnode bash
sacctmgr add federation scaleout clusters=taco,burrito,quesadilla
```

Remove the federation clusters:

```bash
export FEDERATION="taco burrito quesadilla"
make uninstall
truncate -s0 scaleout/nodelist
```

## Cloud mode

Cloud mode starts a monitor that scales `cloud` nodes up and down as Slurm resumes and suspends them. Linux only: Windows builds leave the `cloud` nodes out of `slurm.conf`.

```bash
make clean
make cloud   # runs in the foreground; stop with Ctrl-C
```

See the [developer workflow](developer-build-workflow.md#section-10---cloud-mode-deep-dive) for how it works.
