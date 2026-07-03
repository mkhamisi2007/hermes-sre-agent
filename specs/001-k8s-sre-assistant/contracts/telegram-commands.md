# Contract: Telegram Operator Interface

The Telegram bot is the sole operator surface. All inbound interactions are authorized against
`TELEGRAM_ALLOWED_USERS` before any processing (FR-007). Unauthorized senders receive a rejection
and nothing is acted upon (SC-006).

## Inbound: free-form questions

- **Sender**: allowlisted chat ID.
- **Message**: natural language (e.g., "why is payments restarting?", "list not-ready pods").
- **Handling**: routed to `k8s-query`; read-only answer returned. Mutating intent → refusal +
  pointer to `remediation-proposer`.

## Inbound: skill upload

- **Sender**: allowlisted chat ID.
- **Message**: a `SKILL.md` file (optionally a small bundle) sent as a document.
- **Handling**:
  1. Received into `data/.hub/quarantine/` with `state = pending` (never auto-activated).
  2. Validated (front matter present/parseable; safe structure). Invalid → rejected, active skills
     unchanged (US4 AS3).
  3. Agent replies asking the operator to approve or reject.
  4. On explicit approval → moved into `skills/` (hot-reloaded), `state = approved`, logged to
     `audit.log`. On rejection → discarded.
- **Maps to**: FR-011, FR-012, FR-013, FR-017; Principle III.

## Inbound: remediation approval / rejection

- **Sender**: allowlisted chat ID.
- **Message**: approve or reject a specific pending proposal (referenced by id).
- **Handling**: only an explicit approval permits the proposed action to proceed; approval + outcome
  logged. No approval ⇒ no mutation (SC-005).

## Outbound: alerts

- **To**: allowlisted chat ID(s).
- **Content**: issue summary (what/where/why), grouped during floods; `unreachable` notice when the
  cluster can't be reached.
- **Dedup**: at most one alert per active issue until status materially changes (SC-003).

## Rejection contract

Any inbound message from a non-allowlisted sender → single rejection reply, no side effects, event
recorded. This is the enforcement point for FR-007 / SC-006.
