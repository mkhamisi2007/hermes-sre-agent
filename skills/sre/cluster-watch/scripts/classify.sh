#!/bin/sh
# Classify the JSON snapshot from collect.sh into newline-delimited Issue JSON objects.
# Each line: {"id":..., "type":..., "resource":..., "namespace":..., "severity":..., "detail":...}
#
# Usage: classify.sh <snapshot_dir>
# Requires: jq
set -eu

DIR="${1:?usage: classify.sh <snapshot_dir>}"

if [ -f "$DIR/UNREACHABLE" ]; then
  jq -n '{id:"unreachable:cluster", type:"unreachable", resource:"cluster", namespace:"-",
          severity:"critical", detail:"kubectl could not reach the API server after retry"}'
  exit 0
fi

RESTART_THRESHOLD=5

# crashloop + restarts, from container statuses across all pods
jq -c '
  .items[] as $pod |
  ($pod.status.containerStatuses // [])[] as $cs |
  [
    (if ($cs.state.waiting.reason? // "") == "CrashLoopBackOff" then
      {id: ("crashloop:" + $pod.metadata.namespace + "/" + $pod.metadata.name),
       type: "crashloop", resource: $pod.metadata.name, namespace: $pod.metadata.namespace,
       severity: "critical",
       detail: ("container " + $cs.name + " is in CrashLoopBackOff")}
     else empty end),
    (if ($cs.restartCount // 0) > '"$RESTART_THRESHOLD"' then
      {id: ("restarts:" + $pod.metadata.namespace + "/" + $pod.metadata.name),
       type: "restarts", resource: $pod.metadata.name, namespace: $pod.metadata.namespace,
       severity: "warning",
       detail: ("container " + $cs.name + " has restarted " + ($cs.restartCount|tostring) + " times")}
     else empty end)
  ][]
' "$DIR/pods.json"

# pending / unschedulable pods
jq -c '
  .items[] |
  select(.status.phase == "Pending") |
  {id: ("pending:" + .metadata.namespace + "/" + .metadata.name),
   type: "pending", resource: .metadata.name, namespace: .metadata.namespace,
   severity: "warning",
   detail: ("pod has been Pending" +
     (if ([.status.conditions[]? | select(.type=="PodScheduled" and .status=="False")] | length > 0)
      then " (unschedulable: " + ([.status.conditions[]? | select(.type=="PodScheduled" and .status=="False") | .message][0] // "unknown") + ")"
      else "" end))}
' "$DIR/pods.json"

# node not-ready
jq -c '
  .items[] |
  select([.status.conditions[]? | select(.type=="Ready" and .status!="True")] | length > 0) |
  {id: ("node_not_ready:node/" + .metadata.name),
   type: "node_not_ready", resource: .metadata.name, namespace: "-",
   severity: "critical",
   detail: ("node Ready condition is " + ([.status.conditions[]? | select(.type=="Ready") | .status][0] // "Unknown"))}
' "$DIR/nodes.json"

# warning events (recent window only; caller may pre-filter by time)
jq -c '
  .items[] |
  select(.type == "Warning") |
  {id: ("warning_event:" + (.involvedObject.namespace // "-") + "/" + .involvedObject.name),
   type: "warning_event", resource: .involvedObject.name, namespace: (.involvedObject.namespace // "-"),
   severity: "info",
   detail: (.reason + ": " + .message)}
' "$DIR/events.json"
