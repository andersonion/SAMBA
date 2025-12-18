#!/usr/bin/env bash
set -euo pipefail

ENV_NAME="${ENV_NAME:-samba-py}"
DEFAULT_PREFIX="$(pwd)/.envs/${ENV_NAME}"
ENV_PREFIX="${ENV_PREFIX:-$DEFAULT_PREFIX}"

LOCK_YML="${LOCK_YML:-environment.lock.yml}"
META_TXT="${META_TXT:-environment.lock.meta.txt}"

die(){ echo "[ERROR] $*" >&2; exit 1; }
info(){ echo "[INFO] $*"; }
have(){ command -v "$1" >/dev/null 2>&1; }

if [[ ! -f "environment.yml" ]]; then
  die "Run this from SAMBA_python/ (expected ./environment.yml)."
fi

if have micromamba; then TOOL="micromamba"
elif have mamba; then TOOL="mamba"
elif have conda; then TOOL="conda"
else die "Need conda/mamba/micromamba on PATH."
fi

run_in_env() {
  case "$TOOL" in
    conda|mamba) "$TOOL" run -p "$ENV_PREFIX" "$@";;
    micromamba)  micromamba run -p "$ENV_PREFIX" "$@";;
  esac
}

[[ -d "$ENV_PREFIX" ]] || die "Env prefix does not exist: $ENV_PREFIX"

DATE_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
GIT_SHA="(not a git repo)"
GIT_BRANCH="(unknown)"
if have git && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  GIT_SHA="$(git rev-parse HEAD)"
  GIT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
fi

info "Freezing env prefix '$ENV_PREFIX' using $TOOL"
info "Writing: $LOCK_YML"
info "Writing: $META_TXT"

case "$TOOL" in
  conda|mamba)
    "$TOOL" env export -p "$ENV_PREFIX" --no-builds > "$LOCK_YML"
    ;;
  micromamba)
    micromamba env export -p "$ENV_PREFIX" --no-builds > "$LOCK_YML"
    ;;
esac

PIP_FREEZE="$(run_in_env python -m pip freeze || true)"

cat > "$META_TXT" <<EOF
Frozen environment metadata
==========================

date_utc:   $DATE_UTC
env_prefix: $ENV_PREFIX
tool:       $TOOL
git_branch: $GIT_BRANCH
git_sha:    $GIT_SHA

pip_freeze:
-----------
$PIP_FREEZE
EOF

info "Done."
echo "Tip: commit $LOCK_YML and $META_TXT when you reach a known-good milestone."
