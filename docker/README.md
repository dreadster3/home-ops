# Docker

Docker Compose services managed through GitOps powered by [Doco-CD](https://github.com/kimdre/doco-cd). All service definitions live in this repo — Doco-CD watches for changes and automatically applies them.

## Services

Enabled stacks are listed in each node's `.doco-cd.yaml` poll config; any directory not referenced there is currently disabled.

### Management node (`docker/mgmt/`)

| Service                                                   | Description                                                                                 |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| [Traefik](https://traefik.io/)                            | Reverse proxy and TLS termination for all Docker services                                   |
| [Infisical](https://infisical.com/)                       | Secrets management — source of truth for all runtime secrets (backed by PostgreSQL + Redis) |
| [Home Assistant](https://www.home-assistant.io/)          | Home automation platform                                                                    |
| [Omada Controller](https://www.tp-link.com/en/omada-sdn/) | TP-Link Omada SDN network controller (backed by MongoDB)                                    |
| [Duplicati](https://www.duplicati.com/)                   | Encrypted backup solution                                                                   |
| [Doco-CD](https://github.com/kimdre/doco-cd)              | Continuous delivery for Docker Compose stacks                                               |
| [Databasus](https://databasus.com/)                       | Database management UI                                                                      |
| [IT Tools](https://it-tools.tech/)                        | Collection of handy IT utilities                                                            |
| [Stirling PDF](https://stirlingtools.com/)                | Self-hosted PDF manipulation tools                                                          |
| [Peanut](https://github.com/brandawg93/peanut)            | UPS monitoring and management                                                               |
| [Speedtest Tracker](https://docs.speedtest-tracker.dev/)  | Continuous internet speed monitoring (backed by PostgreSQL)                                 |
| [Arcane](https://getarcane.app/)                          | Docker management UI with OIDC SSO (backed by PostgreSQL)                                   |

### VPN node (`docker/vpn/`)

| Service                                       | Description                                                                              |
| --------------------------------------------- | ---------------------------------------------------------------------------------------- |
| [Traefik](https://traefik.io/)                | Reverse proxy and TLS termination for VPN-hosted services (e.g. wg-easy UI)              |
| [wg-easy](https://github.com/wg-easy/wg-easy) | WireGuard VPN management UI with noNAT setup (backed by Litestream DB replication to S3) |
| [Netbird](https://netbird.io/)                | WireGuard-based overlay VPN client for remote access                                     |
| [Doco-CD](https://github.com/kimdre/doco-cd)  | Continuous delivery for Docker Compose stacks                                            |

## Directory Structure

```
docker/
├── mgmt/               # Management node services
│   ├── traefik/
│   ├── infisical/
│   ├── home-assistant/
│   ├── omada-controller/
│   ├── duplicati/
│   ├── appraise/        # disabled
│   ├── dockhand/        # disabled
│   ├── doco-cd/
│   ├── databasus/
│   ├── it-tools/
│   ├── stirling-pdf/
│   ├── peanut/
│   ├── speedtracker/
│   ├── arcane/
│   └── cadvisor/        # disabled
└── vpn/                # VPN node services
    ├── traefik/
    ├── wireguard/      # wg-easy + litestream
    ├── netbird/
    └── doco-cd/
```
