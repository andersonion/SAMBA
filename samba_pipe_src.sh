#!/usr/bin/env bash
# samba_pipe_src.sh
#
# Host-side helper for launching SAMBA inside Singularity/Apptainer.

if [[ -n "${_SAMBA_PIPE_SRC_LOADED:-}" ]]; then
  return 0
fi
_SAMBA_PIPE_SRC_LOADED=1

# ----------------------------------------------------------------------
# Defaults
# ----------------------------------------------------------------------
if [[ -z "${SAMBA_APPS_DIR:-}" ]]; then
  SAMBA_APPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

: "${SAMBA_SCHED_BACKEND:=proxy}"
: "${SAMBA_SCHED_DIR:=$HOME/.samba_sched}"

# ----------------------------------------------------------------------
# EXTRA_BINDS
# ----------------------------------------------------------------------
if ! declare -p EXTRA_BINDS >/dev/null 2>&1; then
  declare -a EXTRA_BINDS=()
fi

_samba_setup_extra_binds() {
  [[ -d /etc/slurm ]]              && EXTRA_BINDS+=( --bind "/etc/slurm:/etc/slurm" )
  [[ -d /usr/local/bin ]]          && EXTRA_BINDS+=( --bind "/usr/local/bin:/usr/local/bin" )
  [[ -d /usr/local/lib/slurm ]]    && EXTRA_BINDS+=( --bind "/usr/local/lib/slurm:/usr/local/lib/slurm" )
}
if [[ -z "${_SAMBA_EXTRA_BINDS_INIT:-}" ]]; then
  _samba_setup_extra_binds
  _SAMBA_EXTRA_BINDS_INIT=1
fi

# ----------------------------------------------------------------------
# Find scheduler daemon
# ----------------------------------------------------------------------
_samba_find_daemon() {
  if command -v samba_sched_daemon >/dev/null 2>&1; then
    command -v samba_sched_daemon
    return 0
  fi

  local c1="${SAMBA_APPS_DIR}/samba_sched_wrappers/samba_sched_daemon"
  local c2="${SAMBA_APPS_DIR}/SAMBA/samba_sched_wrappers/samba_sched_daemon"

  [[ -x "$c1" ]] && { echo "$c1"; return 0; }
  [[ -x "$c2" ]] && { echo "$c2"; return 0; }

  return 1
}

# ----------------------------------------------------------------------
# Start daemon (FIXED BUG HERE)
# ----------------------------------------------------------------------
_samba_ensure_daemon() {
  [[ "${SAMBA_SCHED_BACKEND:-native}" != "proxy" ]] && return 0

  local daemon
  if ! daemon="$(_samba_find_daemon)"; then
    echo "FATAL: SAMBA_SCHED_BACKEND=proxy but no samba_sched_daemon found." >&2
    return 1
  fi

  mkdir -p "$SAMBA_SCHED_DIR"

  # Reuse daemon if already running
  local dpid=""
  if [[ -f "$SAMBA_SCHED_DIR/daemon.pid" ]]; then
    dpid="$(cat "$SAMBA_SCHED_DIR/daemon.pid" 2>/dev/null || true)"
    if [[ -n "$dpid" ]]; then
      if kill -0 "$dpid" 2>/dev/null; then
        return 0
      fi
    fi
  fi

  echo "[sched] starting samba_sched_daemon as $USER" >&2
  echo "[sched] daemon=$daemon" >&2
  echo "[sched] dir=${SAMBA_SCHED_DIR}" >&2

  # FIXED: use --dir (not --ipc-dir)
  nohup "$daemon" --dir "$SAMBA_SCHED_DIR" --backend slurm \
      >"$SAMBA_SCHED_DIR/daemon.log" 2>&1 &

  echo $! > "$SAMBA_SCHED_DIR/daemon.pid"
  sleep 0.5

  dpid="$(cat "$SAMBA_SCHED_DIR/daemon.pid" 2>/dev/null || true)"

  # --- FIXED: bash-safe validation ---
  if [[ -z "$dpid" ]]; then
    echo "FATAL: could not read daemon pid" >&2
    return 1
  fi

  # numeric check
  case "$dpid" in
    ''|*[!0-9]*)
      echo "FATAL: daemon pid is not numeric: '$dpid'" >&2
      return 1
      ;;
  esac

  # process alive?
  if ! kill -0 "$dpid" 2>/dev/null; then
    echo "FATAL: daemon failed to start; see ${SAMBA_SCHED_DIR}/daemon.log" >&2
    return 1
  fi
}

# ----------------------------------------------------------------------
# Main SAMBA launcher
# ----------------------------------------------------------------------
function samba-pipe {
  local hf="$1"

  if [[ -z "$hf" ]]; then
    echo "Usage: samba-pipe headfile.hf" >&2
    return 1
  fi

  if [[ "${hf:0:1}" != "/" && "${hf:0:2}" != "~/" ]]; then
    hf="${PWD}/${hf}"
  fi

  if [[ ! -f "$hf" ]]; then
    echo "ERROR: headfile not found: $hf" >&2
    return 1
  fi

  # BIGGUS_DISKUS selection
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
    echo "ERROR: BIGGUS_DISKUS '$BIGGUS_DISKUS' not writable." >&2
    return 1
  fi

  # Start daemon for proxy mode
  if [[ "${SAMBA_SCHED_BACKEND:-native}" == "proxy" ]]; then
    if ! _samba_ensure_daemon; then
      echo "[sched] WARNING: proxy unavailable, using native." >&2
      export SAMBA_SCHED_BACKEND=native
    fi
    export SAMBA_SCHED_DIR
  fi

  # Atlas binds
  local BIND_ATLAS=()
  if [[ -n "${ATLAS_FOLDER:-}" && -d "$ATLAS_FOLDER" ]]; then
    BIND_ATLAS=( --bind "$ATLAS_FOLDER:$ATLAS_FOLDER" )
  fi

  export SAMBA_ATLAS_BIND="${BIND_ATLAS[*]}"
  export SAMBA_BIGGUS_BIND="$BIGGUS_DISKUS:$BIGGUS_DISKUS"

  local hf_tmp="/tmp/${USER}_samba_$(date +%s)_$(basename "$hf")"
  cp "$hf" "$hf_tmp"

  local ENV_FILE
  ENV_FILE="$(mktemp /tmp/samba_env.XXXXXX)"

  local BIND_HF_DIR=( --bind "$(dirname "$hf")":"$(dirname "$hf")" )
  local CMD_PREFIX_A=(
    "$CONTAINER_CMD"
    exec
    --env-file "$ENV_FILE"
    --bind "$BIGGUS_DISKUS:$BIGGUS_DISKUS"
    "${BIND_HF_DIR[@]}"
    "${BIND_ATLAS[@]}"
    "${EXTRA_BINDS[@]}"
    "$SIF_PATH"
  )

  export CONTAINER_CMD_PREFIX="${CMD_PREFIX_A[*]}"

  local var val
  for var in USER BIGGUS_DISKUS SIF_PATH ATLAS_FOLDER \
             SAMBA_SCHED_BACKEND SAMBA_SCHED_DIR \
             NOTIFICATION_EMAIL PIPELINE_QUEUE SLURM_RESERVATION; do
    val="${!var:-}"
    [[ -n "$val" ]] && printf '%s=%s\n' "$var" "$val" >> "$ENV_FILE"
  done

  eval "${CONTAINER_CMD_PREFIX}" SAMBA_startup "$hf_tmp"
}
