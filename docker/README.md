# Docker

Docker Compose services running on the management node, managed through GitOps powered by [Doco-CD](https://github.com/kimdre/doco-cd). All service definitions live in this repo — Doco-CD watches for changes and automatically applies them.

## Services

| Service                                                   | Description                                                                                 |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| [Traefik](https://traefik.io/)                            | Reverse proxy and TLS termination for all Docker services                                   |
| [Infisical](https://infisical.com/)                       | Secrets management — source of truth for all runtime secrets (backed by PostgreSQL + Redis) |
| [Home Assistant](https://www.home-assistant.io/)          | Home automation platform                                                                    |
| [Omada Controller](https://www.tp-link.com/en/omada-sdn/) | TP-Link Omada SDN network controller (backed by MongoDB)                                    |
| [Duplicati](https://www.duplicati.com/)                   | Encrypted backup solution                                                                   |
| [Apprise](https://github.com/caronc/apprise)              | Notification service supporting multiple providers                                          |
| [Dockhand](https://github.com/fnsys/dockhand)             | Automated container image update management                                                 |
| [Doco-CD](https://github.com/kimdre/doco-cd)              | Continuous delivery for Docker Compose stacks                                               |
| [Databasus](https://databasus.com/)                       | Database management UI                                                                      |
| [IT Tools](https://it-tools.tech/)                        | Collection of handy IT utilities                                                            |
| [Stirling PDF](https://stirlingtools.com/)                | Self-hosted PDF manipulation tools                                                          |
| [Peanut](https://github.com/brandawg93/peanut)            | UPS monitoring and management                                                               |
| [Speedtest Tracker](https://docs.speedtest-tracker.dev/)  | Continuous internet speed monitoring (backed by PostgreSQL)                                 |

## Directory Structure

```
docker/
└── mgmt/               # Management node services
    ├── traefik/
    ├── infisical/
    ├── home-assistant/
    ├── omada-controller/
    ├── duplicati/
    ├── appraise/
    ├── dockhand/
    ├── doco-cd/
    ├── databasus/
    ├── it-tools/
    ├── stirling-pdf/
    ├── peanut/
    └── speedtracker/
```
