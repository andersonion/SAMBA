#!/usr/bin/env bash
#
# samba_pipe_src.sh — clean, portable SAMBA launcher
#
# Usage:
#   source samba_pipe_src.sh
#   samba-pipe path/to/startup.headfile
#

# DO NOT use set -e here — failures must not kill login shells
set -u
set -o pipefail

# ------------------------------------------------------------
# Runtime discovery
# ------------------------------------------------------------
_samba_find_runtime() {
  if [[ -n "${SAMBA_CONTAINER_RUNTIME:-}" && -x "${SAMBA_CONTAINER_RUNTIME}" ]]; then
    echo "${SAMBA_CONTAINER_RUNTIME}"
    return 0
  fi
  if command -v apptainer >/dev/null 2>&1; then
    command -v apptainer
    return 0
  fi
  if command -v singularity >/dev/null 2>&1; then
    command -v singularity
    return 0
  fi
  for c in /usr/local/bin/apptainer /usr/bin/apptainer /usr/local/bin/singularity /usr/bin/singularity; do
    [[ -x "$c" ]] && { echo "$c"; return 0; }
  done
  echo "ERROR: apptainer/singularity not found" >&2
  return 1
}

CONTAINER_CMD="$(_samba_find_runtime)" || return 1
export CONTAINER_CMD

# ------------------------------------------------------------
# Locate samba.sif
# ------------------------------------------------------------
_samba_find_sif() {
  if [[ -n "${SAMBA_CONTAINER_PATH:-}" && -f "$SAMBA_CONTAINER_PATH" ]]; then
    echo "$SAMBA_CONTAINER_PATH"
    return
  fi
  if [[ -n "${SINGULARITY_IMAGE_DIR:-}" && -f "$SINGULARITY_IMAGE_DIR/samba.sif" ]]; then
    echo "$SINGULARITY_IMAGE_DIR/samba.sif"
    return
  fi
  if [[ -f "$HOME/containers/samba.sif" ]]; then
    echo "$HOME/containers/samba.sif"
    return
  fi
  local root="${SAMBA_SEARCH_ROOT:-$HOME}"
  find "$root" -maxdepth 6 -type f -name samba.sif 2>/dev/null | head -n 1
}

SIF_PATH="$(_samba_find_sif)"
[[ -f "$SIF_PATH" ]] || { echo "ERROR: samba.sif not found" >&2; return 1; }
export SIF_PATH

# ------------------------------------------------------------
# Main entry
# ------------------------------------------------------------
samba-pipe() {
  local hf="${1:-}"
  [[ -n "$hf" ]] || { echo "Usage: samba-pipe headfile.hf" >&2; return 1; }

  # Absolute headfile
  [[ "$hf" = /* || "$hf" = ~/* ]] || hf="$PWD/$hf"
  [[ -f "$hf" ]] || { echo "ERROR: headfile not found: $hf" >&2; return 1; }

  # --------------------------------------------------------
  # Resolve BIGGUS_DISKUS (CRITICAL)
  # --------------------------------------------------------
  if [[ -z "${BIGGUS_DISKUS:-}" ]]; then
    if [[ -d "${SCRATCH:-}" ]]; then
      BIGGUS_DISKUS="$SCRATCH"
    elif [[ -d "${WORK:-}" ]]; then
      BIGGUS_DISKUS="$WORK"
    else
      BIGGUS_DISKUS="$HOME/samba_scratch"
      mkdir -p "$BIGGUS_DISKUS"
    fi
  fi

  [[ -d "$BIGGUS_DISKUS" && -w "$BIGGUS_DISKUS" ]] || {
    echo "ERROR: BIGGUS_DISKUS not writable: $BIGGUS_DISKUS" >&2
    return 1
  }
  export BIGGUS_DISKUS

  # --------------------------------------------------------
  # Core container paths
  # --------------------------------------------------------
  local SAMBA_APPS_IN_CONTAINER="/opt/samba"

  # --------------------------------------------------------
  # HOME handling (FIXES MCR)
  # --------------------------------------------------------
  local host_home="${HOME:-/home/$(id -un)}"
  [[ -d "$host_home" ]] || { echo "ERROR: HOME not found: $host_home" >&2; return 1; }

  # --------------------------------------------------------
  # Atlas resolution (host-first)
  # --------------------------------------------------------
  local atlas_env=()
  local binds=()

  if [[ -n "${SAMBA_ATLAS_DIR_HOST:-}" ]]; then
    [[ -d "$SAMBA_ATLAS_DIR_HOST" ]] || {
      echo "ERROR: SAMBA_ATLAS_DIR_HOST not a directory: $SAMBA_ATLAS_DIR_HOST" >&2
      return 1
    }
    binds+=( --bind "$SAMBA_ATLAS_DIR_HOST:/opt/atlases_override" )
    atlas_env+=( --env SAMBA_ATLAS_DIR=/opt/atlases_override )
  fi

  # --------------------------------------------------------
  # Binds
  # --------------------------------------------------------
  local hf_dir
  hf_dir="$(dirname "$hf")"

  binds+=(
    --bind "$hf_dir:$hf_dir"
    --bind "$BIGGUS_DISKUS:$BIGGUS_DISKUS"
    --bind "$host_home:$host_home"
  )

  # Optional external inputs
  local opt_ext
  opt_ext="$(grep -E '^optional_external_inputs_dir\s*=' "$hf" 2>/dev/null | sed 's/.*= *//')"
  if [[ -n "$opt_ext" && -d "$opt_ext" ]]; then
    binds+=( --bind "$opt_ext:$opt_ext" )
  fi

  # --------------------------------------------------------
  # Stage headfile
  # --------------------------------------------------------
  local hf_tmp="/tmp/${USER}_samba_$(date +%s)_$(basename "$hf")"
  cp "$hf" "$hf_tmp"

  # --------------------------------------------------------
  # Container command prefixes
  # --------------------------------------------------------
  local BASE_ENV=(
    --env SAMBA_APPS_DIR="$SAMBA_APPS_IN_CONTAINER"
    --env BIGGUS_DISKUS="$BIGGUS_DISKUS"
    --env HOME="$host_home"
    --env USER="${USER:-$(id -un)}"
    --env TMPDIR="/tmp"
  )

  CONTAINER_CMD_PREFIX="$CONTAINER_CMD exec --cleanenv ${BASE_ENV[*]} ${atlas_env[*]} ${binds[*]} $SIF_PATH"
  export CONTAINER_CMD_PREFIX

  local HOST_CMD=(
    "$CONTAINER_CMD" exec --cleanenv
    "${BASE_ENV[@]}"
    --env CONTAINER_CMD_PREFIX="$CONTAINER_CMD_PREFIX"
    "${atlas_env[@]}"
    "${binds[@]}"
    "$SIF_PATH"
    /opt/samba/SAMBA/vbm_pipeline_start.pl
    "$hf_tmp"
  )

  echo "samba-pipe: launching:"
  printf '  %q ' "${HOST_CMD[@]}"
  echo

  "${HOST_CMD[@]}"
  local rc=$?

  if [[ $rc -ne 0 ]]; then
    echo "samba-pipe: SAMBA exited with status $rc (shell remains alive)" >&2
  fi
  return $rc
}

export -f samba-pipe
