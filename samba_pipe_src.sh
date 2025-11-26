#!/usr/bin/env bash
#
# samba_pipe_src.sh
# Host-side helper for launching SAMBA inside a Singularity/Apptainer container
# and wiring up the scheduler proxy (samba_sched_daemon + samba_sched_proxy).
#

# -----------------------------
# Core locations / defaults
# -----------------------------

# Where the SAMBA repo lives on the host (for daemon, etc.)
if [[ -z "${SAMBA_APPS_DIR:-}" ]]; then
  SAMBA_APPS_DIR="/home/apps/SAMBA"
fi
export SAMBA_APPS_DIR

# Default scheduler backend: use proxy (daemon on host, proxy in container)
if [[ -z "${SAMBA_SCHED_BACKEND:-}" ]]; then
  SAMBA_SCHED_BACKEND="proxy"
fi
export SAMBA_SCHED_BACKEND

# Container launcher (host side)
if [[ -z "${CONTAINER_CMD:-}" ]]; then
  if command -v singularity >/dev/null 2>&1; then
    CONTAINER_CMD="singularity"
  elif command -v apptainer >/dev/null 2>&1; then
    CONTAINER_CMD="apptainer"
  else
    echo "ERROR: neither 'singularity' nor 'apptainer' found in PATH." >&2
    echo "       Set CONTAINER_CMD to the full path of your Singularity binary and re-source." >&2
    return 1 2>/dev/null || exit 1
  fi
fi
export CONTAINER_CMD

# Resolve SIF_PATH robustly:
# 1) If SIF_PATH is set AND points to a real file, keep it.
# 2) Else, try $SINGULARITY_IMAGE_DIR/samba.sif
# 3) Else, try /opt/containers/samba.sif
# 4) Else, hard fail.
if [[ -n "${SIF_PATH:-}" && -f "${SIF_PATH}" ]]; then
  :  # keep as-is
else
  # clear bogus value
  SIF_PATH=""

  if [[ -n "${SINGULARITY_IMAGE_DIR:-}" && -f "${SINGULARITY_IMAGE_DIR%/}/samba.sif" ]]; then
    SIF_PATH="${SINGULARITY_IMAGE_DIR%/}/samba.sif"
  elif [[ -f "/opt/containers/samba.sif" ]]; then
    SIF_PATH="/opt/containers/samba.sif"
  else
    echo "ERROR: could not determine SIF_PATH for samba.sif." >&2
    echo "       Tried:" >&2
    echo "         - existing \$SIF_PATH (invalid or missing)" >&2
    echo "         - \$SINGULARITY_IMAGE_DIR/samba.sif" >&2
    echo "         - /opt/containers/samba.sif" >&2
    echo "       Export SIF_PATH explicitly and re-source." >&2
    return 1 2>/dev/null || exit 1
  fi
fi
export SIF_PATH

# Extra bind mounts (auto-detect some common Slurm locations; harmless if unused)
EXTRA_BINDS=()
if [[ -d /etc/slurm ]]; then
  EXTRA_BINDS+=( --bind /etc/slurm:/etc/slurm )
fi
if [[ -d /usr/local/bin ]]; then
  EXTRA_BINDS+=( --bind /usr/local/bin:/usr/local/bin )
fi
if [[ -d /usr/local/lib/slurm ]]; then
  EXTRA_BINDS+=( --bind /usr/local/lib/slurm:/usr/local/lib/slurm )
fi

# -----------------------------
# Scheduler daemon helpers
# -----------------------------

_samba_find_daemon() {
  local d=""

  # 1) In PATH
  if command -v samba_sched_daemon >/dev/null 2>&1; then
    d="$(command -v samba_sched_daemon)"
    echo "$d"
    return 0
  fi

  # 2) In SAMBA_APPS_DIR/samba_sched_wrappers
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

  # 3) In SAMBA_APPS_DIR/SAMBA/samba_sched_wrappers
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

_samba_ensure_daemon() {
  # Only relevant in proxy mode
  if [[ "${SAMBA_SCHED_BACKEND:-native}" != "proxy" ]]; then
    return 0
  fi

  # IPC directory visible to both host + container
  if [[ -z "${SAMBA_SCHED_DIR:-}" ]]; then
    SAMBA_SCHED_DIR="${HOME}/samba_sched_ipc"
  fi
  export SAMBA_SCHED_DIR
  mkdir -p "${SAMBA_SCHED_DIR}"

  # Locate daemon binary
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

  if [[ -n "${dpid}" ]]; then
    if [[ "${dpid}" =~ ^[0-9]+$ ]] && kill -0 "${dpid}" 2>/dev/null; then
      # Already running
      return 0
    fi
  fi

  echo "[sched] starting samba_sched_daemon as user ${USER}"
  echo "[sched] daemon=${daemon}"
  echo "[sched] dir=${SAMBA_SCHED_DIR}"

  nohup "${daemon}" --dir "${SAMBA_SCHED_DIR}" --backend slurm \
    > "${SAMBA_SCHED_DIR}/daemon.log" 2>&1 &
  dpid=$!
  echo "${dpid}" > "${pid_file}"

  # Confirm it's alive
  sleep 0.1
  if ! kill -0 "${dpid}" 2>/dev/null; then
    echo "FATAL: samba_sched_daemon failed to start. See ${SAMBA_SCHED_DIR}/daemon.log" >&2
    return 1
  fi
}

# -----------------------------
# Main entry: samba-pipe
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

  # Ensure scheduler daemon (if using proxy)
  if ! _samba_ensure_daemon; then
    return 1
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

  # Stage HF to /tmp for stable path
  local hf_tmp="/tmp/${USER}_samba_$(date +%s)_$(basename "$hf")"
  cp "$hf" "$hf_tmp"

  # Build headfile directory bind
  local BIND_HF_DIR=( --bind "$(dirname "$hf")":"$(dirname "$hf")" )

  # Build prefix that jobs *inside* the container should use when they need
  # to launch more Singularity containers (e.g., nested sbatch scripts)
  local CMD_PREFIX_A=(
    "$CONTAINER_CMD" exec
    --bind "$BIGGUS_DISKUS:$BIGGUS_DISKUS"
    "${BIND_HF_DIR[@]}"
    "${BIND_ATLAS[@]}"
    "${EXTRA_BINDS[@]}"
    "$SIF_PATH"
  )
  export CONTAINER_CMD_PREFIX="${CMD_PREFIX_A[*]}"

  # Make sure scheduler env is exported so it reaches the container
  export SAMBA_SCHED_BACKEND
  export SAMBA_SCHED_DIR

  # Finally, launch SAMBA_startup inside the container
  "$CONTAINER_CMD" exec \
    --bind "$BIGGUS_DISKUS:$BIGGUS_DISKUS" \
    "${BIND_HF_DIR[@]}" \
    "${BIND_ATLAS[@]}" \
    "${EXTRA_BINDS[@]}" \
    "$SIF_PATH" \
    SAMBA_startup "$hf_tmp"
}
