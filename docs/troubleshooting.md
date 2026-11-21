# Troubleshooting

[Back to README](../README.md)

For a longer failure catalog, see the [developer workflow](developer-build-workflow.md#section-12---failure-catalog-and-troubleshooting-matrix).

## Network pool overlap or max depth exceeded

```
ERROR: Pool overlaps with other one on this address space
```

```
failed to prepare ${HASH}: max depth exceeded
ERROR: Service 'slurmdbd' failed to build : Build failed
```

Fix:

```bash
make clean
docker network prune -f
sudo systemctl restart docker
```

If another network permanently uses `10.11.0.0/16`, run on a [different subnet](customization.md#subnets-and-multiple-instances).

## `unauthorized` or `authentication required` on image pulls

Setup never runs `docker login`; it expects public registry access. Treat this as a registry or network problem on the host, such as Docker Hub rate limits or a proxy.

## `pull access denied` for local images such as `scaleout:latest`

Compose may try to pull locally built images before building them. If the build continues afterwards, ignore it. If the build fails, look for the first real Dockerfile error after these lines.

## Containers missing after setup

If `setup_2.sh` reports running containers but `docker ps` shows none, you are probably in a different privilege context (for example, setup ran with `sudo` on a podman-backed `docker`). Run all lifecycle commands the same way.

## `proctrack_g_create: No space left on device`

The kernel allows 65535 cgroups in total. Large numbers of jobs or several cluster instances can exhaust them. Run fewer jobs or instances.
