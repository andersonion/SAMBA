#!/usr/bin/env bash
#
# Host-side helper for running SAMBA inside a Singularity container.
# Provides:
#   - samba-pipe function
#   - scheduler proxy/daemon plumbing (Slurm/SGE)
#

########################################
# Basic defaults
########################################

# Where the SAMBA repo / helpers live on the host.
# If SAMBA_APPS_DIR is already set, we do NOT override it.
if [[ -z "${SAMBA_APPS_DIR:-}" ]]; then
  # This script is expected at:  ${SAMBA_APPS_DIR}/SAMBA/samba_pipe_src.sh
  # So SAMBA_APPS_DIR is one level above the directory containing this file.
  SAMBA_APPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
export SAMBA_APPS_DIR

# Default scheduler backend: proxy (recommended) or native.
: "${SAMBA_SCHED_BACKEND:=proxy}"
export SAMBA_SCHED_BACKEND

# Container command and image path are usually set by the site,
# but we provide soft defaults so sourcing doesn't explode.
: "${CONTAINER_CMD:=singularity}"
: "${SIF_PATH:=/opt/containers/samba.sif}"

# Ensure EXTRA_BINDS is a bash array (but don't clobber existing contents).
if ! declare -p EXTRA_BINDS >/dev/null 2>&1; then
  declare -a EXTRA_BINDS=()
fi

########################################
# Scheduler daemon discovery
########################################

_samba_find_daemon() {
  local d=""

  # 1) If it's already in PATH as an executable
  if command -v samba_sched_daemon >/dev/null 2>&1; then
    d="$(command -v samba_sched_daemon)"
    echo "$d"
    return 0
  fi

  # 2) Look in ${SAMBA_APPS_DIR}/samba_sched_wrappers/
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

  # 3) Look in ${SAMBA_APPS_DIR}/SAMBA/samba_sched_wrappers/ (older layout)
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

########################################
# Ensure scheduler daemon is running (host side)
########################################

_samba_ensure_daemon() {
  # Only do anything if we're in proxy mode
  if [[ "${SAMBA_SCHED_BACKEND:-native}" != "proxy" ]]; then
    return 0
  fi

  # Where the IPC lives; must be visible to both host + container
  if [[ -z "${SAMBA_SCHED_DIR:-}" ]]; then
    SAMBA_SCHED_DIR="${HOME}/.samba_sched"
  fi
  export SAMBA_SCHED_DIR
  mkdir -p "${SAMBA_SCHED_DIR}"

  # Find the daemon binary (in PATH or in the repo)
  local daemon
  daemon="$(_samba_find_daemon || true)"

  if [[ -z "${daemon}" ]]; then
    echo "FATAL: SAMBA_SCHED_BACKEND=proxy but samba_sched_daemon not found." >&2
    echo "       Looked in PATH and in ${SAMBA_APPS_DIR}/samba_sched_wrappers/ and ${SAMBA_APPS_DIR}/SAMBA/samba_sched_wrappers/." >&2
    return 1
  fi

  # Check if it is already running
  local pid_file="${SAMBA_SCHED_DIR}/daemon.pid"
  local dpid=""
  if [[ -f "${pid_file}" ]]; then
    dpid="$(cat "${pid_file}" 2>/dev/null || true)"
  fi

  # If we have a numeric PID and it's alive, we're done
  if [[ -n "${dpid}" ]] && kill -0 "${dpid}" 2>/dev/null; then
    return 0
  fi

  echo "[sched] starting samba_sched_daemon as user ${USER}"
  echo "[sched] daemon=${daemon}"
  echo "[sched] dir=${SAMBA_SCHED_DIR}"

  # Start daemon on host; it will watch SAMBA_SCHED_DIR for requests.
  # NOTE: daemon expects:  --dir <ipc_dir> [--backend slurm|sge]
  nohup "${daemon}" \
    --dir "${SAMBA_SCHED_DIR}" \
    --backend slurm \
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

########################################
# Main entry: samba-pipe
########################################

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
  # Warn if directory is not group-writable (more accurate than -g/setgid)
  if ! perl -e 'exit((stat($ARGV[0]))[2] & 0020 ? 0 : 1)' "$BIGGUS_DISKUS"; then
    echo "Warning: $BIGGUS_DISKUS is not group-writable. Multi-user workflows may fail."
  fi

  # Atlas bind (array-safe)
  local BIND_ATLAS=()
  if [[ -n "${ATLAS_FOLDER:-}" && -d "$ATLAS_FOLDER" ]]; then
    BIND_ATLAS=( --bind "$ATLAS_FOLDER:$ATLAS_FOLDER" )
  else
    echo "Warning: ATLAS_FOLDER not set or does not exist. Proceeding with default atlas."
  fi

  # Export for Perl glue
  export SAMBA_ATLAS_BIND="${BIND_ATLAS[*]}"
  export SAMBA_BIGGUS_BIND="$BIGGUS_DISKUS:$BIGGUS_DISKUS"

  # Ensure scheduler daemon (for proxy backend)
  if ! _samba_ensure_daemon; then
    return 1
  fi

  # Stage HF to /tmp for stable path
  local hf_tmp="/tmp/${USER}_samba_$(date +%s)_$(basename "$hf")"
  cp "$hf" "$hf_tmp"

  # Env-file for container
  local ENV_FILE
  ENV_FILE="$(mktemp /tmp/samba_env.XXXXXX)"

  # Build command prefix (include BIGGUS & HF dir binds, atlas, extra binds)
  local BIND_HF_DIR=( --bind "$(dirname "$hf")":"$(dirname "$hf")" )
  local CMD_PREFIX_A=(
    "$CONTAINER_CMD" exec
    --bind "$BIGGUS_DISKUS:$BIGGUS_DISKUS"
    "${BIND_HF_DIR[@]}"
    "${BIND_ATLAS[@]}"
    "${EXTRA_BINDS[@]}"
    "$SIF_PATH"
  )
  export CONTAINER_CMD_PREFIX="${CMD_PREFIX_A[*]}"

  # Write selected env vars to ENV_FILE (visible inside container)
  local var val
  for var in \
      USER \
      BIGGUS_DISKUS \
      SIF_PATH \
      ATLAS_FOLDER \
      NOTIFICATION_EMAIL \
      PIPELINE_QUEUE \
      SLURM_RESERVATION \
      SAMBA_SCHED_BACKEND \
      SAMBA_SCHED_DIR \
      CONTAINER_CMD_PREFIX; do
    val="${!var:-}"
    if [[ -n "$val" ]]; then
      printf '%s=%s\n' "$var" "$val" >> "$ENV_FILE"
    fi
  done

  # Run inside the container
  eval "$CONTAINER_CMD_PREFIX" SAMBA_startup "$hf_tmp"
}
