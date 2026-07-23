# Architecture Decision Log

Decisions made throughout the life of this project, with rationale and context.

---

## 1. Use Talos Linux as the node OS

- **Date:** 2026-02-22
- **Status:** Accepted
- **Context:** Initial project setup and cluster bootstrap.
- **Decision:** Deploy Talos Linux on all 6 nodes (3 control-plane, 3 workers) rather than Ubuntu/CentOS.
- **Rationale:** Talos is purpose-built for Kubernetes — immutable, minimal attack surface, declarative config management via TalosMachineImages, and tight integration with the Kubernetes API.

## 2. Run Ceph natively on Proxmox, consumed externally by Kubernetes

- **Date:** 2026-02-22
- **Status:** Accepted
- **Context:** Storage layer design.
- **Decision:** Ceph runs natively on Proxmox (MGR endpoints at `192.168.30.5`, `192.168.30.6`, `192.168.30.10`). Kubernetes consumes it via Rook as an **external** Ceph cluster.
- **Rationale:** Avoids the complexity of running Ceph inside Kubernetes on top of Proxmox-managed Ceph, which would result in ~9x storage usage (Ceph-in-Ceph). Keeps storage management in one place (Proxmox) while still providing dynamic PV provisioning via Rook's `ceph-block` and `ceph-filesystem` StorageClasses.

## 3. Use Flux for GitOps

- **Date:** 2026-02-22
- **Status:** Accepted
- **Context:** Continuous delivery mechanism.
- **Decision:** Use Flux (not ArgoCD) as the GitOps controller, watching the `main` branch of this repository.
- **Rationale:** Flux integrates well with Kustomize, has native OCI repository support, and its event-driven reconciliation model fits the home lab use case well.

## 4. Use per-service PostgreSQL clusters via CloudNativePG

- **Date:** 2026-02-22
- **Status:** Accepted
- **Context:** Database architecture.
- **Decision:** Each application gets its own CloudNativePG `PGCluster` rather than sharing a multi-tenant database.
- **Rationale:** Isolation (crash recovery, backups, scaling are independent per app), simpler operations (no cross-app dependency concerns), and aligns with CloudNativePG's design philosophy.

## 5. Use SOPS + age for bootstrap secrets

- **Date:** 2026-02-22
- **Status:** Accepted
- **Context:** Encryption for sensitive bootstrap data.
- **Decision:** Use Mozilla SOPS with age encryption keys for all bootstrap secrets (domain names, cluster settings, TLS CA certs).
- **Rationale:** Age is simpler and more modern than PGP. SOPS integrates well with Flux's Kustomize workflow, allowing encrypted files to be committed to the repo and decrypted at runtime.

## 6. Use Prometheus + Grafana + Loki + Thanos for observability

- **Date:** 2026-02-22
- **Status:** Accepted
- **Context:** Monitoring and observability stack.
- **Decision:** Deploy Prometheus (metrics), Grafana (dashboards), Loki (logs), and Thanos (long-term storage) as the core observability stack, with Grafana Alloy as the collector.
- **Rationale:** Industry-standard open-source stack. Thanos provides long-term metrics retention with S3-compatible storage (Ceph ObjectStore). Alloy replaces older exporters with a unified metrics + log collector.

## 7. Use Renovate for dependency automation

