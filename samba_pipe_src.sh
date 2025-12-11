#!/usr/bin/env bash
#
# samba_pipe_src.sh
#
# Host-side launcher for SAMBA inside Singularity.
#
# Usage:
#   source /home/apps/SAMBA/samba_pipe_src.sh
#   samba-pipe /path/to/startup.headfile
#
# This wrapper:
#   - figures out BIGGUS_DISKUS (or uses existing env)
#   - auto-binds atlas folder if ATLAS_FOLDER is set
#   - adds Slurm + host lib binds
#   - builds a singularity exec prefix for in-pipeline wrapping
#   - LAUNCHES SAMBA_startup inside the container, explicitly
#     passing CONTAINER_CMD_PREFIX into the container env.
#

# ----------------------------------------------------------------------
# Container command + image
# ----------------------------------------------------------------------

# Always use raw singularity here; ignore any inherited wrapper.
CONTAINER_CMD=singularity
export CONTAINER_CMD

# Try to auto-detect SIF if not provided.
if [[ -z "${SIF_PATH:-}" ]]; then
  if [[ -f "/home/apps/ubuntu-22.04/singularity/images/samba.sif" ]]; then
    SIF_PATH="/home/apps/ubuntu-22.04/singularity/images/samba.sif"
  elif [[ -f "/opt/containers/samba.sif" ]]; then
    SIF_PATH="/opt/containers/samba.sif"
  elif [[ -f "/opt/samba/samba.sif" ]]; then
    SIF_PATH="/opt/samba/samba.sif"
  fi
fi

if [[ -z "${SIF_PATH:-}" ]]; then
  echo "ERROR: SIF_PATH is not set and samba.sif could not be autodetected." >&2
  echo "       Please export SIF_PATH=/full/path/to/samba.sif and re-source this file." >&2
fi

export SIF_PATH

# ----------------------------------------------------------------------
# Extra bind detection (Slurm + host libs)
# ----------------------------------------------------------------------

declare -a EXTRA_BINDS=()

# Slurm config
if [[ -d /etc/slurm ]]; then
  EXTRA_BINDS+=( --bind /etc/slurm:/etc/slurm )
fi

# sbatch/scancel (prefer /usr/local/bin if present)
if command -v sbatch >/dev/null 2>&1; then
  if [[ -d /usr/local/bin ]]; then
    EXTRA_BINDS+=( --bind /usr/local/bin:/usr/local/bin )
  fi
fi

# Slurm plugins/libs
if [[ -d /usr/local/lib/slurm ]]; then
  EXTRA_BINDS+=( --bind /usr/local/lib/slurm:/usr/local/lib/slurm )
elif [[ -d /usr/lib/slurm ]]; then
  EXTRA_BINDS+=( --bind /usr/lib/slurm:/usr/lib/slurm )
fi

# Host glibc + system libs (for sbatch GLIBC mismatch)
if [[ -d /lib/x86_64-linux-gnu ]]; then
  EXTRA_BINDS+=( --bind /lib/x86_64-linux-gnu:/lib/x86_64-linux-gnu )
fi

if [[ -d /usr/lib/x86_64-linux-gnu ]]; then
  EXTRA_BINDS+=( --bind /usr/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu )
fi

# Allow user to inject extra binds:
#   export SAMBA_EXTRA_BINDS="--bind /foo:/foo --bind /bar:/bar"
if [[ -n "${SAMBA_EXTRA_BINDS:-}" ]]; then
  # shellcheck disable=SC2206
  ADDL=( ${SAMBA_EXTRA_BINDS} )
  EXTRA_BINDS+=( "${ADDL[@]}" )
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

  # Make headfile absolute once
  if [[ "${hf:0:1}" != "/" && "${hf:0:2}" != "~/" ]]; then
    hf="${PWD}/${hf}"
  fi
  if [[ ! -f "$hf" ]]; then
    echo "ERROR: headfile not found: $hf" >&2
    return 1
  fi

  # BIGGUS_DISKUS selection & validation
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

  # Warn if directory is not group-writable
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

  # Export for Perl glue if you want them later
  export SAMBA_ATLAS_BIND="${BIND_ATLAS[*]}"
  export SAMBA_BIGGUS_BIND="$BIGGUS_DISKUS:$BIGGUS_DISKUS"

  # Stage HF to /tmp for stable path
  local hf_tmp="/tmp/${USER}_samba_$(date +%s)_$(basename "$hf")"
  cp "$hf" "$hf_tmp"

  # Bind HF directory (host path visible in container)
  local BIND_HF_DIR=( --bind "$(dirname "$hf")":"$(dirname "$hf")" )

  # ------------------------------------------------------------------
  # 1) Pipeline-facing CONTAINER_CMD_PREFIX that lives in the env
  #    and is used INSIDE the container to wrap sbatch commands.
  # ------------------------------------------------------------------
  local PIPELINE_CMD_PREFIX_A=(
    "$CONTAINER_CMD" exec
    --bind "$BIGGUS_DISKUS:$BIGGUS_DISKUS"
    "${BIND_ATLAS[@]}"
    "${EXTRA_BINDS[@]}"
    "$SIF_PATH"
  )

  export CONTAINER_CMD_PREFIX="${PIPELINE_CMD_PREFIX_A[*]}"

  # ------------------------------------------------------------------
  # 2) Host-side container launch for this run
  #    Inject CONTAINER_CMD_PREFIX into container env.
  # ------------------------------------------------------------------
  local HOST_CMD_PREFIX_A=(
    "$CONTAINER_CMD" exec
    --env CONTAINER_CMD_PREFIX="$CONTAINER_CMD_PREFIX"
    --bind "$BIGGUS_DISKUS:$BIGGUS_DISKUS"
    "${BIND_HF_DIR[@]}"
    "${BIND_ATLAS[@]}"
    "${EXTRA_BINDS[@]}"
    "$SIF_PATH"
  )

  # Finally run SAMBA_startup inside the container
  eval "${HOST_CMD_PREFIX_A[*]}" SAMBA_startup "$hf_tmp"
}
