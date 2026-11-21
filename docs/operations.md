# Operating the cluster

[Back to README](../README.md)

All commands run from the repository root. On Windows, see [Windows commands](building.md#windows).

| Task | Command |
|---|---|
| Start the cluster | `make` |
| Stop the cluster | `make stop` |
| Shell on the login node | `make bash` |
| Shell on another container | `make HOST=mgmtnode bash` |
| Reverse all runtime changes (containers, volumes, local images, submodule state) | `make clean` |
| Remove all images | `make uninstall` |
| Save all images to `./scaleout.tar` | `make save` |
| Load images from `./scaleout.tar` | `make load` |

## Change the default shell host

```bash
export SCALEOUT_DEFAULT_HOST=mgmtnode
make bash
```

## After a host reboot

Make sure Docker is running, then run `make`. If the network fails to create, see [Troubleshooting](troubleshooting.md#network-pool-overlap-or-max-depth-exceeded).

## Trigger an XDMoD data ingest

XDMoD ingests Slurm job data hourly. To run it immediately:

```bash
make HOST=mgmtnode bash
bash /etc/cron.hourly/dump_xdmod.sh
exit

make HOST=xdmod bash
sudo -u xdmod -- /usr/bin/xdmod-shredder -r scaleout -f slurm -i /xdmod/data.csv
sudo -u xdmod -- /usr/bin/xdmod-ingestor
exit
```
