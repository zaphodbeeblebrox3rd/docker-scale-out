# Architecture and services

[Back to README](../README.md)

## Nodes

| Role | Containers |
|---|---|
| MariaDB | `db` |
| Slurm management | `mgmtnode`, `mgmtnode2`, `slurmdbd` |
| Compute | `node[00-09]` (see [custom nodes](customization.md#custom-node-list)) |
| Login | `login` |
| Slurm REST API | `rest` |
| Nginx proxy | `proxy` |

## Web services and endpoints

| Service | URL | Login | Notes |
|---|---|---|---|
| Open OnDemand | http://localhost:8081/ | `fred` or `wilma` / `password` | |
| Open XDMoD | http://localhost:8082/ | | See [XDMoD data ingest](operations.md#trigger-an-xdmod-data-ingest) |
| Grafana | http://localhost:3000/ | `admin` / `admin` | |
| OpenSearch | http://localhost:9200/ | | Slurm `jobcomp/elasticsearch` target |
| OpenSearch Dashboards | http://127.0.0.1:5601/ | | IPv4 only |
| Keycloak admin console | http://127.0.0.1:8083/ | `admin` / `password` | |
| Auth REST API | http://localhost:8080/auth | | Through the proxy |
| Slurm REST API | http://localhost:8080/slurm/ | | Through the proxy |

## Network

The cluster uses a private bridge network: IPv4 `10.11.0.0/16` and IPv6 `2001:db8:1:1::/64` by default. Service nodes always use `${SUBNET}.1.0/24` and `${SUBNET6}1:0/122`. To change the subnets, see [Customization](customization.md#subnets-and-multiple-instances).

## Caveat

All nodes share the host's CPUs, so each host thread is counted once per node. Do not run computationally intensive work.
