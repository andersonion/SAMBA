#!/usr/bin/env bash
#
# samba_pipe_src.sh
#
# Host-side launcher for SAMBA inside Singularity.
#  - Sets up CONTAINER_CMD_PREFIX so Perl inside the container can wrap
#    system/`/open.
#  - Dynamically adds extra --binds for any host paths referenced in the
#    startup headfile that are *not* already covered by existing binds.
#

########################################
# 0. Basic defaults / env
########################################

# Where the Singularity image lives (override if needed before sourcing)
: "${SINGULARITY_IMAGE_DIR:=/home/apps//ubuntu-22.04/singularity/images}"
: "${SAMBA_SIF_NAME:=samba.sif}"

SAMBA_SIF_PATH="${SINGULARITY_IMAGE_DIR}/${SAMBA_SIF_NAME}"

# Where SAMBA lives *inside* the container
SAMBA_IN_CONTAINER_DIR="/opt/samba/SAMBA"

# BIGGUS_DISKUS is used by Perl as the root for project paths.
# We *expect* you to export this in your environment before calling samba-pipe.
# Example:
#   export BIGGUS_DISKUS=/mnt/newStor/paros/paros_WORK/mouse
# We deliberately do not set a default here.


########################################
# 1. Helper: parse SAMBA_BASE_BINDS → array
########################################
# SAMBA_BASE_BINDS is optional. If set, it should look like:
#   SAMBA_BASE_BINDS="/host1:/ctr1;/host2:/ctr2;..."
#
# If SAMBA_BASE_BINDS is *not* set, we fall back to:
#   BIGGUS_DISKUS -> BIGGUS_DISKUS   (and with trailing slash variant)
#
_samba_collect_base_binds() {
    local -n _out_arr="$1"
    _out_arr=()

    # 1) User-configurable base binds (highest priority)
    if [ -n "${SAMBA_BASE_BINDS:-}" ]; then
        # Split on ';'
        IFS=';' read -r -a _tmp <<< "${SAMBA_BASE_BINDS}"
        for pair in "${_tmp[@]}"; do
            # skip empties
            [ -z "$pair" ] && continue
            _out_arr+=("$pair")
        done
    fi

    # 2) If nothing provided, fall back to BIGGUS_DISKUS if available
    if [ ${#_out_arr[@]} -eq 0 ] && [ -n "${BIGGUS_DISKUS:-}" ]; then
        local root="$BIGGUS_DISKUS"
        # Strip trailing slash for consistency
        root="${root%/}"
        _out_arr+=("${root}:${root}")
        _out_arr+=("${root}/:${root}/")
    fi

    # 3) Generic cluster-ish binds that are safe everywhere
    _out_arr+=("/etc/slurm:/etc/slurm")
    _out_arr+=("/usr/local/lib/slurm:/usr/local/lib/slurm")
    _out_arr+=("/usr/local/bin:/usr/local/bin")
}


########################################
# 2. Helper: derive extra binds from headfile
########################################
# _samba_dynamic_binds_from_headfile HEADFILE base_bind_array...
#
#   HEADFILE: path to startup .headfile (host path)
#   base_bind_array: entries of the form "/host/path:/container/path"
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

    # Grab all absolute path-looking tokens from the headfile.
    local raw_paths
    raw_paths=$(grep -Eo '/[A-Za-z0-9._/\-]+' "$hf" 2>/dev/null | sort -u) || return 0

    # For each path, reduce to a "root" directory (moderately high-level)
    while read -r p; do
        [ -z "$p" ] && continue

        local d
        d=$(dirname "$p")

        [[ "$d" != /* ]] && continue

        # Collapse to something like: /a/b/c/d/e
        # If fewer components, leave as-is.
        local r
        r=$(printf '%s\n' "$d" | awk -F/ '
            NF>=6 {printf "/%s/%s/%s/%s/%s\n",$2,$3,$4,$5,$6; next}
            {print $0}
        ')
        [ -z "$r" ] && continue
        [ -d "$r" ] || continue  # only bind real directories

        printf '%s\n' "$r"
    done <<< "$raw_paths" | sort -u | while read -r root; do
        [ -z "$root" ] && continue

        # Skip if root is already covered by an existing host bind path
        local skip=0
        local pair host
        for pair in "${existing[@]}"; do
            host="${pair%%:*}"
            # host might not have trailing slash; normalize both mildly
            host="${host%/}"
            if [[ "$root" == "$host"* ]]; then
                skip=1
                break
            fi
        done
        [ "$skip" -eq 1 ] && continue

        # Emit a bind mapping host-root -> same path inside container
        printf -- '--bind %s:%s\n' "$root" "$root"
    done
}


########################################
# 3. Main entry point: samba-pipe
########################################
# Usage:
#   source /home/apps/SAMBA/samba_pipe_src.sh
#   samba-pipe /path/to/startup.headfile
########################################
samba-pipe() {
    local hf="$1"

    if [ -z "$hf" ]; then
        echo "Usage: samba-pipe /path/to/startup.headfile" >&2
        return 1
    fi
    if [ ! -r "$hf" ]; then
        echo "ERROR: cannot read headfile: $hf" >&2
        return 1
    fi

    if [ ! -f "$SAMBA_SIF_PATH" ]; then
        echo "ERROR: Singularity image not found at: $SAMBA_SIF_PATH" >&2
        return 1
    fi

    ########################################
    # 3.1 Collect base binds (env-driven)
    ########################################
    local -a base_binds
    _samba_collect_base_binds base_binds

    ########################################
    # 3.2 Build full bind list: base + headfile-derived extras
    ########################################
    local bind_opts=""
    local pair

    for pair in "${base_binds[@]}"; do
        bind_opts+=" --bind ${pair}"
    done

    # Headfile-driven binds (extra roots referenced in hf)
    while read -r extra_bind; do
        [ -n "$extra_bind" ] || continue
        bind_opts+=" ${extra_bind}"
    done < <(_samba_dynamic_binds_from_headfile "$hf" "${base_binds[@]}")

    ########################################
    # 3.3 Export CONTAINER_CMD_PREFIX for Perl
    ########################################
    export CONTAINER_CMD_PREFIX="singularity exec${bind_opts} ${SAMBA_SIF_PATH}"

    echo "[SAMBA_startup] SPath=${SAMBA_IN_CONTAINER_DIR}"
    echo "[SAMBA_startup] CONTAINER_CMD_PREFIX=${CONTAINER_CMD_PREFIX}"
    echo "[SAMBA_startup] PIPELINE_LAUNCH=${CONTAINER_CMD_PREFIX} ${SAMBA_IN_CONTAINER_DIR}/vbm_pipeline_start.pl"
    echo "[SAMBA_startup] ARGS: ${hf}"

    ########################################
    # 3.4 Actually launch the pipeline
    ########################################
    singularity exec ${bind_opts} "${SAMBA_SIF_PATH}" "${SAMBA_IN_CONTAINER_DIR}/vbm_pipeline_start.pl" "$hf"
}
