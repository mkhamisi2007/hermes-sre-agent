<!--
Sync Impact Report
==================
Version change: (template) → 1.0.0
Bump rationale: Initial ratification of the Hermes SRE Agent constitution.

Modified principles: N/A (initial creation)
Added principles:
  - I. Local-First Data Sovereignty
  - II. Secrets Stay Out of the Repo (NON-NEGOTIABLE)
  - III. Human-in-the-Loop Remediation (NON-NEGOTIABLE)
  - IV. Reproducible Containerized Environment
  - V. Least-Privilege & Auditability
Added sections:
  - Security & Operational Constraints
  - Development Workflow
  - Governance

Templates requiring updates:
  - ✅ .specify/templates/plan-template.md (generic "Constitution Check" gate; no principle
       names hardcoded — no edit required)
  - ✅ .specify/templates/spec-template.md (no constitution references — no edit required)
  - ✅ .specify/templates/tasks-template.md (no constitution references — no edit required)

Follow-up TODOs: None. Ratification date set to initial adoption date (2026-07-03).
-->

# Hermes SRE Agent Constitution

## Core Principles

### I. Local-First Data Sovereignty
All persistent agent state — skills, memory, configuration, and logs — MUST live inside the
local project directory and MUST NOT be written to remote services or shared drives by default.
The agent MUST remain fully functional without any external SaaS dependency for its core loop.
Any feature that requires egress to a third-party service MUST be opt-in, documented, and
disableable via configuration.

**Rationale**: A local-first design keeps the portfolio project self-contained, reproducible on
any machine, and free of hidden cloud coupling that would compromise privacy or portability.

### II. Secrets Stay Out of the Repo (NON-NEGOTIABLE)
No secret — API key, token, kubeconfig credential, password, or certificate private key — MAY be
committed to version control. Secrets MUST be supplied at runtime via environment variables,
mounted files, or a local secret store that is `.gitignore`d. Every change MUST be scannable for
leaked credentials before commit, and any detected leak MUST block the commit.

**Rationale**: A security-conscious DevOps project must model the practices it advocates; a single
committed credential permanently compromises the repo's history and its credibility.

### III. Human-in-the-Loop Remediation (NON-NEGOTIABLE)
Any action that mutates infrastructure state — scaling, restarting, deleting, patching, or applying
manifests to the Kubernetes cluster — MUST require explicit human approval before execution. The
agent MAY diagnose, propose, and prepare remediation plans autonomously, but MUST NOT auto-apply
them. Every proposed action MUST be presented with its intended effect and blast radius so a human
can approve or reject it.

**Rationale**: Autonomous remediation against live infrastructure is high-risk; a human gate keeps
the operator accountable and prevents an agent error from cascading into an outage.

### IV. Reproducible Containerized Environment
The Hermes agent MUST run inside a Docker container on Docker Desktop, and the target Kubernetes
cluster MUST be provisioned via kubeadm on Docker Desktop. Environment setup MUST be codified
(Dockerfile, compose files, manifests) so a clean machine can reproduce the full stack from the
repository. Undocumented manual host mutations are NOT permitted as part of the supported workflow.

**Rationale**: Reproducibility is what turns a demo into a portfolio-grade project; codified
environments guarantee the reviewer sees exactly what the author built.

### V. Least-Privilege & Auditability
The agent's access to the cluster and host MUST follow least-privilege: it MUST use scoped
credentials and RBAC that grant only what a given task requires. Every remediation decision and
approved action MUST produce a structured, human-readable audit record (what, why, who approved,
outcome) stored locally per Principle I.

**Rationale**: Least-privilege limits the damage of a compromise or bug, and an audit trail makes
the agent's behavior reviewable and trustworthy.

## Security & Operational Constraints

- Runtime target: Docker container on Docker Desktop (Mac); cluster via kubeadm on Docker Desktop.
- Secret handling: injected at runtime only; never committed (Principle II).
- Data locality: skills and memory persisted to the local project directory only (Principle I).
- Network egress: default-deny posture for third-party services; opt-in and documented when needed.
- Destructive/mutating operations: gated behind human approval (Principle III).

## Development Workflow

- Changes MUST be reviewed against this constitution before merge; violations MUST be justified in
  writing or the change MUST be revised.
- Pre-commit secret scanning MUST pass before any commit lands.
- New auto-remediation capabilities MUST ship with an approval-gate implementation and an audit
  record, or they MUST NOT ship.
- Environment changes MUST be reflected in the codified setup (Dockerfile / manifests) in the same
  change that introduces them.

## Governance

This constitution supersedes ad-hoc practices for the Hermes SRE Agent project. Amendments MUST be
proposed as a documented change to this file, including the rationale and the semantic version bump.

Versioning policy (semantic):
- MAJOR: backward-incompatible removal or redefinition of a principle or governance rule.
- MINOR: a new principle or section, or materially expanded guidance.
- PATCH: clarifications, wording, or non-semantic refinements.

Compliance review: every plan, spec, and task set generated for this project MUST pass a
Constitution Check against the principles above. The NON-NEGOTIABLE principles (II and III) admit no
exceptions. Complexity or deviations MUST be explicitly justified against these principles or removed.

**Version**: 1.0.0 | **Ratified**: 2026-07-03 | **Last Amended**: 2026-07-03
