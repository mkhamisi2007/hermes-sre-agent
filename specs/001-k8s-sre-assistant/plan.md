# Implementation Plan: Kubernetes SRE Assistant

**Branch**: `001-k8s-sre-assistant` | **Date**: 2026-07-03 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-k8s-sre-assistant/spec.md`

## Summary

Deploy the Nous Research **Hermes Agent** as a containerized AI SRE assistant that watches a local
kubeadm Kubernetes cluster and drives an operator's Telegram workflow. A scheduled (cron) skill runs
read-only `kubectl` against a mounted kubeconfig on a fixed interval, detects abnormal conditions,
deduplicates them, and pushes human-readable alerts to Telegram. Operators can ask cluster questions
in the same chat and receive answers; diagnoses and resolutions are written as Markdown runbook notes
into a local Obsidian vault that also serves as the agent's RAG memory. New capabilities can be added
at runtime by sending a `SKILL.md` file over Telegram, which lands in quarantine and activates only
after explicit human approval. Any mutating/remediation action is proposed but never auto-applied.
All secrets/settings live in `.env`; the stack is operated through a `Makefile` and `docker-compose`.

The bulk of the work is **configuration + skill authoring** on top of the Hermes Agent runtime, not
building an agent from scratch. Custom code is limited to skill definitions (`SKILL.md` + small
read-only helper scripts) and glue configuration.

## Technical Context

**Language/Version**: Python-based Hermes Agent runtime (upstream image); custom work is `SKILL.md`
Markdown + POSIX shell helper scripts invoking `kubectl`. No compiled application code of our own.

**Primary Dependencies**: Hermes Agent (`nousresearch/hermes-agent`, `/nousresearch/hermes-agent`
v2026.6.5), `kubectl`, Ollama (host LLM, OpenAI-compatible endpoint), Telegram Bot API (long
polling), Obsidian-compatible Markdown vault. Docker Desktop + Compose for orchestration.

**Storage**: Local filesystem only — `./obsidian/` (runbook vault + RAG source), `./skills/`
(hot-reloadable skill files), `./data/` (Hermes `/opt/data` persistent volume: memory, `.hub`
quarantine + `audit.log`), `./kubeconfig/` (read-only cluster credential, mounted).

**Testing**: Quickstart validation scenarios (deploy a deliberately broken workload and observe the
alert), per-skill `## Verification` sections, and `make`-driven smoke checks. No unit-test framework
for our own code since there is effectively no application code beyond skills/config.

**Target Platform**: Docker container on Docker Desktop (macOS); target is a single kubeadm cluster
on the same Docker Desktop, reached via `host.docker.internal`.

**Project Type**: Single-project containerized agent deployment (config + skills), not a
frontend/backend split.

**Performance Goals**: Detect and report a new fault within one monitoring cycle (default ≤5 min,
SC-001); answer a cluster-status question in <30 s under normal conditions (SC-004).

**Constraints**: Local-first, no public IP (Telegram long polling), read-only cluster access by
default, all secrets in `.env` (never committed), no autonomous mutations.

**Scale/Scope**: Single cluster; single operator or small trusted team; allowlist-based
authorization. Multi-tenant isolation and long-term metric archival are out of scope for v1.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Status |
|-----------|------|--------|
| I. Local-First Data Sovereignty | All state (`obsidian/`, `skills/`, `data/`, config) lives in project dir; LLM is host-local Ollama; no third-party SaaS in the core loop (Telegram is the operator channel, opt-in and documented). | ✅ PASS |
| II. Secrets Stay Out of Repo (NON-NEGOTIABLE) | All tokens/paths in `.env`; repo ships `.env.example` only; `.gitignore` excludes `.env`, `kubeconfig/`, `data/`. | ✅ PASS |
| III. Human-in-the-Loop Remediation (NON-NEGOTIABLE) | `kubectl` usage is read-only by default; remediation skills produce proposals requiring explicit approval; uploaded skills land in `.hub/quarantine/` and activate only after human approval. | ✅ PASS |
| IV. Reproducible Containerized Environment | `docker-compose.yml` + `Makefile` (`up/down/restart/logs`) codify the full stack; upstream pinned image; kubeconfig mounted, not baked. | ✅ PASS |
| V. Least-Privilege & Auditability | Cluster access via a scoped read-only kubeconfig/ServiceAccount; every proposed action, approval, and skill install recorded in `data/.hub/audit.log` + runbook notes. | ✅ PASS |

**Result**: No violations. Complexity Tracking not required.

## Project Structure

### Documentation (this feature)

```text
specs/001-k8s-sre-assistant/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   ├── skills.md        # SKILL.md contracts for the SRE skills
│   ├── telegram-commands.md  # Operator command/interaction contract
│   └── config.md        # .env + config.yaml contract
└── tasks.md             # Phase 2 output (/speckit-tasks — NOT created here)
```

### Source Code (repository root)

```text
hermes-sre-agent/
├── Makefile                     # up / down / restart / logs (+ helpers)
├── docker-compose.yml           # Hermes Agent service, volumes, host.docker.internal
├── .env.example                 # Documented config template (committed)
├── .env                         # Real secrets/settings (gitignored)
├── .gitignore                   # Excludes .env, kubeconfig/, data/
├── config.yaml                  # Hermes model/provider + platform config
├── kubeconfig/                  # Mounted read-only cluster credential (gitignored)
│   └── config                   # server: https://host.docker.internal:6443
├── skills/                      # Mounted → hot-reloadable SRE skills
│   └── sre/
│       ├── cluster-watch/       # P1: cron monitoring + alerting
│       │   ├── SKILL.md
│       │   └── scripts/         # read-only kubectl helpers
│       ├── k8s-query/           # P2: answer cluster questions
│       │   └── SKILL.md
│       ├── runbook/             # P3: write/lookup Obsidian runbook notes
│       │   └── SKILL.md
│       └── remediation-proposer/# HITL: propose (never apply) fixes
│           └── SKILL.md
├── obsidian/                    # Runbook vault + RAG source (gitignored content)
│   └── runbooks/
└── data/                        # Hermes /opt/data volume: memory, .hub/quarantine, audit.log (gitignored)
```

**Structure Decision**: Single-project containerized deployment. There is no application source tree
of our own; the deliverables are (a) infrastructure/config files at the repo root and (b) skill
definitions under `skills/sre/`. This matches the Hermes Agent model where behavior is expressed as
`SKILL.md` files plus configuration rather than bespoke services.

## Complexity Tracking

No constitution violations — section intentionally empty.
