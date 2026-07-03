# Escapes free-form text for Telegram MarkdownV2, but treats single-backtick-delimited
# segments as inline code: those get the NARROW code-escape rule (only backslash and backtick)
# and stay wrapped in backticks so they render as clean monospace, instead of the full
# punctuation-escape rule that makes kubectl commands / jsonpath expressions unreadable (a wall
# of backslashes before every hyphen, dot, bracket, brace).
#
# Usage: awk -f esc-mixed.awk   (reads text on stdin, one call per logical string)
# Assumes well-formed (even count) backticks; an unmatched trailing backtick is treated as
# literal prose text rather than left dangling.
BEGIN { FS = "`" }
{
  if (NF % 2 == 0) {
    # Odd number of backticks (even field count) - not a clean set of pairs (e.g. a code span
    # opened right before the 280-char truncation cut off its closing backtick - live-observed).
    # Treat the whole line as prose. This branch processes $0 (the raw, UNSPLIT line), which
    # still contains every original backtick character - unlike the per-field loop below, where
    # a prose segment can never contain a backtick by construction (FS already split on it).
    # The escape class here MUST include backtick, or a stray one leaks through unescaped and
    # Telegram starts parsing an unclosed inline-code entity (live-reproduced: caused
    # "MarkdownV2 parse failed" further into the message).
    seg = $0
    gsub(/\\/, "\\\\", seg)
    gsub(/[_*\[\]()~`>#+=|{}.!-]/, "\\\\&", seg)
    print seg
    next
  }
  out = ""
  for (i = 1; i <= NF; i++) {
    seg = $i
    if (i % 2 == 1) {
      gsub(/\\/, "\\\\", seg)
      gsub(/[_*\[\]()~>#+=|{}.!-]/, "\\\\&", seg)
      out = out seg
    } else {
      gsub(/\\/, "\\\\", seg)
      gsub(/`/, "\\`", seg)
      out = out "`" seg "`"
    }
  }
  print out
}
