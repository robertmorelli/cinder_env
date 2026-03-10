#!/bin/bash

# Parse --config=<file> out of args
EXTRA_ARGS=()
PASSTHROUGH=()

for arg in "$@"; do
  if [[ "$arg" == --config=* ]]; then
    CONFIG_FILE="${arg#--config=}"
  else
    PASSTHROUGH+=("$arg")
  fi
done

# Load config flags (defaults if no config provided)
EXTRA_ARGS=($(python /scripts/parse_config.py ${CONFIG_FILE:+$CONFIG_FILE}))

# Typecheck (no extra flags)
TC_OUTPUT=$(python -m cinderx.compiler --static -c "${PASSTHROUGH[@]}" 2>&1)
if [ $? -ne 0 ]; then
  echo "$(printf '("typecheck error", %q, "")' "$TC_OUTPUT")" >&2
  exit 1
fi

# Run (with extra flags expanded before the file)
OUTPUT=$(python "${EXTRA_ARGS[@]}" "${PASSTHROUGH[@]}" 2>/tmp/runtime_stderr)
EXIT_CODE=$?
STDERR=$(cat /tmp/runtime_stderr)

if [ $EXIT_CODE -ne 0 ] || [ -n "$STDERR" ]; then
  echo "$(printf '("runtime error", %q, %q)' "$STDERR" "$OUTPUT")" >&2
  exit $EXIT_CODE
fi

echo "$OUTPUT"