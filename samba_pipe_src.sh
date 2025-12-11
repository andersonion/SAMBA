#!/usr/bin/env bash
#
# samba_pipe_src.sh
#
# Host-side launcher for SAMBA inside Singularity.
#
# Usage:
#   source /home/apps/SAMBA/samba_pipe_src.sh
#   samba-pipe /path/to/startup.headfile
#
# Goals:
#   - Cluster-agnostic, no site-specific paths.
#   - All code (MATLAB execs, MCR, etc.) lives inside the SIF.
#   - Jobs use CONTAINER_CMD_PREFIX from env inside the container.
#

# ----------------------------------------------------------------------
# Discover a usable singularity binary without aliases
# ----------------------------------------------------------------------
if command -v singularity >/dev/null 2>&1; then
  CONTAINER_CMD="$(command -v singularity)"
else
  echo "ERROR: 'singularity' not found in PATH." >&2
  return 1
fi
export CONTAINER_CMD

# ----------------------------------------------------------------------
# Locate the container image (SIF)
#
# Precedence:
#   1. SAMBA_CONTAINER_PATH (explicit)
#   2. $SINGULARITY_IMAGE_DIR/samba.sif
#   3. $HOME/containers/samba.sif
#   4. Optional search via find(1)
# ----------------------------------------------------------------------
if [[ -n "${SAMBA_CONTAINER_PATH:-}" && -f "${SAMBA_CONTAINER_PATH}" ]]; then
  SIF_PATH="${SAMBA_CONTAINER_PATH}"
elif [[ -n "${SINGULARITY_IMAGE_DIR:-}" && -f "${SINGULARITY_IMAGE_DIR}/samba.sif" ]]; then
  SIF_PATH="${SINGULARITY_IMAGE_DIR}/samba.sif"
elif [[ -f "${HOME}/containers/samba.sif" ]]; then
  SIF_PATH="${HOME}/containers/samba.sif"
else
  echo "Trying to locate samba.sif using find... (this may take a moment)" >&2
  SEARCH_ROOT="${SAMBA_SEARCH_ROOT:-$HOME}"
  SIF_PATH="$(find "${SEARCH_ROOT}" -type f -name 'samba.sif' 2>/dev/null | head -n 1)"
  if [[ -z "${SIF_PATH}" ]]; then
    echo "ERROR: Could not locate samba.sif" >&2
    echo "Set SAMBA_CONTAINER_PATH or place it in one of:" >&2
    echo "  \$SINGULARITY_IMAGE_DIR/samba.sif" >&2
    echo "  \$HOME/containers/samba.sif" >&2
    return 1
  else
    echo "Found samba.sif at: ${SIF_PATH}" >&2
  fi
fi

export SIF_PATH

# ----------------------------------------------------------------------
# samba-pipe: main entry point
# ----------------------------------------------------------------------
function samba-pipe {
  local hf="$1"

  if [[ -z "$hf" ]]; then
    echo "Usage: samba-pipe headfile.hf" >&2
    return 1
  fi

  # Make headfile absolute if needed
  if [[ "${hf:0:1}" != "/" && "${hf:0:2}" != "~/" ]]; then
    hf="${PWD}/${hf}"
  fi
  if [[ ! -f "$hf" ]]; then
    echo "ERROR: headfile not found: $hf" >&2
    return 1
  fi

  # ------------------------------------------------------------------
  # BIGGUS_DISKUS selection & validation
  # ------------------------------------------------------------------
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

  # Optional warning for group-writability
  if ! perl -e 'exit((stat($ARGV[0]))[2] & 0020 ? 0 : 1)' "$BIGGUS_DISKUS"; then
    echo "Warning: $BIGGUS_DISKUS is not group-writable. Multi-user workflows may fail."
  fi

  # ------------------------------------------------------------------
  # ATLAS binding (from ATLAS_FOLDER env if provided)
  # ------------------------------------------------------------------
  local BIND_ATLAS=()
  if [[ -n "${ATLAS_FOLDER:-}" && -d "$ATLAS_FOLDER" ]]; then
    BIND_ATLAS=( --bind "$ATLAS_FOLDER:$ATLAS_FOLDER" )
  else
    echo "Warning: ATLAS_FOLDER not set or does not exist. Proceeding with default atlas visibility." >&2
  fi

  # ------------------------------------------------------------------
  # Extra binds: HF dir, BIGGUS_DISKUS, optional external inputs, user extras
  # ------------------------------------------------------------------
  local EXTRA=()

  # Headfile directory bind (anything next to the HF)
  local hf_dir
  hf_dir="$(dirname "$hf")"
  EXTRA+=( --bind "${hf_dir}:${hf_dir}" )

  # Scratch/work root
  EXTRA+=( --bind "${BIGGUS_DISKUS}:${BIGGUS_DISKUS}" )

  # Bind atlas (if any)
  EXTRA+=( "${BIND_ATLAS[@]}" )

  # Bind optional_external_inputs_dir if present in HF
  local ext_dir
  ext_dir="$(grep -E '^\s*optional_external_inputs_dir\s*=' "$hf" \
              | sed 's/.*=\s*//; s/[[:space:]]*$//')"
  if [[ -n "$ext_dir" && -d "$ext_dir" ]]; then
    EXTRA+=( --bind "${ext_dir}:${ext_dir}" )
  fi

  # Optional user-specified extra binds:
  #   export SAMBA_EXTRA_BINDS="--bind /foo:/foo --bind /bar:/bar"
  if [[ -n "${SAMBA_EXTRA_BINDS:-}" ]]; then
    # shellcheck disable=SC2206
    local ADDL=( ${SAMBA_EXTRA_BINDS} )
    EXTRA+=( "${ADDL[@]}" )
  fi

  # ------------------------------------------------------------------
  # Environment for *inside* the container
  #
  # We IGNORE any host SAMBA_APPS_DIR and force the in-image path.
  # Adjust this if your staged build used a different layout.
  # ------------------------------------------------------------------
  export SAMBA_APPS_DIR="/opt/samba/SAMBA"

  # Prefix used *inside* the container when submitting jobs, etc.
  local PIPELINE_CMD_PREFIX_A=(
    "${CONTAINER_CMD}"
    exec
    --bind "${BIGGUS_DISKUS}:${BIGGUS_DISKUS}"
    "${BIND_ATLAS[@]}"
    "${EXTRA[@]}"
    "${SIF_PATH}"
  )
  export CONTAINER_CMD_PREFIX="${PIPELINE_CMD_PREFIX_A[*]}"

  # ------------------------------------------------------------------
  # Stage HF to /tmp for a stable path inside the container
  # ------------------------------------------------------------------
  local hf_tmp="/tmp/${USER}_samba_$(date +%s)_$(basename "$hf")"
  cp "$hf" "$hf_tmp"

  # ------------------------------------------------------------------
  # Host-side launch of the containerized pipeline
  #   - inject CONTAINER_CMD_PREFIX
  #   - inject SAMBA_APPS_DIR
  # ------------------------------------------------------------------
  local HOST_CMD_A=(
    "${CONTAINER_CMD}" exec
    --env CONTAINER_CMD_PREFIX="${CONTAINER_CMD_PREFIX}"
    --env SAMBA_APPS_DIR="${SAMBA_APPS_DIR}"
    "${EXTRA[@]}"
    "${SIF_PATH}"
    /opt/samba/SAMBA/vbm_pipeline_start.pl
    "${hf_tmp}"
  )

  echo "samba-pipe: launching:" >&2
  printf '  %q' "${HOST_CMD_A[@]}" >&2
  echo >&2

  "${HOST_CMD_A[@]}"
}
