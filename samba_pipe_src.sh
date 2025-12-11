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

# ----------------------------------------------------------------------
# 0. Container binary (host-side)
# ----------------------------------------------------------------------

CONTAINER_CMD="${CONTAINER_CMD:-singularity}"
export CONTAINER_CMD

# ----------------------------------------------------------------------
# 1. Helper: trim leading/trailing whitespace
# ----------------------------------------------------------------------
_trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"  # leading
  s="${s%"${s##*[![:space:]]}"}"  # trailing
  printf '%s' "$s"
}

# ----------------------------------------------------------------------
# 2. Helper: locate SIF_PATH in a cluster-agnostic way
#
# Priority:
#   1. SAMBA_CONTAINER_PATH (explicit)
#   2. SIF_PATH (if already exported and exists)
#   3. $SINGULARITY_IMAGE_DIR/samba.sif
#   4. $HOME/containers/samba.sif
#   5. search in $SAMBA_SEARCH_ROOT or $HOME
# ----------------------------------------------------------------------
_locate_sif() {
  if [[ -n "${SAMBA_CONTAINER_PATH:-}" ]]; then
    echo "$SAMBA_CONTAINER_PATH"
    return 0
  fi

  if [[ -n "${SIF_PATH:-}" && -f "${SIF_PATH}" ]]; then
    echo "$SIF_PATH"
    return 0
  fi

  if [[ -n "${SINGULARITY_IMAGE_DIR:-}" && -f "${SINGULARITY_IMAGE_DIR}/samba.sif" ]]; then
    echo "${SINGULARITY_IMAGE_DIR}/samba.sif"
    return 0
  fi

  if [[ -f "${HOME}/containers/samba.sif" ]]; then
    echo "${HOME}/containers/samba.sif"
    return 0
  fi

  local root="${SAMBA_SEARCH_ROOT:-$HOME}"
  echo "Trying to locate samba.sif using find under ${root}... (this may take a moment)" >&2
  local found
  found=$(find "$root" -type f -name "samba.sif" 2>/dev/null | head -n 1 || true)
  if [[ -n "$found" ]]; then
    echo "Found samba.sif at: $found" >&2
    echo "$found"
    return 0
  fi

  echo "ERROR: Could not locate samba.sif" >&2
  echo "Set SAMBA_CONTAINER_PATH or place it in one of:" >&2
  echo "  \$SINGULARITY_IMAGE_DIR/samba.sif" >&2
  echo "  \$HOME/containers/samba.sif" >&2
  return 1
}

