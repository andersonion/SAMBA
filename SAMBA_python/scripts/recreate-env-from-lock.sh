#!/usr/bin/env bash
set -euo pipefail

ENV_NAME="${ENV_NAME:-samba-py}"
LOCK_YML="${LOCK_YML:-environment.lock.yml}"

die(){ echo "[ERROR] $*" >&2; exit 1; }
info(){ echo "[INFO] $*"; }
have(){ command -v "$1" >/dev/null 2>&1; }

if [[ ! -f "$LOCK_YML" ]]; then
  die "Missing $LOCK_YML (run freeze-env.sh first or copy it into place)."
fi

if have micromamba; then TOOL="micromamba"
elif have mamba; then TOOL="mamba"
elif have conda; then TOOL="conda"
else die "Need conda/mamba/micromamba on PATH."
fi

info "Creating env '$ENV_NAME' from lock file: $LOCK_YML"
case "$TOOL" in
  conda|mamba)
    "$TOOL" env create -n "$ENV_NAME" -f "$LOCK_YML"
    ;;
  micromamba)
    micromamba create -n "$ENV_NAME" -f "$LOCK_YML" -y
    ;;
esac

info "Done."
