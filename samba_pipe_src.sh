#!/usr/bin/env bash
#
# samba_pipe_src.sh
#
# Host-side helper for launching SAMBA inside Singularity/Apptainer.
# Also auto-manages scheduler proxy daemon when SAMBA_SCHED_BACKEND=proxy.
#
# Usage:
#   source /path/to/samba_pipe_src.sh
#   samba-pipe /path/to/headfile
#

set -euo pipefail

# -----------------------------
#  Core configuration (host)
# -----------------------------

# Location of singularity/apptainer and samba.sif on THIS machine.
: "${CONTAINER_CMD:=singularity}"
: "${SIF_PATH:=/opt/containers/samba.sif}"

# Where THIS SAMBA repo lives on the host (for finding daemon, etc.)
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

# -----------------------------
#  Scheduler proxy configuration
# -----------------------------

# Default to proxy unless user overrides before sourcing.
: "${SAMBA_SCHED_BACKEND:=proxy}"
: "${SAMBA_SCHED_DIR:=$HOME/.samba_sched}"

# If user wants proxy to be mandatory, set SAMBA_SCHED_REQUIRE_PROXY=1
: "${SAMBA_SCHED_REQUIRE_PROXY:=0}"

export SAMBA_SCHED_BACKEND SAMBA_SCHED_DIR SAMBA_SCHED_REQUIRE_PROXY

# Ensure dir exists and is writable.
mkdir -p "$SAMBA_SCHED_DIR"
if [[ ! -d "$SAMBA_SCHED_DIR" || ! -w "$SAMBA_SCHED_DIR" ]]; then
    echo "FATAL: SAMBA_SCHED_DIR not writable: $SAMBA_SCHED_DIR" >&2
    return 1
fi

# Find daemon executable.
_samba_find_sched_daemon() {
    local d=""

    # 1) explicit override
    if [[ -n "${SAMBA_SCHED_DAEMON:-}" && -x "${SAMBA_SCHED_DAEMON}" ]]; then
        d="${SAMBA_SCHED_DAEMON}"
        echo "$d"
        return 0
    fi

    # 2) in PATH
    if command -v samba_sched_daemon >/dev/null 2>&1; then
        d="$(command -v samba_sched_daemon)"
        [[ -x "$d" ]] && { echo "$d"; return 0; }
    fi

    # 3) in repo (common locations)
    for cand in \
        "${SAMBA_APPS_DIR}/samba_sched_wrappers/samba_sched_daemon" \
        "${SAMBA_APPS_DIR}/samba_sched_daemon" \
        "${SAMBA_APPS_DIR}/bin/samba_sched_daemon" \
        "${SAMBA_APPS_DIR}/samba_sched_wrappers/samba_sched_daemon.sh"
    do
        if [[ -x "$cand" ]]; then
            echo "$cand"
            return 0
        fi
    done

    return 1
}

# Start daemon if needed (per-user, no sudo).
_samba_start_sched_daemon_if_needed() {
    [[ "${SAMBA_SCHED_BACKEND}" == "proxy" ]] || return 0

    local pidfile="${SAMBA_SCHED_DIR}/daemon.pid"
    local logfile="${SAMBA_SCHED_DIR}/daemon.log"

    # If pidfile exists and process alive, we’re good.
    if [[ -f "$pidfile" ]]; then
        local pid
        pid="$(cat "$pidfile" 2>/dev/null || true)"
        if [[ -n "$pid" ]] && ps -p "$pid" >/dev/null 2>&1; then
            return 0
        fi
        rm -f "$pidfile"
    fi

    local daemon
    if ! daemon="$(_samba_find_sched_daemon)"; then
        if [[ "$SAMBA_SCHED_REQUIRE_PROXY" -eq 1 ]]; then
            echo "FATAL: SAMBA_SCHED_BACKEND=proxy but samba_sched_daemon not found." >&2
            echo "       Looked in PATH and in ${SAMBA_APPS_DIR}/samba_sched_wrappers/." >&2
            return 1
        fi

        # Soft-fallback to native if possible.
        if command -v sbatch >/dev/null 2>&1; then
            echo "[sched] WARNING: proxy requested but daemon not found; falling back to native backend." >&2
            export SAMBA_SCHED_BACKEND="native"
            return 0
        else
            echo "FATAL: proxy daemon missing AND no native sbatch found on host." >&2
            return 1
        fi
    fi

    echo "[sched] starting samba_sched_daemon as user ${USER}"
    echo "[sched] daemon=${daemon}"
    echo "[sched] dir=${SAMBA_SCHED_DIR}"

    # Start in background, record pid.
    nohup "${daemon}" \
        --ipc-dir "${SAMBA_SCHED_DIR}" \
        >"${logfile}" 2>&1 &

    echo $! > "${pidfile}"
    disown || true

    # Tiny wait to let it initialize.
    sleep 0.1
    return 0
}

