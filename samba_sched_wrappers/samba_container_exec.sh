#!/usr/bin/env bash
set -euo pipefail

sched_dir="${SAMBA_SCHED_DIR:?SAMBA_SCHED_DIR not set}"
meta="${sched_dir%/}/container.meta"

# shellcheck disable=SC1090
source "$meta"  # provides RUNTIME, SIF, ENVFILE, BINDSFILE

# Build binds args from file
bind_args=()
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  bind_args+=( --bind "$line" )
done < "$BINDSFILE"

exec "$RUNTIME" exec --cleanenv --env-file "$ENVFILE" "${bind_args[@]}" "$SIF" "$@"
