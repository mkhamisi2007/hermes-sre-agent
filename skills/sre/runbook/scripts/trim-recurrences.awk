# Keeps everything up to and including "## Recurrence Log", then keeps only the LAST N
# "### Recurrence at ..." blocks after that heading (each block runs until the next one or EOF).
# Usage: awk -v max=10 -f trim-recurrences.awk notefile.md
BEGIN { in_log = 0; block = -1 }
{
  lines[NR] = $0
  if ($0 ~ /^## Recurrence Log/) { log_line = NR }
  if ($0 ~ /^### Recurrence at/) { block++; block_start[block] = NR }
}
END {
  total = NR
  if (!log_line) {
    for (i = 1; i <= total; i++) print lines[i]
    exit
  }
  for (i = 1; i <= log_line; i++) print lines[i]
  first_kept_block = block - max + 1
  if (first_kept_block < 0) first_kept_block = 0
  start_line = block_start[first_kept_block]
  for (i = start_line; i <= total; i++) print lines[i]
}
