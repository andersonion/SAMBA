#!/usr/bin/env bash
#
# samba_pipe_src.sh
#
# Defines the `samba-pipe` front-end and scheduler glue for running
# SAMBA inside a Singularity/Apptainer container, with optional
# Slurm/SGE proxy backend.

# -------------------------------
# Core env defaults / detection
# -------------------------------

# Where SAMBA lives on the *host* (not inside container).
# On your systems this is usually /home/apps/
if [[ -z "${SAMBA_APPS_DIR:-}" ]]; then
  # Try to infer from this script’s path, but don’t overwrite if set
  if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    # e.g. /home/apps/SAMBA/samba_pipe_src.sh -> /home/apps
    _ssp="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SAMBA_APPS_DIR="$(cd "${_ssp}/.." && pwd)"
    unset _ssp
  else
    SAMBA_APPS_DIR="/home/apps"
  fi
fi
export SAMBA_APPS_DIR

# Default scheduler backend: use proxy (daemon) by default
export SAMBA_SCHED_BACKEND="${SAMBA_SCHED_BACKEND:-proxy}"

# -------------------------------
# Helper: find container image
# -------------------------------
_samba_detect_container() {
  # 1) Respect pre-set SIF_PATH if valid
  if [[ -n "${SIF_PATH:-}" && -f "${SIF_PATH}" ]]; then
    return 0
  fi

  local candidates=()

  # 2) Explicit override
  if [[ -n "${SAMBA_CONTAINER_PATH:-}" ]]; then
    candidates+=( "${SAMBA_CONTAINER_PATH}" )
  fi

  # 3) Singularity image dir (your standard setup)
  if [[ -n "${SINGULARITY_IMAGE_DIR:-}" ]]; then
    candidates+=( "${SINGULARITY_IMAGE_DIR%/}/samba.sif" )
  fi

  # 4) Some common fallbacks
  candidates+=( \
    "${HOME}/containers/samba.sif" \
    "/opt/containers/samba.sif" \
    "/home/apps/singularity/images/samba.sif" \
    "/home/apps/ubuntu-22.04/singularity/images/samba.sif" \
  )

  for p in "${candidates[@]}"; do
    if [[ -n "${p}" && -f "${p}" ]]; then
      export SIF_PATH="${p}"
      break
    fi
  done

  if [[ -z "${SIF_PATH:-}" ]]; then
    echo "ERROR: could not locate samba.sif container image." 1>&2
    echo "       Checked (in order):" 1>&2
    for p in "${candidates[@]}"; do
      echo "         ${p}" 1>&2
    done
    echo "       You can fix this by setting SIF_PATH or SAMBA_CONTAINER_PATH." 1>&2
    return 1
  fi

  return 0
}

# -------------------------------
# Helper: find scheduler daemon
# -------------------------------
_samba_find_daemon() {
  local d=""

  # 1) In PATH
  if command -v samba_sched_daemon >/dev/null 2>&1; then
    d="$(command -v samba_sched_daemon)"
    echo "${d}"
    return 0
  fi

  # 2) In SAMBA_APPS_DIR/samba_sched_wrappers
  if [[ -x "${SAMBA_APPS_DIR}/samba_sched_wrappers/samba_sched_daemon" ]]; then
    d="${SAMBA_APPS_DIR}/samba_sched_wrappers/samba_sched_daemon"
    echo "${d}"
    return 0
  fi
  if [[ -x "${SAMBA_APPS_DIR}/samba_sched_wrappers/samba_sched_daemon.sh" ]]; then
    d="${SAMBA_APPS_DIR}/samba_sched_wrappers/samba_sched_daemon.sh"
    echo "${d}"
    return 0
  fi

  # 3) In SAMBA_APPS_DIR/SAMBA/samba_sched_wrappers (your current layout)
  if [[ -x "${SAMBA_APPS_DIR}/SAMBA/samba_sched_wrappers/samba_sched_daemon" ]]; then
    d="${SAMBA_APPS_DIR}/SAMBA/samba_sched_wrappers/samba_sched_daemon"
    echo "${d}"
    return 0
  fi
  if [[ -x "${SAMBA_APPS_DIR}/SAMBA/samba_sched_wrappers/samba_sched_daemon.sh" ]]; then
    d="${SAMBA_APPS_DIR}/SAMBA/samba_sched_wrappers/samba_sched_daemon.sh"
    echo "${d}"
    return 0
  fi

  return 1
}

