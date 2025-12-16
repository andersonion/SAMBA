#!/usr/bin/env bash
#
# samba_pipe_src.sh  (portable-ish launcher)
#
# Usage:
#   source /path/to/samba_pipe_src.sh
#   samba-pipe /path/to/startup.headfile
#

# NOTE:
# This file is meant to be SOURCED. Therefore: do NOT set -euo pipefail at top-level.
# We enable strict mode inside the samba-pipe() function only.

# ---------- runtime detection (host) ----------
_samba_find_runtime() {
  local ct=""
  if [[ -n "${SAMBA_CONTAINER_RUNTIME-}" && -x "${SAMBA_CONTAINER_RUNTIME}" ]]; then
    ct="${SAMBA_CONTAINER_RUNTIME}"
  elif command -v apptainer >/dev/null 2>&1; then
    ct="$(command -v apptainer)"
  elif command -v singularity >/dev/null 2>&1; then
    ct="$(command -v singularity)"
  else
    for cand in /usr/local/bin/apptainer /usr/bin/apptainer /usr/local/bin/singularity /usr/bin/singularity; do
      if [[ -x "$cand" ]]; then ct="$cand"; break; fi
    done
  fi
  [[ -n "$ct" ]] || { echo "ERROR: apptainer/singularity not found in PATH" >&2; return 1; }
  echo "$ct"
}

# ---------- locate samba.sif (host) ----------
_samba_find_sif() {
  local sif=""
  if [[ -n "${SAMBA_CONTAINER_PATH-}" && -f "$SAMBA_CONTAINER_PATH" ]]; then
    sif="$SAMBA_CONTAINER_PATH"
  elif [[ -n "${SINGULARITY_IMAGE_DIR-}" && -f "$SINGULARITY_IMAGE_DIR/samba.sif" ]]; then
    sif="$SINGULARITY_IMAGE_DIR/samba.sif"
  elif [[ -f "$HOME/containers/samba.sif" ]]; then
    sif="$HOME/containers/samba.sif"
  else
    local root="${SAMBA_SEARCH_ROOT:-$HOME}"
    sif="$(find "$root" -maxdepth 6 -type f -name 'samba.sif' 2>/dev/null | head -n 1 || true)"
  fi
  [[ -n "$sif" && -f "$sif" ]] || {
    echo "ERROR: Could not locate samba.sif on host." >&2
    echo "Set SAMBA_CONTAINER_PATH or SINGULARITY_IMAGE_DIR or place at $HOME/containers/samba.sif" >&2
    return 1
  }
  echo "$sif"
}

_samba_abs_path() {
  local p="${1-}"
  [[ -n "$p" ]] || return 1
  if [[ "${p:0:1}" != "/" && "${p:0:2}" != "~/" ]]; then
    echo "${PWD}/${p}"
  else
    echo "$p"
  fi
}

_samba_hf_get() {
  local key="${1:?key required}" hf="${2:?headfile required}"
  grep -E "^${key}[[:space:]]*=" "$hf" 2>/dev/null | head -n 1 | sed -E 's/^[^=]*=[[:space:]]*//'
}

_samba_find_host_atlas_root() {
  # Given atlas name (e.g., IITmean_RPI), find a host atlas root that contains:
  #   <root>/<atlas>/<atlas>_fa.nii or .nii.gz
  local atlas="${1:?atlas name required}"

  local roots=()
  if [[ -n "${ATLAS_FOLDER:-}" ]]; then roots+=( "$ATLAS_FOLDER" ); fi
  if [[ -n "${SAMBA_ATLAS_SEARCH_ROOTS:-}" ]]; then
    IFS=':' read -r -a _more <<< "${SAMBA_ATLAS_SEARCH_ROOTS}"
    roots+=( "${_more[@]}" )
  fi
  roots+=( "$HOME/atlases" "$HOME/Atlases" "$HOME/atlas" "$HOME/Atlas" )

  local r=""
  for r in "${roots[@]}"; do
    [[ -n "$r" && -d "$r" ]] || continue
    if [[ -f "$r/$atlas/${atlas}_fa.nii.gz" || -f "$r/$atlas/${atlas}_fa.nii" ]]; then
      echo "$r"
      return 0
    fi
  done

  if [[ -n "${SAMBA_ATLAS_FIND_ROOT:-}" && -d "${SAMBA_ATLAS_FIND_ROOT}" ]]; then
    local hit
    hit="$(find "${SAMBA_ATLAS_FIND_ROOT}" -maxdepth 6 -type f \( -name "${atlas}_fa.nii" -o -name "${atlas}_fa.nii.gz" \) 2>/dev/null | head -n 1 || true)"
    if [[ -n "$hit" ]]; then
      echo "$(dirname "$(dirname "$hit")")"
      return 0
    fi
  fi

  return 1
}

# ---------- initialize host-global vars (safe when sourced) ----------
CONTAINER_CMD="$(_samba_find_runtime)"
export CONTAINER_CMD

SIF_PATH="$(_samba_find_sif)"
export SIF_PATH

