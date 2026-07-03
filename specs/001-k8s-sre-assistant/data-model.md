# Phase 1 Data Model: Kubernetes SRE Assistant

The system is file-first: entities are represented as Markdown documents, small JSON/state files, and
log lines within the project directory (Principle I). No database is introduced.

## Entity: Issue (detected cluster condition)

Represents one abnormal condition found by the `cluster-watch` skill. Held in a dedup state file
(`./data/sre-state/issues.json`) between cycles; surfaced to the operator as an Alert.

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | Stable identity = `{type}:{namespace}/{resource}` (or `{type}:node/{node}`). Used for dedup. |
| `type` | enum | `crashloop`, `restarts`, `pending`, `node_not_ready`, `warning_event`, `unreachable`. |
| `resource` | string | Affected pod/node/object name. |
| `namespace` | string | Namespace, or `-` for cluster/node-scoped. |
| `severity` | enum | `info`, `warning`, `critical`. |
| `detail` | string | Human-readable reason (e.g., reason/message from the event). |
| `first_seen` | timestamp | When first detected. |
| `last_seen` | timestamp | Updated each cycle the condition persists. |
| `status` | enum | `active`, `resolved`. Resolved when absent from a subsequent cycle. |
| `alerted` | bool | True once an alert has been sent; gates dedup (FR-004, SC-003). |

**Validation / rules**:
- An Issue whose `id` already exists updates `last_seen` and does **not** re-alert unless `severity`
  changed materially (FR-004).
- An Issue absent from the current cycle transitions to `resolved` and stops generating alerts (US1 AS3).
- A cycle that cannot reach the cluster emits a single `unreachable` Issue (FR-005, US1 AS4).

## Entity: Alert (notification to operator)

Ephemeral message derived from one or more Issues; not persisted beyond the audit log.

| Field | Type | Notes |
|-------|------|-------|
| `summary` | string | One-line headline. |
| `issues` | Issue[] | One or more grouped issues (FR-016 flood grouping). |
| `sent_at` | timestamp | Delivery time. |
| `channel` | string | Telegram chat ID (from allowlist). |

**Rules**: During floods, multiple Issues in one cycle are grouped into a single digest Alert (FR-016).

## Entity: Runbook Note

Markdown document in the Obsidian vault (`./obsidian/runbooks/`), one per issue class. Also the RAG
retrieval unit.

| Field (front matter / heading) | Type | Notes |
|-------|------|-------|
| `title` | string | e.g., "CrashLoopBackOff — payments". |
| `issue_type` | enum | Matches `Issue.type` for lookup. |
| `symptom` | markdown | Observable signs. |
| `cause` | markdown | Root cause(s) if known. |
| `remediation` | markdown | Proposed steps (informational; execution is HITL). |
| `created` / `updated` | timestamp | Note lifecycle. |
| `occurrences` | int | Incremented on recurrence (FR-010). |

**Rules**: A completed diagnosis MUST produce or update a matching note (FR-009, SC-007). Notes are
plain Markdown, editable outside the agent (FR-018).

## Entity: Skill

A capability unit (`SKILL.md` + optional `scripts/`, `references/`). Managed via the Skills Hub.

| Field | Type | Notes |
|-------|------|-------|
| `name` | string | From SKILL.md front matter. |
| `location` | enum | `quarantine` (`./data/.hub/quarantine/`) → `active` (`./skills/...`). |
| `state` | enum | `pending`, `approved`, `rejected`. |
| `submitted_by` | string | Telegram sender ID (must be allowlisted). |
| `installed_at` | timestamp | Set on approval; logged to `audit.log`. |

**State transitions**: `received → pending (quarantine) → approved (active) | rejected (discarded)`.
Only an authorized operator can approve (FR-011–FR-013, Principle III). Rejection or malformed input
leaves active skills unchanged (US4 AS3).

## Entity: Authorized Sender

| Field | Type | Notes |
|-------|------|-------|
| `chat_id` | string | Telegram user/chat ID. |
| `allowed` | bool | Present in `.env` allowlist ⇒ allowed. |

**Rules**: Any request or skill submission from a non-allowlisted sender is rejected (FR-007, SC-006).

## Entity: Configuration

Single source: `.env` (secrets/settings) + `config.yaml` (Hermes model/platform wiring). See
[contracts/config.md](./contracts/config.md).

| Key (env) | Purpose |
|-----------|---------|
| `TELEGRAM_BOT_TOKEN` | Bot auth (secret). |
| `TELEGRAM_ALLOWED_USERS` | Comma-separated allowlist. |
| `LLM_BASE_URL` / `LLM_MODEL_NAME` / `LLM_API_KEY` | Ollama endpoint + model. |
| `KUBECONFIG_PATH` | Mounted read-only kubeconfig. |
| `MONITOR_INTERVAL` | Cron cadence (default ≤5 min). |

**Rules**: Missing required keys ⇒ fail fast at startup with a clear message (FR-015). No secret is
committed; `.env.example` documents every key (Principle II).

## Entity: Audit Record

Append-only lines in `./data/.hub/audit.log` (and mirrored context in runbook notes): what happened,
why, who approved, outcome — covering detections, proposed actions, approvals, and skill installs
(FR-017, Principle V).
