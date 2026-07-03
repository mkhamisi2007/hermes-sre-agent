---
name: runbook
description: Records and retrieves runbook knowledge (symptom/cause/remediation) as Markdown notes in the local Obsidian vault.
version: 1.0.0
platforms: [linux]
metadata:
  hermes:
    tags: [kubernetes, sre, knowledge-base]
    category: sre
---

# Runbook

## When to Use

Invoked by `cluster-watch` after a new alert, by `k8s-query` when a diagnosis is reached, or by
`remediation-proposer` once an issue is resolved. Also consult it proactively: before answering a
question about a recurring issue, check for an existing note first.

## Procedure

Writing and reading are both **deterministic scripts**, not LLM-driven steps — same reliability
pattern as `cluster-watch` (a small local model can't be trusted to remember to look something up
or to write consistent front matter every time).

1. **Write** (`scripts/write-note.sh`): called automatically from `cluster-watch`'s digest
   formatting for every alerted issue. One note per issue **type** (not per specific resource) at
   `obsidian/runbooks/<type>.md`. First occurrence creates the note with `Cause: Unknown —
   captured automatically...`; later occurrences increment `occurrences`, bump `updated`, and
   append a dated entry under `## Recurrence Log` (capped at the most recent 10 entries so the
   file doesn't grow unbounded — see `scripts/trim-recurrences.awk`).
2. **Look up** (`scripts/lookup-note.sh <issue_type>`): called from `cluster-watch` (before writing,
   so it reflects prior history) and should be called from `k8s-query` before answering a question
   about a matching issue type. Returns JSON: `{"exists", "verified", "occurrences", "cause",
   "remediation"}`.
3. **The `verified` flag is the whole point**: it's `true` only if a human has actually edited the
   `## Cause` section away from the automated placeholder text. Treat `verified: true` as
   established knowledge worth stating directly; treat `verified: false` as an unconfirmed first
   guess — mention it exists, don't present it as fact. This is what separates "the system
   remembers what happened" from "the system re-states its own earlier guess as if it were true."
4. Notes are plain Markdown files inside the project directory — they remain readable and editable
   outside the agent (FR-018) and are never deleted automatically. **Editing the `## Cause` section
   by hand is how a note becomes `verified` — this is the intended way for an operator to teach the
   system, not something the agent does on its own.**

## Pitfalls

- Don't create a new note per occurrence — always look up first and update in place (SC-007 measures
  "a runbook note is available", not one-per-incident).
- Don't put executable remediation steps that could be blindly copy-run without context; keep
  `remediation` descriptive and pair it with `remediation-proposer` for actual execution.

## Verification

Trigger a diagnosis and confirm a note appears under `obsidian/runbooks/`. Trigger the same issue
again and confirm the existing note's `occurrences` increments rather than a duplicate note being
created, and that a later question about the same issue references it.
