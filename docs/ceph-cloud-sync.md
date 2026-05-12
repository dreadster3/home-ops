# Ceph RGW Cloud Sync to Garage

A tutorial for configuring Ceph RGW cloud sync to back up bucket data from a Rook-Ceph cluster to a Garage S3-compatible endpoint.

> **Ceph version**: 19.2.3 (Squid)
>
> **Why Garage?** MinIO and rustfs return `BucketAlreadyExists` (409) when Ceph RGW tries to create a bucket that already exists, but AWS S3 returns `BucketAlreadyOwnedByYou` (200). Ceph RGW treats the 409 as a fatal error and stops syncing. Garage correctly implements `BucketAlreadyOwnedByYou`, making it a compatible cloud sync target.

---

## Architecture

```
┌───────────────────────────┐            ┌───────────────────────────┐
│                           │   cloud    │                           │
│  Ceph RGW                 │   sync     │  Garage                   │
│  ┌─────────────────────┐  │ ─────────► │  ┌─────────────────────┐  │
│  │  ceph-objectstore   │  │   push     │  │  bucket: test       │  │
│  │  (master zone)      │  │   only     │  │  (S3-compatible)    │  │
│  └─────────────────────┘  │            │  └─────────────────────┘  │
│                           │            │                           │
│  ┌─────────────────────┐  │            │                           │
│  │  garage-cloud-sync  │  │            │                           │
│  │  (cloud zone)       │  │            │                           │
│  │  tier_type=cloud    │  │            │                           │
│  │  tier_config=...    │  │            │                           │
│  └─────────────────────┘  │            │                           │
│                           │            │                           │
└───────────────────────────┘            └───────────────────────────┘
```

Cloud sync is **unidirectional** — Ceph pushes objects to Garage. Data never flows back.

The "garage-cloud-sync" zone is a **logical zone** that doesn't run its own RGW instance. It shares the master RGW endpoint and acts as a configuration container for the cloud sync module (tier_type=cloud, Garage credentials, target bucket).

---

## Prerequisites

- A Rook-Ceph cluster with a working RGW deployment
- A Garage instance accessible from the cluster network
- `kubectl rook-ceph` plugin or direct access to `radosgw-admin` via the toolbox pod
- Garage API key with read/write access to that bucket

### In This Tutorial

| Component              | Value                                                    |
| ---------------------- | -------------------------------------------------------- |
| Ceph cluster namespace | `rook-ceph`                                              |
| Master zone            | `ceph-objectstore`                                       |
| Cloud zone             | `garage-cloud-sync`                                      |
| RGW service endpoint   | `http://rook-ceph-rgw-ceph-objectstore.rook-ceph.svc:80` |
| Garage endpoint        | `http://garage-endpoint`                                 |
| Garage bucket          | `test`                                                   |
| Toolbox pod            | `rook-ceph-tools-c69c99679-qmpds` (yours will differ)    |
| RGW deployment         | `rook-ceph-rgw-ceph-objectstore-a`                       |

> Throughout this guide, `kubectl rook-ceph radosgw-admin` is used as a wrapper. If you don't have the plugin, run `radosgw-admin` directly inside the toolbox pod:
>
> ```bash
> kubectl -n rook-ceph exec rook-ceph-tools-XXXX -- radosgw-admin <command>
> ```

---

## Step 1 — Create the Cloud Sync Zone

The cloud zone is a new zone in the same zonegroup as your master zone. It holds the cloud sync configuration (remote endpoint, credentials, target path) but doesn't need its own RGW daemon — it shares the master zone's RGW endpoint.

```bash
kubectl rook-ceph radosgw-admin zone create \
  --rgw-zonegroup=ceph-objectstore \
  --rgw-zone=garage-cloud-sync \
  --endpoints=http://rook-ceph-rgw-ceph-objectstore.rook-ceph.svc:80 \
  --tier-type=cloud
```

**Important points:**

- `--endpoints` must be set to the **master zone's RGW endpoint** (not the Garage endpoint). The cloud zone borrows this endpoint because it doesn't have its own RGW.
- `--tier-type=cloud` tells Ceph this zone syncs to a cloud S3 backend (not another Ceph zone).

Verify the zone was created:

```bash
kubectl rook-ceph radosgw-admin zone get --rgw-zone=garage-cloud-sync
```

