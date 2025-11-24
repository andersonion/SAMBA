#!/usr/bin/env bash
#
# samba_sched_daemon.sh
#
# Host-side daemon that proxies Slurm commands for SAMBA containers.
# It watches a directory for *.req files, executes the real Slurm command,
# and writes back .out / .err / .status files.
#
# Supported commands: sbatch, squeue, sacct, scontrol, scancel
#
# Environment (host side):
#   SAMBA_SCHED_DIR   : directory for request/response files
#                       (default: "$BIGGUS_DISKUS/samba_sched_ipc" or /tmp/samba_sched_ipc)
#   POLL_INTERVAL     : sleep between scans (seconds, default 0.01)
#   REAL_SBATCH       : override path to sbatch     (default: command -v sbatch)
#   REAL_SQUEUE       : override path to squeue     (default: command -v squeue)
#   REAL_SACCT        : override path to sacct      (default: command -v sacct)
#   REAL_SCONTROL     : override path to scontrol   (default: command -v scontrol)
#   REAL_SCANCEL      : override path to scancel    (default: command -v scancel)
#

set -euo pipefail

# --- Config: IPC dir ---
if [[ -n "${SAMBA_SCHED_DIR:-}" ]]; then
    SCHED_DIR="$SAMBA_SCHED_DIR"
elif [[ -n "${BIGGUS_DISKUS:-}" ]]; then
    SCHED_DIR="${BIGGUS_DISKUS%/}/samba_sched_ipc"
else
    SCHED_DIR="/tmp/samba_sched_ipc"
fi

POLL_INTERVAL="${POLL_INTERVAL:-0.01}"

mkdir -p "$SCHED_DIR"
chmod 0770 "$SCHED_DIR" 2>/dev/null || true

echo "[daemon] Using IPC dir: $SCHED_DIR"

# --- Resolve real Slurm commands on the host ---
REAL_SBATCH="${REAL_SBATCH:-$(command -v sbatch  || true)}"
REAL_SQUEUE="${REAL_SQUEUE:-$(command -v squeue  || true)}"
REAL_SACCT="${REAL_SACCT:-$(command -v sacct   || true)}"
REAL_SCONTROL="${REAL_SCONTROL:-$(command -v scontrol || true)}"
REAL_SCANCEL="${REAL_SCANCEL:-$(command -v scancel  || true)}"

if [[ -z "$REAL_SBATCH$REAL_SQUEUE$REAL_SACCT$REAL_SCONTROL$REAL_SCANCEL" ]]; then
    echo "[daemon] ERROR: No Slurm commands (sbatch/squeue/sacct/scontrol/scancel) found in PATH." >&2
    exit 1
fi

echo "[daemon] Slurm commands:"
echo "  sbatch   = ${REAL_SBATCH:-<missing>}"
echo "  squeue   = ${REAL_SQUEUE:-<missing>}"
echo "  sacct    = ${REAL_SACCT:-<missing>}"
echo "  scontrol = ${REAL_SCONTROL:-<missing>}"
echo "  scancel  = ${REAL_SCANCEL:-<missing>}"
echo "[daemon] Waiting for requests..."

# --- Main loop ---
while true; do
    shopt -s nullglob
    for req in "$SCHED_DIR"/*.req; do
        base="${req%.req}"
        out="${base}.out"
        err="${base}.err"
        st="${base}.status"

        CMD=""
        CWD=""
        ARGS_Q=""

        # Load request (simple K=V pairs: CMD, CWD, ARGS_Q)
        # shellcheck disable=SC1090
        . "$req" || true
        rm -f "$req"

        if [[ -z "$CMD" ]]; then
            echo "[daemon] WARNING: request $req missing CMD" >&2
            echo "missing CMD" >"${err}.tmp"
            echo 1 >"${st}.tmp"
            mv "${err}.tmp" "$err" 2>/dev/null || true
            mv "${st}.tmp" "$st" 2>/dev/null || true
            continue
        fi

        case "$CMD" in
            sbatch)   real_cmd="$REAL_SBATCH"   ;;
            squeue)   real_cmd="$REAL_SQUEUE"   ;;
            sacct)    real_cmd="$REAL_SACCT"    ;;
            scontrol) real_cmd="$REAL_SCONTROL" ;;
            scancel)  real_cmd="$REAL_SCANCEL"  ;;
            *)
                real_cmd=""
                ;;
        esac

        if [[ -z "$real_cmd" ]]; then
            echo "[daemon] WARNING: command '$CMD' requested, but REAL_$CMD not set/found." >&2
            echo "command $CMD not available on host" >"${err}.tmp"
            echo 127 >"${st}.tmp"
            mv "${err}.tmp" "$err" 2>/dev/null || true
            mv "${st}.tmp" "$st" 2>/dev/null || true
            continue
        fi

        (
            # Run in requested CWD if valid, else /
            if [[ -n "$CWD" && -d "$CWD" ]]; then
                cd "$CWD"
            else
                cd /
            fi

            # Reconstruct argv from ARGS_Q (a list of %q-quoted args)
            if [[ -n "$ARGS_Q" ]]; then
                eval "set -- $ARGS_Q"
            else
                set --
            fi

            "$real_cmd" "$@" >"${out}.tmp" 2>"${err}.tmp"
        )
        rc=$?

        echo "$rc" >"${st}.tmp"

        mv "${out}.tmp" "$out" 2>/dev/null || true
        mv "${err}.tmp" "$err" 2>/dev/null || true
        mv "${st}.tmp" "$st" 2>/dev/null || true
    done
    shopt -u nullglob
    sleep "$POLL_INTERVAL"
done
