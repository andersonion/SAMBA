#!/usr/bin/env bash
#
# samba_pipe_src.sh
#
# Host-side launcher for SAMBA inside Singularity.
# - Builds a singularity command with:
#     * data binds inferred from the startup headfile
#     * Slurm-related binds for sbatch/squeue/etc.
#     * environment forwarding for BIGGUS_DISKUS (if set or in headfile)
#     * SAMBA_WRAP_DISABLE=1 so in-container Perl does NOT double-wrap
# - Exports CONTAINER_CMD_PREFIX for in-pipeline use.
#
# Usage:
#   source /home/apps/SAMBA/samba_pipe_src.sh
#   samba-pipe /path/to/startup.headfile
#

########################################
# 0. Basic defaults / env
########################################

# Directory where samba.sif lives (can override before sourcing)
: "${SINGULARITY_IMAGE_DIR:=/home/apps//ubuntu-22.04/singularity/images}"
: "${SAMBA_SIF_NAME:=samba.sif}"

SAMBA_SIF_PATH="${SINGULARITY_IMAGE_DIR}/${SAMBA_SIF_NAME}"

# Where SAMBA lives *inside* the container
SAMBA_IN_CONTAINER_DIR="/opt/samba/SAMBA"

########################################
# 1. Helper: derive extra data binds from headfile
########################################
# _samba_dynamic_binds_from_headfile HEADFILE BASE_BIND1 BASE_BIND2 ...
#
#   HEADFILE:  path to startup .headfile
#   BASE_BIND: entries of the form "/host/path:/container/path"
#
# Emits zero or more lines:
#   --bind /host/root:/host/root
#
# Only binds directories that:
#   - appear as absolute paths in the headfile
#   - exist on the host
#   - are NOT already covered by one of the base binds
#
_samba_dynamic_binds_from_headfile() {
    local hf="$1"; shift
    local -a existing=("$@")

    # If we can't read the headfile, bail quietly.
    [ -r "$hf" ] || return 0

    # 1) Grab all absolute path-looking tokens from the headfile.
    local raw_paths
    raw_paths=$(grep -Eo '/[A-Za-z0-9._/\-]+' "$hf" 2>/dev/null | sort -u) || return 0

    # 2) For each path, reduce to a "root" directory (up to depth 6),
    #    and only keep roots that actually exist on the host.
    while read -r p; do
        [ -z "$p" ] && continue

        local d
        d=$(dirname "$p")

        # Only care about absolute paths
        [[ "$d" != /* ]] && continue

        # Collapse to a reasonably high-level root:
        #   /<2>/<3>/<4>/<5>/<6>
        # If fewer than 6 components, keep it as-is.
        local r
        r=$(printf '%s\n' "$d" | awk -F/ '
            NF>=6 {printf "/%s/%s/%s/%s/%s\n",$2,$3,$4,$5,$6; next}
            {print $0}
        ')

        [ -z "$r" ] && continue
        [ -d "$r" ] || continue  # only bind things that exist on the host

        printf '%s\n' "$r"
    done <<< "$raw_paths" | sort -u | while read -r root; do
        [ -z "$root" ] && continue

        # 3) Skip any root that's already covered by an existing bind.
        local skip=0
        local pair host
        for pair in "${existing[@]}"; do
            host="${pair%%:*}"
            # If root is under an already bound host path, skip it
            if [[ "$root" == "$host"* ]]; then
                skip=1
                break
            fi
        done
        [ "$skip" -eq 1 ] && continue

        # 4) Emit a --bind directive mapping host → same path inside container.
        printf -- '--bind %s:%s\n' "$root" "$root"
    done
}

########################################
# 2. Helper: ensure BIGGUS_DISKUS is set (env or headfile)
########################################
# _samba_ensure_env_BIGGUS_DISKUS_FROM_HF HEADFILE
#
# Behavior:
#   - If BIGGUS_DISKUS is already set in the env, leave it alone.
#   - Otherwise, look in the headfile for a line like:
#         BIGGUS_DISKUS = /some/path
#     and export BIGGUS_DISKUS=/some/path if found.
#   - If nothing found, we do NOT invent a default.
#
_samba_ensure_env_BIGGUS_DISKUS_FROM_HF() {
    local hf="$1"

    # If already set in the environment, trust that.
    if [[ -n "${BIGGUS_DISKUS:-}" ]]; then
        return 0
    fi

    [[ -r "$hf" ]] || return 0

    local line val
    line=$(grep -E '^[[:space:]]*BIGGUS_DISKUS[[:space:]]*=' "$hf" 2>/dev/null | head -n1) || true
    [[ -z "$line" ]] && return 0

    # Strip "key =" part
    val="${line#*=}"

    # Strip inline comments (after #)
    val="${val%%#*}"

    # Trim leading/trailing whitespace
    val="$(printf '%s' "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    # Strip optional quotes
    val="${val%\"}"; val="${val#\"}"
    val="${val%\'}"; val="${val#\'}"

    if [[ -n "$val" ]]; then
        export BIGGUS_DISKUS="$val"
    fi
}

########################################
# 3. Main entry point: samba-pipe
########################################
# Usage:
#   samba-pipe /path/to/startup.headfile
########################################
samba-pipe() {
    local hf="$1"

    if [[ -z "$hf" ]]; then
        echo "Usage: samba-pipe /path/to/startup.headfile" >&2
        return 1
    fi
    if [[ ! -r "$hf" ]]; then
        echo "ERROR: cannot read headfile: $hf" >&2
        return 1
    fi

    if [[ ! -f "$SAMBA_SIF_PATH" ]]; then
        echo "ERROR: Singularity image not found at: $SAMBA_SIF_PATH" >&2
        return 1
    fi

    ################################################################
    # 3.1 Base binds: Slurm + tools ONLY (no data paths hardcoded)
    ################################################################
    local -a base_binds=(
        "/etc/slurm:/etc/slurm"
        "/usr/local/lib/slurm:/usr/local/lib/slurm"
        "/usr/local/bin:/usr/local/bin"
    )

    ################################################################
    # 3.2 Build bind options: base + headfile-derived data roots
    ################################################################
    local bind_opts=""
    local pair
    for pair in "${base_binds[@]}"; do
        bind_opts+=" --bind ${pair}"
    done

    # Headfile-driven binds for data (e.g. /mnt/newStor/.../mouse, /human, etc.)
    while read -r extra_bind; do
        [[ -n "$extra_bind" ]] || continue
        bind_opts+=" ${extra_bind}"
    done < <(_samba_dynamic_binds_from_headfile "$hf" "${base_binds[@]}")

    ################################################################
    # 3.3 Ensure BIGGUS_DISKUS is in the environment
    #     (env wins; otherwise try to discover in headfile)
    ################################################################
    _samba_ensure_env_BIGGUS_DISKUS_FROM_HF "$hf"

    ################################################################
    # 3.4 Environment options:
    #     - Pass BIGGUS_DISKUS into container if we have it
    #     - Disable in-container re-wrapping (SAMBA_WRAP_DISABLE=1)
    ################################################################
    local env_opts=""
    if [[ -n "${BIGGUS_DISKUS:-}" ]]; then
        env_opts+=" --env BIGGUS_DISKUS=${BIGGUS_DISKUS}"
    fi
    # We are already inside the container, so do NOT re-wrap things
    env_opts+=" --env SAMBA_WRAP_DISABLE=1"

    ################################################################
    # 3.5 Export CONTAINER_CMD_PREFIX for in-pipeline use
    ################################################################
    export CONTAINER_CMD_PREFIX="singularity exec${env_opts}${bind_opts} ${SAMBA_SIF_PATH}"

    echo "[SAMBA_startup] SPath=${SAMBA_IN_CONTAINER_DIR}"
    echo "[SAMBA_startup] CONTAINER_CMD_PREFIX=${CONTAINER_CMD_PREFIX}"
    echo "[SAMBA_startup] PIPELINE_LAUNCH=${CONTAINER_CMD_PREFIX} ${SAMBA_IN_CONTAINER_DIR}/vbm_pipeline_start.pl"
    echo "[SAMBA_startup] ARGS: ${hf}"

    ################################################################
    # 3.6 Actually launch the pipeline start script inside container
    ################################################################
    singularity exec ${env_opts} ${bind_opts} "${SAMBA_SIF_PATH}" \
        "${SAMBA_IN_CONTAINER_DIR}/vbm_pipeline_start.pl" "$hf"
}
