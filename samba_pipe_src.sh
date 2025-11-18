#!/usr/bin/env bash
#
# samba_pipe_src.sh
#
# Host-side helper for launching SAMBA inside the Singularity/Apptainer
# container via a simple:
#
#   samba-pipe /path/to/headfile.hf
#
# It:
#   - Normalizes the headfile path
#   - Chooses BIGGUS_DISKUS (scratch) if not already set
#   - Sets up scheduler-proxy env (SAMBA_SCHED_*)
#   - Builds the Singularity exec command with all necessary binds
#   - Exposes CONTAINER_CMD_PREFIX (used inside SAMBA to launch jobs)
#

# -----------------------------
#  Core configuration (host)
# -----------------------------

# Location of samba.sif and Singularity/Apptainer on THIS machine.
: "${CONTAINER_CMD:=singularity}"
: "${SIF_PATH:=/opt/containers/samba.sif}"

# Where the SAMBA repo is installed on the host (for this helper script).
# This is not strictly required at runtime but is often useful.
: "${SAMBA_APPS_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)}"

# Default scratch selection if BIGGUS_DISKUS is not already set.
_samba_pick_biggus() {
  if [[ -n "${BIGGUS_DISKUS:-}" ]]; then
    return 0
  fi
  if [[ -d "${SCRATCH:-}" ]]; then
    export BIGGUS_DISKUS="$SCRATCH"
  elif [[ -d "${WORK:-}" ]]; then
    export BIGGUS_DISKUS="$WORK"
  else
    export BIGGUS_DISKUS="$HOME/samba_scratch"
    mkdir -p "$BIGGUS_DISKUS"
  fi
}

# Scheduler proxy configuration:
#   - SAMBA_SCHED_BACKEND=proxy (use host daemon via file-based protocol)
#   - SAMBA_SCHED_DIR is a shared directory visible to both host & container
: "${SAMBA_SCHED_DIR:=$HOME/.samba_sched}"
: "${SAMBA_SCHED_BACKEND:=proxy}"

export SAMBA_SCHED_DIR SAMBA_SCHED_BACKEND

# Create the scheduler directory on the host so it can be bind-mounted.
mkdir -p "$SAMBA_SCHED_DIR"

# Extra binds you want *always* for this site (host-specific).
# You can customize these to your environment; here we keep it minimal and
# let headfile & BIGGUS bindings be handled dynamically per call.
EXTRA_BINDS=()

# -----------------------------
#  Main entrypoint function
# -----------------------------
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

  # Ensure BIGGUS_DISKUS is set to a writable dir
  _samba_pick_biggus
  if [[ ! -d "$BIGGUS_DISKUS" || ! -w "$BIGGUS_DISKUS" ]]; then
    echo "ERROR: BIGGUS_DISKUS ('$BIGGUS_DISKUS') is not writable or does not exist." >&2
    return 1
  fi

  # Warn if directory is not group-writable (more accurate than -g/setgid)
  if ! perl -e 'exit((stat($ARGV[0]))[2] & 0020 ? 0 : 1)' "$BIGGUS_DISKUS"; then
    echo "Warning: $BIGGUS_DISKUS is not group-writable. Multi-user workflows may fail."
  fi

  # Atlas bind (if a host atlas folder is set)
  local BIND_ATLAS=()
  if [[ -n "${ATLAS_FOLDER:-}" && -d "$ATLAS_FOLDER" ]]; then
    BIND_ATLAS=( --bind "$ATLAS_FOLDER:$ATLAS_FOLDER" )
  fi

  # Scheduler directory bind (for proxy backend)
  local BIND_SCHED=()
  if [[ "$SAMBA_SCHED_BACKEND" == "proxy" && -d "$SAMBA_SCHED_DIR" ]]; then
    BIND_SCHED=( --bind "$SAMBA_SCHED_DIR:$SAMBA_SCHED_DIR" )
  fi

  # Headfile directory bind
  local HF_DIR
  HF_DIR="$(dirname "$hf")"
  local BIND_HF_DIR=( --bind "$HF_DIR:$HF_DIR" )

  # BIGGUS_DISKUS bind
  local BIND_BIGGUS=( --bind "$BIGGUS_DISKUS:$BIGGUS_DISKUS" )

  # Aggregate binds for container invocation
  local BIND_ALL=(
    "${BIND_BIGGUS[@]}"
    "${BIND_HF_DIR[@]}"
    "${BIND_ATLAS[@]}"
    "${BIND_SCHED[@]}"
    "${EXTRA_BINDS[@]}"
  )

  # Stage HF to /tmp for a stable path inside the container
  local hf_tmp="/tmp/${USER}_samba_$(date +%s)_$(basename "$hf")"
  cp "$hf" "$hf_tmp"

  # Build command prefix used inside the container for sbatch/squeue logic
  local CMD_PREFIX_A=(
    "$CONTAINER_CMD" exec
    "${BIND_ALL[@]}"
    "$SIF_PATH"
  )
  export CONTAINER_CMD_PREFIX="${CMD_PREFIX_A[*]}"

  # Export for the container environment (via singularity env propagation)
  # NOTE: We call `env VAR=... "$CONTAINER_CMD" exec ...` so that these
  #       variables are definitely present inside the container.
  env \
    USER="$USER" \
    BIGGUS_DISKUS="$BIGGUS_DISKUS" \
    SIF_PATH="$SIF_PATH" \
    ATLAS_FOLDER="${ATLAS_FOLDER:-}" \
    NOTIFICATION_EMAIL="${NOTIFICATION_EMAIL:-}" \
    PIPELINE_QUEUE="${PIPELINE_QUEUE:-}" \
    SLURM_RESERVATION="${SLURM_RESERVATION:-}" \
    CONTAINER_CMD_PREFIX="${CMD_PREFIX_A[*]}" \
    SAMBA_SCHED_BACKEND="$SAMBA_SCHED_BACKEND" \
    SAMBA_SCHED_DIR="$SAMBA_SCHED_DIR" \
    "$CONTAINER_CMD" exec \
      "${BIND_ALL[@]}" \
      "$SIF_PATH" \
      SAMBA_startup "$hf_tmp"
}

# Optional: tiny sanity helper
function samba-pipe-prefix-debug {
  samba-pipe /dev/null 2>/dev/null || true
  env | grep '^CONTAINER_CMD_PREFIX='
}
