#!/usr/bin/env bash
#
# samba_pipe_src.sh  (portable-ish launcher)
#
# Usage:
#   source /home/apps/SAMBA/samba_pipe_src.sh
#   samba-pipe /path/to/startup.headfile
#

# ----------------------------------------------------------------------
# Locate singularity executable on the *host*
# ----------------------------------------------------------------------
CONTAINER_CMD="$(command -v singularity 2>/dev/null || true)"
if [[ -z "$CONTAINER_CMD" ]]; then
  echo "ERROR: singularity not found in PATH" >&2
  return 1 2>/dev/null || exit 1
fi
export CONTAINER_CMD

# ----------------------------------------------------------------------
# Locate the samba.sif image (host side)
#   Priority:
#     1) SAMBA_CONTAINER_PATH (explicit)
#     2) SINGULARITY_IMAGE_DIR/samba.sif
#     3) \$HOME/containers/samba.sif
#     4) find under SAMBA_SEARCH_ROOT (or \$HOME)
# ----------------------------------------------------------------------
if [[ -n "${SAMBA_CONTAINER_PATH:-}" && -f "$SAMBA_CONTAINER_PATH" ]]; then
  SIF_PATH="$SAMBA_CONTAINER_PATH"
elif [[ -n "${SINGULARITY_IMAGE_DIR:-}" && -f "$SINGULARITY_IMAGE_DIR/samba.sif" ]]; then
  SIF_PATH="$SINGULARITY_IMAGE_DIR/samba.sif"
elif [[ -f "$HOME/containers/samba.sif" ]]; then
  SIF_PATH="$HOME/containers/samba.sif"
else
  echo "samba-pipe: trying to locate samba.sif using find (host side)..." >&2
  SEARCH_ROOT="${SAMBA_SEARCH_ROOT:-$HOME}"
  SIF_PATH="$(find "$SEARCH_ROOT" -maxdepth 6 -type f -name 'samba.sif' 2>/dev/null | head -n 1)"
fi

if [[ -z "${SIF_PATH:-}" || ! -f "$SIF_PATH" ]]; then
  echo "ERROR: Could not locate samba.sif on host." >&2
  echo "Set SAMBA_CONTAINER_PATH or SINGULARITY_IMAGE_DIR, or place it at:" >&2
  echo "  \$HOME/containers/samba.sif" >&2
  return 1 2>/dev/null || exit 1
fi
export SIF_PATH

# ----------------------------------------------------------------------
# Main entry point
# ----------------------------------------------------------------------
function samba-pipe {
  local hf="$1"

  if [[ -z "$hf" ]]; then
    echo "Usage: samba-pipe headfile.hf" >&2
    return 1
  fi

  # Make headfile absolute
  if [[ "${hf:0:1}" != "/" && "${hf:0:2}" != "~/" ]]; then
    hf="${PWD}/${hf}"
  fi
  if [[ ! -f "$hf" ]]; then
    echo "ERROR: headfile not found: $hf" >&2
    return 1
  fi

  # ---------------- BIGGUS_DISKUS ----------------
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

  # Optional warning for group-writability (multi-user friendliness)
  perl -e 'exit((stat($ARGV[0]))[2] & 0020 ? 0 : 1)' "$BIGGUS_DISKUS" 2>/dev/null \
    || echo "Warning: $BIGGUS_DISKUS is not group-writable. Multi-user workflows may fail."

  # ---------------- Atlas bind (if provided) ----------------
  local BIND_ATLAS=()
  if [[ -n "${ATLAS_FOLDER:-}" && -d "$ATLAS_FOLDER" ]]; then
    BIND_ATLAS=( --bind "$ATLAS_FOLDER:$ATLAS_FOLDER" )
  fi

  # ---------------- Bind HF dir + optional external inputs ----------------
  local hf_dir
  hf_dir="$(dirname "$hf")"
  local BIND_HF_DIR=( --bind "$hf_dir:$hf_dir" )

  local EXTRA_BINDS=()
  # bind BIGGUS_DISKUS so the -inputs/-work/-results dirs are visible
  EXTRA_BINDS+=( --bind "$BIGGUS_DISKUS:$BIGGUS_DISKUS" )

  # Try to pull optional_external_inputs_dir from the headfile for a clean bind
  local opt_ext
  opt_ext="$(grep -E '^optional_external_inputs_dir *=' "$hf" 2>/dev/null | sed 's/.*= *//')"
  if [[ -n "$opt_ext" && -d "$opt_ext" ]]; then
    EXTRA_BINDS+=( --bind "$opt_ext:$opt_ext" )
  fi

  # ---------------- Container-side app root ----------------
  # Inside the image we have:
  #   /opt/samba/SAMBA/...
  #   /opt/samba/matlab_execs_for_SAMBA/...
  #   /opt/samba/MATLAB2015b_runtime/...
  #
  # So SAMBA_APPS_DIR must be /opt/samba (NOT /home/apps).
  local SAMBA_APPS_IN_CONTAINER="/opt/samba"

  # Stage HF into /tmp to avoid surprises with weird paths
  local hf_tmp="/tmp/${USER}_samba_$(date +%s)_$(basename "$hf")"
  cp "$hf" "$hf_tmp"

  # ---------------- Build in-pipeline CONTAINER_CMD_PREFIX ----------------
  # This string is what cluster_exec()->wrap_in_container() will prepend
  # around sbatch / external commands.
  local PIPELINE_CMD_PREFIX_A=(
    "$CONTAINER_CMD" exec
    --env SAMBA_APPS_DIR="$SAMBA_APPS_IN_CONTAINER"
    --bind "$BIGGUS_DISKUS:$BIGGUS_DISKUS"
    "${BIND_ATLAS[@]}"
    "${EXTRA_BINDS[@]}"
    "$SIF_PATH"
  )
  export CONTAINER_CMD_PREFIX="${PIPELINE_CMD_PREFIX_A[*]}"

  # ---------------- Host-side launch ----------------
  local HOST_CMD_PREFIX_A=(
    "$CONTAINER_CMD" exec
    --env CONTAINER_CMD_PREFIX="$CONTAINER_CMD_PREFIX"
    --env SAMBA_APPS_DIR="$SAMBA_APPS_IN_CONTAINER"
    --bind "$BIGGUS_DISKUS:$BIGGUS_DISKUS"
    "${BIND_HF_DIR[@]}"
    "${BIND_ATLAS[@]}"
    "${EXTRA_BINDS[@]}"
    "$SIF_PATH"
  )

  echo "samba-pipe: launching:"
  printf '  %q ' "${HOST_CMD_PREFIX_A[@]}" "/opt/samba/SAMBA/vbm_pipeline_start.pl" "$hf_tmp"
  echo

  "${HOST_CMD_PREFIX_A[@]}" /opt/samba/SAMBA/vbm_pipeline_start.pl "$hf_tmp"
}
