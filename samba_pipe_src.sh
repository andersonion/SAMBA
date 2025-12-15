#!/usr/bin/env bash
#
# samba_pipe_src.sh  (portable-ish launcher)
#
# Usage:
#   source /home/apps/SAMBA/samba_pipe_src.sh
#   samba-pipe /path/to/startup.headfile
#
# Notes:
# - Container-side runtime env is sourced from /opt/env/samba.sh via %environment.
# - We still pass CONTAINER_CMD_PREFIX into the container so the pipeline can wrap
#   scheduler calls / external commands on the host.
#

# ----------------------------------------------------------------------
# Locate container runtime executable on the *host* (Apptainer preferred)
# ----------------------------------------------------------------------
_samba_find_container_runtime() {
  local ct=""

  if [[ -n "${SAMBA_CONTAINER_RUNTIME-}" && -x "${SAMBA_CONTAINER_RUNTIME}" ]]; then
    ct="${SAMBA_CONTAINER_RUNTIME}"
  elif command -v apptainer >/dev/null 2>&1; then
    ct="$(command -v apptainer)"
  elif command -v singularity >/dev/null 2>&1; then
    ct="$(command -v singularity)"
  else
    # common site paths fallback
    local cand
    for cand in \
      /usr/local/bin/apptainer /usr/bin/apptainer \
      /usr/local/bin/singularity /usr/bin/singularity \
      /home/apps/ubuntu-22.04/singularity/bin/singularity
    do
      if [[ -x "$cand" ]]; then ct="$cand"; break; fi
    done
  fi

  if [[ -z "$ct" ]]; then
    echo "ERROR: Neither apptainer nor singularity found in PATH" >&2
    return 1
  fi

  echo "$ct"
}

CONTAINER_CMD="$(_samba_find_container_runtime)" || { return 1 2>/dev/null || exit 1; }
export CONTAINER_CMD

# ----------------------------------------------------------------------
# Locate the samba.sif image (host side)
#   Priority:
#     1) SAMBA_CONTAINER_PATH (explicit)
#     2) SINGULARITY_IMAGE_DIR/samba.sif or APPTAINER_IMAGE_DIR/samba.sif
#     3) $HOME/containers/samba.sif
#     4) find under SAMBA_SEARCH_ROOT (or $HOME)
# ----------------------------------------------------------------------
_samba_find_sif() {
  local sif=""

  if [[ -n "${SAMBA_CONTAINER_PATH:-}" && -f "${SAMBA_CONTAINER_PATH}" ]]; then
    sif="${SAMBA_CONTAINER_PATH}"
  elif [[ -n "${SINGULARITY_IMAGE_DIR:-}" && -f "${SINGULARITY_IMAGE_DIR}/samba.sif" ]]; then
    sif="${SINGULARITY_IMAGE_DIR}/samba.sif"
  elif [[ -n "${APPTAINER_IMAGE_DIR:-}" && -f "${APPTAINER_IMAGE_DIR}/samba.sif" ]]; then
    sif="${APPTAINER_IMAGE_DIR}/samba.sif"
  elif [[ -f "${HOME}/containers/samba.sif" ]]; then
    sif="${HOME}/containers/samba.sif"
  else
    echo "samba-pipe: trying to locate samba.sif using find (host side)..." >&2
    local root="${SAMBA_SEARCH_ROOT:-$HOME}"
    sif="$(find "$root" -maxdepth 6 -type f -name 'samba.sif' 2>/dev/null | head -n 1 || true)"
  fi

  [[ -n "$sif" && -f "$sif" ]] || return 1
  echo "$sif"
}

SIF_PATH="$(_samba_find_sif)" || {
  echo "ERROR: Could not locate samba.sif on host." >&2
  echo "Set SAMBA_CONTAINER_PATH or SINGULARITY_IMAGE_DIR/APPTAINER_IMAGE_DIR, or place it at:" >&2
  echo "  \$HOME/containers/samba.sif" >&2
  return 1 2>/dev/null || exit 1
}
export SIF_PATH

