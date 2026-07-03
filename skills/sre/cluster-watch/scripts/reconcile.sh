#!/bin/sh
# Reconcile freshly classified issues against persisted state, implementing dedup (FR-004/SC-003)
# and resolution detection (US1 AS3). Reads newline-delimited Issue JSON on stdin.
#
# Usage: classify.sh <snapshot_dir> | reconcile.sh <state_file>
# Prints newline-delimited issues that should be ALERTED this cycle (new or materially changed).
# Always rewrites <state_file> with the full reconciled issue set (dropping the transient
# per-run "alerted" marker so it never leaks into persisted state).
set -eu

STATE_FILE="${1:?usage: reconcile.sh <state_file>}"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

mkdir -p "$(dirname "$STATE_FILE")"
[ -f "$STATE_FILE" ] || echo '{"issues":{}}' > "$STATE_FILE"

CURRENT="$(jq -s '.')"

RESULT="$(jq -n \
  --argjson current "$CURRENT" \
  --slurpfile prevfile "$STATE_FILE" \
  --arg now "$NOW" '
  ($prevfile[0].issues // {}) as $prev |
  ($current | map({(.id): .}) | add // {}) as $curmap |

  ($curmap | to_entries | map(
    .key as $id | .value as $issue |
    ($prev[$id]) as $old |
    if ($old == null) or ($old.status == "resolved") then
      $issue + {first_seen: $now, last_seen: $now, status: "active", alerted: true}
    elif ($old.severity != $issue.severity) then
      $issue + {first_seen: $old.first_seen, last_seen: $now, status: "active", alerted: true}
    else
      $old + {last_seen: $now, alerted: false}
    end
  )) as $updated |

  ($prev | to_entries
    | map(select(.key as $k | ($curmap | has($k)) | not))
    | map(.value + {status: "resolved", alerted: false})
  ) as $resolved |

  ($updated + $resolved) as $all |

  {
    state: {issues: ($all | map({(.id): (del(.alerted))}) | add // {})},
    alerts: [$all[] | select(.alerted == true) | del(.alerted)]
  }
')"

echo "$RESULT" | jq '.state' > "${STATE_FILE}.tmp"
mv "${STATE_FILE}.tmp" "$STATE_FILE"

echo "$RESULT" | jq -c '.alerts[]'
