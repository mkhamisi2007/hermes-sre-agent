# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

An AI SRE assistant built on [Hermes Agent](https://github.com/nousresearch/hermes-agent) (upstream
image `nousresearch/hermes-agent`) that watches a local kubeadm/Docker-Desktop Kubernetes cluster,
alerts and answers questions over Telegram, records runbook knowledge in a local Obsidian vault, and
proposes (never auto-applies) remediations. There is **no application source code** — the entire
"codebase" is Hermes configuration plus a handful of shell/awk scripts and `SKILL.md` files. Read
`README.md` for user-facing setup and `.specify/memory/constitution.md` for the non-negotiable
project rules (local-first, no committed secrets, human-in-the-loop remediation, least-privilege).

The `specs/001-k8s-sre-assistant/` directory holds the full spec-kit trail (spec, plan, research,
data-model, contracts, tasks) for this feature — read it before making architectural changes,
especially `research.md` (documents *why* things are wired the way they are) and `tasks.md`
(current completion state, including honestly-marked gaps).

## Commands

```sh
make up             # validate config, build image (adds kubectl+jq+curl via Dockerfile), start stack
make down            # stop the stack
make restart         # down then up
make logs            # follow container logs
make verify-config   # just the .env validation, no build/start
```

`make up` also copies `config.yaml` → `data/config.yaml` with env vars resolved via `envsubst`
(see "Config resolution gotchas" below for why this is necessary rather than a straight bind mount).

There is no test suite / linter / build step beyond the above — validation is done by exercising the
real stack (see `specs/001-k8s-sre-assistant/quickstart.md` for the four scripted validation
scenarios) and by reading `hermes` logs directly:

```sh
docker exec hermes-sre-agent sh -c 'hermes cron list'                      # scheduled job status
docker exec hermes-sre-agent sh -c 'tail -f /opt/data/logs/agent.log'      # LLM/agent turns
docker exec hermes-sre-agent sh -c 'tail -f /opt/data/logs/errors.log'    # warnings/errors only
docker exec hermes-sre-agent sh -c 'hermes cron run <job_id>'              # force a cron tick now
```

To test a single shell script in isolation without waiting for a cron tick:

```sh
docker exec hermes-sre-agent sh -c '
  /opt/data/skills/sre/cluster-watch/scripts/collect.sh /tmp/cw
  /opt/data/skills/sre/cluster-watch/scripts/classify.sh /tmp/cw \
    | /opt/data/skills/sre/cluster-watch/scripts/reconcile.sh /tmp/state.json \
    | /opt/data/skills/sre/cluster-watch/scripts/format-digest.sh'
```

After editing anything under `skills/sre/`, changes are live immediately (bind-mounted, no rebuild
needed) — but a manual `docker cp <file> hermes-sre-agent:/opt/data/skills/sre/.../<file>` during a
live debugging session doesn't survive a container recreate; always also save to the host path so
`make up`'s rebuild/restart persists it. Only the `Dockerfile` (kubectl/jq/curl tooling) requires
`docker compose down && make up` to take effect.

## Architecture

### Skills, not application code

Behavior lives entirely under `skills/sre/<name>/SKILL.md` (+ `scripts/`). Each `SKILL.md` states
explicitly whether it's **deterministic** (plain shell, no LLM in the loop) or **LLM-driven**
(the agent reads the markdown as instructions and decides what to do). This distinction is the
central architectural decision in this repo and was arrived at the hard way — read it before adding
a new skill or changing an existing one:

- **`cluster-watch`** — fully deterministic. Registered as a Hermes cron job in `--no-agent`
  ("watchdog") mode: the job's stdout is delivered to Telegram verbatim, with no LLM turn at all.
  This was a deliberate pivot from an earlier LLM-driven design — the local model proved unreliable
  at the simple "stay silent unless something's new" judgment (it sometimes suppressed genuine
  alerts), so detection/dedup correctness must not depend on model instruction-following.
  Pipeline: `collect.sh` (read-only `kubectl` snapshot) → `classify.sh` (raw → `Issue` JSON) →
  `reconcile.sh` (dedup/resolve against `data/sre-state/issues.json`) → `format-digest.sh`
  (severity-sorted, budget-limited enrichment + Telegram delivery formatting). `format-digest.sh`
  also calls `snippet.sh` (compact per-issue status), `propose-fix.sh` (isolated direct Ollama call,
  NOT through the agent loop, with a deterministic per-type fallback), and
  `../../runbook/scripts/{lookup-note,write-note}.sh`.
- **`k8s-query`, `remediation-proposer`** — LLM-driven, conversational. The SKILL.md is the actual
  instruction set the agent follows at runtime; edit it like you'd edit a prompt, not like
  documentation. `remediation-proposer` is the **only** path that can lead to a cluster mutation,
  and even it never executes anything itself — it composes a proposal and requires an explicit
  human approval reply (Constitution Principle III, non-negotiable).
