# Minecraft

Dedicated Docker host for the Better MC (BMC4) Minecraft server.

## Services

| Service                                                       | Description                                                                                                          |
| ------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| [Minecraft](https://docker-minecraft-server.readthedocs.io/)  | Better MC (BMC4) Forge modded server (CurseForge `AUTO_CURSEFORGE`) — `docker/minecraft/server/`                      |
| [mc-router](https://github.com/itzg/mc-router)                | Routes Minecraft client connections to backend servers by hostname — in `docker/minecraft/server/`                     |
| [Newt](https://fossorial.io/)                                 | Pangolin tunnel client for external access — `docker/minecraft/newt/`                                                |
| [Doco-CD](https://github.com/kimdre/doco-cd)                  | Continuous delivery for Docker Compose stacks                                                                        |

## Networking

Two isolated networks so nothing can bypass the router:

```
Pangolin/Newt (edge) → mc-router (edge + backend) → minecraft (backend)
```

- `edge` — newt + mc-router; `backend` — mc-router + minecraft (created by the `server` stack, external for others)
- Newt cannot reach the game server directly — only mc-router, by design
- `mc-router` mapping: `minecraft` hostname → `minecraft:25565` (add one `MAPPING` line per future server) and `depends_on` the server
- Only `mc-router` publishes 25565; the server itself is never exposed directly

## Setup

1. Provision the host, install Docker, and clone this repo to the same path as this repository
2. `mkdir -p /opt/docker/minecraft/data` — server data bind mount
3. Fill in `docker/minecraft/server/.env` (`CF_API_KEY`, `WHITELIST`, `MEM_LIMIT`) and `docker/minecraft/newt/newt.env` (`PANGOLIN_ENDPOINT`, `NEWT_ID`, `NEWT_SECRET`), then sops-encrypt both
4. Start the `doco-cd` stack (`docker/minecraft/doco-cd/compose.yaml`) — it polls this repo and deploys the stacks declared in `.doco-cd.yaml`
5. In Pangolin, create a Newt client and a resource with target `mc-router:25565` on the `minecraft-mc-router` container (protocol TCP), then paste the client ID/secret into `newt.env`
6. `mkdir -p /opt/docker/doco-cd` and place the age key for sops decryption there (same as other nodes)