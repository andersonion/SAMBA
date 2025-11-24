#!/usr/bin/env bash
#
# samba_pipe_src.sh  (host-side)
#
# Source this file on the host to get samba-pipe.
# It launches SAMBA inside Singularity/Apptainer and, if using proxy
# scheduler backend, automatically provisions + starts a per-user daemon
# with no sudo required.
#
#   source samba_pipe_src.sh
#   samba-pipe /path/to/headfile.hf
#

# -----------------------------
# Core configuration (host)
# -----------------------------

: "${CONTAINER_CMD:=singularity}"
: "${SIF_PATH:=/opt/containers/samba.sif}"

# Where this script lives (assumed inside host-side SAMBA checkout)
: "${SAMBA_APPS_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)}"

# Array of extra binds added site-wide
EXTRA_BINDS=()

# -----------------------------
# Helpers
# -----------------------------

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

_samba_ensure_sched_dir() {
  : "${SAMBA_SCHED_BACKEND:=proxy}"

  # Default shared IPC dir to BIGGUS so host+container see same filesystem
  if [[ -z "${SAMBA_SCHED_DIR:-}" ]]; then
    SAMBA_SCHED_DIR="${BIGGUS_DISKUS%/}/samba_sched_ipc"
  fi

  export SAMBA_SCHED_BACKEND SAMBA_SCHED_DIR
  mkdir -p "$SAMBA_SCHED_DIR"
}

_samba_find_daemon_source() {
  # Return path to daemon script we can use as a source
  local src=""

  if command -v samba_sched_daemon >/dev/null 2>&1; then
    src="$(command -v samba_sched_daemon)"
  elif [[ -x "${SAMBA_APPS_DIR}/samba_sched_wrappers/samba_sched_daemon" ]]; then
    src="${SAMBA_APPS_DIR}/samba_sched_wrappers/samba_sched_daemon"
  elif [[ -x "${SAMBA_APPS_DIR}/samba_sched_daemon" ]]; then
    src="${SAMBA_APPS_DIR}/samba_sched_daemon"
  fi

  printf "%s" "$src"
}

_samba_stage_daemon_userlocal() {
  # Ensure we have a daemon binary somewhere user-writable.
  # Echo the final daemon path, or empty on failure.

  local src
  src="$(_samba_find_daemon_source)"
  if [[ -z "$src" ]]; then
    echo ""
    return 0
  fi

  # If already in PATH, just use it
  if command -v samba_sched_daemon >/dev/null 2>&1; then
    printf "%s" "$(command -v samba_sched_daemon)"
    return 0
  fi

  # Candidate user bins
  local dstdir=""
  if [[ -d "$HOME/.local/bin" && -w "$HOME/.local/bin" ]]; then
    dstdir="$HOME/.local/bin"
  else
    dstdir="${BIGGUS_DISKUS%/}/.samba_host_bin"
    mkdir -p "$dstdir" 2>/dev/null || true
  fi

  if [[ ! -d "$dstdir" || ! -w "$dstdir" ]]; then
    echo ""
    return 0
  fi

  local dst="${dstdir%/}/samba_sched_daemon"
  cp -f "$src" "$dst"
  chmod +x "$dst"

  printf "%s" "$dst"
}

_samba_start_proxy_daemon_if_needed() {
  if [[ "${SAMBA_SCHED_BACKEND}" != "proxy" ]]; then
    return 0
  fi

  local daemon_bin
  daemon_bin="$(_samba_stage_daemon_userlocal)"

  if [[ -z "$daemon_bin" || ! -x "$daemon_bin" ]]; then
    echo "FATAL: SAMBA_SCHED_BACKEND=proxy but samba_sched_daemon not found." >&2
    echo "       Looked in PATH and in ${SAMBA_APPS_DIR}/samba_sched_wrappers/." >&2
    echo "       You should have samba_sched_daemon committed in the repo there." >&2
    return 1
  fi

  # One daemon per SAMBA_SCHED_DIR
  local pidfile="${SAMBA_SCHED_DIR%/}/daemon.pid"
  if [[ -f "$pidfile" ]]; then
    local pid
    pid="$(cat "$pidfile" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
  fi

  echo "[sched] starting samba_sched_daemon as user $(whoami)"
  echo "[sched] daemon=${daemon_bin}"
  echo "[sched] dir=${SAMBA_SCHED_DIR}"

  nohup "$daemon_bin" \
        --dir "$SAMBA_SCHED_DIR" \
        --backend "${SAMBA_SCHED_HOST_BACKEND:-slurm}" \
        >"${SAMBA_SCHED_DIR%/}/daemon.log" 2>&1 &

  echo $! > "$pidfile"
}

