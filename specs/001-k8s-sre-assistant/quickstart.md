# Quickstart & Validation: Kubernetes SRE Assistant

End-to-end validation that the feature works. Details live in [plan.md](./plan.md),
[data-model.md](./data-model.md), and [contracts/](./contracts/). This guide is run-and-observe, not
implementation.

## Prerequisites

- Docker Desktop (macOS) running, with a kubeadm Kubernetes cluster reachable at
  `https://host.docker.internal:6443`.
- Ollama running on the host with a chat model pulled (e.g. `ollama pull qwen2.5:14b`), serving on
  `:11434`.
- A Telegram bot token (from @BotFather) and your Telegram numeric chat ID.

## Setup

1. Copy config template and fill secrets:
   - `cp .env.example .env`, then set `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS`,
     `LLM_MODEL_NAME`, and confirm `LLM_BASE_URL=http://host.docker.internal:11434/v1`.
2. Place a **read-only** kubeconfig at `./kubeconfig/config` with server
   `https://host.docker.internal:6443`. Verify from host: `kubectl --kubeconfig ./kubeconfig/config get nodes`.
3. Start the stack: `make up`. Follow startup: `make logs`.
   - **Expected**: gateway starts, Telegram connects via long polling, no missing-config errors.
   - **Fail-fast check**: temporarily unset a required key → `make up` reports the missing key and
     does not start broken (FR-015).

## Scenario 1 — Monitoring & alerting (US1 / P1)

1. Deploy a deliberately broken workload:
   `kubectl run crashy --image=busybox --restart=Always -- /bin/sh -c 'exit 1'`.
2. Wait one monitoring cycle (≤5 min).
   - **Expected**: a Telegram alert names `crashy`, its namespace, and the crashloop condition
     (SC-001).
3. Wait a second cycle.
   - **Expected**: **no** duplicate alert for the same issue (SC-003).
4. Delete it: `kubectl delete pod crashy`.
   - **Expected**: next cycle produces no new alert for it (resolved).
5. Stop the cluster/API briefly.
   - **Expected**: a single `unreachable` notice, not silence (FR-005).

## Scenario 2 — Conversational diagnostics (US2 / P2)

1. From an allowlisted Telegram account, ask: "what pods are not ready?"
   - **Expected**: reply reflecting real cluster state within ~30 s (SC-004).
2. From a **non-allowlisted** account, send any message.
   - **Expected**: rejection, no action taken (SC-006).
3. Ask the agent to "delete the crashy pod".
   - **Expected**: it refuses to act and routes you to an approval-gated proposal (FR-008).

## Scenario 3 — Runbook knowledge (US3 / P3)

1. After Scenario 1's diagnosis, inspect `obsidian/runbooks/`.
   - **Expected**: a Markdown note capturing symptom/cause/remediation (SC-007), editable outside the
     agent.
2. Re-introduce the same failure and ask about it.
   - **Expected**: the reply references the existing runbook note (FR-010).

## Scenario 4 — Runtime skill extension (US4 / P4)

1. From an allowlisted account, send a valid `SKILL.md` document.
   - **Expected**: it lands in `data/.hub/quarantine/` as pending; the agent asks for approval; it is
     **not** active yet (Principle III).
2. Approve it.
   - **Expected**: skill moves into `skills/`, hot-reloads, and is logged in `data/.hub/audit.log`.
3. Send a malformed skill / send one from a non-allowlisted account.
   - **Expected**: rejected; existing skills unchanged (FR-013, SC-006).

## Teardown

- `make down`. All state remains under the project dir (`obsidian/`, `skills/`, `data/`) — nothing
  leaves the machine (Principle I).

## Success gate

Feature is validated when all four scenarios pass and the Constitution gates in
[plan.md](./plan.md#constitution-check) still hold: local-only state, no committed secrets, every
mutation approval-gated, reproducible via `make up`.
