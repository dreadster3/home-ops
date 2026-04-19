# Kubernetes

GitOps-managed Kubernetes cluster using [Flux](https://fluxcd.io/).

## Nodes (VMs)

- **3 control-plane nodes** — one per physical host
- **3 worker nodes** — spread across node2 and node3

> **Note:** Ceph runs natively on Proxmox and is consumed by the Kubernetes cluster as an **external** Ceph cluster via Rook. Ceph MGR endpoints: `192.168.30.5`, `192.168.30.6`, `192.168.30.10`.

**Network:**

- LoadBalancer IP pool: `192.168.30.240/28`
- DNS server: `192.168.30.2` (RFC2136 / internal zone)

## Cluster Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster                  │
│                                                         │
│  ┌──────────┐   ┌──────────┐   ┌──────────────────────┐ │
│  │  Cilium  │   │  Envoy   │   │   Flux (GitOps)      │ │
│  │  (CNI +  │   │ Gateway  │   │  source: GitHub      │ │
│  │  L2 LB)  │   │  (HTTPS) │   │  branch: main        │ │
│  └──────────┘   └──────────┘   └──────────────────────┘ │
│                                                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │                    Storage                       │   │
│  │  Rook/Ceph (block + filesystem)  NFS  LocalPath  │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

## Infrastructure

### Networking

| Component | Description |
|-----------|-------------|
| [Cilium](https://cilium.io/) | CNI, kube-proxy replacement, WireGuard node encryption, L2 announcements for LoadBalancer IPs, Hubble observability |
| [Envoy Gateway](https://gateway.envoyproxy.io/) | Kubernetes Gateway API implementation — terminates TLS and routes HTTPS traffic to all internal services |
| [External DNS](https://github.com/kubernetes-sigs/external-dns) | Syncs DNS records to internal RFC2136 DNS server for all HTTPRoute hostnames |
| [Netbird](https://netbird.io/) | WireGuard-based overlay VPN for remote access |
| [Maddy](https://maddy.email/) | Self-hosted SMTP relay — forwards outgoing mail from all apps to Gmail |

### Security

| Component | Description |
|-----------|-------------|
| [cert-manager](https://cert-manager.io/) | TLS certificate management via Let's Encrypt (DNS-01 / Cloudflare) and internal CA |
| [External Secrets](https://external-secrets.io/) | Syncs secrets from [Infisical](https://infisical.com/) into Kubernetes |

### Storage

| Component | Description |
|-----------|-------------|
| [Rook/Ceph](https://rook.io/) | Connects to the **external** Proxmox-managed Ceph cluster; provides `ceph-block` and `ceph-filesystem` StorageClasses |
| [NFS Subdir Provisioner](https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner) | NFS-backed persistent volumes |
| Local Path | Node-local storage for latency-sensitive workloads (e.g. Vault Raft) |

### Databases

| Component | Description |
|-----------|-------------|
| [CloudNativePG](https://cloudnative-pg.io/) | PostgreSQL operator — each app gets its own managed cluster |
| [DragonflyDB](https://dragonflydb.io/) | High-performance Redis-compatible cache (used by Immich, OpenWebUI, Harbor, Netbox, Paperless, Searxng) |
| [Redis Operator](https://github.com/OT-CONTAINER-KIT/redis-operator) | Redis sentinel/replication clusters |

### Observability

| Component | Description |
|-----------|-------------|
| [Prometheus](https://prometheus.io/) | Metrics collection and alerting |
| [Grafana](https://grafana.com/) | Dashboards for cluster and application metrics |
| [Loki](https://grafana.com/oss/loki/) | Log aggregation |
| [Thanos](https://thanos.io/) | Long-term Prometheus metrics storage |
| [Grafana Alloy](https://grafana.com/oss/alloy/) | Metrics and log collector/forwarder |
| [Metrics Server](https://github.com/kubernetes-sigs/metrics-server) | Resource usage metrics for HPA and `kubectl top` |
| [KRR](https://github.com/robusta-dev/krr) | Kubernetes resource recommendations |

### Platform

| Component | Description |
|-----------|-------------|
| [Flux](https://fluxcd.io/) | GitOps continuous delivery — watches this repo and reconciles cluster state |
| [Reloader](https://github.com/stakater/Reloader) | Automatically rolls deployments when ConfigMaps or Secrets change |

## Applications

All apps are exposed internally via Envoy Gateway (HTTPS, TLS terminated) with individual per-app PostgreSQL clusters and Cilium network policies.

| App | Description |
|-----|-------------|
| [Authentik](https://goauthentik.io/) | Identity provider and SSO — used for login across all apps |
| [Vaultwarden](https://github.com/dani-garcia/vaultwarden) | Self-hosted Bitwarden-compatible password manager |
| [Vault](https://www.vaultproject.io/) | HashiCorp Vault — secrets management (HA Raft, mTLS) |
| [Immich](https://immich.app/) | Self-hosted photo and video backup |
| [Paperless-NGX](https://docs.paperless-ngx.com/) | Document management and OCR |
| [Joplin](https://joplinapp.org/) | Note-taking app with end-to-end encryption sync server |
| [Open WebUI](https://openwebui.com/) | Web interface for LLMs (Ollama) with SSO |
| [n8n](https://n8n.io/) | Workflow automation and integration platform |
| [Searxng](https://docs.searxng.org/) | Privacy-respecting meta search engine |
| [Harbor](https://goharbor.io/) | Self-hosted container registry with vulnerability scanning |
| [Netbox](https://netbox.dev/) | Network IPAM and infrastructure documentation |
| [Termix](https://github.com/lukegus/termix) | Web-based bookmark and quick-launch dashboard |
| [Uptime Kuma](https://uptime.kuma.pet/) | Self-hosted uptime and service monitoring |
| [Pangolin](https://fossorial.io/) | Self-hosted tunneling / reverse proxy (Newt client) |

## Directory Structure

```
kubernetes/
├── apps/
│   ├── base/           # App definitions (HelmRelease, HTTPRoute, NetworkPolicy, etc.)
│   └── overlays/
│       ├── dev/        # Dev-specific patches
│       └── prd/        # Production-specific patches
├── clusters/
│   ├── dev/            # Dev cluster entrypoints (infrastructure.yaml, apps.yaml)
│   └── production/     # Production cluster entrypoints
├── components/
│   └── substitute/     # Shared settings/secrets ConfigMap+Secret for Flux variable substitution
└── infrastructure/
    ├── base/           # Infrastructure definitions
    └── overlays/
        ├── dev/        # Dev-specific patches (local CA, dev issuers, etc.)
        └── prd/        # Production secrets (SOPS-encrypted)
```

## Secrets Management

Secrets follow a layered approach:
- **Runtime secrets** (API tokens, passwords) are stored in [Infisical](https://infisical.com/) and synced into the cluster via [External Secrets Operator](https://external-secrets.io/)
- **Bootstrap secrets** (domain names, cluster settings) are SOPS-encrypted with [age](https://age-encryption.org/) and stored directly in this repo
- **TLS certificates** are issued by cert-manager via Let's Encrypt (DNS-01 challenge through Cloudflare)
