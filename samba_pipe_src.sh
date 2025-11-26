#!/usr/bin/env bash
#
# samba_pipe_src.sh
#
# Shell helpers for launching SAMBA inside a Singularity/Apptainer
# container, with optional Slurm/SGE scheduler proxying.
#
# This file is meant to be sourced, not executed:
#   source /home/apps/SAMBA/samba_pipe_src.sh
#

##############################################################################
# Core config: where SAMBA + container live
##############################################################################

# Base SAMBA install directory on the *host*
: "${SAMBA_APPS_DIR:=/home/apps/}"

# Default image dir (e.g., used on your clusters)
: "${SINGULARITY_IMAGE_DIR:=/opt/containers}"

# Default Singularity binary
: "${CONTAINER_CMD:=singularity}"

# Default SIF path; can be overridden by exporting SIF_PATH beforehand
: "${SIF_PATH:=${SINGULARITY_IMAGE_DIR}/samba.sif}"

# Default scheduler backend:
#   native -> call sbatch/squeue/etc directly
#   proxy  -> go via samba_sched_daemon on host
: "${SAMBA_SCHED_BACKEND:=proxy}"

export SAMBA_APPS_DIR
export SINGULARITY_IMAGE_DIR
export CONTAINER_CMD
export SIF_PATH
export SAMBA_SCHED_BACKEND

##############################################################################
# Slurm / system auto-binds
##############################################################################

# EXTRA_BINDS is an array of "--bind src:dest ..." elements
EXTRA_BINDS=()

_samba_auto_bind_slurm() {
  EXTRA_BINDS=()

  # Slurm config
  if [[ -d /etc/slurm ]]; then
    EXTRA_BINDS+=( --bind /etc/slurm:/etc/slurm )
  fi

  # Slurm libraries
  if [[ -d /usr/local/lib/slurm ]]; then
    EXTRA_BINDS+=( --bind /usr/local/lib/slurm:/usr/local/lib/slurm )
  fi

  # Slurm binaries (sbatch, squeue, etc.)
  if command -v sbatch >/dev/null 2>&1; then
    sbatch_path="$(command -v sbatch)"
    sbatch_dir="$(dirname "$sbatch_path")"
    EXTRA_BINDS+=( --bind "${sbatch_dir}:${sbatch_dir}" )
  fi
}

##############################################################################
# Scheduler daemon discovery
##############################################################################

_samba_find_daemon() {
  local d=""

  # 1) PATH
  if command -v samba_sched_daemon >/dev/null 2>&1; then
    d="$(command -v samba_sched_daemon)"
    echo "$d"
    return 0
  fi

  # 2) In SAMBA repo: ${SAMBA_APPS_DIR}/samba_sched_wrappers
  if [[ -x "${SAMBA_APPS_DIR}/samba_sched_wrappers/samba_sched_daemon" ]]; then
    d="${SAMBA_APPS_DIR}/samba_sched_wrappers/samba_sched_daemon"
    echo "$d"
    return 0
  fi

  if [[ -x "${SAMBA_APPS_DIR}/samba_sched_wrappers/samba_sched_daemon.sh" ]]; then
    d="${SAMBA_APPS_DIR}/samba_sched_wrappers/samba_sched_daemon.sh"
    echo "$d"
    return 0
  fi

  # 3) In SAMBA repo: ${SAMBA_APPS_DIR}/SAMBA/samba_sched_wrappers
  if [[ -x "${SAMBA_APPS_DIR}/SAMBA/samba_sched_wrappers/samba_sched_daemon" ]]; then
    d="${SAMBA_APPS_DIR}/SAMBA/samba_sched_wrappers/samba_sched_daemon"
    echo "$d"
    return 0
  fi

  if [[ -x "${SAMBA_APPS_DIR}/SAMBA/samba_sched_wrappers/samba_sched_daemon.sh" ]]; then
    d="${SAMBA_APPS_DIR}/SAMBA/samba_sched_wrappers/samba_sched_daemon.sh"
    echo "$d"
    return 0
  fi

  return 1
}

##############################################################################
# Ensure scheduler daemon is running (host side, not in container)
##############################################################################

