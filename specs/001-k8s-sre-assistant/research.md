# Phase 0 Research: Kubernetes SRE Assistant

All Technical Context items were resolvable from the user's stated environment plus Hermes Agent
documentation (Context7: `/nousresearch/hermes-agent`). No unresolved `NEEDS CLARIFICATION` remain.

## R1 — Agent runtime: Hermes Agent in Docker

- **Decision**: Run the upstream `nousresearch/hermes-agent` image via `docker-compose`, started with
  the `gateway run` command, with a persistent `/opt/data` volume mapped to `./data/`.
- **Rationale**: Hermes Agent already provides persistent memory, a Telegram gateway, cron
  automations, and a `SKILL.md` extension model — exactly the capabilities the spec requires, so we
  configure rather than build. Pinning the image (v2026.6.5) satisfies reproducibility (Principle IV).
- **Alternatives considered**: Building a bespoke Python agent (rejected — reinvents Hermes' gateway,
  memory, and skill system); LangChain/custom bot (rejected — more code, weaker fit to the skills/cron
  model, and not what "built on Hermes Agent" asks for).

## R2 — Reaching the kubeadm cluster from inside the container

- **Decision**: Mount a dedicated kubeconfig at `./kubeconfig/config` (read-only) and set the server
  address to `https://host.docker.internal:6443`. Use a **read-only** ServiceAccount/RBAC credential.
- **Rationale**: The container cannot reach the host's `127.0.0.1` API server; `host.docker.internal`
  resolves to the Docker Desktop host. A read-only credential enforces Principles III and V — the
  agent can observe everything but cannot mutate without a human executing an approved action.
- **Alternatives considered**: `--network host` (not supported the same way on Docker Desktop Mac);
  baking kubeconfig into the image (rejected — leaks a credential into the image, violates Principle
  II); full-admin kubeconfig (rejected — violates least privilege).

## R3 — LLM backend: host Ollama

- **Decision**: Point Hermes' model provider at `http://host.docker.internal:11434/v1` (OpenAI-
  compatible), provider `custom`, no API key. Model name configurable in `.env`
  (`LLM_MODEL_NAME`, default a locally available instruct model).
- **Rationale**: Keeps inference local (Principle I — no third-party SaaS in the core loop) and free.
  Hermes documents the `custom` provider with an OpenAI-compatible `base_url`; Ollama exposes `/v1`.
- **Alternatives considered**: Hosted APIs (Anthropic/OpenAI) — rejected for the core loop as they
  break local-first and add cost/secrets; running Ollama inside the container — rejected because the
  user already runs it on the host and GPU/Metal access is simplest from the host.

## R4 — Messaging: Telegram via long polling

- **Decision**: Enable the Telegram platform in `config.yaml` with the bot token from `.env`; use
  long polling (Hermes default) so no inbound port or public IP is required.
- **Rationale**: Long polling works behind Docker Desktop NAT with zero networking setup, matching the
  "no public IP required" constraint. Authorization is enforced by an allowlist of Telegram chat/user
  IDs in `.env` (satisfies FR-007, SC-006).
- **Alternatives considered**: Telegram webhooks (rejected — needs a public HTTPS endpoint/tunnel);
  Slack/Discord (out of scope; Telegram was specified).

## R5 — Memory / knowledge base: local Obsidian vault as RAG

- **Decision**: Mount `./obsidian/` into the container as the runbook vault and RAG source; the
  `runbook` skill writes diagnosis notes there as Markdown, and retrieval reads from it.
- **Rationale**: Obsidian vaults are plain Markdown, so notes stay readable/editable outside the agent
  (FR-009, FR-018, SC-007) and remain in the project directory (Principle I). Hermes' cron guide shows
  an `obsidian` skill pattern for exactly this note-writing flow.
- **Alternatives considered**: External vector DB (rejected — adds a service and breaks local-first);
  Hermes' built-in `MEMORY.md`/`USER.md` only (kept for agent self-notes, but insufficient as a
  browsable runbook library, so the Obsidian vault is the system of record for runbooks).

## R6 — Monitoring loop: cron-scheduled read-only kubectl skill

- **Decision**: A `cluster-watch` skill runs on a Hermes cron schedule (default every ≤5 min) that
  executes read-only `kubectl` queries (pods, nodes, events), classifies abnormal conditions, and
  emits alerts. Deduplication uses a small state file under `./data/` keyed by issue identity
  (type + resource) with first/last-seen tracking.
- **Rationale**: Meets SC-001 (report within one cycle) and FR-004/SC-003 (no repeat spam). Hermes'
  `/cron add "<schedule>" "<prompt>" --skill <name>` is the native scheduling mechanism.
- **Alternatives considered**: Watching the Kubernetes events API stream (rejected for v1 — more
  complex, harder to keep read-only-simple and to dedupe deterministically; polling is sufficient at
  this scale); a sidecar Prometheus/Alertmanager (rejected — heavy, defeats the local, agent-native
  design).

## R7 — Runtime skill extension with human approval

- **Decision**: Skills sent over Telegram are received into Hermes' Skills Hub **quarantine**
  (`./data/.hub/quarantine/`) and only moved into active `./skills/` after explicit operator
  approval; installs are appended to `./data/.hub/audit.log`. `./skills/` being mounted enables
  hot-reload without rebuilding the image.
- **Rationale**: Directly satisfies FR-011–FR-013 and Principle III (Human-in-the-Loop). Hermes'
  documented `.hub/quarantine/` + `audit.log` structure is purpose-built for this trust boundary.
- **Alternatives considered**: Auto-installing uploaded skills (rejected — arbitrary code execution
  from a chat message; violates Principle III); requiring image rebuild per skill (rejected — breaks
  the "hot-reloadable via Telegram" requirement).

## R8 — Configuration and lifecycle management

- **Decision**: All secrets/settings in `.env` (bot token, allowlisted chat IDs, Ollama URL/model,
  cron interval, kubeconfig path); commit only `.env.example`. A `Makefile` exposes `up`, `down`,
  `restart`, `logs` wrapping `docker-compose`. `.gitignore` excludes `.env`, `kubeconfig/`, `data/`,
  and vault contents.
- **Rationale**: Satisfies FR-014/FR-015 and Principles II & IV; a clean machine reproduces the stack
  from the repo (SC-008).
- **Alternatives considered**: Committing config with secrets (rejected — Principle II); shell scripts
  instead of a Makefile (rejected — the user specified a Makefile and it gives a stable command
  surface).

## Open items

None. All Technical Context fields are resolved.