# -------------------------------
# Helper: ensure daemon running
# -------------------------------
_samba_ensure_daemon() {
  # Only do anything if we're in proxy mode
  if [[ "${SAMBA_SCHED_BACKEND:-native}" != "proxy" ]]; then
    return 0
  fi

  # IPC directory visible to both host & container
  if [[ -z "${SAMBA_SCHED_DIR:-}" ]]; then
    SAMBA_SCHED_DIR="${HOME}/.samba_sched"
  fi
  export SAMBA_SCHED_DIR
  mkdir -p "${SAMBA_SCHED_DIR}"

  # Find daemon binary
  local daemon
  daemon="$(_samba_find_daemon || true)"

  if [[ -z "${daemon}" ]]; then
    echo "FATAL: SAMBA_SCHED_BACKEND=proxy but samba_sched_daemon not found." 1>&2
    echo "       Looked in PATH and in ${SAMBA_APPS_DIR}/samba_sched_wrappers/ and ${SAMBA_APPS_DIR}/SAMBA/samba_sched_wrappers/." 1>&2
    return 1
  fi

  # Check if already running
  local pid_file="${SAMBA_SCHED_DIR}/daemon.pid"
  local dpid=""
  if [[ -f "${pid_file}" ]]; then
    dpid="$(cat "${pid_file}" 2>/dev/null || true)"
  fi

  if [[ -n "${dpid}" ]]; then
    if [[ "${dpid}" =~ ^[0-9]+$ ]]; then
      if kill -0 "${dpid}" 2>/dev/null; then
        # Already alive
        return 0
      fi
    fi
  fi

  echo "[sched] starting samba_sched_daemon as user ${USER}"
  echo "[sched] daemon=${daemon}"
  echo "[sched] dir=${SAMBA_SCHED_DIR}"

  # Note: daemon expects --dir, not --ipc-dir
  nohup "${daemon}" --dir "${SAMBA_SCHED_DIR}" --backend slurm > "${SAMBA_SCHED_DIR}/daemon.log" 2>&1 &
  dpid=$!
  echo "${dpid}" > "${pid_file}"

  # Give it a moment and confirm it's alive
  sleep 0.2
  if ! kill -0 "${dpid}" 2>/dev/null; then
    echo "FATAL: samba_sched_daemon failed to start. See ${SAMBA_SCHED_DIR}/daemon.log" 1>&2
    return 1
  fi
}

