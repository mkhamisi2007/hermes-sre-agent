# Feature Specification: Kubernetes SRE Assistant

**Feature Branch**: `001-k8s-sre-assistant`

**Created**: 2026-07-03

**Status**: Draft

**Input**: User description: "An AI SRE assistant built on Hermes Agent running in Docker. It watches a kubeadm Kubernetes cluster (on Docker Desktop) for events using a cron-based skill with kubectl. It detects issues, notifies via Telegram bot, answers user questions from Telegram, and stores runbook knowledge in a local Obsidian vault inside the project directory. Users can send a new skill file via Telegram to extend the agent. All configuration is stored in .env. Project is managed via Makefile."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Automated cluster monitoring and alerting (Priority: P1)

An on-call operator wants to be told when something goes wrong in their cluster without having to
watch a terminal. The assistant periodically inspects the cluster, recognizes abnormal conditions
(crashing pods, restart loops, pending/unschedulable pods, node problems, warning events), and
sends a clear, human-readable alert to the operator's messaging channel describing what happened,
where, and why it matters.

**Why this priority**: This is the core value of the product — turning a live cluster into proactive
notifications. Without it, nothing else has a reason to exist. It is the minimum viable product.

**Independent Test**: Deploy a deliberately broken workload (e.g., an image that always crashes) to
the cluster, wait for the next monitoring cycle, and confirm a correctly described alert arrives in
the messaging channel within the configured interval.

**Acceptance Scenarios**:

1. **Given** a healthy cluster, **When** a pod enters a crash loop, **Then** the operator receives
   an alert naming the pod, namespace, and the detected condition within one monitoring cycle.
2. **Given** a previously reported issue, **When** the same issue persists across cycles, **Then**
   the operator is not spammed with a duplicate alert for every cycle.
3. **Given** an issue that has been resolved, **When** the next monitoring cycle runs, **Then** the
   condition no longer generates a new alert.
4. **Given** the cluster is unreachable, **When** a monitoring cycle runs, **Then** the operator is
   notified that monitoring could not reach the cluster rather than silently failing.

---

### User Story 2 - Ask the assistant questions from the messaging channel (Priority: P2)

An operator wants to investigate the cluster conversationally — asking things like "why is the
payments pod restarting?" or "show me pods that aren't ready" — and get an answer back in the same
channel, without opening a terminal or a dashboard.

**Why this priority**: On-demand diagnostics greatly amplify the value of alerts by letting the
operator triage from their phone, but the product still delivers value with alerts alone.

**Independent Test**: Send a question about a known cluster condition to the messaging channel and
confirm a relevant, accurate answer is returned referencing real cluster state.

**Acceptance Scenarios**:

1. **Given** the assistant is running, **When** the operator asks about the status of a named
   workload, **Then** the assistant replies with the current state of that workload.
2. **Given** an unauthorized sender, **When** they message the assistant, **Then** their request is
   rejected and not acted upon.
3. **Given** a question the assistant cannot answer or that would require a mutating action, **When**
   it is received, **Then** the assistant responds explaining the limitation rather than guessing or
   acting without approval.

---

### User Story 3 - Capture and reuse runbook knowledge (Priority: P3)

When the assistant diagnoses an issue or an operator resolves one, the relevant knowledge (symptom,
cause, remediation steps) is recorded as a note in a local knowledge base so it can be referenced and
reused the next time a similar issue appears.

**Why this priority**: Institutional knowledge accumulation differentiates an assistant from a bare
alerting script, but the alerting and Q&A flows are usable before this exists.

**Independent Test**: Trigger a diagnosis, confirm a corresponding runbook note is created in the
local knowledge base, then ask about the same issue later and confirm the assistant references the
stored knowledge.

**Acceptance Scenarios**:

1. **Given** a diagnosed issue, **When** the diagnosis completes, **Then** a runbook note capturing
   the symptom and suggested remediation is written to the local knowledge base.
2. **Given** an existing runbook note for a recurring issue, **When** the same issue recurs, **Then**
   the assistant's response references the stored runbook knowledge.
3. **Given** the knowledge base, **When** notes are written, **Then** they remain in the local project
   directory and are readable/editable outside the assistant.

---

### User Story 4 - Extend the assistant by sending a new skill (Priority: P4)

An operator wants to teach the assistant a new capability at runtime by sending a new skill file
through the messaging channel, without rebuilding or redeploying the container.

**Why this priority**: Runtime extensibility is a powerful differentiator but is an advanced,
lower-frequency workflow that depends on all prior stories being in place.

**Independent Test**: Send a valid new skill file through the messaging channel and confirm the
assistant registers it and can invoke the new capability, gated by an approval step.

**Acceptance Scenarios**:

1. **Given** an authorized operator, **When** they send a valid skill file, **Then** the assistant
   stores it in the local project directory and makes the new capability available after explicit
   human approval.
2. **Given** a skill file from an unauthorized sender, **When** it is received, **Then** it is
   rejected and never installed.
3. **Given** a malformed or invalid skill file, **When** it is received, **Then** the assistant
   rejects it with a clear explanation and does not alter its existing capabilities.

---

### Edge Cases

- What happens when the messaging service is unreachable while an alert needs to be sent? Alerts
  should be queued or retried, and failures surfaced, so notifications are not silently lost.
- How does the system handle a flood of simultaneous cluster events? Alerts should be grouped or
  rate-limited so the operator receives a digestible summary rather than hundreds of messages.
