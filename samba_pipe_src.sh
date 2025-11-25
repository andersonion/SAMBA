#!/usr/bin/env bash
# samba_pipe_src.sh
#
# Host-side helper for launching SAMBA inside Singularity/Apptainer.
#  - Sets up BIGGUS_DISKUS, atlas bind, and other binds.
#  - Optionally uses a scheduler proxy/daemon for Slurm/SGE.
#
# Source this in your shell, then run:
#   samba-pipe /path/to/headfile.hf

# ----------------------------------------------------------------------
# One-time guard to avoid re-defining functions if sourced twice
# ----------------------------------------------------------------------
if [[ -n "${_SAMBA_PIPE_SRC_LOADED:-}" ]]; then
  return 0
fi
_SAMBA_PIPE_SRC_LOADED=1

# ----------------------------------------------------------------------
# Basic defaults
# ----------------------------------------------------------------------
# Where the SAMBA repo lives on the host
if [[ -z "${SAMBA_APPS_DIR:-}" ]]; then
  SAMBA_APPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Where the image lives (caller can/usually does override before sourcing)
/usr/bin/true  # no-op placeholder; avoids "set -e" surprises in caller

# Default scheduler backend: native or proxy
: "${SAMBA_SCHED_BACKEND:=proxy}"

# Default scheduler IPC dir on host (shared with container via BIGGUS_DISKUS or explicit bind)
: "${SAMBA_SCHED_DIR:=$HOME/.samba_sched}"

# ----------------------------------------------------------------------
# Optional: auto-augment EXTRA_BINDS with scheduler + host libs
# (only used when we might call host sbatch/squeue/etc. from inside container)
# ----------------------------------------------------------------------
if ! declare -p EXTRA_BINDS >/dev/null 2>&1; then
  # ensure it's an array
  declare -a EXTRA_BINDS=()
fi

_samba_setup_extra_binds() {
  # Slurm config
  if [[ -d /etc/slurm ]]; then
    EXTRA_BINDS+=( --bind "/etc/slurm:/etc/slurm" )
  fi

  # Host Slurm libs (if used in native mode)
  if [[ -d /usr/local/lib/slurm ]]; then
    EXTRA_BINDS+=( --bind "/usr/local/lib/slurm:/usr/local/lib/slurm" )
  fi

  # Common host bin dir so /usr/local/bin/sbatch is visible inside container
  if [[ -d /usr/local/bin ]]; then
    EXTRA_BINDS+=( --bind "/usr/local/bin:/usr/local/bin" )
  fi

  # If you want to support native-host glibc for sbatch, uncomment these:
  # if [[ -d /lib/x86_64-linux-gnu ]]; then
  #   EXTRA_BINDS+=( --bind "/lib/x86_64-linux-gnu:/lib/x86_64-linux-gnu" )
  # fi
  # if [[ -d /usr/lib/x86_64-linux-gnu ]]; then
  #   EXTRA_BINDS+=( --bind "/usr/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu" )
  # fi
}

if [[ -z "${_SAMBA_EXTRA_BINDS_INIT:-}" ]]; then
  _samba_setup_extra_binds
  _SAMBA_EXTRA_BINDS_INIT=1
fi

# ----------------------------------------------------------------------
# Scheduler daemon discovery + startup (host side)
# ----------------------------------------------------------------------
_samba_find_daemon() {
  local d=""

  # 1) If installed in PATH (e.g., /usr/local/bin/samba_sched_daemon)
  if command -v samba_sched_daemon >/dev/null 2>&1; then
    d="$(command -v samba_sched_daemon)"
    echo "$d"
    return 0
  fi

  # 2) In repo root dir
  if [[ -x "${SAMBA_APPS_DIR}/samba_sched_wrappers/samba_sched_daemon" ]]; then
    d="${SAMBA_APPS_DIR}/samba_sched_wrappers/samba_sched_daemon"
    echo "$d"
    return 0
  fi

  # 3) Sometimes SAMBA_APPS_DIR might be /home/apps, and repo is /home/apps/SAMBA
  if [[ -x "${SAMBA_APPS_DIR}/SAMBA/samba_sched_wrappers/samba_sched_daemon" ]]; then
    d="${SAMBA_APPS_DIR}/SAMBA/samba_sched_wrappers/samba_sched_daemon"
    echo "$d"
    return 0
  fi

  return 1
}

