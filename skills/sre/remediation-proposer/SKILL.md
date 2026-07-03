---
name: remediation-proposer
description: Proposes concrete remediation steps for a cluster issue and requires explicit human approval before anything executes.
version: 1.0.0
platforms: [linux]
metadata:
  hermes:
    tags: [kubernetes, sre, remediation]
    category: sre
---

# Remediation Proposer

## When to Use

Invoked whenever `k8s-query` or `cluster-watch` identifies a fix-shaped request or a known issue with
a candidate remediation. This is the ONLY path in the system that may lead to a cluster mutation —
and even here, this skill itself never mutates anything. It proposes; a human approves; only then
does an already-approved action proceed. This enforces Constitution Principle III
(Human-in-the-Loop Remediation, NON-NEGOTIABLE).

## Procedure

1. **Compose the proposal**: state the exact command(s) or manifest change that would resolve the
   issue, in full (no placeholders), plus:
   - **Effect**: what will change.
   - **Blast radius**: what else could be affected (namespace scope, other workloads, downtime).
   - **Reversibility**: how to undo it if it goes wrong.
2. **Request approval**: send the proposal to the requesting/allowlisted operator via Telegram and
   wait for an explicit approve/reject reply referencing this proposal. A proposal with no response
   is treated as not approved — never proceed on silence or ambiguity (FR-008, SC-005).
3. **On approval**: the operator-approved action is the one that proceeds (this skill documents and
   hands off the exact approved step; it does not silently substitute a different action). Record
   the approval (who, when, what) before anything runs.
4. **On rejection or timeout**: discard the proposal, take no action, and confirm to the operator
   that nothing was changed.
5. **Log everything**: append the proposal, the approval/rejection, and the outcome to
   `data/skills/.hub/audit.log` (FR-017, Principle V).
6. **Hand off to runbook**: once resolved, invoke `runbook` to capture the remediation for reuse
   (FR-010).

## Pitfalls

- Never execute a mutating command as part of "showing what would happen" — dry-run output is fine
  to include in the proposal, but nothing that actually changes cluster state runs before approval.
- Don't accept a vague "ok" as approval for an unrelated or previously-unstated action — approval
  must map to the specific proposal shown.
- Don't silently expand scope (e.g., proposing to delete one pod but approval-executing a
  broader `kubectl delete` selector).

## Verification

Request a fix for a known issue — a proposal is returned naming the exact command, effect, and
blast radius, and no cluster mutation occurs until an explicit approval is given. Reject a proposal
— confirm nothing changed and the rejection is logged.
