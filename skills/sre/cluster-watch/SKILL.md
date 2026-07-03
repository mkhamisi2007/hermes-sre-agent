---
name: cluster-watch
description: Periodically inspects the Kubernetes cluster read-only, detects abnormal conditions, and sends deduplicated Telegram alerts.
version: 1.0.0
platforms: [linux]
metadata:
  hermes:
    tags: [kubernetes, sre, monitoring]
    category: sre
    config:
      - key: sre.monitor_interval
        description: "Cron schedule for cluster inspection"
        default: "*/5 * * * *"
        prompt: "How often should the cluster be checked?"
---

# Cluster Watch

## When to Use

Run on the schedule registered via `/cron` (see Procedure step 4). Do not invoke this skill directly
for one-off questions — that's `k8s-query`. This skill's `kubectl` usage MUST remain read-only
(`get`/`list`/`watch` only); the mounted kubeconfig is RBAC-restricted to enforce this regardless.

## Procedure

This skill runs as a **deterministic `--no-agent` cron job**, not an LLM-driven turn: the LLM
proved unreliable at the simple "stay silent unless there's something new" instruction during
validation (a small local model occasionally suppressed genuine new issues). Detection and dedup
correctness must not depend on model instruction-following, so the whole pipeline below is plain
shell + `kubectl` + `jq`, and its stdout is delivered verbatim (empty stdout = no message sent —
the standard watchdog pattern).

1. **Collect** cluster state using read-only `kubectl` (`scripts/collect.sh`):
   - `kubectl get pods -A -o json`
   - `kubectl get nodes -o json`
   - `kubectl get events -A --sort-by=.lastTimestamp -o json` (recent window only)
2. **Classify** raw output into `Issue` records (`scripts/classify.sh`), one per abnormal
   condition:
   - `crashloop`: a container's `waiting.reason == CrashLoopBackOff`
   - `restarts`: `restartCount` above a small threshold (default 5) within a short window
   - `pending`: pod `phase == Pending` for longer than one cycle, or `Unschedulable` condition
   - `node_not_ready`: a node's `Ready` condition is `False`/`Unknown`
   - `warning_event`: an Event with `type == Warning`
   - Each Issue's identity is `{type}:{namespace}/{resource}` (or `{type}:node/{node}`).
3. **Reconcile against state** in `data/sre-state/issues.json` (`scripts/reconcile.sh`):
   - New or materially-changed issue (severity increased) → mark for alerting.
   - Persisting issue → update `last_seen`, do NOT re-alert (dedup, FR-004/SC-003).
   - Issue no longer observed this cycle → transition to `resolved`, no alert.
   - If `collect` failed entirely (API unreachable) → produce a single `unreachable` issue instead
     of any per-resource issues this cycle (FR-005).
4. **Enrich + format** (`scripts/format-digest.sh`): issues are sorted critical-first, and each
   gets, budget-permitting:
   - A focused status snippet (`scripts/snippet.sh`) — the specific container's
     image/restartCount/state/lastState, or the relevant node condition. Deliberately NOT a full
     `-o yaml` dump: that was measured at ~1.5-2KB per issue and blew past Telegram's 4096-char
     message limit with more than a couple of issues.
   - A proposed fix (`scripts/propose-fix.sh`) — a single, isolated call straight to Ollama (NOT
     routed through Hermes' agent loop), with a 12s timeout and a deterministic per-type fallback
     if the call fails. Output is capped at 280 chars and labeled "AI-generated — verify before
     running": live testing showed the local `llama3.2:latest` model sometimes invents plausible
     but wrong or nonexistent commands (e.g. `kubectl rollingupdate`, `docker-compose restart
     --force etcd` for a static pod) — treat suggestions as a starting point, not a script to run.
   - Issues beyond a ~2200-char running budget get a compact one-line summary instead of full
     enrichment (no snippet/LLM call for those — also avoids burning an LLM call with no room to
     show the answer). Prints nothing if there's nothing new (FR-016 flood grouping).
5. **Deliver**: registered via
   `hermes cron create "$MONITOR_INTERVAL" --no-agent --script cluster-watch-run.sh --deliver telegram:$TELEGRAM_ALLOWED_USERS --name sre-cluster-watch`
   (note: `--script` paths are relative to `~/.hermes/scripts/` already — passing
   `scripts/cluster-watch-run.sh` instead of `cluster-watch-run.sh` silently doubles the path and
   the job fails with "Script not found") run from `data/scripts/cluster-watch-run.sh`, which
   chains steps 1-4. Empty output = nothing sent this cycle.
6. **Hand off to runbook**: for each newly-alerted issue, invoke the `runbook` skill to record or
   update the corresponding runbook note (FR-009, FR-010). (Currently manual/operator-triggered;
   see tasks.md T027 for wiring this automatically.)
7. **Log**: append one line per detection/alert to `data/skills/.hub/audit.log`
   (what was detected, what was sent, when). (Currently the cron job itself is the audit trail via
   `hermes cron list`/logs; a dedicated audit.log line is a follow-up — see tasks.md T017.)

## Pitfalls

- Do not widen the mounted kubeconfig's RBAC to allow writes — remediation is a separate,
  human-approved flow (`remediation-proposer`). This skill must never mutate the cluster.
- Don't alert once per resource per cycle during a flood — always group (step 4).
- A transient single `kubectl` timeout is not the same as `unreachable`; retry (3 attempts with
  backoff) before declaring the cluster unreachable, to avoid false-positive outage alerts — a
  single retry proved too fragile live (one real transient blip produced a false "unreachable").
- `--no-agent` cron scripts run as the `hermes` user (`$HOME=/opt/data/home`), not `root` —
  `kubectl`'s default `$HOME/.kube/config` lookup misses entirely for that user and silently falls
  back to the insecure `localhost:8080` default. `KUBECONFIG` must be set as a container-wide
  environment variable (see docker-compose.yml), not rely on the default per-user lookup path.
- Telegram caps messages at 4096 chars and `--no-agent` delivery sends stdout as ONE message with
  no auto-splitting — don't remove the enrichment budget in `format-digest.sh` without re-checking
  real digest size against several simultaneous issues.

## Verification

Deploy a workload that crash-loops. Within one scheduled cycle, confirm a Telegram alert names the
pod, namespace, and `crashloop` condition. Confirm the next cycle sends no duplicate. Delete the
workload and confirm the following cycle sends no alert for it. Stop the cluster API briefly and
confirm a single `unreachable` notice is sent instead of silence or a flood of per-resource errors.
