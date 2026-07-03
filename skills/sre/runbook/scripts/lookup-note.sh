#!/bin/sh
# Looks up the runbook note for one issue type and reports whether its Cause section has
# actually been human-verified, vs still holding the automated placeholder written by
# write-note.sh. This distinction matters: feeding an unverified AI guess back into future
# answers just reinforces a first guess, not real learning — only a human-edited Cause is
# trustworthy enough to surface as established knowledge.
#
# Usage: lookup-note.sh <issue-type>
# Prints JSON: {"exists":bool, "verified":bool, "occurrences":N, "cause":"...", "remediation":"..."}
# to stdout. exists=false if no note file yet.
set -eu

TYPE="${1:?usage: lookup-note.sh <issue-type>}"
VAULT_DIR="/opt/data/obsidian/runbooks"
NOTE_FILE="$VAULT_DIR/${TYPE}.md"

if [ ! -f "$NOTE_FILE" ]; then
  echo '{"exists":false,"verified":false,"occurrences":0,"cause":"","remediation":""}'
  exit 0
fi

OCC=$(grep -m1 '^occurrences:' "$NOTE_FILE" | sed 's/occurrences: *//')
case "$OCC" in ''|*[!0-9]*) OCC=1 ;; esac

# Extract the Cause section body: everything between "## Cause" and the next "## " heading.
CAUSE=$(awk '/^## Cause/{f=1;next} /^## /{f=0} f' "$NOTE_FILE" | sed '/^[[:space:]]*$/d')
REMEDIATION=$(awk '/^## Remediation/{f=1;next} /^## /{f=0} f' "$NOTE_FILE" | sed '/^[[:space:]]*$/d')

case "$CAUSE" in
  "Unknown — captured automatically"*) VERIFIED=false ;;
  "") VERIFIED=false ;;
  *) VERIFIED=true ;;
esac

jq -n --arg cause "$CAUSE" --arg remediation "$REMEDIATION" --argjson occ "$OCC" --argjson verified "$VERIFIED" \
  '{exists: true, verified: $verified, occurrences: $occ, cause: $cause, remediation: $remediation}'
