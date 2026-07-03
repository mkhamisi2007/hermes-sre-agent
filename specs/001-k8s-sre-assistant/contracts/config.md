# Contract: Configuration (`.env` + `config.yaml` + compose)

Single source of truth for secrets/settings is `.env` (gitignored); only `.env.example` is committed
(Principle II). Missing required keys ⇒ fail fast at startup (FR-015).

## `.env` keys

| Key | Required | Example | Purpose |
|-----|----------|---------|---------|
| `TELEGRAM_BOT_TOKEN` | yes | `123456:ABC...` | Telegram bot auth (secret). |
| `TELEGRAM_ALLOWED_USERS` | yes | `11111111,22222222` | Authorization allowlist. |
| `LLM_BASE_URL` | yes | `http://host.docker.internal:11434/v1` | Ollama OpenAI-compatible endpoint. |
| `LLM_MODEL_NAME` | yes | `qwen2.5:14b` | Local model name pulled in Ollama. |
| `LLM_API_KEY` | no | `NA` | Placeholder; Ollama needs none. |
| `KUBECONFIG_PATH` | yes | `./kubeconfig/config` | Read-only cluster credential (mounted). |
| `MONITOR_INTERVAL` | no | `*/5 * * * *` | Cron cadence for `cluster-watch` (default ≤5 min). |
| `OBSIDIAN_VAULT_PATH` | no | `./obsidian` | Runbook vault mount source. |
| `SKILLS_PATH` | no | `./skills` | Hot-reloadable skills mount source. |

## `config.yaml` (Hermes wiring)

```yaml
model:
  default: ${LLM_MODEL_NAME}
  provider: custom
  base_url: ${LLM_BASE_URL}
platforms:
  telegram:
    enabled: true
    token: ${TELEGRAM_BOT_TOKEN}
```

## `docker-compose.yml` requirements

- Image: `nousresearch/hermes-agent:<pinned>` (e.g. `v2026.6.5`), `command: gateway run`,
  `restart: unless-stopped`.
- `extra_hosts` / rely on Docker Desktop's `host.docker.internal` for cluster + Ollama reachability.
- Volumes (host → container), all under the project dir:
  - `./data:/opt/data` (memory, `.hub/quarantine`, `audit.log`)
  - `./skills:/opt/data/skills` (hot-reload)
  - `./obsidian:<vault mount>` (runbook RAG)
  - `${KUBECONFIG_PATH}:/root/.kube/config:ro` (read-only)
  - `./.env` provides environment.

## `.gitignore` contract

Must exclude at minimum: `.env`, `kubeconfig/`, `data/`, and vault contents (keep `.env.example`,
`skills/sre/**` committed as the shipped SRE skills, and an `obsidian/.gitkeep`).

## `Makefile` targets (contract)

| Target | Behavior |
|--------|----------|
| `up` | `docker compose up -d` (validates required `.env` keys first). |
| `down` | `docker compose down`. |
| `restart` | `down` then `up`. |
| `logs` | `docker compose logs -f hermes`. |

**Maps to**: FR-014, FR-015, FR-018; Principles I, II, IV; SC-008.