# ---------- main entry ----------
samba-pipe() {
   set -u  # keep nounset if you like; safe
   set +e  # ensure we never auto-exit on failures

  local hf="${1-}"
  [[ -n "$hf" ]] || { echo "Usage: samba-pipe headfile.hf" >&2; return 1; }

  hf="$(_samba_abs_path "$hf")"
  [[ -f "$hf" ]] || { echo "ERROR: headfile not found: $hf" >&2; return 1; }

  # -------- BIGGUS_DISKUS selection --------
  if [[ -z "${BIGGUS_DISKUS:-}" ]]; then
    if [[ -d "${SCRATCH:-}" ]]; then
      BIGGUS_DISKUS="$SCRATCH"
    elif [[ -d "${WORK:-}" ]]; then
      BIGGUS_DISKUS="$WORK"
    else
      BIGGUS_DISKUS="$HOME/samba_scratch"
      mkdir -p "$BIGGUS_DISKUS"
    fi
    export BIGGUS_DISKUS
  fi
  [[ -d "$BIGGUS_DISKUS" && -w "$BIGGUS_DISKUS" ]] || {
    echo "ERROR: BIGGUS_DISKUS ('$BIGGUS_DISKUS') is not writable or does not exist." >&2
    return 1
  }

  local USER_SAFE="${USER:-$(id -un 2>/dev/null || echo unknown)}"

  # -------- binds --------
  local hf_dir
  hf_dir="$(dirname "$hf")"

  local binds=()
  binds+=( --bind "$hf_dir:$hf_dir" )
  binds+=( --bind "$BIGGUS_DISKUS:$BIGGUS_DISKUS" )

  local opt_ext=""
  opt_ext="$(_samba_hf_get "optional_external_inputs_dir" "$hf" || true)"
  if [[ -n "$opt_ext" && -d "$opt_ext" ]]; then
    binds+=( --bind "$opt_ext:$opt_ext" )
  fi

  # -------- atlas intent from headfile --------
  local rigid_atlas label_atlas atlas_name
  rigid_atlas="$(_samba_hf_get "rigid_atlas_name" "$hf" || true)"
  label_atlas="$(_samba_hf_get "label_atlas_name" "$hf" || true)"
  atlas_name="${label_atlas:-$rigid_atlas}"

  local atlas_env=()
  if [[ -n "$atlas_name" ]]; then
    local host_atlas_root=""
    if host_atlas_root="$(_samba_find_host_atlas_root "$atlas_name" 2>/dev/null)"; then
      binds+=( --bind "$host_atlas_root:/opt/atlases_host" )
      atlas_env+=( --env ATLAS_FOLDER=/opt/atlases_host )
      echo "samba-pipe: using HOST atlas root: $host_atlas_root (bound to /opt/atlases_host)" >&2
    else
      echo "samba-pipe: host atlas for '$atlas_name' not found; falling back to embedded atlas in image" >&2
    fi
  fi

  # -------- container-side app root (must be /opt/samba) --------
  local SAMBA_APPS_IN_CONTAINER="/opt/samba"

  # stage HF into /tmp (host-side)
  local hf_tmp="/tmp/${USER_SAFE}_samba_$(date +%s)_$(basename "$hf")"
  cp "$hf" "$hf_tmp"

  # -------- pipeline prefix --------
  local PIPELINE_CMD_PREFIX_A=(
    "$CONTAINER_CMD" exec --cleanenv
    --env SAMBA_APPS_DIR="$SAMBA_APPS_IN_CONTAINER"
    --env BIGGUS_DISKUS="$BIGGUS_DISKUS"
    --env USER="$USER_SAFE"
    "${atlas_env[@]}"
    "${binds[@]}"
    "$SIF_PATH"
  )
  export CONTAINER_CMD_PREFIX="${PIPELINE_CMD_PREFIX_A[*]}"

  # -------- host-side launch --------
  local HOST_CMD_PREFIX_A=(
    "$CONTAINER_CMD" exec --cleanenv
    --env CONTAINER_CMD_PREFIX="$CONTAINER_CMD_PREFIX"
    --env SAMBA_APPS_DIR="$SAMBA_APPS_IN_CONTAINER"
    --env BIGGUS_DISKUS="$BIGGUS_DISKUS"
    --env USER="$USER_SAFE"
    "${atlas_env[@]}"
    "${binds[@]}"
    "$SIF_PATH"
  )

  echo "samba-pipe: launching:"
  printf '  %q ' "${HOST_CMD_PREFIX_A[@]}" "/opt/samba/SAMBA/vbm_pipeline_start.pl" "$hf_tmp"
  echo

  "${HOST_CMD_PREFIX_A[@]}" /opt/samba/SAMBA/vbm_pipeline_start.pl "$hf_tmp"
  rc=$?
  if [[ $rc -ne 0 ]]; then
     echo "samba-pipe: SAMBA exited with status $rc (shell remains alive)" >&2
  fi
return $rc

}
export -f samba-pipe
