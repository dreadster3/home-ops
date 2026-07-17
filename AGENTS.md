# AGENTS.md

Guidance for AI agents working on this repository.

## Project Overview

This is a personal home infrastructure repository managed via GitOps with Flux. It covers:

- **Kubernetes** — 6-node Talos cluster (3 control-plane, 3 workers) on Proxmox, with Rook/Ceph external storage, Cilium CNI, Envoy Gateway ingress, and CloudNativePG databases
- **Docker** — Compose services on the management node, managed by Doco-CD

All infrastructure state is declared here. Nothing exists outside this repo.

## Key Conventions

### Commit Messages

Use [conventional commits](https://www.conventionalcommits.org/):

```
type(scope): description

chore(deps): update ghcr.io/dragonflydb/dragonfly docker tag to v1.38.0
feat(kubernetes): add DragonflyDB for cache layer
fix(immich): allow egress to authentik
docs(readme): acknowledge onedr0p/home-ops for project structure
```

Types observed: `feat`, `fix`, `chore`, `docs`. Scope is optional but preferred when clear.

### Pull Requests

- All changes go through PRs to `main` (branch protection enforced)
- PR titles follow the same conventional commit format
- Renovate handles dependency updates automatically (grouped where applicable)

### Secrets

- **Runtime secrets** → stored in Infisical, synced via External Secrets Operator
- **Bootstrap secrets** → SOPS-encrypted with age keys, committed to repo
- **Never** commit plaintext secrets or age private keys

### Naming

- HelmRelease names match the app name (e.g., `immich`, `paperless`)
- Namespace names match the app name
- All names are preserved across migrations for in-place upgrades

## Project Structure

```
.
├── .taskfiles/           # Taskfile (go-task) sub-projects
│   ├── kubernetes/       # k8s tasks (build, dev cluster, eso, flux, talos)
│   └── docker/           # docker tasks
├── .pi/                  # Project-level agent skills
│   └── skills/
│       └── decision-log/ # Enforces DECISION.md updates for major changes
├── DECISION.md           # Architecture decision log (synced to codebase-memory MCP)
├── docker/               # Docker Compose services (management node)
│   └── mgmt/             # Per-service compose stacks
├── flake.nix             # Dev shell (flux, kustomize, minikube, etc.)
├── kubernetes/
│   ├── apps/             # Application definitions
│   │   ├── base/         # Shared app resources (HelmRelease, HTTPRoute, etc.)
│   │   └── overlays/     # Environment-specific patches
│   │       ├── dev/      # Dev cluster patches
│   │       └── prd/      # Production patches
│   ├── clusters/         # Cluster entrypoints
│   │   ├── dev/          # Dev cluster manifests
│   │   └── production/   # Production manifests
│   ├── components/       # Shared components
│   │   └── substitute/   # ConfigMap+Secret for Flux variable substitution
│   ├── infrastructure/   # Infrastructure definitions
│   │   ├── base/
│   │   └── overlays/
│   │       ├── dev/
│   │       └── prd/
│   └── talos/            # Talos node configs
│       └── prd/
├── README.md
└── Taskfile.yml          # Root task runner
```

## Task Commands

Run via `task` (go-task). Install with `nix develop` or `go install go-task/task@latest`.

### Kubernetes

```bash
task kubernetes:build PATH=<path>        # Build kustomize config with envsubst
task kubernetes:reconcile                # Reconcile Flux git source
task kubernetes:dev:cluster:start        # Start minikube dev cluster (3 nodes)
task kubernetes:dev:cluster:stop         # Stop dev cluster
task kubernetes:dev:cluster:tunnel       # Open minikube tunnel
task kubernetes:get:secret NAME=... NS=  # Dump a cluster secret
task kubernetes:nas:suspend              # Suspend all NAS-dependent deployments
task kubernetes:nas:resume               # Resume all NAS-dependent deployments
```

### Docker

```bash
task docker:help                           # List available docker tasks
```

### Nix Dev Shell

```bash
nix develop                                  # Enter dev environment
```

Includes: flux, fluxcd-operator, kustomize, minikube, yq, gitleaks, pre-commit, vault, infisical, grafana-alloy.

## Adding a New Application

1. Create app directory under `kubernetes/apps/base/<app>/`
2. Add resources: `namespace.yaml`, `helm.yaml`, `kustomization.yaml`, `network.yaml`, `secrets.yaml`, `store.yaml`
3. Add overlay patches under `kubernetes/apps/overlays/<dev|prd>/<app>/`
4. Reference the app's `ks.yaml` in the cluster entrypoint (`clusters/<dev|prd>/apps.yaml`)
5. Add to Infisical for runtime secrets
6. Add to Renovate config for auto-updates

## Adding a Management Docker Service

1. Create directory under `docker/mgmt/<service>/`
2. Add compose files and config
3. Add to Doco-CD watch path
4. Add to Renovate config for auto-updates

## Important Notes

- **Dev cluster** uses minikube (kvm2 driver) with its own Rook/Ceph — separate from production's external Proxmox Ceph
- **Ceph** runs natively on Proxmox; Kubernetes consumes it externally via Rook. Never deploy Ceph inside Kubernetes on top of Proxmox Ceph (causes ~9x storage overhead)
- **DNS** is managed by External DNS syncing to an internal RFC2136 server — do not add manual DNS entries
- **Ingress** is via Envoy Gateway with Gateway API (HTTPRoute/TLSRoute/TCPRoute) — not legacy Ingress resources
- **Remote access** is via Netbird WireGuard overlay — not public internet exposure
- **Per-service PGClusters** — each app has its own CloudNativePG cluster, never shared databases
- **DECISION.md** — document any major architectural or operational decision before implementing it
- **DECISION.md → codebase-memory MCP sync** — whenever `DECISION.md` is created or modified, the full decisions body must be re-synced to the `codebase-memory` MCP ADR store. The `manage_adr` tool is overwrite-only, so always send the *entire* decisions content (all `## N.` sections, including `### Na/...` sub-sections), not just the changed section.

  ### How to sync DECISION.md to the codebase-memory MCP

  1. Extract the decisions body from `DECISION.md` — from the first `## 1.` heading through the last decision, excluding the `# Architecture Decision Log` preamble and the trailing `*This log is maintained...` footer (and any trailing `---` separators).
  2. Call the `codebase-memory` MCP tool `manage_adr` with:
     - `project`: `home-dreadster-Documents-projects-github-home-ops`
     - `mode`: `update`
     - `content`: the full decisions body from step 1
  3. Verify the sync by calling `manage_adr` with `mode: "sections"` and confirming every `## N.` heading (and `### Na.` sub-heading) is present.

  > **Note:** Do *not* call `update` once per decision — each `update` overwrites the entire ADR blob. A successful per-decision call would erase all prior decisions. Always send the complete content in a single `update`.
