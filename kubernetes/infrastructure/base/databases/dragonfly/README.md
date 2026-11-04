# Dragonfly (shared cache instance)

Single centralized Dragonfly instance (2 replicas) in the `dragonfly` namespace,
shared by multiple consumers. Endpoint: `dragonfly.dragonfly.svc.cluster.local:6379`.
Auth is a single shared password (`/dragonfly/DRAGONFLY_PASSWORD` via Infisical),
so consumers are separated by **logical DB indexes** (Dragonfly supports 16 by default → `0`–`15`).

## Logical DB index assignments

| Index | Consumer          | Used for                             | Config                                                    |
|------:|-------------------|--------------------------------------|-----------------------------------------------------------|
| 0     | Harbor (core)     | Core cache                           | `kubernetes/apps/base/harbor/helm.yaml` (`coreDatabaseIndex`) |
| 1     | Harbor (jobservice) | Job service cache                  | `kubernetes/apps/base/harbor/helm.yaml` (`jobserviceDatabaseIndex`) |
| 2     | Harbor (registry) | Registry cache                       | `kubernetes/apps/base/harbor/helm.yaml` (`registryDatabaseIndex`) |
| 3     | Harbor (trivy)    | Trivy adapter cache                  | `kubernetes/apps/base/harbor/helm.yaml` (`trivyAdapterIndex`) |
| 4     | OpenWebUI         | Redis cache                          | `kubernetes/apps/base/openwebui/secrets.yaml` (`REDIS_URL`) |
| 5     | OpenWebUI         | WebSocket pub/sub                    | `kubernetes/apps/base/openwebui/secrets.yaml` (`WEBSOCKET_REDIS_URL`) |
| 6     | Immich            | Redis cache/job queues               | `kubernetes/apps/base/immich/configmap.yaml` (`REDIS_DBINDEX`) |
| 7     | LiteLLM           | Redis cache                          | `kubernetes/apps/base/litellm/secrets.yaml` (`REDIS_URL`) |
| 8     | Netbox            | Task queue                           | `kubernetes/apps/base/netbox/helm.yaml` (`tasksDatabase.database`) |
| 9     | Netbox            | Caching                              | `kubernetes/apps/base/netbox/helm.yaml` (`cachingDatabase.database`) |
| 10    | Paperless         | Redis cache/job queues               | `kubernetes/apps/base/paperless/secrets.yaml` (Redis URL `/10`) |
| 11    | Searxng           | Valkey cache                         | `kubernetes/apps/base/searxng/secrets.yaml` (`SEARXNG_VALKEY_URL`) |
| 12    | *free*            | — (previously Sure, now removed)     | —                                                          |
| 13    | Renovate Operator | Executor repository-cache queue      | `kubernetes/infrastructure/base/platform/renovate-operator/app/secrets.yaml` (`redis-url`) |
| 14    | *free*            | —                                    | —                                                          |
| 15    | *free*            | —                                    | —                                                          |

## Adding a new consumer

1. Pick the next free index above and add a row.
2. Sync the shared password into the app's namespace via External Secrets, keyed on `/dragonfly/DRAGONFLY_PASSWORD` (matches the `redis://:<password>@dragonfly.dragonfly.svc.cluster.local:6379/<index>` URL form).
3. Allow egress to the dragonfly namespace in the app's `network.yaml` (Cilium policy), mirroring the existing `dragonfly-egress` rules in other apps.
4. Dragonfly's own network policy (`cluster/network.yaml`) must also allow the new namespace in.

> If 16 indexes run out, Dragonfly's `databases` setting can be raised beyond the default 16.
