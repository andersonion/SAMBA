#!/usr/bin/env bash
#
# samba_pipe_src.sh
#
# Host-side helper for launching SAMBA inside Singularity/Apptainer:
#   source /path/to/samba_pipe_src.sh
#   samba-pipe /path/to/headfile.hf
#
# Responsibilities:
#   - Normalize headfile path
#   - Pick BIGGUS_DISKUS if unset
#   - Configure scheduler backend (proxy or native)
#   - Auto-start samba_sched_daemon for proxy backend (no root needed)
#   - Build container exec prefix + binds
#   - Export CONTAINER_CMD_PREFIX into container env for in-container dispatch
#

# -----------------------------
#  Core configuration (host)
# -----------------------------

# Singularity/Apptainer executable and image path on THIS machine
: "${CONTAINER_CMD:=singularity}"
: "${SIF_PATH:=/opt/containers/samba.sif}"

# Location of SAMBA repo on the host (used to locate daemon if not in PATH)
: "${SAMBA_APPS_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)}"

# Scheduler proxy configuration
: "${SAMBA_SCHED_BACKEND:=proxy}"          # proxy | native
: "${SAMBA_SCHED_DIR:=$HOME/.samba_sched}" # host+container shared IPC dir

export SAMBA_SCHED_BACKEND SAMBA_SCHED_DIR

# Extra binds that you ALWAYS want for this site (optional)
EXTRA_BINDS=()

# -----------------------------
#  Helpers
# -----------------------------

# Default scratch selection if BIGGUS_DISKUS is not already set
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

# Locate samba_sched_daemon on host
_samba_find_daemon() {
    local d=""

    if command -v samba_sched_daemon >/dev/null 2>&1; then
        d="$(command -v samba_sched_daemon)"
        echo "$d"
        return 0
    fi

    # Expected repo locations (per your org):
    #   SAMBA/samba_sched_wrappers/samba_sched_daemon
    #   SAMBA/samba_sched_wrappers/samba_sched_daemon.sh
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

    return 1
}

# Check if an existing daemon is alive
_samba_daemon_alive() {
    local pidfile="${SAMBA_SCHED_DIR}/daemon.pid"
    local pid=""

    [[ -f "$pidfile" ]] || return 1
    pid="$(cat "$pidfile" 2>/dev/null || true)"
    [[ -n "$pid" ]] || return 1
    kill -0 "$pid" 2>/dev/null
}

# Start daemon (user-level, no special perms)
_samba_start_daemon() {
    mkdir -p "$SAMBA_SCHED_DIR"

    if _samba_daemon_alive; then
        return 0
    fi

    local daemon
    if ! daemon="$(_samba_find_daemon)"; then
        echo "FATAL: SAMBA_SCHED_BACKEND=proxy but samba_sched_daemon not found." >&2
        echo "       Looked in PATH and in ${SAMBA_APPS_DIR}/samba_sched_wrappers/." >&2
        echo "       You should have samba_sched_daemon committed in the repo there." >&2
        return 1
    fi

    echo "[sched] starting samba_sched_daemon as user ${USER}"
    echo "[sched] daemon=${daemon}"
    echo "[sched] dir=${SAMBA_SCHED_DIR}"

    # Use nohup so daemon survives shell exit; log+pid in SAMBA_SCHED_DIR
    nohup "${daemon}" \
        --ipc-dir "${SAMBA_SCHED_DIR}" \
        > "${SAMBA_SCHED_DIR}/daemon.log" 2>&1 &

    local pid=$!
    echo "$pid" > "${SAMBA_SCHED_DIR}/daemon.pid"

    # Tiny wait to avoid race with first request
    sleep 0.05

    if ! kill -0 "$pid" 2>/dev/null; then
        echo "FATAL: samba_sched_daemon failed to start. See ${SAMBA_SCHED_DIR}/daemon.log" >&2
        return 1
    fi
}

# -----------------------------
#  Main entrypoint
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
    _samba_pick_biggus
    if [[ ! -d "$BIGGUS_DISKUS" || ! -w "$BIGGUS_DISKUS" ]]; then
        echo "ERROR: BIGGUS_DISKUS ('$BIGGUS_DISKUS') is not writable or does not exist." >&2
        return 1
    fi

    # Warn if directory is not group-writable
    if ! perl -e 'exit((stat($ARGV[0]))[2] & 0020 ? 0 : 1)' "$BIGGUS_DISKUS"; then
        echo "Warning: $BIGGUS_DISKUS is not group-writable. Multi-user workflows may fail."
    fi

    # If proxy backend, ensure daemon is running *before* container starts
    if [[ "${SAMBA_SCHED_BACKEND}" == "proxy" ]]; then
        _samba_start_daemon || return 1
    fi

    # Atlas bind (array-safe)
    local BIND_ATLAS=()
    if [[ -n "${ATLAS_FOLDER:-}" && -d "$ATLAS_FOLDER" ]]; then
        BIND_ATLAS=( --bind "$ATLAS_FOLDER:$ATLAS_FOLDER" )
    else
        echo "Warning: ATLAS_FOLDER not set or does not exist. Proceeding with default atlas."
    fi

    # Scheduler dir bind (needed for proxy)
    local BIND_SCHED=()
    if [[ "${SAMBA_SCHED_BACKEND}" == "proxy" ]]; then
        mkdir -p "$SAMBA_SCHED_DIR"
        BIND_SCHED=( --bind "$SAMBA_SCHED_DIR:$SAMBA_SCHED_DIR" )
    fi

    # Headfile directory bind
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

    # Export for Perl glue (kept from your version)
    export SAMBA_ATLAS_BIND="${BIND_ATLAS[*]}"
    export SAMBA_BIGGUS_BIND="$BIGGUS_DISKUS:$BIGGUS_DISKUS"

    # Stage HF to /tmp for stable path in container
    local hf_tmp="/tmp/${USER}_samba_$(date +%s)_$(basename "$hf")"
    cp "$hf" "$hf_tmp"

    # Build CONTAINER_CMD_PREFIX for in-container job dispatch
    local CMD_PREFIX_A=(
        "$CONTAINER_CMD" exec
        "${BIND_ALL[@]}"
        "$SIF_PATH"
    )
    export CONTAINER_CMD_PREFIX="${CMD_PREFIX_A[*]}"

    # Run inside the container with env propagation
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

# Tiny sanity helper
function samba-pipe-prefix-debug {
    samba-pipe /dev/null 2>/dev/null || true
    env | grep '^CONTAINER_CMD_PREFIX='
}
