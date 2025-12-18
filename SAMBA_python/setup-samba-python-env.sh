#!/usr/bin/env bash
set -euo pipefail

ENV_YML="${ENV_YML:-environment.yml}"
ENV_NAME="${ENV_NAME:-samba-py}"

# Option C default: repo-local env prefix
DEFAULT_PREFIX="$(pwd)/.envs/${ENV_NAME}"
ENV_PREFIX="${ENV_PREFIX:-$DEFAULT_PREFIX}"

FREEZE_AFTER=0

PIP_EXTRAS=(
  "indexed_gzip"
)

die(){ echo "[ERROR] $*" >&2; exit 1; }
info(){ echo "[INFO] $*"; }
have(){ command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<EOF
Usage:
  $0 [--freeze] [--prefix /abs/or/rel/path]

Defaults:
  Env prefix: ./.envs/<ENV_NAME>   (repo-local, recommended)

Options:
  --freeze           After successful setup, run scripts/freeze-env.sh
  --prefix PATH      Create/update environment at PATH (prefix mode)

Environment variables:
  ENV_NAME           Logical env name (used only for default prefix folder name)
  ENV_PREFIX         Override prefix path
  ENV_YML            Environment file (default: environment.yml)
EOF
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --freeze)
      FREEZE_AFTER=1
      shift
      ;;
    --prefix)
      [[ $# -ge 2 ]] || die "--prefix requires a PATH"
      ENV_PREFIX="$2"
      shift 2
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

# Preconditions
[[ -f "$ENV_YML" ]] || die "Missing $ENV_YML in $(pwd)"
[[ -d "scripts" ]] || die "Expected ./scripts directory (run from SAMBA_python/)"
mkdir -p "$(dirname "$ENV_PREFIX")"

# Choose conda frontend
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
info "Environment file: $ENV_YML"
info "Env name (logical): $ENV_NAME"
info "Env prefix (actual): $ENV_PREFIX"

run_in_env() {
  case "$TOOL" in
    conda|mamba)
      "$TOOL" run -p "$ENV_PREFIX" "$@"
      ;;
    micromamba)
      micromamba run -p "$ENV_PREFIX" "$@"
      ;;
  esac
}

prefix_exists() {
  [[ -d "$ENV_PREFIX" ]] && [[ -f "$ENV_PREFIX/conda-meta/history" || -f "$ENV_PREFIX/conda-meta/pinned" || -d "$ENV_PREFIX/conda-meta" ]]
}

# Create/update env at prefix
case "$TOOL" in
  conda|mamba)
    if prefix_exists; then
      info "Prefix exists; updating..."
      "$TOOL" env update -p "$ENV_PREFIX" -f "$ENV_YML" --prune
    else
      info "Prefix does not exist; creating..."
      "$TOOL" env create -p "$ENV_PREFIX" -f "$ENV_YML"
    fi
    ;;
  micromamba)
    if prefix_exists; then
      info "Prefix exists; installing/updating from $ENV_YML..."
      micromamba install -p "$ENV_PREFIX" -f "$ENV_YML" -y
    else
      info "Prefix does not exist; creating..."
      micromamba create -p "$ENV_PREFIX" -f "$ENV_YML" -y
    fi
    ;;
esac

# pip extras
if [[ "${#PIP_EXTRAS[@]}" -gt 0 ]]; then
  info "Installing pip extras: ${PIP_EXTRAS[*]}"
  run_in_env python -m pip install --upgrade pip
  run_in_env python -m pip install "${PIP_EXTRAS[@]}"
fi

# Install package editable
info "Installing SAMBA_python package (editable)"
run_in_env python -m pip install -e .

# Sanity checks
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

# Optional freeze
if [[ "$FREEZE_AFTER" -eq 1 ]]; then
  info "--freeze requested; freezing environment"
  [[ -x "scripts/freeze-env.sh" ]] || die "scripts/freeze-env.sh not found or not executable"
  ENV_PREFIX="$ENV_PREFIX" scripts/freeze-env.sh
fi

info "Setup complete."
echo "Run tests with:"
case "$TOOL" in
  conda|mamba) echo "  $TOOL run -p \"$ENV_PREFIX\" pytest -q";;
  micromamba)  echo "  micromamba run -p \"$ENV_PREFIX\" pytest -q";;
esac