> **Note:** `radosgw-admin zone get` may show `tier_type` as empty or missing. This is a [known display bug](https://tracker.ceph.com/issues/67879) in Ceph v19. The tier_type is stored correctly in the period. Verify with:
>
> ```bash
> kubectl rook-ceph radosgw-admin period get | grep tier_type
> ```
>
> You should see `"tier_type": "cloud"` for the `garage-cloud-sync` zone.

---

## Step 2 — Configure the Cloud Connection

Set the Garage S3 credentials and endpoint on the cloud zone:

```bash
# Garage S3 credentials
kubectl rook-ceph radosgw-admin zone modify \
  --rgw-zone=garage-cloud-sync \
  --tier-config=connection.access_key=xxxxxxxxxxxxxxxxxxxx \
  --tier-config=connection.secret=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \
  --tier-config=connection.endpoint=http://[garage-endpoint] \
  --tier-config=connection.host_style=path \
  --tier-config=connection.region=eu-west-1 \
  --tier-config=target_path=test
```

**What each field means:**

| Field                   | Description                                                                                                                                                    |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `connection.access_key` | Garage S3 access key                                                                                                                                           |
| `connection.secret`     | Garage S3 secret key                                                                                                                                           |
| `connection.endpoint`   | Garage HTTP endpoint URL                                                                                                                                       |
| `connection.host_style` | `path` for path-style S3 URLs (`http://host:port/bucket/key`). Use `virtual` for virtual-hosted style (`http://bucket.host:port/key`). Garage uses path-style. |
| `connection.region`     | AWS region string. Can be anything for Garage; `eu-west-1` is conventional.                                                                                    |
| `target_path`           | The destination bucket name on Garage. All synced objects land in this bucket.                                                                                 |

### About `target_path`

With the **trivial configuration** (what we set up above), `target_path` is just the destination S3 bucket name:

```
Ceph bucket: openwebui-7ace3b18-.../abc.png  →  Garage: test/abc.png
Ceph bucket: other-bucket/report.pdf          →  Garage: test/report.pdf
```

Objects from **all synced buckets** go into the **same** Garage bucket, keeping their original keys. If two source buckets have objects with the same key, the last write wins.

For per-bucket isolation, use the **non-trivial profiles configuration** (see [Advanced: Per-Bucket Destination Paths](#advanced-per-bucket-destination-paths)).

---

## Step 3 — Create a System User

A system user is required for the cloud zone to authenticate when pulling data logs from the master zone:

```bash
kubectl rook-ceph radosgw-admin user create \
  --uid=cloud-sync \
  --display-name="Cloud Sync System User" \
  --system
```

Take note of the `access_key` and `secret` from the output — you'll need them next.

---

## Step 4 — Set the System Key on the Cloud Zone

The cloud zone needs the system user's credentials to authenticate with the master zone's data log API:

```bash
kubectl rook-ceph radosgw-admin zone modify \
  --rgw-zone=garage-cloud-sync \
  --access-key=<SYSTEM_USER_ACCESS_KEY> \
  --secret=<SYSTEM_USER_SECRET_KEY>
```

For example, if the user created in Step 3 returned:

```json
{
  "keys": [
    {
      "access_key": "access_key",
      "secret": "secret_key"
    }
  ]
}
```

Then:

```bash
kubectl rook-ceph radosgw-admin zone modify \
  --rgw-zone=garage-cloud-sync \
  --access-key=access_key \
  --secret=secret_key
```

---

## Step 5 — Set the Zone Endpoints

The cloud zone must have the master RGW's endpoint so the sync daemon can reach it. **This is critical** — without it, the RGW logs `WARNING: can't generate connection for zone garage-cloud-sync: no endpoints defined`:

```bash
kubectl rook-ceph radosgw-admin zone modify \
  --rgw-zone=garage-cloud-sync \
  --endpoints=http://rook-ceph-rgw-ceph-objectstore.rook-ceph.svc:80
```

> **Note:** `radosgw-admin zone get` may show `endpoints: []` even after this. This is a display bug. The period (the authoritative config) contains the correct endpoint. Verify with:
>
> ```bash
> kubectl rook-ceph radosgw-admin period get | grep -A3 "garage-cloud-sync"
> ```

---

## Step 6 — Commit the Period

The period is Ceph's cluster-wide configuration. Any zone or zonegroup change must be committed before it takes effect:

```bash
kubectl rook-ceph radosgw-admin period update --commit
```

---

## Step 7 — Restart the RGW

The RGW must restart to pick up the new period:

```bash
kubectl rollout restart deployment/rook-ceph-rgw-ceph-objectstore-a -n rook-ceph
kubectl rollout status deployment/rook-ceph-rgw-ceph-objectstore-a -n rook-ceph --timeout=60s
```

Verify the RGW loaded the cloud zone connection:

```bash
kubectl logs -n rook-ceph deployment/rook-ceph-rgw-ceph-objectstore-a -c rgw --tail=50 \
  | grep "generating connection"
```

You should see:

```
rgw main: generating connection object for zone garage-cloud-sync id f79b5859-...
```

If you see `WARNING: can't generate connection for zone garage-cloud-sync: no endpoints defined`, repeat Step 5 and commit again.

---

## Step 8 — Define the Sync Policy

The sync policy tells Ceph **which data flows where**. It has three levels:

```
┌─────────────────────────────────┐
│  Sync Policy Group              │
│  (named container)              │
│                                 │
│  ┌───────────────────────────┐  │
│  │  Data Flow                │  │    Direction: source zone → dest zone
│  │  (directional)            │  │    You can have multiple flows per group
│  └───────────────────────────┘  │
│                                 │
│  ┌───────────────────────────┐  │
│  │  Pipe                     │  │    Which data flows: source bucket → dest bucket
│  │  (one or more)            │  │    Wildcards (*) match everything
│  └───────────────────────────┘  │
│                                 │
│  Status: "allowed" or "enabled" │    "allowed" = per-bucket opt-in
│                                 │    "enabled" = auto-sync all buckets
└─────────────────────────────────┘
```

### Create the sync policy group

The sync policy is built from three parts: a **group** (container), **flows** (data direction), and **pipes** (which buckets flow through). Ceph provides dedicated `sync group`, `sync group flow`, and `sync group pipe` subcommands for each.

#### Create the group

```bash
kubectl rook-ceph radosgw-admin sync group create \
  --group-id=cloud-backup \
  --status=allowed
```

`status=allowed` means each bucket must explicitly opt in with `bucket sync enable`. Use `status=enabled` if you want all buckets to sync automatically.

> **Note:** Zonegroup-level sync policy changes (groups, flows, pipes) require a `period update --commit` afterward. Bucket-level policy changes do not.

#### Create a directional flow

This defines that data flows **one way** from `ceph-objectstore` to `garage-cloud-sync`:

```bash
kubectl rook-ceph radosgw-admin sync group flow create \
  --group-id=cloud-backup \
  --flow-id=cloud-backup-flow \
  --flow-type=directional \
  --source-zone=ceph-objectstore \
  --dest-zone=garage-cloud-sync
```

- `--flow-type=directional` means one-way (Ceph → Garage). Use `symmetrical` for two-way replication between Ceph zones.
- `--flow-id` is an arbitrary name for this flow.

#### Create a pipe

The pipe defines **which buckets** use the flow. Wildcards (`*`) match all buckets:

```bash
kubectl rook-ceph radosgw-admin sync group pipe create \
  --group-id=cloud-backup \
  --pipe-id=all-buckets \
  --source-zones='*' \
  --dest-zones='*' \
  --mode=system
```

- `--source-zones='*'` and `--dest-zones='*'` use wildcards that resolve to the zones defined in the flow.
- `--mode=system` means the sync is system-managed (not user-initiated).
- You can also specify `--source-bucket` / `--dest-bucket` with bucket names or wildcards, and `--prefix` to filter by object key prefix.

#### Verify the policy

```bash
kubectl rook-ceph radosgw-admin sync group get --group-id=cloud-backup
```

You should see:

```json
{
  "id": "cloud-backup",
  "data_flow": {
    "directional": [
      {
        "source_zone": "ceph-objectstore",
        "dest_zone": "garage-cloud-sync"
      }
    ]
  },
  "pipes": [
    {
      "id": "all-buckets",
      "source": { "bucket": "*", "zones": ["ceph-objectstore"] },
      "dest": { "bucket": "*", "zones": ["garage-cloud-sync"] },
      "params": { "mode": "system" }
    }
  ],
  "status": "allowed"
}
```

#### Commit

```bash
kubectl rook-ceph radosgw-admin period update --commit
```

### Status: `allowed` vs `enabled`

| Status    | Behavior                                                                                |
| --------- | --------------------------------------------------------------------------------------- |
| `allowed` | Buckets must individually opt in with `bucket sync enable`. Good for selective backups. |
| `enabled` | All buckets in the zonegroup sync automatically. Good for full disaster recovery.       |

To change status later:

```bash
kubectl rook-ceph radosgw-admin sync group modify \
  --group-id=cloud-backup \
  --status=enabled

kubectl rook-ceph radosgw-admin period update --commit
```

---

## Step 9 — Initialize Sync and Enable Buckets

### Initialize the data sync engine

```bash
kubectl rook-ceph radosgw-admin data sync init \
  --source-zone=ceph-objectstore \
  --rgw-zone=garage-cloud-sync

kubectl rook-ceph radosgw-admin metadata sync init \
  --rgw-zone=garage-cloud-sync
```

### Enable sync on a bucket

With status `allowed`, each bucket needs explicit opt-in:

```bash
kubectl rook-ceph radosgw-admin bucket sync enable \
  --bucket=bucket-name
```

### Verify sync is active

```bash
# Overall data sync status
kubectl rook-ceph radosgw-admin data sync status \
  --source-zone=ceph-objectstore \
  --rgw-zone=garage-cloud-sync

# Bucket-level sync info
kubectl rook-ceph radosgw-admin sync info \
  --bucket=bucket-name
```

You should see `status: sync` and all 128 shards in `incremental-sync` once initial sync completes.

---

## Step 10 — Verify

### Check objects in Garage

Use any S3 client (aws-cli, s3cmd, or a Python script) to list objects in the `test` bucket on Garage:

```bash
# Example using aws-cli with path-style access
aws --endpoint-url=http://garage-endpoint \
    s3 ls s3://test/ \
    --no-sign-request  # if bucket allows anonymous reads
```

### Check sync errors

```bash
kubectl rook-ceph radosgw-admin sync error list
```

An empty list means no sync errors.

### Check RGW logs

```bash
kubectl logs -n rook-ceph deployment/rook-ceph-rgw-ceph-objectstore-a -c rgw --tail=100 \
  | grep -i "sync_object\|creating bucket\|cloud"
```

Look for lines like:

```
sync_object: b=openwebui-7ace3b18-... k=abc.png
AWS: creating bucket test
```

---

## Adding Another Bucket to Sync

If you're using status `allowed`, enable each new bucket:

```bash
kubectl rook-ceph radosgw-admin bucket sync enable \
  --bucket=<new-bucket-name>
```

That's it. The bucket will match the existing wildcard pipe and start syncing to the same Garage `test` bucket.

If you want a different destination for each bucket, see [Advanced: Per-Bucket Destination Paths](#advanced-per-bucket-destination-paths).

---

## Monitoring

### Data sync status

```bash
kubectl rook-ceph radosgw-admin data sync status \
  --source-zone=ceph-objectstore \
  --rgw-zone=garage-cloud-sync
```

- `status: init` — sync is initializing
- `status: building-full-sync-maps` — building initial sync maps
- `status: sync` — active and running
- `full_sync: total=N, complete=N` — how many buckets completed initial sync

### Bucket sync status

```bash
kubectl rook-ceph radosgw-admin bucket sync status \
  --bucket=<bucket-name>
```

### Force a sync run

If objects aren't syncing and you want to trigger it manually:

```bash
kubectl rook-ceph radosgw-admin data sync run \
  --source-zone=ceph-objectstore \
  --rgw-zone=garage-cloud-sync
```

---

## Troubleshooting

### "can't generate connection for zone ... no endpoints defined"

The cloud zone has no endpoint. Fix:

```bash
kubectl rook-ceph radosgw-admin zone modify \
  --rgw-zone=garage-cloud-sync \
  --endpoints=http://rook-ceph-rgw-ceph-objectstore.rook-ceph.svc:80
kubectl rook-ceph radosgw-admin period update --commit
kubectl rollout restart deployment/rook-ceph-rgw-ceph-objectstore-a -n rook-ceph
```

### "Sync is disabled for bucket ... or bucket has no sync sources"

Either:

1. The bucket hasn't been enabled for sync: `kubectl rook-ceph radosgw-admin bucket sync enable --bucket=<name>`
2. The sync policy pipe doesn't match the bucket (check the wildcard pattern)
3. The sync policy group status is `allowed` (not `enabled`) and the bucket hasn't opted in

### `radosgw-admin zone get` shows `tier_type` as missing

This is a [known display bug](https://tracker.ceph.com/issues/67879) in Ceph v19. The period stores the correct value. Verify with:

```bash
kubectl rook-ceph radosgw-admin period get | grep tier_type
```

You should see `"tier_type": "cloud"` for the cloud zone.

### `radosgw-admin zonegroup set` strips `dest.zone` from pipe config

This is another known bug in some Ceph versions. The workaround is to use the `--sync-policy-group-*` CLI options (as shown in this tutorial) rather than manually editing the JSON and feeding it back with `zonegroup set`.

### "BucketAlreadyExists" (409) from remote

This happens with MinIO/rustfs backends. Ceph RGW creates a bucket via `CreateBucket` and expects `BucketAlreadyOwnedByYou` (200) if it already exists. MinIO returns `BucketAlreadyExists` (409) instead, which Ceph treats as a fatal error.

**Solution:** Use Garage (which correctly returns `BucketAlreadyOwnedByYou`) or an AWS S3 backend.

### 403 errors on `/admin/realm/period`

An anonymous client trying to pull the realm period. This is typically the cloud sync daemon using stale credentials. Fix by ensuring the system user on the cloud zone matches the actual system user:

```bash
# Compare zone system_key with user credentials
kubectl rook-ceph radosgw-admin zone get --rgw-zone=garage-cloud-sync | grep access_key
kubectl rook-ceph radosgw-admin user info --uid=cloud-sync | grep access_key
```

### Data sync stuck at `status: init` or `building-full-sync-maps`

Try reinitializing:

```bash
kubectl rook-ceph radosgw-admin data sync init \
  --source-zone=ceph-objectstore \
  --rgw-zone=garage-cloud-sync

kubectl rook-ceph radosgw-admin metadata sync init \
  --rgw-zone=garage-cloud-sync
```

Also ensure the RGW has restarted after the latest period commit.

---

## Advanced: Per-Bucket Destination Paths

By default, all synced objects go into a single Garage bucket (`test`). If you want each source bucket to have its own prefix or a different destination bucket, use the **non-trivial profiles configuration**:

```bash
# Remove the trivial target_path
kubectl rook-ceph radosgw-admin zone modify \
  --rgw-zone=garage-cloud-sync \
  --tier-config-rm=target_path

# Add a default target_path (fallback)
kubectl rook-ceph radosgw-admin zone modify \
  --rgw-zone=garage-cloud-sync \
  --tier-config=default.connection.access_key=xxxxxxxxxxxxxxxxxxxx \
  --tier-config=default.connection.secret=xxxxxxxxxxxxxxxxxxx \
  --tier-config=default.connection.endpoint=http://garage-endpoint \
  --tier-config=default.connection.host_style=path \
  --tier-config=default.connection.region=eu-west-1 \
  --tier-config=default.target_path=backups

# Add a profile for specific buckets (using ${bucket} variable)
kubectl rook-ceph radosgw-admin zone modify \
  --rgw-zone=garage-cloud-sync \
  --tier-config=profiles[].source_bucket=openwebui-* \
  --tier-config=profiles[-1].target_path=backups/\${bucket}

kubectl rook-ceph radosgw-admin period update --commit
```

The `${bucket}` variable expands to the source bucket name, producing paths like:

- `backups/openwebui-7ace3b18-.../abc.png`

### `target_path` Variables

| Variable          | Description             |
| ----------------- | ----------------------- |
| `${sid}`          | Unique sync instance ID |
| `${zonegroup}`    | Zonegroup name          |
| `${zonegroup_id}` | Zonegroup ID            |
| `${zone}`         | Zone name               |
| `${zone_id}`      | Zone ID                 |
| `${bucket}`       | Source bucket name      |
| `${owner}`        | Source bucket owner ID  |

For example, `target_path=rgwx-${zone}/${owner}/${bucket}` would produce:

- `rgwx-ceph-objectstore/user-id/openwebui-7ace3b18-.../abc.png`

---

## Advanced: SSL/TLS Configuration

If your Garage endpoint uses HTTPS with a self-signed or internal certificate, add:

```bash
kubectl rook-ceph radosgw-admin zone modify \
  --rgw-zone=garage-cloud-sync \
  --tier-config=connection.ssl_verify=false
```

Or set the RGW config to trust your CA:

```bash
kubectl -n rook-ceph exec rook-ceph-tools-XXXX -- \
  ceph config set client.rgw radosgw_getssl_cert_path /path/to/ca-bundle.crt
```

---

## Complete Command Reference

### Zone Management

```bash
# Create a cloud zone
kubectl rook-ceph radosgw-admin zone create \
  --rgw-zonegroup=<zonegroup> \
  --rgw-zone=<zone-name> \
  --endpoints=<master-rgw-endpoint> \
  --tier-type=cloud

# View zone config
kubectl rook-ceph radosgw-admin zone get --rgw-zone=<zone-name>

# Set zone endpoints
kubectl rook-ceph radosgw-admin zone modify \
  --rgw-zone=<zone-name> \
  --endpoints=<endpoint>

# Set system key
kubectl rook-ceph radosgw-admin zone modify \
  --rgw-zone=<zone-name> \
  --access-key=<key> \
  --secret=<secret>

# Configure tier (cloud connection)
kubectl rook-ceph radosgw-admin zone modify \
  --rgw-zone=<zone-name> \
  --tier-config=connection.access_key=<key> \
  --tier-config=connection.secret=<secret> \
  --tier-config=connection.endpoint=<url> \
  --tier-config=connection.host_style=path \
  --tier-config=connection.region=<region> \
  --tier-config=target_path=<bucket>

# Remove a tier config key
kubectl rook-ceph radosgw-admin zone modify \
  --rgw-zone=<zone-name> \
  --tier-config-rm=<key>
```

### Sync Policy

```bash
# Create a sync policy group
kubectl rook-ceph radosgw-admin sync group create \
  --group-id=<group-name> \
  --status=allowed|enabled

# Create a directional data flow (one-way: source → dest)
kubectl rook-ceph radosgw-admin sync group flow create \
  --group-id=<group-name> \
  --flow-id=<flow-id> \
  --flow-type=directional \
  --source-zone=<source-zone> \
  --dest-zone=<dest-zone>

# Create a symmetrical data flow (two-way replication)
kubectl rook-ceph radosgw-admin sync group flow create \
  --group-id=<group-name> \
  --flow-id=<flow-id> \
  --flow-type=symmetrical \
  --zones=<zone1,zone2,...>

# Create a pipe (which buckets flow through the data flow)
kubectl rook-ceph radosgw-admin sync group pipe create \
  --group-id=<group-name> \
  --pipe-id=<pipe-id> \
  --source-zones='*' \
  --dest-zones='*' \
  --mode=system

# Create a pipe with specific source/dest buckets
kubectl rook-ceph radosgw-admin sync group pipe create \
  --group-id=<group-name> \
  --pipe-id=<pipe-id> \
  --source-zones=<source-zone> \
  --source-bucket=<bucket-pattern> \
  --dest-zones=<dest-zone> \
  --dest-bucket=<bucket-pattern> \
  --mode=system

# Create a pipe with a prefix filter (only sync objects starting with "foo/")
kubectl rook-ceph radosgw-admin sync group pipe create \
  --group-id=<group-name> \
  --pipe-id=<pipe-id> \
  --source-zones='*' --dest-zones='*' \
  --prefix=foo/

# View the full sync policy
kubectl rook-ceph radosgw-admin sync policy get

# View a specific group
kubectl rook-ceph radosgw-admin sync group get --group-id=<group-id>

# Modify group status
kubectl rook-ceph radosgw-admin sync group modify \
  --group-id=<group-name> \
  --status=allowed|enabled|forbidden

# Remove a pipe
kubectl rook-ceph radosgw-admin sync group pipe remove \
  --group-id=<group-name> \
  --pipe-id=<pipe-id> \
  --source-zones='*' --dest-zones='*'

# Remove a flow
kubectl rook-ceph radosgw-admin sync group flow remove \
  --group-id=<group-name> \
  --flow-id=<flow-id> \
  --flow-type=directional \
  --source-zone=<source-zone> \
  --dest-zone=<dest-zone>

# Remove a group
kubectl rook-ceph radosgw-admin sync group remove --group-id=<group-name>

# Bucket-level policy (applied to a specific bucket only)
kubectl rook-ceph radosgw-admin sync group create \
  --bucket=<bucket-name> \
  --group-id=<group-id> \
  --status=enabled

kubectl rook-ceph radosgw-admin sync group pipe create \
  --bucket=<bucket-name> \
  --group-id=<group-id> \
  --pipe-id=<pipe-id> \
  --source-zones='*' --dest-zones='*'

# Remove a bucket-level group
kubectl rook-ceph radosgw-admin sync group remove \
  --bucket=<bucket-name> \
  --group-id=<group-id>
```

### Bucket Sync

```bash
# Enable sync on a bucket
kubectl rook-ceph radosgw-admin bucket sync enable --bucket=<name>

# Disable sync on a bucket
kubectl rook-ceph radosgw-admin bucket sync disable --bucket=<name>

# Check sync info for a bucket
kubectl rook-ceph radosgw-admin sync info --bucket=<name>

# Check bucket sync status
kubectl rook-ceph radosgw-admin bucket sync status --bucket=<name>
```

### Sync Operations

```bash
# Initialize data sync
kubectl rook-ceph radosgw-admin data sync init \
  --source-zone=<source-zone> \
  --rgw-zone=<cloud-zone>

# Initialize metadata sync
kubectl rook-ceph radosgw-admin metadata sync init \
  --rgw-zone=<cloud-zone>

# Check data sync status
kubectl rook-ceph radosgw-admin data sync status \
  --source-zone=<source-zone> \
  --rgw-zone=<cloud-zone>

# Force a sync run
kubectl rook-ceph radosgw-admin data sync run \
  --source-zone=<source-zone> \
  --rgw-zone=<cloud-zone>

# Check sync errors
kubectl rook-ceph radosgw-admin sync error list
```

### Period Management

```bash
# Commit period changes (required after any zone/zonegroup change)
kubectl rook-ceph radosgw-admin period update --commit

# View current period
kubectl rook-ceph radosgw-admin period get
```

### RGW Management

```bash
# Restart RGW to pick up period changes
kubectl rollout restart deployment/rook-ceph-rgw-ceph-objectstore-a -n rook-ceph

# Check RGW logs for sync activity
kubectl logs -n rook-ceph deployment/rook-ceph-rgw-ceph-objectstore-a -c rgw --tail=100 \
  | grep -i "sync\|cloud\|garage\|connection.*zone"

# Increase debug level (temporarily)
kubectl -n rook-ceph exec rook-ceph-tools-XXXX -- \
  ceph config set client.rgw debug_rgw 20/20

# Reset debug level
kubectl -n rook-ceph exec rook-ceph-tools-XXXX -- \
  ceph config set client.rgw debug_rgw 1/5
```

---

## Known Issues (Ceph v19 Squid)

| Issue                                                                      | Workaround                                                                                                                             |
| -------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `radosgw-admin zone get` shows `tier_type: null` even when set to `cloud`  | Check `period get` instead — it shows the correct value                                                                                |
| `radosgw-admin zonegroup set` strips `dest.zone` from pipe config JSON     | Use `sync group create`, `sync group flow create`, and `sync group pipe create` subcommands instead of editing zonegroup JSON directly |
| `radosgw-admin zone modify --tier-type=cloud` silently ignored on zone set | Set `--tier-type=cloud` on `zone create`, then use `tier-config` for connection details                                                |
| RGW logs `not syncing to/from zone` for cloud zone                         | Ensure zone has endpoints set to master RGW; commit period; restart RGW                                                                |
| `BucketAlreadyExists` (409) from MinIO/rustfs                              | Use Garage instead, or use an rclone-based cronjob (see [Alternative: rclone Cronjob](#alternative-rclone-cronjob-for-rustfs))        |

---

## Alternative: rclone Cronjob for Rustfs

Ceph RGW's built-in cloud sync is incompatible with rustfs (and MinIO) because these backends return `BucketAlreadyExists` (409) instead of `BucketAlreadyOwnedByYou` (200) when Ceph tries to create a bucket that already exists. For rustfs targets, use an rclone-based CronJob instead.

### Architecture

```
┌───────────────────────────┐            ┌───────────────────────────┐
│                           │   rclone    │                           │
│  Ceph RGW                 │   copy      │  Rustfs                   │
│  ┌─────────────────────┐  │ ─────────► │  ┌─────────────────────┐  │
│  │  openwebui-...      │  │   every     │  │  openwebui          │  │
│  │  (source bucket)    │  │   15 min    │  │  (dest bucket)      │  │
│  └─────────────────────┘  │            │  └─────────────────────┘  │
│                           │            │                           │
└───────────────────────────┘            └───────────────────────────┘
```

### How It Works

- A Kubernetes CronJob runs `rclone copy` every 15 minutes
- `rclone copy` (default) only copies new/changed files — nothing is deleted from the destination
- Change `SYNC_MODE=sync` to mirror source (deletes files removed from source)
- Source and destination credentials are pulled from Infisical via ExternalSecrets
- The rclone config is injected as environment variables from K8s Secrets

### Kubernetes Resources

The CronJob and related resources live in `kubernetes/infrastructure/base/storage/rook/sync/`:

| File              | Purpose                                                        |
| ----------------- | -------------------------------------------------------------- |
| `cronjob.yaml`    | CronJob running rclone every 15 minutes                        |
| `configmap.yaml`  | Sync script (copy or sync mode)                               |
| `secrets.yaml`    | ExternalSecrets for Ceph RGW and Rustfs S3 credentials         |
| `kustomization.yaml` | Kustomize manifest                                         |

### Infisical Secrets Required

Create these secrets in Infisical (project: `kubernetes`, environment: `prod`):

| Path                          | Key         | Value                                          |
| ----------------------------- | ----------- | ---------------------------------------------- |
| `/ceph/S3_SYNC_ACCESS_KEY`   | access_key  | Ceph RGW `s3-sync` user access key             |
| `/ceph/S3_SYNC_SECRET_KEY`   | secret_key  | Ceph RGW `s3-sync` user secret key             |
| `/rustfs/S3_ACCESS_KEY`       | access_key  | Rustfs S3 access key                            |
| `/rustfs/S3_SECRET_KEY`       | secret_key  | Rustfs S3 secret key                            |

### Ceph RGW User

A dedicated `s3-sync` user was created for the cronjob:

```bash
kubectl rook-ceph radosgw-admin user create \
  --uid=s3-sync \
  --display-name="S3 Sync CronJob" \
  --max-buckets=100

# Grant read access to all buckets
kubectl rook-ceph radosgw-admin caps add \
  --uid=s3-sync --caps="buckets=*"

# Link specific buckets to the user
kubectl rook-ceph radosgw-admin bucket link \
  --bucket=openwebui-7ace3b18-7171-4b67-b74e-57cce30ae1e6 \
  --uid=s3-sync
```

### Configuration

Key settings in `cronjob.yaml`:

| Setting          | Default                                                       | Description                                          |
| ---------------- | -------------------------------------------------------------- | ---------------------------------------------------- |
| `SRC_BUCKET`     | `openwebui-7ace3b18-7171-4b67-b74e-57cce30ae1e6`              | Source bucket on Ceph RGW                            |
| `DST_BUCKET`     | `openwebui`                                                    | Destination bucket on Rustfs                          |
| `SYNC_MODE`      | `copy`                                                         | `copy` (safe) or `sync` (mirror, deletes removed files) |
| `schedule`       | `*/15 * * * *`                                                 | Cron schedule (every 15 minutes)                     |

### Adding Another Bucket

Copy the CronJob and change the bucket names:

```yaml
# In the new CronJob, update:
- name: SRC_BUCKET
  value: "my-other-bucket"       # Source bucket on Ceph RGW
- name: DST_BUCKET
  value: "my-other-bucket-backup" # Destination bucket on Rustfs
```

Or link the additional bucket to the `s3-sync` user:

```bash
kubectl rook-ceph radosgw-admin bucket link \
  --bucket=my-other-bucket \
  --uid=s3-sync
```

### Manual Sync

To trigger a sync outside the cron schedule:

```bash
kubectl create job --from=cronjob/ceph-rgw-sync manual-sync-$(date +%s) -n rook-ceph
```

### Viewing Logs

```bash
# List recent jobs
kubectl get jobs -n rook-ceph

# View logs for a specific job
kubectl logs -n rook-ceph job/manual-sync-XXXXX

# View CronJob status
kubectl describe cronjob ceph-rgw-sync -n rook-ceph
```
