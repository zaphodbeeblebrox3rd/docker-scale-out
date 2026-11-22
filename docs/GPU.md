# GPUs

Every compute node advertises GPUs to Slurm so you can practice GPU scheduling. If the host has an NVIDIA GPU that Docker can use, the cluster also gets a `gpu01` node with the real GPU.

## Fake GPUs on every node

Each node, `node00` to `node09`, has 3 fake GPUs of type `gtx`. They are configured in [`gres.conf`](../scaleout/slurm/gres.conf) and map to dummy devices such as `/dev/zero`. Slurm schedules and accounts for them like real GPUs, but there is no hardware behind them, so `nvidia-smi` and CUDA programs do not work on these nodes.

```bash
srun --gres=gpu:gtx:2 hostname
```

## The real GPU on gpu01

`buildout.sh` adds `gpu01` when all of these are true:

- `nvidia-smi` runs on the host.
- Docker has the `nvidia` runtime (`docker info` lists it).
- `DISABLE_GPU` and `FEDERATION` are not set.

`gpu01` is a normal compute node in the `debug` partition. Its GPUs are named after the card, for example `gpu:rtx_2070_super:1`, and it has no fake GPUs.

```bash
sinfo -N -o "%N %G"
srun -w gpu01 --gres=gpu:1 nvidia-smi
```

Requirements by host:

| Host | Requirement |
|---|---|
| Windows | Docker Desktop with the WSL2 backend and a current NVIDIA driver. Docker Desktop passes all GPUs through one device, `/dev/dxg`, so Slurm counts one GPU. |
| Linux | The NVIDIA driver and the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html), registered with `sudo nvidia-ctk runtime configure --runtime=docker` and a Docker restart. Each GPU is a separate `/dev/nvidiaN` device. |
| macOS | No NVIDIA GPUs, so there is no `gpu01`. |

This is for demos, not real isolation. Slurm does not restrict device access (`ConstrainDevices=no`), so any job on `gpu01` can use the GPU, even without `--gres=gpu`.

## Hosts without a GPU

If the host has no NVIDIA GPU, or Docker can't use it, the cluster is built without `gpu01`. Everything else is the same, including the fake GPUs on `node00` to `node09`. Nothing fails, and no NVIDIA software is needed.

## Changing the setup

The GPU check runs every time `buildout.sh` generates `docker-compose.yml`. The GPU configuration is copied into the Slurm image and the `/etc/slurm` volume, so after adding or removing a GPU, or setting `DISABLE_GPU=1`, rebuild with:

```bash
make clean
make build
```