# ----------------------------------------------------------------------
# 3. Helper: parse headfile and derive bind dirs
#
# - scan "key = value" lines
# - ignore comments / blank lines
# - any absolute value (/...) → if dir: bind dir, if file: bind parent dir
# - de-duplicate
# ----------------------------------------------------------------------
_headfile_auto_binds() {
  local hf="$1"
  local -a dirs=()

  [[ -f "$hf" ]] || return 0

  while IFS='=' read -r key rawval; do
    rawval=${rawval%%#*}
    key=$(_trim "$key")
    local val=$(_trim "$rawval")

    [[ -z "$val" ]] && continue
    [[ "$val" != /* ]] && continue

    local path="$val"
    [[ "$path" != "/" ]] && path="${path%/}"

    local bind_dir=""
    if [[ -d "$path" ]]; then
      bind_dir="$path"
    else
      bind_dir="${path%/*}"
      [[ -z "$bind_dir" ]] && continue
      [[ -d "$bind_dir" ]] || continue
    fi
    dirs+=( "$bind_dir" )
  done < "$hf"

  declare -A seen=()
  local -a unique=()
  local d
  for d in "${dirs[@]}"; do
    [[ -n "${seen[$d]:-}" ]] && continue
    seen["$d"]=1
    unique+=( "$d" )
  done

  local -a out=()
  for d in "${unique[@]}"; do
    out+=( --bind "$d:$d" )
  done

  echo "${out[@]}"
}

# ----------------------------------------------------------------------
# 4. Main entry point: samba-pipe
# ----------------------------------------------------------------------
samba-pipe() {
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

  # Auto-select BIGGUS_DISKUS if not set
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

  # Validate BIGGUS_DISKUS
  if [[ ! -d "$BIGGUS_DISKUS" || ! -w "$BIGGUS_DISKUS" ]]; then
    echo "ERROR: BIGGUS_DISKUS ('$BIGGUS_DISKUS') is not writable or does not exist." >&2
    return 1
  fi

  # Optional warning about group writability
  if ! perl -e 'exit((stat($ARGV[0]))[2] & 0020 ? 0 : 1)' "$BIGGUS_DISKUS"; then
    echo "Warning: $BIGGUS_DISKUS is not group-writable. Multi-user workflows may fail."
  fi

  # ---------------- ATLAS FOLDER BIND (RESTORED) ----------------
  # If you export ATLAS_FOLDER=/mnt/newStor/paros//paros_WORK/atlas,
  # we will bind that 1:1 into the container.
  local BIND_ATLAS=()
  if [[ -n "${ATLAS_FOLDER:-}" && -d "$ATLAS_FOLDER" ]]; then
    BIND_ATLAS=( --bind "$ATLAS_FOLDER:$ATLAS_FOLDER" )
  else
    echo "Warning: ATLAS_FOLDER not set or does not exist. Proceeding without explicit atlas bind." >&2
  fi
  export SAMBA_ATLAS_BIND="${BIND_ATLAS[*]}"

  # Locate the container image
  local sif
  sif=$(_locate_sif) || return 1
  export SIF_PATH="$sif"

  # Stage HF to /tmp for stable path
  local hf_tmp="/tmp/${USER}_samba_$(date +%s)_$(basename "$hf")"
  cp "$hf" "$hf_tmp"

  # Bind original headfile directory
  local hf_dir
  hf_dir="$(dirname "$hf")"
  local BIND_HF_DIR=( --bind "$hf_dir:$hf_dir" )

  # Headfile-driven auto-binds
  local HF_AUTO_BINDS_STR
  HF_AUTO_BINDS_STR="$(_headfile_auto_binds "$hf")"
  # shellcheck disable=SC2206
  local HF_AUTO_BINDS=( $HF_AUTO_BINDS_STR )

  # User-injected extra binds
  local EXTRA=()
  if [[ -n "${SAMBA_EXTRA_BINDS:-}" ]]; then
    # shellcheck disable=SC2206
    EXTRA=( ${SAMBA_EXTRA_BINDS} )
  fi

  # ------------------------------------------------------------------
  # 5. Build pipeline-facing CONTAINER_CMD_PREFIX (used inside Perl)
  # ------------------------------------------------------------------
  local PIPELINE_CMD_PREFIX_A=(
    "$CONTAINER_CMD" exec
    --bind "$BIGGUS_DISKUS:$BIGGUS_DISKUS"
    "${BIND_ATLAS[@]}"
    "${HF_AUTO_BINDS[@]}"
    "${EXTRA[@]}"
    "$SIF_PATH"
  )
  export CONTAINER_CMD_PREFIX="${PIPELINE_CMD_PREFIX_A[*]}"

  # ------------------------------------------------------------------
  # 6. Host-side container launch for this run
  # ------------------------------------------------------------------
  local HOST_CMD_PREFIX_A=(
    "$CONTAINER_CMD" exec
    --env CONTAINER_CMD_PREFIX="$CONTAINER_CMD_PREFIX"
    --bind "$BIGGUS_DISKUS:$BIGGUS_DISKUS"
    "${BIND_HF_DIR[@]}"
    "${BIND_ATLAS[@]}"
    "${HF_AUTO_BINDS[@]}"
    "${EXTRA[@]}"
    "$SIF_PATH"
  )

  echo "samba-pipe: launching:" >&2
  printf '  %q ' "${HOST_CMD_PREFIX_A[@]}" /opt/samba/SAMBA/vbm_pipeline_start.pl "$hf_tmp" >&2
  echo >&2

  "${HOST_CMD_PREFIX_A[@]}" /opt/samba/SAMBA/vbm_pipeline_start.pl "$hf_tmp"
}
