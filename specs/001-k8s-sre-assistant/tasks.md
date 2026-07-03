---
description: "Task list for Kubernetes SRE Assistant implementation"
---

# Tasks: Kubernetes SRE Assistant

**Input**: Design documents from `/specs/001-k8s-sre-assistant/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Not requested in the spec. This is a configuration-and-skills deployment on the Hermes
Agent runtime with no application-code test framework; validation is performed via the
[quickstart.md](./quickstart.md) run-and-observe scenarios, which appear as explicit validation tasks
inside each user story phase.

**Organization**: Tasks are grouped by user story so each can be implemented and validated
independently. All paths are repository-relative to the project root
(`/Users/khamisi/Main/hermes/hermes-sre-agent/`).

## Path Conventions

Single-project containerized deployment. No `src/` tree — deliverables are root-level infra/config
files and `SKILL.md` files under `skills/sre/`. See [plan.md](./plan.md) Project Structure.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project skeleton and secret-safe configuration surface

- [X] T001 Create the directory skeleton: `skills/sre/`, `obsidian/runbooks/` (with `.gitkeep`), `kubeconfig/`, `data/` at the project root per plan.md Project Structure
- [X] T002 [P] Create `.gitignore` excluding `.env`, `kubeconfig/`, `data/`, and `obsidian/runbooks/*` (keep `.gitkeep`, `.env.example`, and `skills/sre/**`) per contracts/config.md
- [X] T003 [P] Create `.env.example` documenting every key (`TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS`, `LLM_BASE_URL`, `LLM_MODEL_NAME`, `LLM_API_KEY`, `KUBECONFIG_PATH`, `MONITOR_INTERVAL`, `OBSIDIAN_VAULT_PATH`, `SKILLS_PATH`) with comments, per contracts/config.md

**Checkpoint**: Repo scaffolding exists and is safe to commit (no secrets).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Runtime, connectivity, config, and authorization that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Create `docker-compose.yml` defining the `hermes` service: **builds from a local `Dockerfile`** (extends the pinned `nousresearch/hermes-agent:v2026.6.5` base with `kubectl`+`jq`, discovered missing at runtime), `command: gateway run`, `restart: unless-stopped`, env from `./.env`, and volume mounts `./data:/opt/data`, `./skills/sre:/opt/data/skills/sre` (corrected from `./skills` — see data-model.md Entity: Skill), `./obsidian:/opt/data/obsidian`, `${KUBECONFIG_PATH}:/root/.kube/config:ro`, per contracts/config.md
- [X] T005 [P] Create `config.yaml` wiring the Ollama `custom` provider (`base_url=${LLM_BASE_URL}`, `default=${LLM_MODEL_NAME}`) and enabling the Telegram platform with `token=${TELEGRAM_BOT_TOKEN}`, per contracts/config.md and research.md R3/R4 — **live-validated**: `${VAR}` substitution confirmed working at runtime for both fields
- [X] T006 [P] Create `Makefile` with `up` (validate required `.env` keys, copy config.yaml into data/, build, then `docker compose up -d`), `down`, `restart`, and `logs` targets, per contracts/config.md
- [X] T007 [P] Create a scoped read-only ServiceAccount + ClusterRole/Binding manifest at `skills/sre/cluster-watch/scripts/rbac-readonly.yaml` (get/list/watch on pods, nodes, events) — **applied to the live cluster and verified**: reads succeed, `kubectl delete`/`run` correctly Forbidden
- [X] T008 Generate the read-only kubeconfig into `kubeconfig/config` from the T007 ServiceAccount — **corrected server address to `https://kubernetes.docker.internal:6443`** (the live apiserver cert's SAN list does not include `host.docker.internal`; verified via `openssl s_client`), long-lived token Secret minted and verified from inside a real container
- [X] T009 Populate a local `.env` from `.env.example` with the real bot token, allowlisted user ID, and Ollama model (`llama3.2:latest`, confirmed pulled); confirmed the host Ollama endpoint answers at `http://host.docker.internal:11434/v1` (research.md R3) — **found and fixed**: the correct env var is `TELEGRAM_ALLOWED_USERS`, not `TELEGRAM_ALLOWED_CHAT_IDS` as originally planned (renamed everywhere)
- [X] T010 Run `make up`; confirmed the gateway starts, Telegram connects via long polling (`✓ telegram connected`), and that removing a required `.env` key makes `make up` fail fast with the exact missing key (FR-014, FR-015) — also found/fixed a real bug: unquoted `MONITOR_INTERVAL=*/5 * * * *` in `.env` caused shell glob-expansion when sourced (`Makefile: command not found`); now quoted

**Checkpoint**: Hermes Agent is running, authorized, cluster-reachable (read-only), and LLM-connected.

---

## Phase 3: User Story 1 - Automated cluster monitoring & alerting (Priority: P1) 🎯 MVP

**Goal**: A scheduled skill detects abnormal cluster conditions and pushes deduplicated, grouped
Telegram alerts.

**Independent Test**: Deploy a crashing pod → an accurate alert arrives within one cycle; no duplicate
next cycle; deleting the pod stops alerts; an unreachable cluster produces one notice.

- [X] T011 [US1] Author `skills/sre/cluster-watch/SKILL.md` (front matter per contracts/skills.md) describing the read-only monitoring procedure, condition classification, and alert wording — updated after validation to document the `--no-agent` architecture (see T016 note)
- [X] T012 [P] [US1] Add read-only helper `skills/sre/cluster-watch/scripts/collect.sh` — **live-tested** against the real cluster with retry-then-`UNREACHABLE` marker logic
- [X] T013 [P] [US1] Add `skills/sre/cluster-watch/scripts/classify.sh` mapping raw output to `Issue` records — **live-tested**: correctly classified real `restarts` and `warning_event` conditions from the actual cluster
- [X] T014 [US1] Implement dedup + lifecycle state in `data/sre-state/issues.json` (`scripts/reconcile.sh`) — **live-tested** across 3 cycles: new issues alert, persisting issues correctly suppressed (no re-alert), removed issues transition to `resolved`
- [X] T015 [US1] Implement flood grouping (`scripts/format-digest.sh`, one digest per cycle) and the `unreachable` single-alert path — **live-tested**, including a real `UNREACHABLE` snapshot producing exactly one issue
- [X] T016 [US1] Register the cron schedule — **deviated from plan**: registered with `hermes cron create ... --no-agent --script scripts/cluster-watch-run.sh --deliver telegram:$TELEGRAM_ALLOWED_USERS`, not the originally-planned LLM-driven `--skill cluster-watch` prompt. Reason: live-tested the LLM-driven path first and found the local `llama3.2:latest` model unreliably followed the "stay silent unless new" instruction even with genuine new issues (returned `[SILENT]` incorrectly once). Detection/dedup correctness must not depend on small-model instruction-following, so the deterministic script's stdout is now delivered directly (empty = silent, non-empty = the alert) — confirmed working: `Job '91adfda8f2ae': delivered to telegram:997120009 via live adapter`, and the recipient (real human) confirmed receipt in chat
- [X] T017 [US1] Audit trail: **partially done differently than planned** — `hermes cron list`/scheduler logs currently serve as the audit trail for detections/deliveries; a dedicated `data/skills/.hub/audit.log` line per detection (as originally scoped) is not yet wired up — follow-up
- [X] T018 [US1] Validate US1: **live-validated against the real cluster**, not just `quickstart`'s hypothetical `crashy` pod — real control-plane `restarts` and a real `warning_event` were detected, alerted once, correctly deduped on repeat, and correctly suppressed after removal from state; unreachable path tested with a synthetic marker (did not actually stop the live control plane)

**Checkpoint**: MVP — the assistant autonomously watches the cluster and alerts over Telegram.

---

## Phase 4: User Story 2 - Conversational diagnostics (Priority: P2)

**Goal**: Operators ask cluster questions in Telegram and get answers reflecting live state, with
authorization enforced and mutations refused.

**Independent Test**: Ask about a workload → accurate reply <30s; unauthorized sender rejected;
mutating request refused with guidance.

- [X] T019 [US2] Author `skills/sre/k8s-query/SKILL.md` translating natural-language questions to read-only `kubectl` lookups and concise answers, per contracts/skills.md
- [ ] T020 [P] [US2] Reuse/extend the read-only helper scripts (from T012) for on-demand queries referenced by the k8s-query skill (targeted `get`/`describe`) — not yet split into a dedicated script; SKILL.md currently describes the procedure inline
- [X] T021 [US2] Enforce the sender allowlist (`TELEGRAM_ALLOWED_USERS`) at the interaction boundary and document the rejection behavior in the skill (FR-007, SC-006; contracts/telegram-commands.md) — documented in SKILL.md; gateway-level allowlist enforcement confirmed live (unauthenticated senders denied per the gateway's own allowlist warning/enforcement observed in logs)
- [X] T022 [US2] Add the mutation-refusal rule to k8s-query: any mutating request is declined and routed to `remediation-proposer` (FR-008)
- [X] T023 [US2] Author `skills/sre/remediation-proposer/SKILL.md` that produces approval-gated proposals (exact command(s)/manifest + blast radius), never executes, and logs proposal/approval/outcome to `data/.hub/audit.log` (FR-008, FR-017, SC-005; Principle III)
- [ ] T024 [US2] Validate US2 via quickstart Scenario 2 — **not live-tested**: requires interactively messaging the bot as the operator to exercise k8s-query/remediation-proposer conversationally; only the alert-delivery direction (bot → operator) was validated this session

**Checkpoint**: Operators can triage conversationally; no autonomous mutations possible.

---

## Phase 5: User Story 3 - Runbook knowledge capture & reuse (Priority: P3)

**Goal**: Diagnoses are written as Markdown runbook notes in the Obsidian vault and reused via RAG on
recurrence.

**Independent Test**: Trigger a diagnosis → note appears in `obsidian/runbooks/`; recurrence → reply
references it; note editable outside the agent.

- [X] T025 [US3] Author `skills/sre/runbook/SKILL.md` to create/update notes in `obsidian/runbooks/` with the `Runbook Note` fields (title, issue_type, symptom, cause, remediation, occurrences) per data-model.md
- [X] T026 [P] [US3] Add a note template at `skills/sre/runbook/templates/runbook-note.md` matching the Runbook Note contract
- [ ] T027 [US3] Wire `cluster-watch` and `k8s-query` to invoke the runbook skill after a diagnosis — **not yet automatic**: `cluster-watch` is now a deterministic `--no-agent` script (see T016) with no LLM turn to invoke `runbook` from, so this hand-off needs a follow-up design (e.g. a separate scheduled/triggered agent turn, or teaching format-digest.sh to also write the note deterministically)
- [ ] T028 [US3] Confirm the Obsidian vault is the RAG source for retrieval — not exercised this session
- [ ] T029 [US3] Validate US3 via quickstart Scenario 3 — not live-tested

**Checkpoint**: The assistant accumulates and reuses institutional knowledge locally.

---

## Phase 6: User Story 4 - Runtime skill extension via Telegram (Priority: P4)

**Goal**: Authorized operators send a `SKILL.md` over Telegram; it quarantines and activates only
after explicit human approval, then hot-reloads.

**Independent Test**: Send a valid skill → quarantined pending approval; approve → active + logged;
malformed/unauthorized → rejected, existing skills unchanged.

- [ ] T030 [US4] Document and configure the skill-upload flow — **relies on Hermes' built-in Skills Hub**; note `.hub/` was NOT present under `/opt/data/skills/` in the running container before any skill submission — it appears to be created lazily on first use, not at boot. Not yet exercised by actually sending a skill file over Telegram; confirm the exact `.hub` path empirically on first real submission rather than trusting data-model.md's assumption
- [ ] T031 [US4] Enforce the approval gate — built-in Hermes behavior; not live-tested
- [ ] T032 [US4] Add validation/rejection handling — built-in Hermes behavior; not live-tested
- [ ] T033 [US4] Validate US4 via quickstart Scenario 4 — not live-tested this session

**Checkpoint**: The agent is safely extensible at runtime under human control.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, hardening, and full end-to-end validation

- [X] T034 [P] Write `README.md` at the project root: prerequisites, `make` usage, and a pointer to quickstart.md
- [X] T035 [P] Add a `make verify-config` helper — implemented; does not yet check Ollama/cluster reachability, only required `.env` keys presence and that `KUBECONFIG_PATH` exists
- [X] T036 Harden least-privilege: **live-verified twice** — `kubectl delete pod` and `kubectl run` both return `Forbidden` from inside a real container using the mounted kubeconfig
- [ ] T037 Run the full quickstart.md end-to-end (all four scenarios) — **US1 live-validated (real cluster + real Telegram delivery + human-confirmed receipt); US2/US3/US4 not yet exercised interactively.** Container is currently left running (`make down` to stop) with real credentials in `.env` — rotate the bot token if this environment is shared.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately.
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories.
- **User Stories (Phases 3–6)**: All depend on Foundational. US1 is the MVP. US2/US3/US4 can then
  proceed in priority order or in parallel by different people.
- **Polish (Phase 7)**: Depends on the desired user stories being complete.

### User Story Dependencies

- **US1 (P1)**: Independent after Foundational.
- **US2 (P2)**: Independent after Foundational; reuses US1 read-only helpers but is separately testable.
- **US3 (P3)**: Independent after Foundational; T027 hooks into US1/US2 skills for auto-capture but the
  runbook skill itself is testable alone.
- **US4 (P4)**: Independent after Foundational; relies only on Hermes' Skills Hub, not other stories.

### Within Each User Story

- Author `SKILL.md` and helper scripts → wire scheduling/interaction → add audit logging → validate.
- Models here are file/JSON schemas (issues.json, runbook notes) rather than code classes.

### Parallel Opportunities

- Setup: T002, T003 in parallel.
- Foundational: T005, T006, T007 in parallel (T004 first; T008 needs T007; T009/T010 sequential last).
- US1: T012 and T013 in parallel, then T014.
- Across stories: once Phase 2 is done, US1–US4 can be staffed in parallel.

---

## Parallel Example: User Story 1

```bash
# After T011 (SKILL.md), author the two read-only helpers together:
Task: "Add collect.sh in skills/sre/cluster-watch/scripts/collect.sh"
Task: "Add classify.sh in skills/sre/cluster-watch/scripts/classify.sh"
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1 Setup → 2. Phase 2 Foundational → 3. Phase 3 US1 → **STOP & VALIDATE** (quickstart
   Scenario 1) → demo. At this point you have a working autonomous cluster watcher on Telegram.

### Incremental Delivery

Foundation → US1 (MVP) → US2 (conversational triage) → US3 (runbooks) → US4 (extensibility). Each
story is validated via its quickstart scenario before moving on and adds value without breaking prior
stories.

---

## Notes

- `[P]` = different files, no dependency on an incomplete task.
- `[Story]` labels map tasks to spec.md user stories for traceability.
- Constitution guardrails to preserve throughout: cluster access stays read-only (III/V), no secret
  is committed (II), all state stays in the project dir (I), and the stack reproduces via `make up`
  (IV). Every mutation and skill install is approval-gated and logged.
- Commit after each task or logical group.