- **Date:** 2026-02-23
- **Status:** Completed (PR #2)
- **Context:** Dependency update automation.
- **Decision:** Use Renovate (not Dependabot) for automated dependency updates across Docker images, Helm charts, and GitHub Actions.
- **Rationale:** Renovate offers more granular control over update grouping, versioning schemes, and schedule. Grouped updates (e.g., rook + ceph) reduce PR noise.

## 8. Dev cluster for pre-production validation

- **Date:** 2026-02-22
- **Status:** Completed
- **Context:** Environment strategy.
- **Decision:** Maintain a `dev` cluster alongside `production` for validating changes before merging to main.
- **Rationale:** Home infrastructure has no SLA but still needs reliability. The dev cluster catches configuration errors, Helm chart incompatibilities, and network policy issues before they affect production services.

## 9. Deploy Netbird for remote access

- **Date:** 2026-02-26
- **Status:** Completed (PR #39)
- **Context:** Remote access to internal services.
- **Decision:** Deploy Netbird as a WireGuard-based overlay VPN for remote access.
- **Rationale:** Provides mesh networking, NAT traversal, and per-app access control without exposing services to the public internet.

## 10. Move management node services from Terraform to Doco-CD

- **Date:** 2026-03-08
- **Status:** Completed (PR #62)
- **Context:** Non-Kubernetes services running on the Proxmox management node.
- **Decision:** Move management node services from Terraform to Doco-CD (Docker Compose continuous delivery).
- **Rationale:** Doco-CD provides GitOps-style automated deployment for Docker Compose stacks, matching the GitOps philosophy used for Kubernetes workloads. Eliminates the need for separate Terraform state management for simple container deployments.

## 11. Deploy External DNS with RFC2136 for internal DNS

- **Date:** 2026-04-07
- **Status:** Completed
- **Context:** DNS management.
- **Decision:** Use External DNS to sync DNS records to an internal RFC2136 DNS server for all HTTPRoute hostnames.
- **Rationale:** Automates DNS record creation/deletion based on Gateway API routes. Eliminates manual DNS management for internal services.

## 12. Deploy Rook/Ceph on the dev cluster

- **Date:** 2026-04-05
- **Status:** Completed
- **Context:** Dev cluster infrastructure.
- **Decision:** Deploy Rook/Ceph operator on the dev cluster (separate from the external Proxmox Ceph) for dev-only storage.
- **Rationale:** Dev cluster needs its own storage backend for testing CNPG and dynamic PV provisioning independently of the production Ceph cluster.

## 13. Migrate to Gateway API, DragonflyDB, Infisical, and per-service Kustomization structure

- **Date:** 2026-04-14
- **Status:** Completed (PR #153)
- **Context:** Major infrastructure overhaul developed and validated on a dev cluster before merging to production. Touches four distinct areas:

### 13a. Replace Traefik with Envoy Gateway for ingress

- **Decision:** Replace Traefik with Envoy Gateway, using Gateway API (`HTTPRoute`, `TLSRoute`, `TCPRoute`) instead of Ingress resources.
- **Rationale:** Gateway API is the Kubernetes-standard approach (replacing the legacy Ingress API). Envoy provides strong performance, mature feature set (rate limiting, retries, fault injection), and better alignment with cloud-native standards. Includes `HTTPRoute` HTTP→HTTPS redirect, `BackendTLSPolicy` for TLS re-encryption, and `TLSRoute` for non-HTTPS protocols (e.g., Authentik LDAP on port 636).

### 13b. Replace Redis Operator with DragonflyDB

- **Decision:** Replace the Redis Operator (RedisReplication + RedisSentinel) with DragonflyDB for all application caches.
- **Rationale:** DragonflyDB offers higher performance (multi-threaded, Redis-compatible protocol), simpler operational model (single CR vs. separate Replication + Sentinel resources), and built-in clustering. Used by: Harbor, Netbox, Paperless, Searxng, OpenWebUI, Immich.

### 13c. Replace HashiCorp Vault with Infisical for secrets management

- **Decision:** Migrate all `ExternalSecret` resources from HashiCorp Vault to a self-hosted Infisical instance, synced via External Secrets Operator.
- **Rationale:** Infisical provides a more modern secret management UX, native OIDC integration, and eliminates the operational overhead of managing a HashiCorp Vault cluster. Runtime secrets are stored in Infisical and synced into the cluster; bootstrap secrets are SOPS-encrypted with age and stored directly in the repo.

### 13d. Restructure infrastructure from flat `controllers/` + `configs/` to `base/` + `overlays/`

- **Decision:** Restructure from a flat `controllers/` + `configs/` layout to a `base/` + `overlays/` Kustomize pattern with per-service `ks.yaml` Flux Kustomizations.
- **Rationale:** The new structure provides better environment separation (dev vs. prod), clearer ownership per service, and follows the [Kustomize multi-env pattern](https://kubectl.docs.kubernetes.io/guides/common_problems/multitenancy/) more closely. All HelmRelease and Namespace names are preserved to ensure in-place upgrades.

## 14. Expose services via Netbird

- **Date:** 2026-04-16
- **Status:** Completed (PR #172)
- **Context:** Remote access to internal services.
- **Decision:** Add `netbird.io/expose: true` annotation to selected HelmReleases and add Netbird ingress allow rules to `CiliumNetworkPolicy` for each exposed app.
- **Rationale:** Since Netbird was already deployed for other services, opted to use it as a unified remote access solution (replacing Pangolin) for a single solution for everything. However, this migration is still incomplete due to some missing features on the Netbird side.

## 15. Replace dockhand with Arcane

- **Date:** 2026-04-19
- **Status:** Completed (PR #192)
- **Context:** Management node container management.
- **Decision:** Replace dockhand with Arcane (Docker management UI with OIDC SSO).
- **Rationale:** Arcane provides better security (OIDC integration), a more modern UI, and PostgreSQL-backed state management.

## 16. Delete HashiCorp Vault

- **Date:** 2026-04-20
- **Status:** Completed (PR #195)
- **Context:** Post-Infisical migration.
- **Decision:** Remove the HashiCorp Vault deployment from the cluster after migrating all secrets to Infisical.
- **Rationale:** Eliminates operational overhead of maintaining a Vault cluster when Infisical now serves as the secrets provider.

## 17. Migrate all PGClusters to Ceph-backed storage

- **Date:** 2026-04-26
- **Status:** Completed (PR #204)
- **Context:** Database storage layer.
- **Decision:** Migrate all CNPG clusters from `local-path` to Ceph-backed `ceph-block` StorageClass via ObjectStore (barman-cloud) for backups.
- **Rationale:** Reduces the number of replicas per cluster, thereby reducing the amount of resources used per cluster. Eliminates the need for per-app local storage and provides consistent, high-performance block storage.

## 18. Deploy Apache Tika as a central shared-utility service

- **Date:** 2026-07-10
- **Status:** Accepted
- **Context:** Open WebUI needs a content-extraction engine for its RAG pipeline (parsing PDFs, Office docs, etc. into text). Open WebUI supports Apache Tika via `CONTENT_EXTRACTION_ENGINE=tika` + `TIKA_SERVER_URL`. Paperless also *optionally* supports Tika but currently uses its own native Tesseract OCR (`PAPERLESS_OCR_*`) and is not yet a Tika consumer. Tika is completely stateless (HTTP request → extracted text, no persistence) and fairly heavy (JVM + ~1000 parsers + bundled Tesseract OCR, ~512MB–1GB resident).
- **Decision:** Deploy Tika as a standalone app in its own namespace (`kubernetes/apps/base/tika/`), 2 replicas, ~1Gi memory. The container listens on its native port 9998, but the Kubernetes Service exposes port 80 (mapping to the container's 9998) so consumers use the bare URL `http://tika.tika.svc.cluster.local` without a port suffix. Open WebUI points to this central endpoint. Paperless can opt in later by setting `PAPERLESS_TIKA_ENABLED=true` + `PAPERLESS_TIKA_ENDPOINT` without any Tika-side change.
- **Rationale:** Tika is stateless, so a single instance can serve multiple consumers — consistent with the existing shared-utility pattern used for SearXNG (cross-namespace `searxng.searxng.svc.cluster.local`). Centralizing avoids duplicating the heavy JVM/Tesseract footprint per app (a per-app sidecar would ~2x memory for zero functional gain). 2 replicas mitigate the risk that a future Paperless bulk-OCR run starves Open WebUI's interactive parsing. The per-app sidecar pattern (suggested by Open WebUI's Tika PR author) optimizes for security isolation, but in this trusted internal cluster behind Cilium policies that benefit is marginal and not worth the duplicate footprint. Chose central-now over per-app-now-extract-later because the shared-utility pattern is already established here and Paperless opting in later is a two-env-var change.

---

## 19. Migrate WireGuard VPN from wireguard-native to wg-easy, moved into this repo

- **Date:** 2026-07-22
- **Status:** Accepted
- **Context:** The home network was already served by a wireguard-native deployment (manual `wg0.conf` on the management node) providing no-NAT remote access. Management was manual (hand-editing config, adding peers by hand) and the deployment lived outside this repo, so it received no Renovate dependency updates and diverged from the Doco-CD managed management-node stack. The initial setup exposed its WireGuard admin UI through Cloudflare Tunnels.
- **Decision:** Migrate from wireguard-native to `wg-easy` v15, deployed via Docker Compose under `docker/vpn/wireguard/` and managed by Doco-CD. Same no-NAT routing design is preserved: host networking with tun device and `NET_ADMIN`/`NET_RAW`/`SYS_MODULE` caps, IPv6 disabled. A compose-based Traefik fronts the wg-easy UI, and a compose-based Netbird is added under `docker/vpn/` alongside it. The wg-easy admin UI is now exposed through Netbird instead of Cloudflare Tunnels, making it uniform with how other services are exposed. The existing OPNsense no-NAT design (static route for the VPN subnet via the management-node gateway, plus Hybrid Outbound NAT for the VPN subnet at the WAN edge for internet egress) is unchanged.
- **Rationale:** wg-easy provides a web UI for peer/client management (add, remove, generate QR/config) replacing manual `wg0.conf` edits, while keeping the same WireGuard data plane and the existing no-NAT routing — so no OPNsense-side or client-side reconfiguration of the routing/NAT design was needed. Moving the deployment into this repo under `docker/vpn/` brings it under Doco-CD and Renovate, so the wg-easy image and Traefik/Netbird images get automated updates like the rest of the stack. Routing the admin UI through Netbird instead of Cloudflare Tunnels keeps service exposure consistent across the stack.

---

*This log is maintained to provide context for architectural decisions and onboarding.*
