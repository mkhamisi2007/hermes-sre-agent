#!/bin/sh
# Read-only cluster snapshot for the cluster-watch skill.
# Emits three JSON documents to stdout-separated files under $OUT_DIR, or a single
# "unreachable" marker file if the API cannot be reached after retries.
#
# Usage: collect.sh <out_dir>
set -eu

OUT_DIR="${1:?usage: collect.sh <out_dir>}"
mkdir -p "$OUT_DIR"

try_collect() {
  kubectl get pods -A -o json --request-timeout=10s > "$OUT_DIR/pods.json" &&
  kubectl get nodes -o json --request-timeout=10s > "$OUT_DIR/nodes.json" &&
  kubectl get events -A --sort-by=.lastTimestamp -o json --request-timeout=10s > "$OUT_DIR/events.json"
}

# Up to 3 attempts with backoff before declaring the cluster unreachable. A single retry
# proved too fragile in practice — a transient DNS/connection blip produced a false-positive
# "unreachable" alert during live validation (see tasks.md T015 note).
attempt=1
while [ "$attempt" -le 3 ]; do
  if try_collect; then
    rm -f "$OUT_DIR/UNREACHABLE"
    exit 0
  fi
  sleep $((attempt * 3))
  attempt=$((attempt + 1))
done

echo "cluster unreachable at $(date -u +%Y-%m-%dT%H:%M:%SZ) after 3 attempts" > "$OUT_DIR/UNREACHABLE"
exit 1