_samba_ensure_daemon() {
  # Only relevant when using proxy backend
  if [[ "${SAMBA_SCHED_BACKEND:-native}" != "proxy" ]]; then
    return 0
  fi

  local daemon
  if ! daemon="$(_samba_find_daemon)"; then
    echo "FATAL: SAMBA_SCHED_BACKEND=proxy but samba_sched_daemon not found." >&2
    echo "       Looked in PATH and in ${SAMBA_APPS_DIR}/samba_sched_wrappers/ and ${SAMBA_APPS_DIR}/SAMBA/samba_sched_wrappers/." >&2
    return 1
  fi

  # Ensure IPC dir
  mkdir -p "${SAMBA_SCHED_DIR}"

  # If daemon pid exists and is alive, reuse it
  if [[ -f "${SAMBA_SCHED_DIR}/daemon.pid" ]]; then
    local pid
    pid="$(cat "${SAMBA_SCHED_DIR}/daemon.pid" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
  fi

  echo "[sched] starting samba_sched_daemon as user ${USER}" >&2
  echo "[sched] daemon=${daemon}" >&2
  echo "[sched] dir=${SAMBA_SCHED_DIR}" >&2

  # *** FIXED: use --dir, not --ipc-dir ***
  nohup "${daemon}" --dir "${SAMBA_SCHED_DIR}" --backend slurm \
    > "${SAMBA_SCHED_DIR}/daemon.log" 2>&1 &

  echo $! > "${SAMBA_SCHED_DIR}/daemon.pid"

  # Give it a moment, then check if it’s still alive
  sleep 0.5
  local dpid
  dpid="$(cat "${SAMBA_SCHED_DIR}/daemon.pid" 2>/dev/null || true)"
  if [[ -z "$dpid" || ! ( "$dpid" =~ ^[0-9]+$ ) || ! kill -0 "$dpid" 2>/dev/null ]]; then
    echo "FATAL: samba_sched_daemon failed to start. See ${SAMBA_SCHED_DIR}/daemon.log" >&2
    return 1
  fi
}

# ----------------------------------------------------------------------
# Main entry: samba-pipe
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
  # Warn if directory is not group-writable (more accurate than -g/setgid)
  if ! perl -e 'exit((stat($ARGV[0]))[2] & 0020 ? 0 : 1)' "$BIGGUS_DISKUS"; then
    echo "Warning: $BIGGUS_DISKUS is not group-writable. Multi-user workflows may fail."
  fi

  # If using proxy backend, ensure daemon is up, else fall back to native
  local backend="${SAMBA_SCHED_BACKEND:-native}"
  if [[ "$backend" == "proxy" ]]; then
    if ! _samba_ensure_daemon; then
      echo "[sched] WARNING: proxy requested but daemon not available; falling back to native backend." >&2
      backend="native"
      export SAMBA_SCHED_BACKEND="native"
    else
      # make sure SAMBA_SCHED_DIR is exported so proxy inside container can find it
      export SAMBA_SCHED_DIR
    fi
  fi

  # Atlas bind (array-safe)
  local BIND_ATLAS=()
  if [[ -n "${ATLAS_FOLDER:-}" && -d "$ATLAS_FOLDER" ]]; then
    BIND_ATLAS=( --bind "$ATLAS_FOLDER:$ATLAS_FOLDER" )
  else
    echo "Warning: ATLAS_FOLDER not set or does not exist. Proceeding with default atlas." >&2
  fi

  # Export for Perl glue (kept from your version)
  export SAMBA_ATLAS_BIND="${BIND_ATLAS[*]}"
  export SAMBA_BIGGUS_BIND="$BIGGUS_DISKUS:$BIGGUS_DISKUS"

  # Stage HF to /tmp for stable path
  local hf_tmp="/tmp/${USER}_samba_$(date +%s)_$(basename "$hf")"
  cp "$hf" "$hf_tmp"

  # Env-file for container
  local ENV_FILE
  ENV_FILE="$(mktemp /tmp/samba_env.XXXXXX)"

  # Build command prefix (include BIGGUS & HF dir binds, atlas, schedulers)
  local BIND_HF_DIR=( --bind "$(dirname "$hf")":"$(dirname "$hf")" )
  local CMD_PREFIX_A=(
    "${CONTAINER_CMD}"
    exec
    --env-file "$ENV_FILE"
    --bind "$BIGGUS_DISKUS:$BIGGUS_DISKUS"
    "${BIND_HF_DIR[@]}"
    "${BIND_ATLAS[@]}"
    "${EXTRA_BINDS[@]}"
    "${SIF_PATH}"
  )
  export CONTAINER_CMD_PREFIX="${CMD_PREFIX_A[*]}"

  # Write selected env vars to ENV_FILE
  # (do NOT write CONTAINER_CMD_PREFIX itself; that caused the old 'env: exec not found' issue)
  local var val
  for var in USER BIGGUS_DISKUS SIF_PATH ATLAS_FOLDER NOTIFICATION_EMAIL \
             PIPELINE_QUEUE SLURM_RESERVATION SAMBA_SCHED_BACKEND SAMBA_SCHED_DIR; do
    val="${!var:-}"
    if [[ -n "$val" ]]; then
      printf '%s=%s\n' "$var" "$val" >> "$ENV_FILE"
    fi
  done

  # Run inside the container
  eval "${CONTAINER_CMD_PREFIX}" SAMBA_startup "$hf_tmp"
}
