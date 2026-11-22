# Building images

[Back to README](../README.md)

`setup_2.sh` (Linux) and `setup_win.ps1` (Windows) build everything for you. Use these commands when you rebuild by hand.

## Sources

Third-party sources (Slurm, PMIx, munge, and others) are pinned git submodules under `scaleout/src/`. Clone with:

```bash
git clone --recurse-submodules --shallow-submodules https://github.com/zaphodbeeblebrox3rd/docker-scale-out.git
```

For an existing clone:

```bash
git submodule update --init --recursive --checkout --recommend-shallow --single-branch
```

To force-clean the submodules:

```bash
git submodule deinit -f .
```

## Linux

| Task | Command |
|---|---|
| Build images and start the cluster | `make build` |
| Rebuild without the Docker cache | `make nocache` |
| Build from the latest submodule sources and run the test suite | `git submodule update --init --force --remote --recursive && make test-build` |

To build a different Slurm release, see [Customization](customization.md#slurm-version).

## Windows

`setup_win.ps1` installs Git for Windows and GNU make, then runs the same Makefile as Linux in Git Bash. To rebuild by hand, use the commands above from PowerShell or Git Bash, for example `make build`. When make runs outside Git Bash, the Makefile runs its commands in Git Bash itself.

`buildout.ps1` and `Makefile.win` are an older Windows-only build that does not build the Slurm image. `setup_win.ps1` no longer uses them.
