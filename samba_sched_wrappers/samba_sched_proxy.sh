#!/usr/bin/env bash
#
# samba_sched_proxy
#
# Run on the container side. It sends a request to the host daemon for
# one of: sbatch, squeue, sacct, scontrol, scancel
#
# Usage (inside container):
#   samba_sched_proxy sbatch  [args...]
#   samba_sched_proxy squeue  [args...]
#   samba_sched_proxy sacct   [args...]
#   samba_sched_proxy scontrol [args...]
#   samba_sched_proxy scancel [args...]
#
# Environment (inside container):
#   SAMBA_SCHED_DIR : IPC directory (must be the *same path* the daemon sees)
#                     Usually passed in via samba-pipe env-file.
#                     If unset, falls back to "$BIGGUS_DISKUS/samba_sched_ipc" or /tmp/samba_sched_ipc
#

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: samba_sched_proxy <sbatch|squeue|sacct|scontrol|scancel> [args...]" >&2
    exit 1
fi

cmd="$1"
shift || true

case "$cmd" in
    sbatch|squeue|sacct|scontrol|scancel)
        ;;
    *)
        echo "ERROR: unsupported command '$cmd' for samba_sched_proxy" >&2
        exit 1
        ;;
esac

# --- IPC directory (must match daemon) ---
if [[ -n "${SAMBA_SCHED_DIR:-}" ]]; then
    SCHED_DIR="$SAMBA_SCHED_DIR"
elif [[ -n "${BIGGUS_DISKUS:-}" ]]; then
    SCHED_DIR="${BIGGUS_DISKUS%/}/samba_sched_ipc"
else
    SCHED_DIR="/tmp/samba_sched_ipc"
fi

mkdir -p "$SCHED_DIR"

# --- Unique request id ---
req_id="$(date +%s%N)_$$"
req="${SCHED_DIR}/${req_id}.req"
out="${SCHED_DIR}/${req_id}.out"
err="${SCHED_DIR}/${req_id}.err"
st="${SCHED_DIR}/${req_id}.status"

# --- Build quoted args string (safe shell quoting) ---
args_q=""
if [[ "$#" -gt 0 ]]; then
    for a in "$@"; do
        args_q+=" $(printf '%q' "$a")"
    done
fi

# --- Write request file ---
cat >"$req" <<EOF
CMD=$cmd
CWD=$(printf '%q' "$PWD")
ARGS_Q=$args_q
EOF

# --- Wait for daemon to create .status file ---
while [[ ! -f "$st" ]]; do
    sleep 0.01
done

rc=1
if [[ -f "$st" ]]; then
    rc="$(cat "$st" 2>/dev/null || echo 1)"
fi

# --- Relay stdout/stderr back to caller ---
if [[ -f "$out" ]]; then
    cat "$out"
fi

if [[ -f "$err" ]]; then
    cat "$err" >&2
fi

# --- Best-effort cleanup ---
rm -f "$req" "$out" "$err" "$st" 2>/dev/null || true

exit "$rc"