# -------------------------------
# Main front-end: samba-pipe
# -------------------------------
function samba-pipe {
  local hf="$1"

  if [[ -z "${hf}" ]]; then
    echo "Usage: samba-pipe headfile.hf" 1>&2
    return 1
  fi

  # Make headfile absolute
  if [[ "${hf:0:1}" != "/" && "${hf:0:2}" != "~/" ]]; then
    hf="${PWD}/${hf}"
  fi

  if [[ ! -f "${hf}" ]]; then
    echo "ERROR: headfile not found: ${hf}" 1>&2
    return 1
  fi

  # BIGGUS_DISKUS selection & validation
  if [[ -z "${BIGGUS_DISKUS:-}" ]]; then
    if [[ -d "${SCRATCH:-}" ]]; then
      export BIGGUS_DISKUS="${SCRATCH}"
    elif [[ -d "${WORK:-}" ]]; then
      export BIGGUS_DISKUS="${WORK}"
    else
      export BIGGUS_DISKUS="${HOME}/samba_scratch"
      mkdir -p "${BIGGUS_DISKUS}"
    fi
  fi

  if [[ ! -d "${BIGGUS_DISKUS}" || ! -w "${BIGGUS_DISKUS}" ]]; then
    echo "ERROR: BIGGUS_DISKUS ('${BIGGUS_DISKUS}') is not writable or does not exist." 1>&2
    return 1
  fi

  # Warn if not group-writable (more accurate than setgid bit)
  if ! perl -e 'exit((stat($ARGV[0]))[2] & 0020 ? 0 : 1)' "${BIGGUS_DISKUS}"; then
    echo "Warning: ${BIGGUS_DISKUS} is not group-writable. Multi-user workflows may fail."
  fi

  # Atlas bind
  local BIND_ATLAS=()
  if [[ -n "${ATLAS_FOLDER:-}" && -d "${ATLAS_FOLDER}" ]]; then
    BIND_ATLAS=( --bind "${ATLAS_FOLDER}:${ATLAS_FOLDER}" )
  else
    # Your default atlas inside the image
    if [[ -d "/opt/atlases/chass_symmetric3" ]]; then
      ATLAS_FOLDER="/opt/atlases/chass_symmetric3"
      export ATLAS_FOLDER
      BIND_ATLAS=( --bind "${ATLAS_FOLDER}:${ATLAS_FOLDER}" )
    else
      echo "Warning: ATLAS_FOLDER not set and /opt/atlases/chass_symmetric3 not present. Proceeding without explicit atlas bind."
    fi
  fi

  # Export for SAMBA Perl glue (unchanged behavior)
  export SAMBA_ATLAS_BIND="${BIND_ATLAS[*]}"
  export SAMBA_BIGGUS_BIND="${BIGGUS_DISKUS}:${BIGGUS_DISKUS}"

  # Ensure scheduler daemon if using proxy backend
  if ! _samba_ensure_daemon; then
    return 1
  fi

  # Detect container image and container command
  if ! _samba_detect_container; then
    return 1
  fi

  if [[ -z "${CONTAINER_CMD:-}" ]]; then
    if command -v singularity >/dev/null 2>&1; then
      CONTAINER_CMD="singularity"
    elif command -v apptainer >/dev/null 2>&1; then
      CONTAINER_CMD="apptainer"
    else
      echo "ERROR: Neither singularity nor apptainer found in PATH." 1>&2
      return 1
    fi
  fi
  export CONTAINER_CMD

  # Stage HF to /tmp for stable path inside container
  local hf_tmp="/tmp/${USER}_samba_$(date +%s)_$(basename "${hf}")"
  cp "${hf}" "${hf_tmp}"

  # Build bind list
  local BIND_HF_DIR=( --bind "$(dirname "${hf}")":"$(dirname "${hf}")" )

  local EXTRA_BINDS=()
  # Scratch
  EXTRA_BINDS+=( --bind "${BIGGUS_DISKUS}:${BIGGUS_DISKUS}" )

  # Scheduler IPC dir (so proxy & daemon share it)
  if [[ -n "${SAMBA_SCHED_DIR:-}" ]]; then
    EXTRA_BINDS+=( --bind "${SAMBA_SCHED_DIR}:${SAMBA_SCHED_DIR}" )
  fi

  # Final container command prefix
  local CMD_PREFIX_A=(
    "${CONTAINER_CMD}" exec
    "${BIND_HF_DIR[@]}"
    "${BIND_ATLAS[@]}"
    "${EXTRA_BINDS[@]}"
    "${SIF_PATH}"
  )

  export CONTAINER_CMD_PREFIX="${CMD_PREFIX_A[*]}"

  # Export env vars for use inside container / SAMBA
  for var in USER BIGGUS_DISKUS SIF_PATH ATLAS_FOLDER NOTIFICATION_EMAIL \
             PIPELINE_QUEUE SLURM_RESERVATION CONTAINER_CMD_PREFIX \
             SAMBA_SCHED_BACKEND SAMBA_SCHED_DIR SAMBA_APPS_DIR; do
    : "${!var:-}"  # touch for completeness; singularity exec passes env automatically
  done

  # Actually run SAMBA_startup inside the container
  eval "${CONTAINER_CMD_PREFIX}" /opt/samba/SAMBA/SAMBA_startup "${hf_tmp}"
}
