#!/bin/sh
# Formats newline-delimited Issue JSON (from reconcile.sh, on stdin) into a single, rich,
# human-readable digest message. Prints nothing if there are no issues (watchdog convention:
# empty stdout = no delivery). Grouped into one message so a flood becomes one digest, not one
# alert each (FR-016).
#
# Telegram caps messages at 4096 chars, and --no-agent delivery sends this script's stdout as
# ONE message verbatim (no auto-splitting, modulo Hermes' own markdown conversion below). So:
# issues are sorted by severity, and only as many as fit a safe character budget get full
# enrichment (snippet + proposed fix); the rest are listed as compact one-liners.
#
# Formatting: emit PLAIN, standard markdown (**bold**, ```fenced blocks```) with NO manual
# escaping. Hermes' own send path (tools/send_message_tool.py -> format_message() in
# gateway/platforms/telegram.py) converts standard markdown to MarkdownV2 automatically. Two
# live findings, in order:
#   1. Manually pre-escaping this text ourselves made Hermes escape our OWN backslashes a second
#      time (every "\-", "\.", "\(" rendered as a literal visible backslash) - fixed by emitting
#      plain unescaped text and trusting their converter.
#   2. Some digests still intermittently fail MarkdownV2 parsing and fall back to plain text -
#      this is a bug in Hermes' OWN converter, triggered by something in the non-deterministic
#      LLM-generated suggestion text, NOT by our **bold** usage (live-verified: a digest with
#      bold markup entirely removed still failed the same way, while digests WITH bold succeed
#      the large majority of the time and render noticeably better - real code box, highlighted
#      inline `code` spans). So: keep the richer bold/code formatting; accept that a small
#      fraction of alerts will occasionally fall back to plain (still clean, no visible
#      backslashes) rather than degrade every message's formatting to avoid a bug we can't
#      patch (it lives in Hermes' own vendored code, not ours).
set -eu

SCRIPT_DIR="$(dirname "$0")"
CHAR_BUDGET=2200
BUDGET_FILE="/tmp/.format-digest-budget-used.$$"
OVERFLOW_FILE="/tmp/.format-digest-overflow.$$"
trap 'rm -f "$BUDGET_FILE" "$OVERFLOW_FILE"' EXIT

ISSUES="$(cat)"
[ -z "$ISSUES" ] && exit 0

SORTED=$(printf '%s\n' "$ISSUES" | jq -s '
  sort_by(if .severity == "critical" then 0 elif .severity == "warning" then 1 else 2 end)
' | jq -c '.[]')

COUNT=$(printf '%s\n' "$SORTED" | grep -c . || true)

echo "SRE Alert: $COUNT issue(s) detected"
echo ""

printf '%s\n' "$SORTED" | while IFS= read -r issue; do
  TYPE=$(printf '%s' "$issue" | jq -r '.type')
  NAMESPACE=$(printf '%s' "$issue" | jq -r '.namespace')
  RESOURCE=$(printf '%s' "$issue" | jq -r '.resource')
  SEVERITY=$(printf '%s' "$issue" | jq -r '.severity')
  DETAIL=$(printf '%s' "$issue" | jq -r '.detail')

  ONE_LINER="• [$SEVERITY] $TYPE — $NAMESPACE/$RESOURCE: $DETAIL"

  [ -f "$BUDGET_FILE" ] || echo 0 > "$BUDGET_FILE"
  used=$(cat "$BUDGET_FILE")

  if [ "$used" -lt "$CHAR_BUDGET" ]; then
    SNIPPET=$("$SCRIPT_DIR/snippet.sh" "$NAMESPACE" "$RESOURCE" 2>/dev/null || echo "(snippet unavailable)")

    BLOCK="— **[$SEVERITY] $TYPE** — $NAMESPACE/$RESOURCE
Error: **$DETAIL**"

    REASON=$(printf '%s\n' "$SNIPPET" | grep -m1 -E '^(waiting\.reason|terminated\.reason|lastState\.terminated\.reason|reason):' | cut -d: -f2- | sed 's/^ *//')
    if [ -n "$REASON" ]; then
      BLOCK="$BLOCK
Reason: **$REASON**"
    fi

    if [ -n "$SNIPPET" ]; then
      BLOCK="$BLOCK
\`\`\`
$SNIPPET
\`\`\`"
    fi

    # Deterministic runbook lookup — surfaces a HUMAN-VERIFIED cause if one exists (i.e. someone
    # has actually edited the note's Cause section away from the automated placeholder). Checked
    # BEFORE write-note.sh below so this reflects history from prior occurrences, not this one.
    NOTE_LOOKUP=$("$SCRIPT_DIR/../../runbook/scripts/lookup-note.sh" "$TYPE" 2>/dev/null || echo '{"exists":false}')
    NOTE_VERIFIED=$(printf '%s' "$NOTE_LOOKUP" | jq -r '.verified // false')
    if [ "$NOTE_VERIFIED" = "true" ]; then
      PRIOR_OCC=$(printf '%s' "$NOTE_LOOKUP" | jq -r '.occurrences // 0')
      KNOWN_CAUSE=$(printf '%s' "$NOTE_LOOKUP" | jq -r '.cause // ""')
      BLOCK="$BLOCK
Known cause (human-verified, seen $PRIOR_OCC time(s) before): $KNOWN_CAUSE"
    fi

    SUGGESTION=$("$SCRIPT_DIR/propose-fix.sh" "$TYPE" "$DETAIL" 2>/dev/null || echo "")
    if [ -n "$SUGGESTION" ]; then
      BLOCK="$BLOCK
Suggested fix (AI-generated — verify before running): $SUGGESTION"
    fi

    jq -n --arg type "$TYPE" --arg namespace "$NAMESPACE" --arg resource "$RESOURCE" \
      --arg detail "$DETAIL" --arg reason "$REASON" --arg suggestion "$SUGGESTION" \
      '{type:$type, namespace:$namespace, resource:$resource, detail:$detail, reason:$reason, suggestion:$suggestion}' \
      | "$SCRIPT_DIR/../../runbook/scripts/write-note.sh" 2>/dev/null || true

    printf '%s\n\n' "$BLOCK"
    echo $((used + ${#BLOCK} + 2)) > "$BUDGET_FILE"
  else
    echo "$ONE_LINER" >> "$OVERFLOW_FILE"
  fi
done

if [ -f "$OVERFLOW_FILE" ]; then
  echo "More issues (summary only — digest length limit reached):"
  cat "$OVERFLOW_FILE"
fi
