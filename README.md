# home-ops

> HomeOps driven by Kubernetes and GitOps using Flux

## Overview

This repository contains the declarative configuration for my entire home infrastructure, managed through [GitOps](https://www.weave.works/technologies/gitops/) with [Flux](https://fluxcd.io/). All infrastructure and application state is stored here — if it's not in this repo, it doesn't exist.

## Sections

| | |
|--|--|
| [📦 Kubernetes](./kubernetes/README.md) | GitOps-managed Kubernetes cluster — infrastructure, applications, and networking |
| [🐳 Docker](./docker/README.md) | Docker Compose services running on the management node |

## Hardware

### Physical Hosts (Proxmox)

| Host | CPU | RAM | OS | K8s VMs |
|------|-----|-----|----|---------|
| node1 | Intel Celeron J6413 (4c @ 3.0 GHz) | 32 GB | Proxmox | control-plane |
| node2 | Intel Core i9-12900H (20c @ 5.0 GHz) | 96 GB | Proxmox | control-plane + workers |
| node3 | Intel Core i9-12900H (20c @ 5.0 GHz) | 96 GB | Proxmox | control-plane + workers |

**Network:**

- Host/VM subnet: `192.168.30.0/24`

## Acknowledgements

- [Flux](https://fluxcd.io/), [Cilium](https://cilium.io/), [Envoy Gateway](https://gateway.envoyproxy.io/) communities
