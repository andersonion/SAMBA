#!/usr/bin/env bash
set -euo pipefail

ENV_YML="${ENV_YML:-environment.yml}"
ENV_NAME="${ENV_NAME:-samba-py}"

FREEZE_AFTER=0

# pip-only extras (kept out of conda to reduce solver pain)
PIP_EXTRAS=(
  "indexed_gzip"
)

die(){ echo "[ERROR] $*" >&2; exit 1; }
info(){ echo "[INFO] $*"; }
have(){ command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<EOF
Usage:
  $0 [--freeze]

Options:
  --freeze   After successful setup, freeze the environment to
             environment.lock.yml using scripts/freeze-env.sh

Environment variables:
  ENV_NAME   Conda environment name (default: samba-py)
  ENV_YML    Environment file (default: environment.yml)
EOF
}

# -------------------------
# Parse CLI args
# -------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --freeze)
      FREEZE_AFTER=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

# -------------------------
# Preconditions
# -------------------------
[[ -f "$ENV_YML" ]] || die "Missing $ENV_YML in $(pwd)"
[[ -d "scripts" ]] || die "Expected ./scripts directory (are you in SAMBA_python/?)"

# -------------------------
# Choose conda frontend
# -------------------------
if have micromamba; then
  TOOL="micromamba"
elif have mamba; then
  TOOL="mamba"
elif have conda; then
  TOOL="conda"
else
  die "Need conda, mamba, or micromamba on PATH."
fi

info "Using tool: $TOOL"
info "Environment name: $ENV_NAME"
info "Environment file: $ENV_YML"

# -------------------------
# Helpers
# -------------------------
run_in_env() {
  case "$TOOL" in
    conda|mamba)
      "$TOOL" run -n "$ENV_NAME" "$@"
      ;;
    micromamba)
      micromamba run -n "$ENV_NAME" "$@"
      ;;
  esac
}

env_exists() {
  case "$TOOL" in
    conda|mamba)
      "$TOOL" env list | awk '{print $1}' | grep -qx "$ENV_NAME"
      ;;
    micromamba)
      micromamba env list | awk '{print $1}' | grep -qx "$ENV_NAME"
      ;;
  esac
}

# -------------------------
# Create or update env
# -------------------------
case "$TOOL" in
  conda|mamba)
    if env_exists; then
      info "Environment exists; updating..."
      "$TOOL" env update -n "$ENV_NAME" -f "$ENV_YML" --prune
    else
      info "Environment does not exist; creating..."
      "$TOOL" env create -n "$ENV_NAME" -f "$ENV_YML"
    fi
    ;;
  micromamba)
    if env_exists; then
      info "Environment exists; installing/updating from $ENV_YML..."
      micromamba install -n "$ENV_NAME" -f "$ENV_YML" -y
    else
      info "Environment does not exist; creating..."
      micromamba create -n "$ENV_NAME" -f "$ENV_YML" -y
    fi
    ;;
esac

# -------------------------
# pip extras
# -------------------------
if [[ "${#PIP_EXTRAS[@]}" -gt 0 ]]; then
  info "Installing pip extras: ${PIP_EXTRAS[*]}"
  run_in_env python -m pip install --upgrade pip
  run_in_env python -m pip install "${PIP_EXTRAS[@]}"
fi

# -------------------------
# Install SAMBA_python package (editable)
# -------------------------
info "Installing SAMBA_python package (editable)"
run_in_env python -m pip install -e .

# -------------------------
# Sanity checks
# -------------------------
info "Running sanity checks"
run_in_env python - <<'PY'
import sys
import numpy
import nibabel
import samba_py
from samba_py import niigz_io

print("Python:", sys.version.split()[0])
print("numpy:", numpy.__version__)
print("nibabel:", nibabel.__version__)
print("samba_py import: OK")

try:
    import nibabel.openers as op
    print("HAVE_INDEXED_GZIP:", getattr(op, "HAVE_INDEXED_GZIP", None))
except Exception as e:
    print("indexed_gzip check failed:", e)
PY

# -------------------------
# Optional freeze
# -------------------------
if [[ "$FREEZE_AFTER" -eq 1 ]]; then
  info "--freeze requested; freezing environment"
  [[ -x "scripts/freeze-env.sh" ]] || die "scripts/freeze-env.sh not found or not executable"
  ENV_NAME="$ENV_NAME" scripts/freeze-env.sh
fi

# -------------------------
# Done
# -------------------------
info "Setup complete."

case "$TOOL" in
  conda|mamba)
    echo "Activate with: conda activate $ENV_NAME"
    ;;
  micromamba)
    echo "Activate with: micromamba activate $ENV_NAME"
    ;;
esac
