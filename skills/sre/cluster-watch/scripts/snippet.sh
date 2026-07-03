#!/bin/sh
# Fetches a FOCUSED status snippet for one issue's resource — just the fields relevant to
# understanding the failure (container state/lastState/restartCount/image, or the specific
# node condition), not the whole pod/node object. A full `-o yaml` dump of status was
# measured at ~1.5-2KB per issue; with several issues in one digest that blew past Telegram's
# 4096-char message limit (a real, live-measured problem: an unfiltered 9-issue digest came
# to ~33KB). This trades completeness for something that actually fits in an alert.
#
# Usage: snippet.sh <namespace> <resource> [container-name]
# Prints a short YAML-like snippet to stdout. Read-only. Never fails hard.
set -eu

NAMESPACE="${1:?usage: snippet.sh <namespace> <resource> [container]}"
RESOURCE="${2:?usage: snippet.sh <namespace> <resource> [container]}"
CONTAINER="${3:-}"

if [ "$NAMESPACE" = "-" ]; then
  kubectl get node "$RESOURCE" -o json --request-timeout=8s 2>/dev/null | jq -r '
    .status.conditions[] | select(.status != "True" or .type == "Ready") |
    "type: " + .type + "\nstatus: " + .status + "\nreason: " + (.reason // "-") +
    "\nmessage: " + (.message // "-")
  ' | head -c 500 || echo "(snippet unavailable)"
  exit 0
fi

kubectl get pod "$RESOURCE" -n "$NAMESPACE" -o json --request-timeout=8s 2>/dev/null | jq -r --arg c "$CONTAINER" '
  (.status.containerStatuses // [])
  | (if $c != "" then map(select(.name == $c)) else . end)
  | (if length > 0 then . else (.status.containerStatuses // []) end)
  | (.[0] // {}) as $cs |
  "image: " + ($cs.image // "unknown") +
  "\nrestartCount: " + (($cs.restartCount // 0) | tostring) +
  "\nstate: " + (($cs.state // {}) | to_entries | map(.key) | join(",") ) +
  (if $cs.state.waiting then "\nwaiting.reason: " + ($cs.state.waiting.reason // "-") +
     "\nwaiting.message: " + ($cs.state.waiting.message // "-") else "" end) +
  (if $cs.state.terminated then "\nterminated.reason: " + ($cs.state.terminated.reason // "-") +
     "\nterminated.exitCode: " + (($cs.state.terminated.exitCode // 0) | tostring) else "" end) +
  (if $cs.lastState.terminated then "\nlastState.terminated.reason: " + ($cs.lastState.terminated.reason // "-") +
     "\nlastState.terminated.exitCode: " + (($cs.lastState.terminated.exitCode // 0) | tostring) else "" end)
' 2>/dev/null | head -c 500 || echo "(snippet unavailable)"
