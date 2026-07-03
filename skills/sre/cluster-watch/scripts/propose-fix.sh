#!/bin/sh
# Proposes a fix for one issue by calling the local Ollama model directly (bypassing Hermes'
# agent loop entirely - this is a single, isolated completion call, not a conversation turn).
# Deliberately separate from the detection/dedup path: that path stays 100% deterministic
# (see collect.sh/classify.sh/reconcile.sh) because live testing showed the local model
# unreliable at simple "alert or stay silent" judgment calls. Proposing a fix for an ALREADY
# CONFIRMED real issue is a different, lower-risk task (explanation, not gating), and this
# script has a hard timeout plus a deterministic per-type fallback so a bad/slow model
# response can never block or degrade an alert.
#
# Usage: propose-fix.sh <issue-type> <detail-text>
# Prints a short plain-text suggestion to stdout. Never fails (always prints something).
set -u

ISSUE_TYPE="${1:-unknown}"
DETAIL="${2:-}"
TIMEOUT_SECONDS=12

fallback() {
  case "$ISSUE_TYPE" in
    crashloop)
      echo "Check logs from the previous crash: kubectl logs <pod> -n <namespace> --previous. Verify the image, command/args, and any required config or secrets are present.";;
    restarts)
      echo "Investigate why the container keeps restarting: check for OOMKilled (resource limits), a failing liveness probe, or recent error logs.";;
    pending)
      echo "Check node capacity/taints and the pod's resource requests. The PodScheduled condition message usually names the exact scheduling blocker.";;
    node_not_ready)
      echo "Run kubectl describe node <node> to check kubelet health, disk/memory pressure, and network connectivity.";;
    warning_event)
      echo "Review the event message for the root cause - commonly a volume/mount, image pull, or permissions issue.";;
    unreachable)
      echo "Verify the Kubernetes API server is reachable (Docker Desktop running, kubeconfig valid).";;
    *)
      echo "Investigate the resource directly with kubectl describe for full details.";;
  esac
}

BASE_URL="${LLM_BASE_URL:-}"
MODEL="${LLM_MODEL_NAME:-}"
[ -z "$BASE_URL" ] || [ -z "$MODEL" ] && { fallback; exit 0; }

PROMPT=$(printf 'A Kubernetes issue was detected.\nType: %s\nDetail: %s\n\nIn 2-3 sentences, propose a concrete, specific troubleshooting/fix step. Be direct and actionable, no preamble.' "$ISSUE_TYPE" "$DETAIL")

REQUEST_BODY=$(jq -n --arg model "$MODEL" --arg prompt "$PROMPT" \
  '{model: $model, messages: [{role: "user", content: $prompt}], stream: false, max_tokens: 120}')

RESPONSE=$(curl -s -m "$TIMEOUT_SECONDS" -X POST "$BASE_URL/chat/completions" \
  -H "Content-Type: application/json" \
  -d "$REQUEST_BODY" 2>/dev/null)

SUGGESTION=$(printf '%s' "$RESPONSE" | jq -r '.choices[0].message.content // empty' 2>/dev/null)

if [ -n "$SUGGESTION" ] && [ "$SUGGESTION" != "null" ]; then
  # Hard cap regardless of max_tokens — response length in chars is unpredictable and this
  # feeds a message-length-budgeted digest (see format-digest.sh). Truncate at a sentence-ish
  # boundary rather than mid-word where possible.
  printf '%s\n' "$SUGGESTION" | cut -c1-280
else
  fallback
fi
