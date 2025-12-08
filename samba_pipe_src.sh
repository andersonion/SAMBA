#!/usr/bin/env bash
#
# samba_pipe_src.sh
#  - Host-side launcher for SAMBA inside Singularity.
#  - Sets up CONTAINER_CMD_PREFIX so in-container Perl can wrap system/` calls
#    when desired.
#  - Automatically adds extra binds based on paths found in the startup headfile.
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

# BIGGUS_DISKUS should already be exported in your environment before you
# call samba-pipe (Perl side expects it). We don't set a default here on purpose.


########################################
# 1. Helper: derive extra binds from headfile
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

        [[ "$d" != /* ]] && continue

        local r
        r=$(printf '%s\n' "$d" | awk -F/ '
            NF>=6 {printf "/%s/%s/%s/%s/%s\n",$2,$3,$4,$5,$6; next}
            {print $0}
        ')

        [ -z "$r" ] && continue
        [ "$r" = "/" ] && continue        # never bind /:/
        [ -d "$r" ] || continue

        printf '%s\n' "$r"
    done <<< "$raw_paths" | sort -u | while read -r root; do
        [ -z "$root" ] && continue

        # 3) Skip any root that's already covered by an existing bind.
        local skip=0
        local pair host
        for pair in "${existing[@]}"; do
            host="${pair%%:*}"
            host="${host%/}"
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
# 2. Main entry point: samba-pipe
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

    ####################################################################
    # 2.1 Base binds (FROM ENV, NOT HARDCODED)
    #
    # You control these. Two options:
    #   1) SAMBA_BASE_BINDS:
    #        export SAMBA_BASE_BINDS="/host1:/cont1;/host2:/cont2"
    #
    #   2) SINGULARITY_BINDPATH (standard Singularity var):
    #        export SINGULARITY_BINDPATH="/host1:/cont1,/host2:/cont2"
    #
    # If SAMBA_BASE_BINDS is set, we use that.
    # Else, if SINGULARITY_BINDPATH is set, we reuse that.
    ####################################################################
    local -a base_binds=()

    if [ -n "$SAMBA_BASE_BINDS" ]; then
        # SAMBA_BASE_BINDS uses ';' as separator
        IFS=';' read -r -a base_binds <<< "$SAMBA_BASE_BINDS"
    elif [ -n "$SINGULARITY_BINDPATH" ]; then
        # SINGULARITY_BINDPATH uses ',' as separator
        IFS=',' read -r -a base_binds <<< "$SINGULARITY_BINDPATH"
    fi

    ####################################################################
    # 2.2 Build full bind list: base + headfile-derived extras
    ####################################################################
    local bind_opts=""
    local pair
    for pair in "${base_binds[@]}"; do
        [ -z "$pair" ] && continue
        bind_opts+=" --bind ${pair}"
    done

    # Headfile-driven binds (e.g. ADRC_symlink_pool roots)
    while read -r extra_bind; do
        [ -n "$extra_bind" ] || continue
        bind_opts+=" ${extra_bind}"
    done < <(_samba_dynamic_binds_from_headfile "$hf" "${base_binds[@]}")

    ####################################################################
    # 2.3 Export CONTAINER_CMD_PREFIX for Perl wrap on the HOST SIDE.
    #     Inside the container we will set SAMBA_WRAP_DISABLE=1 to avoid
    #     recursive "singularity exec" calls.
    ####################################################################
    export CONTAINER_CMD_PREFIX="singularity exec${bind_opts} ${SAMBA_SIF_PATH}"

    echo "[SAMBA_startup] SPath=${SAMBA_IN_CONTAINER_DIR}"
    echo "[SAMBA_startup] CONTAINER_CMD_PREFIX=${CONTAINER_CMD_PREFIX}"
    echo "[SAMBA_startup] PIPELINE_LAUNCH=${CONTAINER_CMD_PREFIX} ${SAMBA_IN_CONTAINER_DIR}/vbm_pipeline_start.pl"
    echo "[SAMBA_startup] ARGS: ${hf}"

    ####################################################################
    # 2.4 Launch the pipeline inside the container
    #
    # CRITICAL: SAMBA_WRAP_DISABLE=1 inside the container so that the
    # Perl overrides in SAMBA_pipeline_utilities.pm do NOT try to call
    # "singularity exec ..." again from inside the container.
    ####################################################################
    singularity exec \
        ${bind_opts} \
        --env SAMBA_WRAP_DISABLE=1 \
        "${SAMBA_SIF_PATH}" \
        "${SAMBA_IN_CONTAINER_DIR}/vbm_pipeline_start.pl" \
        "$hf"
}
