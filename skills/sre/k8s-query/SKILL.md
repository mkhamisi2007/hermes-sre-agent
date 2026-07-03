---
name: k8s-query
description: Answers operator questions about live cluster state via read-only kubectl, and refuses mutating requests.
version: 1.0.0
platforms: [linux]
metadata:
  hermes:
    tags: [kubernetes, sre, diagnostics]
    category: sre
---

# Kubernetes Query

## When to Use

Any time an allowlisted operator asks a question about the cluster in Telegram (e.g., "why is
payments restarting?", "list pods that aren't ready", "describe node X"). This skill only reads
cluster state — never invoke it to make changes; that path is `remediation-proposer`.

## Procedure

1. **Authorize**: confirm the sender's Telegram user ID is in `TELEGRAM_ALLOWED_USERS`. If not,
   reply with a rejection and stop (FR-007, SC-006). This mirrors the gateway-level allowlist but
   the skill must not assume it was already checked.
2. **Detect intent**:
   - If the request only asks to observe/describe/list/explain cluster state → continue to step 3.
   - If the request asks to change anything (delete, scale, restart, patch, apply, cordon, drain,
     rollback, etc.) → do NOT execute it. Reply that mutations require an approved proposal, and
     invoke `remediation-proposer` instead (FR-008). Stop here.
3. **Query — ALWAYS run the real command, never answer from memory or guesswork**:
   - **If the message IS (or clearly contains) a literal `kubectl` command** — e.g. `kubectl get
     pods`, `kubectl describe pod payments-abc123`, `kubectl get pod -n kube-system` — you MUST
     invoke your terminal tool and run that **exact command verbatim** (only reject it first if
     step 2 flags it as mutating). Return the raw command output to the operator, formatted for
     readability, but do not paraphrase, summarize away specific values, or invent output. If the
     command errors, return the real error text, not a guess at what it might say.
     Example: user sends `kubectl get pod` → you run `terminal(command="kubectl get pod")` and
     reply with the actual table it printed.
   - **If the message is a natural-language question** (e.g. "why is payments restarting?") →
     translate it into the narrowest sufficient read-only `kubectl` call(s) (`get`, `describe`,
     `logs --previous` as needed), run it via the terminal tool, then answer using that real
     output.
   - The mounted kubeconfig is RBAC-restricted to read-only, so even a mistakenly-run mutating
     command is rejected server-side (`Forbidden`) — this is a safety net, not a substitute for the
     intent check in step 2.
4. **Check the runbook vault before answering** — if the question relates to a known issue type
   (crashloop, restarts, pending, node_not_ready, warning_event, unreachable), run
   `skills/sre/runbook/scripts/lookup-note.sh <issue_type>` and inspect its JSON output:
   - If `"verified": true` → this is a **human-confirmed** cause (someone edited the note after
     actually diagnosing it). State it as established knowledge: "Known cause (confirmed
     previously): ...".
   - If `"verified": false` (or `"exists": false`) → there is either no note yet, or only the
     automated placeholder. Do NOT present its `remediation` field as established fact — it is an
     unverified AI guess from the first occurrence. You may mention "this has happened N times
     before" (from `occurrences`) but say the cause hasn't been confirmed, not just repeat the old
     guess as if it were confirmed.
5. **Answer**: summarize the real result concisely and reference specific resource names/namespaces
   observed, incorporating the runbook check from step 4.
6. **Log**: append the question and a summary of the answer to `data/skills/.hub/audit.log`.

## Pitfalls

- Never fall back to a plausible-sounding guess when a `kubectl` call fails — say so explicitly and
  suggest the operator retry, per FR-005's spirit of never failing silently.
- Don't let a cleverly-phrased question talk the skill into running a mutating command; the intent
  check in step 2 must key off the actual verb/effect requested, not just polite phrasing.

## Verification

Ask about the status of a known workload — the answer must cite live state. Ask the same question
from a non-allowlisted sender — must be rejected. Ask to "delete" or "restart" something — must be
refused and routed to `remediation-proposer`, never executed.