# ----------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------
_samba_abs_path() {
  local p="$1"
  if [[ "${p:0:1}" == "/" ]]; then
    echo "$p"
  elif [[ "${p:0:2}" == "~/" ]]; then
    echo "${HOME}/${p:2}"
  else
    echo "${PWD}/${p}"
  fi
}

# Turn an argv array into a safely shell-escaped string (for env passing)
_samba_shell_join() {
  local out="" x
  for x in "$@"; do
    out+=$(printf '%q ' "$x")
  done
  # trim trailing space
  out="${out% }"
  printf '%s' "$out"
}

# ----------------------------------------------------------------------
# Main entry point
# ----------------------------------------------------------------------
samba-pipe() {
  local hf="${1:-}"

  if [[ -z "$hf" ]]; then
    echo "Usage: samba-pipe /path/to/startup.headfile" >&2
    return 1
  fi

  hf="$(_samba_abs_path "$hf")"
  if [[ ! -f "$hf" ]]; then
    echo "ERROR: headfile not found: $hf" >&2
    return 1
  fi

  # ---------------- BIGGUS_DISKUS ----------------
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

  # Optional warning for group-writability (multi-user friendliness)
  perl -e 'exit((stat($ARGV[0]))[2] & 0020 ? 0 : 1)' "$BIGGUS_DISKUS" 2>/dev/null \
    || echo "Warning: $BIGGUS_DISKUS is not group-writable. Multi-user workflows may fail."

  # ---------------- Binds ----------------
  local hf_dir
  hf_dir="$(dirname "$hf")"

  local BINDS=()
  BINDS+=( --bind "$hf_dir:$hf_dir" )
  BINDS+=( --bind "$BIGGUS_DISKUS:$BIGGUS_DISKUS" )

  # Atlas bind (optional)
  if [[ -n "${ATLAS_FOLDER:-}" && -d "$ATLAS_FOLDER" ]]; then
    BINDS+=( --bind "$ATLAS_FOLDER:$ATLAS_FOLDER" )
  fi

  # Optional external inputs from headfile (optional_external_inputs_dir = /path)
  local opt_ext=""
  opt_ext="$(grep -E '^optional_external_inputs_dir[[:space:]]*=' "$hf" 2>/dev/null | sed 's/.*=[[:space:]]*//')"
  if [[ -n "$opt_ext" && -d "$opt_ext" ]]; then
    BINDS+=( --bind "$opt_ext:$opt_ext" )
  fi

  # ---------------- Stage HF into /tmp (host side) ----------------
  local hf_tmp="/tmp/${USER}_samba_$(date +%s)_$(basename "$hf")"
  cp -f "$hf" "$hf_tmp"

  # ---------------- Build CONTAINER_CMD_PREFIX ----------------
  # This is used by cluster_exec()->wrap_in_container() for sbatch/external commands.
  # NOTE: We do NOT need to pass SAMBA_APPS_DIR anymore — image env does it.
  local PIPELINE_CMD_PREFIX_A=(
    "$CONTAINER_CMD" exec
    "${BINDS[@]}"
    "$SIF_PATH"
  )
  export CONTAINER_CMD_PREFIX
  CONTAINER_CMD_PREFIX="$(_samba_shell_join "${PIPELINE_CMD_PREFIX_A[@]}")"

  # ---------------- Host-side launch ----------------
  local HOST_CMD_A=(
    "$CONTAINER_CMD" exec
    --env "CONTAINER_CMD_PREFIX=${CONTAINER_CMD_PREFIX}"
    "${BINDS[@]}"
    "$SIF_PATH"
    /opt/samba/SAMBA/vbm_pipeline_start.pl
    "$hf_tmp"
  )

  echo "samba-pipe: launching:"
  printf '  %q ' "${HOST_CMD_A[@]}"
  echo

  "${HOST_CMD_A[@]}"
}
