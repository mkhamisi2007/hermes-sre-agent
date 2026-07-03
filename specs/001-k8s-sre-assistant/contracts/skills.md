# Contract: SRE Skills (`SKILL.md`)

Each skill is a Hermes `SKILL.md` (YAML front matter + Markdown body: `When to Use`, `Procedure`,
`Pitfalls`, `Verification`) under `skills/sre/`. Helper scripts under a skill's `scripts/` MUST be
**read-only** against the cluster. Contracts below define required behavior, not full implementations.

## `cluster-watch` (P1 — monitoring & alerting)

- **Trigger**: Hermes cron, cadence from `MONITOR_INTERVAL` (default `*/5 * * * *`).
- **Inputs**: read-only `kubectl` (pods across namespaces, nodes, recent events); dedup state file
  `data/sre-state/issues.json`.
- **Behavior**:
  - Classify conditions → `Issue` records (see data-model): crashloop, high restarts, pending/
    unschedulable, node NotReady, warning events.
  - Compare against prior state: new/materially-changed issues → alert; persisting issues → update
    `last_seen`, no re-alert; disappeared issues → mark `resolved`.
  - On kubectl failure/unreachable cluster → emit one `unreachable` alert (FR-005).
  - Group multiple new issues in one cycle into a single digest message (FR-016).
- **Outputs**: Telegram alert(s) to allowlisted chats; updated state file; audit log line.
- **Verification**: Deploy a crashing pod → within one cycle an alert names pod+namespace+condition;
  second cycle sends no duplicate; deleting the pod stops alerts.
- **Maps to**: FR-001–FR-005, FR-016; SC-001, SC-002, SC-003.

## `k8s-query` (P2 — conversational diagnostics)

- **Trigger**: operator message in Telegram (allowlisted sender only).
- **Inputs**: natural-language question; read-only `kubectl`.
- **Behavior**: translate question → read-only cluster query → concise answer citing real state. If
  the request implies a mutation, respond that it must go through the remediation-proposer with human
  approval (never act).
- **Outputs**: Telegram reply.
- **Verification**: Ask status of a known workload → reply reflects live state; unauthorized sender →
  rejected; mutating request → refusal + guidance.
- **Maps to**: FR-006, FR-007, FR-008; SC-004, SC-006.

## `runbook` (P3 — knowledge capture & reuse)

- **Trigger**: invoked after a diagnosis (by `cluster-watch`/`k8s-query`) or explicitly by operator.
- **Inputs**: issue details; existing notes in `obsidian/runbooks/` (RAG).
- **Behavior**: create/update a Markdown `Runbook Note` (symptom/cause/remediation); on recurrence,
  increment `occurrences` and surface the existing note in responses.
- **Outputs**: Markdown file in the Obsidian vault; reference included in agent replies.
- **Verification**: Trigger diagnosis → note appears in `obsidian/runbooks/`; recurrence → response
  references it; note is readable/editable outside the agent.
- **Maps to**: FR-009, FR-010, FR-018; SC-007.

## `remediation-proposer` (HITL — propose, never apply)

- **Trigger**: operator asks for a fix, or a `cluster-watch` issue has a known remediation.
- **Inputs**: issue + matching runbook remediation.
- **Behavior**: produce a concrete proposal (the exact command(s)/manifest and blast radius) and
  request explicit approval. MUST NOT execute any mutating action itself. If approved, the operator
  runs it (or an explicitly-approved step proceeds); the proposal, approval, and outcome are logged.
- **Outputs**: Telegram proposal message; audit log entry.
- **Verification**: Request a fix → proposal returned with effect + blast radius, no cluster change
  occurs without an approval step.
- **Maps to**: FR-008, FR-017; SC-005. Enforces Constitution Principle III.

## Front-matter contract (all skills)

```yaml
---
name: <skill-name>
description: <one line>
version: 1.0.0
platforms: [linux]
metadata:
  hermes:
    tags: [kubernetes, sre]
    category: devops
---
```
