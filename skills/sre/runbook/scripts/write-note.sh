#!/bin/sh
# Writes or updates a runbook note in the Obsidian vault for one issue. Deterministic shell —
# no LLM call of its own (reuses whatever reason/suggestion the caller already computed), same
# reliability approach as cluster-watch's own detection path.
#
# One note per issue TYPE (not per specific resource) — matches skills/sre/runbook/SKILL.md's
# "search for a note whose issue_type matches" lookup model. A recurring issue of the same type
# increments `occurrences` and appends a dated recurrence entry rather than duplicating the note.
#
# Usage: write-note.sh reads one JSON object on stdin:
#   {"type":"crashloop","namespace":"default","resource":"payments","detail":"...","reason":"...","suggestion":"..."}
set -eu

# NOTE: intentionally NOT using $OBSIDIAN_VAULT_PATH here. That variable is a HOST-side path
# (docker-compose.yml's volume source, e.g. "./obsidian") but env_file also exports it into the
# container's own environment, where it's meaningless as a filesystem path — live-found: it
# silently resolved to a relative "./obsidian/runbooks" under whatever the shell's cwd happened
# to be (landed at /opt/hermes/obsidian/, not the real mount), so notes were being written
# outside the actual Obsidian vault entirely. The real, fixed in-container mount point is always
# /opt/data/obsidian (see docker-compose.yml), so it's hardcoded here rather than templated.
VAULT_DIR="/opt/data/obsidian/runbooks"
mkdir -p "$VAULT_DIR"

INPUT="$(cat)"
TYPE=$(printf '%s' "$INPUT" | jq -r '.type')
NAMESPACE=$(printf '%s' "$INPUT" | jq -r '.namespace')
RESOURCE=$(printf '%s' "$INPUT" | jq -r '.resource')
DETAIL=$(printf '%s' "$INPUT" | jq -r '.detail')
REASON=$(printf '%s' "$INPUT" | jq -r '.reason // ""')
SUGGESTION=$(printf '%s' "$INPUT" | jq -r '.suggestion // ""')

NOTE_FILE="$VAULT_DIR/${TYPE}.md"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

MAX_RECURRENCES=10

if [ -f "$NOTE_FILE" ]; then
  OCC=$(grep -m1 '^occurrences:' "$NOTE_FILE" | sed 's/occurrences: *//')
  case "$OCC" in ''|*[!0-9]*) OCC=1 ;; esac
  OCC=$((OCC + 1))
  sed -i -e "s/^occurrences:.*/occurrences: $OCC/" -e "s/^updated:.*/updated: $NOW/" "$NOTE_FILE"

  # "## Recurrence Log" is a real top-level heading (not "###") specifically so
  # lookup-note.sh's section extraction (awk, stops at the next "## ") can tell where
  # "Remediation" ends — without it, every recurrence entry got absorbed into the
  # Remediation text, ballooning without bound (live-found: 60 entries in one note).
  if ! grep -q '^## Recurrence Log' "$NOTE_FILE"; then
    printf '\n## Recurrence Log\n' >> "$NOTE_FILE"
  fi
  {
    echo ""
    echo "### Recurrence at $NOW"
    echo "- Resource: $NAMESPACE/$RESOURCE"
    echo "- Detail: $DETAIL"
    [ -n "$REASON" ] && echo "- Reason: $REASON"
  } >> "$NOTE_FILE"

  # Cap the log to the most recent MAX_RECURRENCES entries so the file (and anything that
  # reads it back) doesn't grow unbounded across months of operation.
  SCRIPT_DIR="$(dirname "$0")"
  awk -v max="$MAX_RECURRENCES" -f "$SCRIPT_DIR/trim-recurrences.awk" "$NOTE_FILE" > "${NOTE_FILE}.tmp"
  mv "${NOTE_FILE}.tmp" "$NOTE_FILE"
else
  {
    echo "---"
    echo "title: \"$TYPE\""
    echo "issue_type: $TYPE"
    echo "created: $NOW"
    echo "updated: $NOW"
    echo "occurrences: 1"
    echo "---"
    echo ""
    echo "## Symptom"
    echo ""
    echo "- Resource: $NAMESPACE/$RESOURCE"
    echo "- Detail: $DETAIL"
    [ -n "$REASON" ] && echo "- Reason: $REASON"
    echo ""
    echo "## Cause"
    echo ""
    echo "Unknown — captured automatically from a detected cluster condition. Edit this section"
    echo "once the root cause is understood; it will not be overwritten by future automated runs"
    echo "beyond the Symptom/recurrence sections above."
    echo ""
    echo "## Remediation"
    echo ""
    if [ -n "$SUGGESTION" ]; then
      echo "$SUGGESTION"
      echo ""
      echo "(AI-generated suggestion — verify before running any commands.)"
    else
      echo "(No suggestion available yet.)"
    fi
  } > "$NOTE_FILE"
fi
