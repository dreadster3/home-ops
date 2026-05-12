#!/bin/sh
set -euo pipefail

echo "=== OpenWebUI S3 Sync ==="
echo "Started at: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"

: "${SRC_REMOTE:?SRC_REMOTE is required}"
: "${DST_REMOTE:?DST_REMOTE is required}"
: "${SRC_BUCKET:?SRC_BUCKET is required}"
: "${DST_BUCKET:?DST_BUCKET is required}"

# Optional: limit sync to a path within the bucket
# e.g. SRC_PATH=images -> syncs only s3://bucket/images/
SRC_PATH="${SRC_PATH:-}"
DST_PATH="${DST_PATH:-}"

SYNC_MODE="${SYNC_MODE:-copy}"

src="${SRC_REMOTE}:${SRC_BUCKET}"
dst="${DST_REMOTE}:${DST_BUCKET}"

if [ -n "${SRC_PATH}" ]; then
  src="${src}/${SRC_PATH}"
fi
if [ -n "${DST_PATH}" ]; then
  dst="${dst}/${DST_PATH}"
fi

echo "  Source:      ${src}"
echo "  Destination: ${dst}"
echo "  Mode:        ${SYNC_MODE}"

if [ "${SYNC_MODE}" = "sync" ]; then
  echo "  sync: destination will mirror source"
  rclone sync \
    "${src}" \
    "${dst}" \
    --verbose \
    --stats-one-line \
    --stats=30s
else
  echo "  copy: only new/changed files, nothing deleted"
  rclone copy \
    "${src}" \
    "${dst}" \
    --verbose \
    --stats-one-line \
    --stats=30s
fi

echo "=== Sync completed at: $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="