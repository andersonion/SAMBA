#!/usr/bin/env bash
#
# samba_pipe_src.sh  (portable-ish launcher)
#
# Usage:
#   source /path/to/samba_pipe_src.sh
#   samba-pipe /path/to/startup.headfile
#
set -euo pipefail

# ---------- runtime detection (host) ----------
_samba_find_runtime() {
  local ct=""
  if [[ -n "${SAMBA_CONTAINER_RUNTIME-}" && -x "${SAMBA_CONTAINER_RUNTIME}" ]]; then
    ct="${SAMBA_CONTAINER_RUNTIME}"
  elif command -v apptainer >/dev/null 2>&1; then
    ct="$(command -v apptainer)"
  elif command -v singularity >/dev/null 2>&1; then
    ct="$(command -v singularity)"
  else
    for cand in /usr/local/bin/apptainer /usr/bin/apptainer /usr/local/bin/singularity /usr/bin/singularity; do
      if [[ -x "$cand" ]]; then ct="$cand"; break; fi
    done
  fi

  if [[ -z "$ct" ]]; then
    echo "ERROR: apptainer/singularity not found in PATH" >&2
    return 1
  fi
  echo "$ct"
}

CONTAINER_CMD="$(_samba_find_runtime)"
export CONTAINER_CMD

# ---------- locate samba.sif (host) ----------
_samba_find_sif() {
  local sif=""
  if [[ -n "${SAMBA_CONTAINER_PATH-}" && -f "$SAMBA_CONTAINER_PATH" ]]; then
    sif="$SAMBA_CONTAINER_PATH"
  elif [[ -n "${SINGULARITY_IMAGE_DIR-}" && -f "$SINGULARITY_IMAGE_DIR/samba.sif" ]]; then
    sif="$SINGULARITY_IMAGE_DIR/samba.sif"
  elif [[ -f "$HOME/containers/samba.sif" ]]; then
    sif="$HOME/containers/samba.sif"
  else
    local root="${SAMBA_SEARCH_ROOT:-$HOME}"
    sif="$(find "$root" -maxdepth 6 -type f -name 'samba.sif' 2>/dev/null | head -n 1 || true)"
  fi

  if [[ -z "$sif" || ! -f "$sif" ]]; then
    echo "ERROR: Could not locate samba.sif on host." >&2
    echo "Set SAMBA_CONTAINER_PATH or SINGULARITY_IMAGE_DIR or place at $HOME/containers/samba.sif" >&2
    return 1
  fi
  echo "$sif"
}

SIF_PATH="$(_samba_find_sif)"
export SIF_PATH

# ---------- main entry ----------
samba-pipe() {
  local hf="${1-}"
  if [[ -z "$hf" ]]; then
    echo "Usage: samba-pipe headfile.hf" >&2
    return 1
  fi

  # make headfile absolute
  if [[ "${hf:0:1}" != "/" && "${hf:0:2}" != "~/" ]]; then
    hf="${PWD}/${hf}"
  fi
  if [[ ! -f "$hf" ]]; then
    echo "ERROR: headfile not found: $hf" >&2
    return 1
  fi

  # -------- BIGGUS_DISKUS selection --------
  if [[ -z "${BIGGUS_DISKUS:-}" ]]; then
    if [[ -d "${SCRATCH:-}" ]]; then
      export BIGGUS_DISKUS="$SCRATCH"
    elif [[ -d "${WORK:-}" ]]; then
      export BIGGUS_DISKUS="$WORK"
    else
      export BIGGUS_DISKUS="$HOME/samba_scratch"
      mkdir -p "$BIGGUS_DISKUS"
    fi
  fi

  if [[ ! -d "$BIGGUS_DISKUS" || ! -w "$BIGGUS_DISKUS" ]]; then
    echo "ERROR: BIGGUS_DISKUS ('$BIGGUS_DISKUS') is not writable or does not exist." >&2
    return 1
  fi

  # -------- binds --------
  local hf_dir
  hf_dir="$(dirname "$hf")"

  local binds=()
  binds+=( --bind "$hf_dir:$hf_dir" )
  binds+=( --bind "$BIGGUS_DISKUS:$BIGGUS_DISKUS" )

  # optional_external_inputs_dir from headfile
  local opt_ext=""
  opt_ext="$(grep -E '^optional_external_inputs_dir *=' "$hf" 2>/dev/null | sed 's/.*= *//' || true)"
  if [[ -n "$opt_ext" && -d "$opt_ext" ]]; then
    binds+=( --bind "$opt_ext:$opt_ext" )
  fi

  # Atlas override (host path) -> bind to fixed container location
  # User sets: export SAMBA_ATLAS_DIR_HOST=/path/on/host/chass_symmetric3
  local atlas_env=()
  if [[ -n "${SAMBA_ATLAS_DIR_HOST:-}" ]]; then
    if [[ ! -d "$SAMBA_ATLAS_DIR_HOST" ]]; then
      echo "ERROR: SAMBA_ATLAS_DIR_HOST is set but not a directory: $SAMBA_ATLAS_DIR_HOST" >&2
      return 1
    fi
    binds+=( --bind "$SAMBA_ATLAS_DIR_HOST:/opt/atlases_override" )
    atlas_env+=( --env SAMBA_ATLAS_DIR=/opt/atlases_override )
  fi

  # -------- container-side root (must be /opt/samba) --------
  local SAMBA_APPS_IN_CONTAINER="/opt/samba"

  # stage HF into /tmp (host-side)
  local hf_tmp="/tmp/${USER}_samba_$(date +%s)_$(basename "$hf")"
  cp "$hf" "$hf_tmp"

  # -------- pipeline prefix (used by scheduler wrappers inside pipeline) --------
  # NOTE: use --cleanenv so host env can't leak /home/apps into SAMBA Perl
  local PIPELINE_CMD_PREFIX_A=(
    "$CONTAINER_CMD" exec --cleanenv
    --env SAMBA_APPS_DIR="$SAMBA_APPS_IN_CONTAINER"
    "${atlas_env[@]}"
    "${binds[@]}"
    "$SIF_PATH"
  )
  export CONTAINER_CMD_PREFIX="${PIPELINE_CMD_PREFIX_A[*]}"

  # -------- host-side launch --------
  local HOST_CMD_PREFIX_A=(
    "$CONTAINER_CMD" exec --cleanenv
    --env CONTAINER_CMD_PREFIX="$CONTAINER_CMD_PREFIX"
    --env SAMBA_APPS_DIR="$SAMBA_APPS_IN_CONTAINER"
    "${atlas_env[@]}"
    "${binds[@]}"
    "$SIF_PATH"
  )

  echo "samba-pipe: launching:"
  printf '  %q ' "${HOST_CMD_PREFIX_A[@]}" "/opt/samba/SAMBA/vbm_pipeline_start.pl" "$hf_tmp"
  echo

  "${HOST_CMD_PREFIX_A[@]}" /opt/samba/SAMBA/vbm_pipeline_start.pl "$hf_tmp"
}
export -f samba-pipe