# -----------------------------
# Extra binds always used here
# -----------------------------
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

    # Normalize headfile path
    if [[ "${hf:0:1}" != "/" && "${hf:0:2}" != "~/" ]]; then
        hf="${PWD}/${hf}"
    fi
    if [[ ! -f "$hf" ]]; then
        echo "ERROR: headfile not found: $hf" >&2
        return 1
    fi

    # Ensure BIGGUS_DISKUS
    _samba_pick_biggus
    if [[ ! -d "$BIGGUS_DISKUS" || ! -w "$BIGGUS_DISKUS" ]]; then
        echo "ERROR: BIGGUS_DISKUS ('$BIGGUS_DISKUS') is not writable or does not exist." >&2
        return 1
    fi

    # Warn if not group-writable
    if ! perl -e 'exit((stat($ARGV[0]))[2] & 0020 ? 0 : 1)' "$BIGGUS_DISKUS"; then
        echo "Warning: $BIGGUS_DISKUS is not group-writable. Multi-user workflows may fail."
    fi

    # Start proxy daemon if needed
    _samba_start_sched_daemon_if_needed

    # Atlas bind (host atlas folder)
    local BIND_ATLAS=()
    if [[ -n "${ATLAS_FOLDER:-}" && -d "$ATLAS_FOLDER" ]]; then
        BIND_ATLAS=( --bind "$ATLAS_FOLDER:$ATLAS_FOLDER" )
    fi

    # Scheduler dir bind (proxy backend)
    local BIND_SCHED=()
    if [[ "$SAMBA_SCHED_BACKEND" == "proxy" && -d "$SAMBA_SCHED_DIR" ]]; then
        BIND_SCHED=( --bind "$SAMBA_SCHED_DIR:$SAMBA_SCHED_DIR" )
    fi

    # Headfile dir bind
    local HF_DIR
    HF_DIR="$(dirname "$hf")"
    local BIND_HF_DIR=( --bind "$HF_DIR:$HF_DIR" )

    # BIGGUS_DISKUS bind
    local BIND_BIGGUS=( --bind "$BIGGUS_DISKUS:$BIGGUS_DISKUS" )

    # Aggregate binds
    local BIND_ALL=(
        "${BIND_BIGGUS[@]}"
        "${BIND_HF_DIR[@]}"
        "${BIND_ATLAS[@]}"
        "${BIND_SCHED[@]}"
        "${EXTRA_BINDS[@]}"
    )

    # Stage HF to /tmp
    local hf_tmp="/tmp/${USER}_samba_$(date +%s)_$(basename "$hf")"
    cp "$hf" "$hf_tmp"

    # Build command prefix for use INSIDE container
    local CMD_PREFIX_A=(
        "$CONTAINER_CMD" exec
        "${BIND_ALL[@]}"
        "$SIF_PATH"
    )
    export CONTAINER_CMD_PREFIX="${CMD_PREFIX_A[*]}"

    # Run startup in container with env propagation
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

# Tiny helper for debugging prefix/binds quickly
function samba-pipe-prefix-debug {
    samba-pipe /dev/null 2>/dev/null || true
    env | grep '^CONTAINER_CMD_PREFIX='
}