- **`runbook`** — mixed: writing and lookup are deterministic scripts
  (`write-note.sh`/`lookup-note.sh`), but *using* the lookup result inside a conversational answer
  (`k8s-query` step 4) is LLM-driven. One Markdown note per issue **type** (not per resource) at
  `obsidian/runbooks/<type>.md`. The `verified` flag returned by `lookup-note.sh` is the whole point
  of the design: it's only `true` if a human has hand-edited the `## Cause` section away from the
  automated placeholder — unverified AI-generated causes/remediations must be presented as unverified
  guesses, never as established fact, or the system just reinforces its own first guess over time.
  Recurrence entries live under a `## Recurrence Log` heading and are capped at the 10 most recent
  (`trim-recurrences.awk`) so notes don't grow unbounded.

### Runtime topology

- The Hermes image is extended by the repo's `Dockerfile` only to add `kubectl`/`jq`/`curl` (the
  scripts' own dependencies) — everything else (behavior, skills, config) is mounted, not baked in,
  per the "configure, don't rebuild" approach.
- `docker-compose.yml` mounts: `./data:/opt/data` (Hermes home — memory, Skills Hub, sessions, logs;
  entirely gitignored), `./skills/sre:/opt/data/skills/sre` (this repo's skills, sitting alongside
  whatever else lands in the default skills root), `./obsidian:/opt/data/obsidian` (the vault),
  and a **read-only** kubeconfig mounted at `/etc/hermes-kubeconfig/config` — deliberately outside
  `/opt/data` (see "Config resolution gotchas").
- Cluster access is enforced read-only by RBAC, not by convention: `skills/sre/cluster-watch/scripts/rbac-readonly.yaml`
  defines a `ServiceAccount`/`ClusterRole` with only `get`/`list`/`watch`, so even an LLM talked into
  running a mutating `kubectl` command gets a server-side `Forbidden` — this is a safety net behind
  the SKILL.md-level intent checks, not a substitute for them.
- `config.yaml` uses `${VAR}` placeholders resolved by `make up` via `envsubst` before being copied
  into `data/config.yaml` — do not rely on Hermes' own runtime `${VAR}` substitution for anything
  that must be correct on every invocation (see gotchas).

### Config resolution gotchas (each cost real debugging time — don't reintroduce them)

- **`KUBECONFIG` must be an explicit container-wide env var**, not left to `kubectl`'s default
  `$HOME/.kube/config` lookup. Cron scripts run as user `hermes` (`$HOME=/opt/data/home`), not
  `root` — the default lookup silently misses and `kubectl` falls back to the insecure
  `localhost:8080`, which reads as a false "cluster unreachable" with no error.
- **`config.yaml` cannot be bind-mounted directly** at a path nested inside `./data:/opt/data` — a
  file-level bind mount inside an existing directory bind mount breaks on Docker Desktop's virtiofs
  ("mountpoint is outside of rootfs"). That's why `make up` copies it into `data/config.yaml` instead
  of mounting it.
- **Do NOT pre-escape MarkdownV2 yourself** when composing Telegram messages. Hermes' own send path
  (`format_message()` in the vendored `gateway/platforms/telegram.py`) converts standard markdown
  (`**bold**`, `` `code` ``, ```` ```fenced``` ````) to MarkdownV2 automatically, including escaping.
  Pre-escaping gets double-escaped by their converter and shows literal backslashes in Telegram.
  Also: a single `*asterisk*` converts to *italic*, not bold — use `**double**` for bold.
- Hermes' `--script` flag for cron jobs resolves paths **relative to `~/.hermes/scripts/`**
  (`/opt/data/scripts/` in-container) already — passing `scripts/foo.sh` instead of `foo.sh` silently
  doubles the path and the job fails with "Script not found".
- Telegram caps messages at 4096 chars and `--no-agent` cron delivery sends stdout as ONE message
  verbatim with no auto-splitting — `format-digest.sh`'s character budget exists for this reason;
  don't remove it without re-checking real digest size against several simultaneous issues.
- `OBSIDIAN_VAULT_PATH`/`SKILLS_PATH` in `.env` are **host-side** paths (compose volume sources) that
  also leak into the container's own environment via `env_file` — they are meaningless as
  in-container filesystem paths. Scripts running inside the container hardcode the real mount point
  (`/opt/data/obsidian`, `/opt/data/skills/sre`) rather than trusting those env vars.

### Known gap: cron registration isn't persisted in git

The actual `hermes cron create ...` command that registers the `cluster-watch` job, and its entry
point script (`data/scripts/cluster-watch-run.sh`, which just chains
`collect.sh | classify.sh | reconcile.sh | format-digest.sh`), both live only in the gitignored
`data/` directory on whichever machine set them up — `make up` does **not** recreate the cron job or
entry script on a fresh clone. After bringing up a new environment, recreate
`data/scripts/cluster-watch-run.sh` (see `skills/sre/cluster-watch/SKILL.md` step 5 for its exact
contents and the registration command) and re-run `hermes cron create` before expecting monitoring
alerts to fire.