- What happens if two monitoring cycles overlap (a cycle runs longer than the interval)? Cycles must
  not stack up or double-report the same condition.
- What happens if an operator asks the assistant to perform a mutating/remediation action? Per the
  project constitution, the assistant must propose it and require explicit human approval, never act
  autonomously.
- What happens if a sent skill file attempts to perform destructive or unauthorized actions? It must
  be quarantined pending human review and never auto-activated.
- What happens if required configuration is missing at startup? The assistant must fail fast with a
  clear message identifying the missing configuration rather than starting in a broken state.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST inspect the target Kubernetes cluster on a recurring, configurable schedule.
- **FR-002**: System MUST detect abnormal cluster conditions including at minimum: crash-looping pods,
  excessive restarts, pending/unschedulable pods, node not-ready conditions, and warning-level events.
- **FR-003**: System MUST send human-readable alerts describing each detected issue (what, where, and
  why it matters) to the operator's messaging channel.
- **FR-004**: System MUST deduplicate alerts so a persistent condition does not generate a repeat
  notification on every cycle.
- **FR-005**: System MUST notify the operator when it cannot reach or inspect the cluster, rather than
  failing silently.
- **FR-006**: Users MUST be able to ask the assistant questions about cluster state through the
  messaging channel and receive relevant answers reflecting real cluster state.
- **FR-007**: System MUST restrict who may interact with it to an authorized set of senders and reject
  all requests from unauthorized senders.
- **FR-008**: System MUST NOT perform any mutating or remediation action against the cluster without
  explicit human approval; it MAY propose and prepare such actions.
- **FR-009**: System MUST record runbook knowledge (symptom, cause, remediation) as notes in a local
  knowledge base stored inside the project directory.
- **FR-010**: System MUST reference relevant stored runbook knowledge when responding to recurring or
  related issues.
- **FR-011**: Users MUST be able to submit a new skill file through the messaging channel to extend the
  assistant's capabilities.
- **FR-012**: System MUST validate submitted skill files and require explicit human approval before a
  new skill becomes active.
- **FR-013**: System MUST reject malformed, invalid, or unauthorized skill submissions without altering
  existing capabilities.
- **FR-014**: System MUST read all its configuration from a single local configuration source and MUST
  NOT require secrets to be committed to version control.
- **FR-015**: System MUST fail fast at startup with a clear message when required configuration is
  missing or invalid.
- **FR-016**: System MUST group or rate-limit alerts during event floods so the operator receives a
  digestible summary rather than an overwhelming stream.
- **FR-017**: System MUST produce a local, human-readable record of detected issues, proposed actions,
  approvals, and outcomes for auditability.
- **FR-018**: All persistent state (runbook notes, skills, configuration, logs) MUST remain within the
  local project directory.

### Key Entities *(include if feature involves data)*

- **Cluster Event / Issue**: A detected abnormal condition, with attributes such as type, affected
  resource (name, namespace/node), severity, first-seen and last-seen timestamps, and current status.
- **Alert / Notification**: A message delivered to the operator, derived from one or more issues,
  including a summary, affected resources, and timestamp.
- **Runbook Note**: A knowledge-base entry capturing an issue's symptom, cause, and remediation steps,
  stored as an editable local document.
- **Skill**: A unit of extensible capability submitted by an authorized operator, with a validation
  state (pending / approved / rejected) and an activation status.
- **Authorized Sender**: An operator permitted to interact with the assistant, identified by the
  messaging channel's sender identity.
- **Configuration**: The set of local settings and secrets that govern schedule, authorization,
  connectivity, and behavior.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A newly introduced cluster fault is reported to the operator within one monitoring cycle
  (default cycle no longer than 5 minutes).
- **SC-002**: At least 95% of alerts delivered to the operator correspond to a real, current cluster
  condition (low false-positive rate).
- **SC-003**: A persistent issue generates no more than one alert until its status materially changes,
  eliminating repeat-notification spam.
- **SC-004**: An operator can get an answer to a cluster-status question through the messaging channel
  in under 30 seconds under normal conditions.
- **SC-005**: 100% of mutating/remediation actions require and receive explicit human approval before
  execution (zero autonomous mutations).
- **SC-006**: 100% of requests and skill submissions from unauthorized senders are rejected.
- **SC-007**: Every diagnosed issue results in a corresponding runbook note being available in the
  local knowledge base.
- **SC-008**: The full system can be started on a clean machine from the project directory using the
  documented management commands, with no manual, undocumented host changes.

## Assumptions

- The messaging channel referenced throughout is a Telegram bot, chosen as the operator's interface
  for both alerts and interaction.
- The local knowledge base is an Obsidian-compatible vault of Markdown notes stored inside the project
  directory, so notes are readable and editable outside the assistant.
- Cluster inspection is read-only by default and performed with credentials scoped to least privilege,
  consistent with the project constitution.
- Authorization is enforced via an allowlist of permitted messaging-channel sender identities defined
  in local configuration.
- Configuration and secrets live in a local `.env` file that is excluded from version control; the
  project is operated via a Makefile.
- The target environment is a single kubeadm Kubernetes cluster running on Docker Desktop (Mac), with
  the assistant itself running in a Docker container.
- Only one operator or a small trusted team uses the assistant; multi-tenant isolation is out of scope
  for the initial version.
- Historical long-term retention/archival of alerts and metrics beyond the local logs and knowledge
  base is out of scope for the initial version.