# -----------------------------
# Main entrypoint
# -----------------------------
function samba-pipe {
  local hf="$1"

  if [[ -z "$hf" ]]; then
    echo "Usage: samba-pipe headfile.hf" >&2
    return 1
  fi

  # Normalize headfile to absolute path once
  if [[ "${hf:0:1}" != "/" && "${hf:0:2}" != "~/" ]]; then
    hf="${PWD}/${hf}"
  fi
  if [[ ! -f "$hf" ]]; then
    echo "ERROR: headfile not found: $hf" >&2
    return 1
  fi

  # BIGGUS_DISKUS selection & validation
  _samba_pick_biggus
  if [[ ! -d "$BIGGUS_DISKUS" || ! -w "$BIGGUS_DISKUS" ]]; then
    echo "ERROR: BIGGUS_DISKUS ('$BIGGUS_DISKUS') is not writable or does not exist." >&2
    return 1
  fi

  # Warn if directory is not group-writable
  if ! perl -e 'exit((stat($ARGV[0]))[2] & 0020 ? 0 : 1)' "$BIGGUS_DISKUS"; then
    echo "Warning: $BIGGUS_DISKUS is not group-writable. Multi-user workflows may fail."
  fi

  # Scheduler proxy env + shared dir
  _samba_ensure_sched_dir
  _samba_start_proxy_daemon_if_needed || return 1

  # Atlas bind
  local BIND_ATLAS=()
  if [[ -n "${ATLAS_FOLDER:-}" && -d "$ATLAS_FOLDER" ]]; then
    BIND_ATLAS=( --bind "$ATLAS_FOLDER:$ATLAS_FOLDER" )
  fi

  # Scheduler IPC bind (only meaningful for proxy backend)
  local BIND_SCHED=()
  if [[ "$SAMBA_SCHED_BACKEND" == "proxy" && -d "$SAMBA_SCHED_DIR" ]]; then
    BIND_SCHED=( --bind "$SAMBA_SCHED_DIR:$SAMBA_SCHED_DIR" )
  fi

  # Headfile dir bind
  local HF_DIR
  HF_DIR="$(dirname "$hf")"
  local BIND_HF_DIR=( --bind "$HF_DIR:$HF_DIR" )

  # BIGGUS bind
  local BIND_BIGGUS=( --bind "$BIGGUS_DISKUS:$BIGGUS_DISKUS" )

  # Aggregate binds
  local BIND_ALL=(
    "${BIND_BIGGUS[@]}"
    "${BIND_HF_DIR[@]}"
    "${BIND_ATLAS[@]}"
    "${BIND_SCHED[@]}"
    "${EXTRA_BINDS[@]}"
  )

  # Stage HF into /tmp for stable container path
  local hf_tmp="/tmp/${USER}_samba_$(date +%s)_$(basename "$hf")"
  cp "$hf" "$hf_tmp"

  # Build command prefix used INSIDE container for dispatch
  local CMD_PREFIX_A=(
    "$CONTAINER_CMD" exec
    "${BIND_ALL[@]}"
    "$SIF_PATH"
  )
  export CONTAINER_CMD_PREFIX="${CMD_PREFIX_A[*]}"

  # Launch SAMBA_startup in container with env guaranteed
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

# Quick sanity helper
function samba-pipe-prefix-debug {
  samba-pipe /dev/null 2>/dev/null || true
  env | grep '^CONTAINER_CMD_PREFIX='
  echo "SAMBA_SCHED_BACKEND=${SAMBA_SCHED_BACKEND:-<unset>}"
  echo "SAMBA_SCHED_DIR=${SAMBA_SCHED_DIR:-<unset>}"
}
