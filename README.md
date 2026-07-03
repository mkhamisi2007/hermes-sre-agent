# Hermes SRE Agent

An AI SRE assistant, built on [Hermes Agent](https://github.com/nousresearch/hermes-agent), that
watches a local kubeadm/Docker-Desktop Kubernetes cluster, alerts and answers questions over
Telegram, records runbook knowledge in a local Obsidian vault, and proposes — but never
auto-applies — remediations. It's a portfolio project built to demonstrate a local-first,
security-conscious approach to operating an AI agent against real infrastructure: every design
decision below exists because something broke in practice and got fixed for a documented reason,
not because it looked good on paper.

See [`.specify/memory/constitution.md`](.specify/memory/constitution.md) for the non-negotiable
rules this project follows (local-first data, no committed secrets, human-in-the-loop remediation,
least-privilege access), and [`specs/001-k8s-sre-assistant/`](specs/001-k8s-sre-assistant/) for the
full spec → plan → research → tasks trail behind this build.

## Screenshots

<img width="1512" height="982" alt="image" src="https://github.com/user-attachments/assets/edc1e484-b525-4833-8c58-23a748d20fd1" />

<img width="779" height="209" alt="image" src="https://github.com/user-attachments/assets/31df034a-a49f-4bfd-ae5d-5cecbcd4a57d" />


## Built with Spec-Driven Development (SDD)

This project wasn't built by prompting an agent to "build an SRE bot" and iterating from there. It
was built with **Spec-Driven Development** via [GitHub's spec-kit](https://github.com/github/spec-kit)
(the `speckit-*` skills in `.claude/skills/`): ratify a project constitution first, then move
through specification → clarification → planning → task breakdown → cross-artifact analysis, and
only then implement. Every artifact that process produced is committed in
[`specs/001-k8s-sre-assistant/`](specs/001-k8s-sre-assistant/) — the spec, the plan, the research
log, the data model, the contracts, and the task list — so the reasoning behind the architecture is
as reviewable as the code itself.

The exact command sequence used to drive this workflow:

```sh
specify init hermes-sre-agent --integration claude
cd hermes-sre-agent

/speckit-constitution
This is a local-first, security-conscious DevOps portfolio project.
Hermes Agent runs inside a Docker container on Docker Desktop (Mac).
Kubernetes cluster runs via kubeadm on Docker Desktop.
All data (skills, memory) stays in the local project directory.
No secrets committed to the repo. Human-in-the-loop for any auto-remediation action.

/speckit-specify
An AI SRE assistant built on Hermes Agent running in Docker.
It watches a kubeadm Kubernetes cluster (on Docker Desktop) for events
using a cron-based skill with kubectl. It detects issues, notifies via
Telegram bot, answers user questions from Telegram, and stores runbook
knowledge in a local Obsidian vault inside the project directory.
Users can send a new skill file via Telegram to extend the agent.
All configuration is stored in .env. Project is managed via Makefile.

/speckit-clarify

/speckit-plan
Runtime: Hermes Agent in Docker container on Docker Desktop Mac.
Cluster: kubeadm on Docker Desktop, accessed via kubeconfig mount.
Server address in kubeconfig uses host.docker.internal (not 127.0.0.1).
LLM: Ollama on Mac host via http://host.docker.internal:11434.
Memory: local ./obsidian/ directory mounted into container as RAG vault.
Skills: local ./skills/ directory mounted and hot-reloadable via Telegram.
Messaging: Telegram Bot API via long polling, no public IP required.
Config: all secrets and settings in .env file.
Management: Makefile with up, down, restart, logs targets.

/speckit-tasks

/speckit-analyze

/speckit-implement
```

Note that the plan's initial assumptions (e.g. `host.docker.internal` for the kubeconfig server
address) were exactly that — assumptions, made before touching real infrastructure. Implementation
surfaced where they were wrong (see "How it works" and `CLAUDE.md` for what actually had to change
and why); SDD front-loads the *thinking*, not a guarantee that the first plan survives contact with
a real cluster.

## How it works

There is no application source code here — the entire system is Hermes Agent configuration plus a
handful of shell/awk scripts and `SKILL.md` instruction files. The central architectural decision is
splitting behavior into two kinds of skill, chosen per-task based on how much it matters that the
behavior is *exactly right every time*:

- **Deterministic** — plain shell, no LLM in the loop, used wherever correctness can't depend on a
  language model's judgment (detecting an issue, deduplicating an alert, writing a note to disk).
- **LLM-driven** — the agent reads a `SKILL.md` as live instructions and decides what to do, used
  wherever the task is inherently conversational (answering an arbitrary question, composing a
  human-readable suggestion).

This split exists because the first version of cluster monitoring *was* LLM-driven, and a local
3B model occasionally decided to stay silent about a genuine new alert — an unacceptable failure
mode for a monitoring system. Detection was rebuilt as a deterministic cron job; the model is still
used, but only for the parts where being conversational matters more than being infallible.

### The monitoring pipeline (`cluster-watch`)

Runs as a Hermes cron job in `--no-agent` ("watchdog") mode: its stdout is delivered to Telegram
verbatim, on a schedule, with **no LLM turn involved in deciding whether to alert**.

```
kubectl (read-only, RBAC-enforced)
        │
        ▼
  collect.sh        snapshot: pods, nodes, recent events (retries before declaring "unreachable")
        │
        ▼
  classify.sh        raw JSON → Issue records: crashloop / restarts / pending /
        │             node_not_ready / warning_event / unreachable
        ▼
  reconcile.sh        dedup against data/sre-state/issues.json — only new or
        │             materially-changed issues get flagged to alert; resolved
        │             issues drop off silently
        ▼
  format-digest.sh     severity-sorted, character-budget-limited digest, each
        │             issue enriched with:
        ├─ snippet.sh        compact per-resource status (not a full YAML dump)
        ├─ propose-fix.sh    ONE isolated call straight to Ollama (bypasses the
        │                    agent loop entirely), 12s timeout, deterministic
        │                    per-type fallback if it fails or times out
        └─ runbook/lookup-note.sh + write-note.sh
                             surfaces a prior human-verified cause if one
                             exists, then records this occurrence
        │
        ▼
   Telegram (empty output = nothing sent this cycle)
```

Empty stdout means silence — the "watchdog" pattern. If `kubectl` can't reach the API after
retrying, a single `unreachable` notice is sent instead of a flood of per-resource errors or dead
silence.

### The conversational skills

- **`k8s-query`** — answers operator questions in Telegram. If your message is literally a `kubectl`
  command, it's run verbatim via the terminal tool and you get the real output back, not a
  paraphrase. Natural-language questions get translated into the narrowest sufficient read-only
  `kubectl` call first. Before answering, it checks the runbook vault for a matching issue type and
  distinguishes a human-verified cause from an unverified first guess.
- **`remediation-proposer`** — the *only* path in the system that can lead to a cluster mutation,
  and even it never executes anything itself. It composes a proposal (exact command, effect, blast
  radius, how to undo it) and waits for an explicit human approval reply. Silence or ambiguity is
  never treated as approval.

### The runbook vault (`obsidian/runbooks/`)

One Markdown note per issue **type** (not per specific resource), written and read by deterministic
scripts (`write-note.sh` / `lookup-note.sh`) — not by agent judgment. Each note has a `verified`
state:

- **Unverified** (default): `## Cause` still holds the automated placeholder. The system treats its
  own AI-generated remediation guess as exactly that — a guess — and says so.
- **Verified**: a human has hand-edited the `## Cause` section with the real, confirmed root cause.
  From then on, the system states it as established fact in both alerts and conversational answers.

This is the whole point of the design: recording an event is not the same as learning from it. The
system only gets measurably smarter about a given failure mode in proportion to how much a human
actually verifies and writes down. Left untouched, it just remembers "this happened N times" plus
its own earlier guess — it does not silently promote that guess into fact over time.

Recurrence history is capped at the 10 most recent entries per note so files don't grow unbounded
over months of operation.

## Security model

- **Containerized, not running directly on the host.** Hermes runs inside a Docker container, not
  as a process on the Mac itself. The container only sees what's explicitly bind-mounted
  (`data/`, `skills/sre/`, `obsidian/`, and a read-only kubeconfig) — it has no access to the rest
  of the host filesystem. This matters most for the "extend the agent by sending a new skill over
  Telegram" feature: an uploaded skill lands in Hermes' Skills Hub quarantine and, even after
  approval, executes inside this same container boundary — not directly on the host machine. It's
  a second layer of isolation underneath the human-approval gate, not a replacement for it.
- **Read-only by RBAC, not by convention.** `skills/sre/cluster-watch/scripts/rbac-readonly.yaml`
  defines a `ServiceAccount`/`ClusterRole` scoped to `get`/`list`/`watch` only. Even if the LLM were
  talked into attempting a mutating `kubectl` command, the cluster rejects it server-side — this is
  a safety net behind the skill-level intent checks, not a substitute for them.
- **Human-in-the-loop for every mutation.** `remediation-proposer` proposes; a human approves;
  only the explicitly-approved action proceeds. No auto-remediation exists anywhere in this system.
- **No secrets in the repo.** Everything sensitive lives in `.env` (gitignored) — see
  `.env.example` for the full list of required/optional keys. `data/`, `kubeconfig/`, and vault
  contents are all gitignored too.
- **Local-first.** All persistent state — memory, skills, runbook notes, logs, cron state — stays
  inside the project directory. The LLM itself is a local Ollama instance; nothing about the core
  monitoring/alerting loop depends on a third-party API.

## Prerequisites

- Docker Desktop (Mac) with a kubeadm/Docker-Desktop Kubernetes cluster running.
- Ollama running on the host with a model pulled (e.g. `ollama pull llama3.2:latest`).
- A Telegram bot token from [@BotFather](https://t.me/BotFather) and your numeric Telegram user ID
  (from [@userinfobot](https://t.me/userinfobot)).

## Setup

```sh
cp .env.example .env        # fill in TELEGRAM_BOT_TOKEN, TELEGRAM_ALLOWED_USERS, LLM_MODEL_NAME
# Apply the read-only RBAC and build kubeconfig/config — see
# skills/sre/cluster-watch/scripts/rbac-readonly.yaml and specs/001-k8s-sre-assistant/research.md R2
make up                     # validates config, builds the image (adds kubectl+jq+curl), starts the stack
make logs                   # follow startup
```

Message your bot on Telegram (send `/start`) before it can push you alerts — Telegram requires the
user to initiate contact with a bot first. The monitoring cron job itself isn't auto-registered on
a fresh clone (see `CLAUDE.md` for why) — register it once with `hermes cron create`, using the
exact command and entry script documented in `skills/sre/cluster-watch/SKILL.md` step 5.

`make down` / `make restart` are also available. Full walkthrough and validation scenarios:
[specs/001-k8s-sre-assistant/quickstart.md](specs/001-k8s-sre-assistant/quickstart.md).

## What's here

```
skills/sre/
├── cluster-watch/        deterministic monitoring + alerting (see pipeline above)
├── k8s-query/            conversational read-only diagnostics
├── remediation-proposer/ propose-and-approve mutation flow (never auto-executes)
└── runbook/              deterministic vault read/write, human-verified vs AI-guessed knowledge
```

Full spec, plan, research, and task breakdown: `specs/001-k8s-sre-assistant/`. Guidance for future
development on this repo (commands, architecture gotchas worth not re-learning the hard way):
[`CLAUDE.md`](CLAUDE.md).
