#!/usr/bin/env bash
set -euo pipefail

ENV_NAME="${ENV_NAME:-samba-py}"
DEFAULT_PREFIX="$(pwd)/.envs/${ENV_NAME}"
ENV_PREFIX="${ENV_PREFIX:-$DEFAULT_PREFIX}"

LOCK_YML="${LOCK_YML:-environment.lock.yml}"

die(){ echo "[ERROR] $*" >&2; exit 1; }
info(){ echo "[INFO] $*"; }
have(){ command -v "$1" >/dev/null 2>&1; }

[[ -f "$LOCK_YML" ]] || die "Missing $LOCK_YML (run freeze-env.sh first)."
mkdir -p "$(dirname "$ENV_PREFIX")"

if have micromamba; then TOOL="micromamba"
elif have mamba; then TOOL="mamba"
elif have conda; then TOOL="conda"
else die "Need conda/mamba/micromamba on PATH."
fi

info "Creating env at prefix '$ENV_PREFIX' from lock file: $LOCK_YML"

case "$TOOL" in
  conda|mamba)
    "$TOOL" env create -p "$ENV_PREFIX" -f "$LOCK_YML"
    ;;
  micromamba)
    micromamba create -p "$ENV_PREFIX" -f "$LOCK_YML" -y
    ;;
esac

info "Done."
echo "Run:"
case "$TOOL" in
  conda|mamba) echo "  $TOOL run -p \"$ENV_PREFIX\" python -c \"import samba_py; print('ok')\"";;
  micromamba)  echo "  micromamba run -p \"$ENV_PREFIX\" python -c \"import samba_py; print('ok')\"";;
esac
