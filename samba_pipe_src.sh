#!/usr/bin/env bash
#
# samba_pipe_src.sh  (portable, no hard-coded host layout)
#
# Usage:
#   source /home/apps/SAMBA/samba_pipe_src.sh
#   samba-pipe /path/to/startup.headfile
#
# Cluster-specific bits (Slurm, weird library locations, etc.) must be
# supplied via:
#   export SAMBA_EXTRA_BINDS="--bind /foo:/foo --bind /bar:/bar"
#

# ----------------------------------------------------------------------
# Container command (absolute binary)
# ----------------------------------------------------------------------
CONTAINER_CMD_BIN="$(command -v singularity || true)"
if [[ -z "$CONTAINER_CMD_BIN" ]]; then
  echo "ERROR: singularity not found in PATH" >&2
  return 1
fi

CONTAINER_CMD="$CONTAINER_CMD_BIN"
export CONTAINER_CMD

# ----------------------------------------------------------------------
# Locate the container image in a portable way
# ----------------------------------------------------------------------
unset SIF_PATH

# 1. Explicit override
if [[ -n "${SAMBA_CONTAINER_PATH:-}" && -f "$SAMBA_CONTAINER_PATH" ]]; then
  SIF_PATH="$SAMBA_CONTAINER_PATH"

# 2. $SINGULARITY_IMAGE_DIR/samba.sif
elif [[ -n "${SINGULARITY_IMAGE_DIR:-}" && -f "${SINGULARITY_IMAGE_DIR}/samba.sif" ]]; then
  SIF_PATH="${SINGULARITY_IMAGE_DIR}/samba.sif"

# 3. $HOME/containers/samba.sif
elif [[ -f "${HOME}/containers/samba.sif" ]]; then
  SIF_PATH="${HOME}/containers/samba.sif"

# 4. Fallback: search under SAMBA_SEARCH_ROOT or $HOME
else
  echo "Trying to locate samba.sif using find... (this may take a moment)" >&2
  SEARCH_ROOT="${SAMBA_SEARCH_ROOT:-$HOME}"
  SIF_PATH="$(find "$SEARCH_ROOT" -type f -name 'samba.sif' 2>/dev/null | head -n 1 || true)"

  if [[ -z "$SIF_PATH" ]]; then
    echo "ERROR: Could not locate samba.sif" >&2
    echo "Set SAMBA_CONTAINER_PATH or place samba.sif in one of:" >&2
    echo "  \$SINGULARITY_IMAGE_DIR/samba.sif" >&2
    echo "  \$HOME/containers/samba.sif" >&2
    echo "Or define SAMBA_SEARCH_ROOT for find()-based search." >&2
    return 1
  else
    echo "Found samba.sif at: $SIF_PATH"
  fi
fi

export SIF_PATH

# ----------------------------------------------------------------------
# Extra bind mounts (cluster-specific, via env)
# ----------------------------------------------------------------------
# Example usage in your shell/cluster config:
#   export SAMBA_EXTRA_BINDS="--bind /etc/slurm:/etc/slurm --bind /usr/local/lib/slurm:/usr/local/lib/slurm"
#
declare -a EXTRA_BINDS=()

if [[ -n "${SAMBA_EXTRA_BINDS:-}" ]]; then
  # shellcheck disable=SC2206
  EXTRA_BINDS=( ${SAMBA_EXTRA_BINDS} )
fi

export EXTRA_BINDS

# ----------------------------------------------------------------------
# Main entry point: samba-pipe
# ----------------------------------------------------------------------
function samba-pipe {
  local hf="$1"

  if [[ -z "$hf" ]]; then
    echo "Usage: samba-pipe headfile.hf" >&2
    return 1
  fi

  # Make headfile absolute if needed
  if [[ "${hf:0:1}" != "/" && "${hf:0:2}" != "~/" ]]; then
    hf="${PWD}/${hf}"
  fi

  if [[ ! -f "$hf" ]]; then
    echo "ERROR: headfile not found: $hf" >&2
    return 1
  fi

  # ---------------- BIGGUS_DISKUS resolution ----------------
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

  # Warn if directory is not group-writable (multi-user sanity)
  if ! perl -e 'exit((stat($ARGV[0]))[2] & 0020 ? 0 : 1)' "$BIGGUS_DISKUS"; then
    echo "Warning: $BIGGUS_DISKUS is not group-writable. Multi-user workflows may fail."
  fi

  # Atlas bind
  local BIND_ATLAS=()
  if [[ -n "${ATLAS_FOLDER:-}" && -d "$ATLAS_FOLDER" ]]; then
    BIND_ATLAS=( --bind "$ATLAS_FOLDER:$ATLAS_FOLDER" )
  else
    echo "Warning: ATLAS_FOLDER not set or does not exist. Proceeding with default atlas."
  fi

  # Export for Perl glue if needed
  export SAMBA_ATLAS_BIND="${BIND_ATLAS[*]}"
  export SAMBA_BIGGUS_BIND="$BIGGUS_DISKUS:$BIGGUS_DISKUS"

  # Bind HF directory (host path visible inside container)
  local hf_dir
  hf_dir="$(dirname "$hf")"
  local BIND_HF_DIR=( --bind "$hf_dir:$hf_dir" )

  # Stage HF to /tmp for stable path inside container
  local hf_tmp="/tmp/${USER}_samba_$(date +%s)_$(basename "$hf")"
  cp "$hf" "$hf_tmp"

  # ------------------------------------------------------------------
  # 1) Build CONTAINER_CMD_PREFIX for use *inside* the pipeline
  # ------------------------------------------------------------------
  local PIPELINE_CMD_PREFIX_A=(
    "$CONTAINER_CMD_BIN" exec
    --bind "$BIGGUS_DISKUS:$BIGGUS_DISKUS"
    "${BIND_ATLAS[@]}"
    "${EXTRA_BINDS[@]}"
    "$SIF_PATH"
  )

  # NOTE: this is *only* for wrap_in_container() in Perl
  export CONTAINER_CMD_PREFIX="${PIPELINE_CMD_PREFIX_A[*]}"

  # ------------------------------------------------------------------
  # 2) Host-side singularity exec for the pipeline (NO eval)
  # ------------------------------------------------------------------
  local HOST_CMD_PREFIX_A=(
    "$CONTAINER_CMD_BIN" exec
    --env "CONTAINER_CMD_PREFIX=${CONTAINER_CMD_PREFIX}"
    --bind "$BIGGUS_DISKUS:$BIGGUS_DISKUS"
    "${BIND_HF_DIR[@]}"
    "${BIND_ATLAS[@]}"
    "${EXTRA_BINDS[@]}"
    "$SIF_PATH"
  )

  echo "samba-pipe: launching:"
  printf '  %q' "${HOST_CMD_PREFIX_A[@]}" /opt/samba/SAMBA/vbm_pipeline_start.pl "$hf_tmp"
  echo

  # IMPORTANT: no eval here – run the array directly
  "${HOST_CMD_PREFIX_A[@]}" /opt/samba/SAMBA/vbm_pipeline_start.pl "$hf_tmp"
}