_samba_ensure_daemon() {
  # Only do anything if we're in proxy mode
  if [[ "${SAMBA_SCHED_BACKEND:-native}" != "proxy" ]]; then
    return 0
  fi

  # IPC dir visible to both host and container
  if [[ -z "${SAMBA_SCHED_DIR:-}" ]]; then
    SAMBA_SCHED_DIR="${HOME}/.samba_sched"
  fi
  export SAMBA_SCHED_DIR
  mkdir -p "${SAMBA_SCHED_DIR}"

  # Find daemon binary
  local daemon
  daemon="$(_samba_find_daemon || true)"

  if [[ -z "${daemon}" ]]; then
    echo "FATAL: SAMBA_SCHED_BACKEND=proxy but samba_sched_daemon not found." >&2
    echo "       Looked in PATH and in ${SAMBA_APPS_DIR}/samba_sched_wrappers/ and ${SAMBA_APPS_DIR}/SAMBA/samba_sched_wrappers/." >&2
    return 1
  fi

  # Check if already running
  local pid_file="${SAMBA_SCHED_DIR}/daemon.pid"
  local dpid=""
  if [[ -f "${pid_file}" ]]; then
    dpid="$(cat "${pid_file}" 2>/dev/null || true)"
  fi

  if [[ -n "${dpid}" && "${dpid}" =~ ^[0-9]+$ ]] && kill -0 "${dpid}" 2>/dev/null; then
    # Already running
    return 0
  fi

  echo "[sched] starting samba_sched_daemon as user ${USER}"
  echo "[sched] daemon=${daemon}"
  echo "[sched] dir=${SAMBA_SCHED_DIR}"

  nohup "${daemon}" --dir "${SAMBA_SCHED_DIR}" --backend slurm \
    > "${SAMBA_SCHED_DIR}/daemon.log" 2>&1 &
  dpid=$!
  echo "${dpid}" > "${pid_file}"

  # Give it a moment and confirm it's alive
  sleep 0.1
  if ! kill -0 "${dpid}" 2>/dev/null; then
    echo "FATAL: samba_sched_daemon failed to start. See ${SAMBA_SCHED_DIR}/daemon.log" >&2
    return 1
  fi
}

##############################################################################
# Main entrypoint: samba-pipe
##############################################################################

samba-pipe() {
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

  # Warn if not group-writable
  if ! perl -e 'exit((stat($ARGV[0]))[2] & 0020 ? 0 : 1)' "$BIGGUS_DISKUS"; then
    echo "Warning: $BIGGUS_DISKUS is not group-writable. Multi-user workflows may fail."
  fi

  # Atlas bind
  local BIND_ATLAS=()
  if [[ -n "${ATLAS_FOLDER:-}" && -d "$ATLAS_FOLDER" ]]; then
    BIND_ATLAS=( --bind "$ATLAS_FOLDER:$ATLAS_FOLDER" )
  fi

  export SAMBA_ATLAS_BIND="${BIND_ATLAS[*]}"
  export SAMBA_BIGGUS_BIND="$BIGGUS_DISKUS:$BIGGUS_DISKUS"

  # Ensure scheduler daemon if proxy backend
  _samba_ensure_daemon || return 1

  # Stage HF to /tmp for stable path
  local hf_tmp="/tmp/${USER}_samba_$(date +%s)_$(basename "$hf")"
  cp "$hf" "$hf_tmp"

  # Auto-detect Slurm libs/bins for binds
  _samba_auto_bind_slurm

  # Headfile dir bind
  local BIND_HF_DIR=( --bind "$(dirname "$hf")":"$(dirname "$hf")" )

  # Build container command prefix (host-side)
  local CMD_PREFIX_A=(
    "$CONTAINER_CMD" exec
    --bind "$BIGGUS_DISKUS:$BIGGUS_DISKUS"
    "${BIND_HF_DIR[@]}"
    "${BIND_ATLAS[@]}"
    "${EXTRA_BINDS[@]}"
    "$SIF_PATH"
  )

  # *** CRITICAL: export into env so SAMBA_startup can see it ***
  export CONTAINER_CMD_PREFIX="${CMD_PREFIX_A[*]}"

  # Also export scheduler env for inside-container code to see
  export SAMBA_SCHED_BACKEND
  export SAMBA_SCHED_DIR
  export BIGGUS_DISKUS
  export ATLAS_FOLDER
  export SIF_PATH

  # For debugging you can uncomment:
  # echo "[DEBUG] CONTAINER_CMD_PREFIX=${CONTAINER_CMD_PREFIX}" >&2

  # Launch SAMBA_startup inside the container
  eval "${CONTAINER_CMD_PREFIX}" /opt/samba/SAMBA/SAMBA_startup "${hf_tmp}"
}

##############################################################################
# End of samba_pipe_src.sh
##############################################################################
