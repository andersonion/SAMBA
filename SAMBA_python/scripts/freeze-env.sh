#!/usr/bin/env bash
set -euo pipefail

# Freeze the current conda/mamba/micromamba environment to a lock file
# and stamp it with date + git commit info.
#
# Usage:
#   ./scripts/freeze-env.sh
#   ENV_NAME=samba-py ./scripts/freeze-env.sh
#
# Output:
#   environment.lock.yml
#   environment.lock.meta.txt

ENV_NAME="${ENV_NAME:-samba-py}"
LOCK_YML="${LOCK_YML:-environment.lock.yml}"
META_TXT="${META_TXT:-environment.lock.meta.txt}"

die(){ echo "[ERROR] $*" >&2; exit 1; }
info(){ echo "[INFO] $*"; }
have(){ command -v "$1" >/dev/null 2>&1; }

# Choose runner tool (supports conda/mamba/micromamba)
if have micromamba; then TOOL="micromamba"
elif have mamba; then TOOL="mamba"
elif have conda; then TOOL="conda"
else die "Need conda/mamba/micromamba on PATH."
fi

run_in_env() {
  case "$TOOL" in
    conda|mamba) "$TOOL" run -n "$ENV_NAME" "$@";;
    micromamba)  micromamba run -n "$ENV_NAME" "$@";;
  esac
}

# Confirm we're in repo root (expects pyproject.toml or environment.yml nearby)
if [[ ! -f "environment.yml" ]]; then
  die "Run this from SAMBA_python/ (expected ./environment.yml)."
fi

# Collect metadata
DATE_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
GIT_SHA="(not a git repo)"
GIT_BRANCH="(unknown)"
if have git && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  GIT_SHA="$(git rev-parse HEAD)"
  GIT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
fi

info "Freezing env '$ENV_NAME' using $TOOL"
info "Writing: $LOCK_YML"
info "Writing: $META_TXT"

# Export lock (no-builds improves portability across similar Linux systems)
case "$TOOL" in
  conda|mamba)
    "$TOOL" env export -n "$ENV_NAME" --no-builds > "$LOCK_YML"
    ;;
  micromamba)
    # micromamba uses a different subcommand
    micromamba env export -n "$ENV_NAME" --no-builds > "$LOCK_YML"
    ;;
esac

# Capture pip freeze too (useful when we install pip extras like indexed_gzip)
PIP_FREEZE="$(run_in_env python -m pip freeze || true)"

# Write metadata file
cat > "$META_TXT" <<EOF
Frozen environment metadata
==========================

date_utc:   $DATE_UTC
env_name:   $ENV_NAME
tool:       $TOOL
git_branch: $GIT_BRANCH
git_sha:    $GIT_SHA

pip_freeze:
-----------
$PIP_FREEZE
EOF

info "Done."
echo "Tip: commit $LOCK_YML and $META_TXT when you reach a known-good milestone."
