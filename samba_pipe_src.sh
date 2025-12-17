#!/usr/bin/env bash
#
# samba_pipe_src.sh — clean, portable SAMBA launcher (host-first atlas + MCR CTF bind)
#
# Usage:
#   source samba_pipe_src.sh
#   samba-pipe path/to/startup.headfile
#

# DO NOT use set -e here — failures must not kill login shells
set -u

# ------------------------------------------------------------
# Runtime discovery
# ------------------------------------------------------------
_samba_find_runtime() {
  if [[ -n "${SAMBA_CONTAINER_RUNTIME:-}" && -x "${SAMBA_CONTAINER_RUNTIME}" ]]; then
    echo "${SAMBA_CONTAINER_RUNTIME}"
    return 0
  fi
  if command -v apptainer >/dev/null 2>&1; then
    command -v apptainer
    return 0
  fi
  if command -v singularity >/dev/null 2>&1; then
    command -v singularity
    return 0
  fi
  for c in /usr/local/bin/apptainer /usr/bin/apptainer /usr/local/bin/singularity /usr/bin/singularity; do
    [[ -x "$c" ]] && { echo "$c"; return 0; }
  done
  echo "ERROR: apptainer/singularity not found" >&2
  return 1
}

CONTAINER_CMD="$(_samba_find_runtime)" || return 1
export CONTAINER_CMD

# ------------------------------------------------------------
# Locate samba.sif
# ------------------------------------------------------------
_samba_find_sif() {
  if [[ -n "${SAMBA_CONTAINER_PATH:-}" && -f "$SAMBA_CONTAINER_PATH" ]]; then
    echo "$SAMBA_CONTAINER_PATH"
    return
  fi
  if [[ -n "${SINGULARITY_IMAGE_DIR:-}" && -f "$SINGULARITY_IMAGE_DIR/samba.sif" ]]; then
    echo "$SINGULARITY_IMAGE_DIR/samba.sif"
    return
  fi
  if [[ -f "$HOME/containers/samba.sif" ]]; then
    echo "$HOME/containers/samba.sif"
    return
  fi
  local root="${SAMBA_SEARCH_ROOT:-$HOME}"
  find "$root" -maxdepth 6 -type f -name samba.sif 2>/dev/null | head -n 1
}

SIF_PATH="$(_samba_find_sif)"
[[ -f "${SIF_PATH:-}" ]] || { echo "ERROR: samba.sif not found" >&2; return 1; }
export SIF_PATH

# ------------------------------------------------------------
# Headfile helper: read key=value
# ------------------------------------------------------------
_hf_get() {
  local hf="$1" key="$2"
  grep -E "^[[:space:]]*${key}[[:space:]]*=" "$hf" 2>/dev/null \
    | head -n 1 \
    | sed -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//" \
    | sed -E "s/[[:space:]]*$//"
}

# ------------------------------------------------------------
# Atlas discovery (host-first)
# ------------------------------------------------------------
_find_atlas_root_for() {
  local atlas="$1" hf_dir="$2" biggus="$3"
  local roots=()

  if [[ -n "${ATLAS_FOLDER_HOST:-}" ]]; then
    roots+=( "$ATLAS_FOLDER_HOST" )
  fi
  if [[ -n "${ATLAS_FOLDER:-}" ]]; then
    roots+=( "$ATLAS_FOLDER" )
  fi
  if [[ -n "${SAMBA_ATLAS_SEARCH_ROOTS:-}" ]]; then
    IFS=':' read -r -a _extra <<< "${SAMBA_ATLAS_SEARCH_ROOTS}"
    roots+=( "${_extra[@]}" )
  fi

  roots+=( "$hf_dir" "$HOME" "$biggus" )

  local r cand_dir
  for r in "${roots[@]}"; do
    [[ -n "$r" && -d "$r" ]] || continue

    cand_dir="${r%/}/${atlas}"
    if [[ -d "$cand_dir" ]]; then
      if ls "${cand_dir}/${atlas}_fa.nii"* >/dev/null 2>&1; then
        echo "${r%/}"
        return 0
      fi
    fi

    if [[ "$(basename "$r")" == "$atlas" ]]; then
      if ls "${r%/}/${atlas}_fa.nii"* >/dev/null 2>&1; then
        echo "$(dirname "${r%/}")"
        return 0
      fi
    fi
  done

  return 1
}

# ------------------------------------------------------------
# Main entry
# ------------------------------------------------------------
samba-pipe() {
  local hf="${1:-}"
  [[ -n "$hf" ]] || { echo "Usage: samba-pipe headfile.hf" >&2; return 1; }

  [[ "$hf" = /* || "$hf" = ~/* ]] || hf="$PWD/$hf"
  [[ -f "$hf" ]] || { echo "ERROR: headfile not found: $hf" >&2; return 1; }

  # --------------------------------------------------------
  # Resolve BIGGUS_DISKUS (CRITICAL)
  # --------------------------------------------------------
  if [[ -z "${BIGGUS_DISKUS:-}" ]]; then
    if [[ -d "${SCRATCH:-}" ]]; then
      BIGGUS_DISKUS="$SCRATCH"
    elif [[ -d "${WORK:-}" ]]; then
      BIGGUS_DISKUS="$WORK"
    else
      BIGGUS_DISKUS="$HOME/samba_scratch"
      mkdir -p "$BIGGUS_DISKUS"
    fi
  fi

  [[ -d "$BIGGUS_DISKUS" && -w "$BIGGUS_DISKUS" ]] || {
    echo "ERROR: BIGGUS_DISKUS not writable: $BIGGUS_DISKUS" >&2
    return 1
  }
  export BIGGUS_DISKUS

  # --------------------------------------------------------
  # Core container paths
  # --------------------------------------------------------
  local SAMBA_APPS_IN_CONTAINER="/opt/samba"

  # --------------------------------------------------------
  # HOME bind (helps MCR and consistency)
  # --------------------------------------------------------
  local host_home="${HOME:-/home/$(id -un)}"
  [[ -d "$host_home" ]] || { echo "ERROR: HOME not found: $host_home" >&2; return 1; }

  # --------------------------------------------------------
  # MCR CTF cache bind (THIS IS THE REAL FIX)
  #   - auto-create persistent host dir (not manual)
  #   - bind to /tmp/mcr_ctf so symlink targets always have a parent dir
  # --------------------------------------------------------
  local host_mcr_ctf="${BIGGUS_DISKUS%/}/.mcr_ctf"
  mkdir -p "$host_mcr_ctf" || {
    echo "ERROR: could not mkdir -p $host_mcr_ctf" >&2
    return 1
  }

  # --------------------------------------------------------
  # Binds baseline
  # --------------------------------------------------------
  local hf_dir
  hf_dir="$(dirname "$hf")"

  local binds=()
  binds+=(
    --bind "$hf_dir:$hf_dir"
    --bind "$BIGGUS_DISKUS:$BIGGUS_DISKUS"
    --bind "$host_home:$host_home"
    --bind "$host_mcr_ctf:/tmp/mcr_ctf"
  )

  # Optional external inputs
  local opt_ext
  opt_ext="$(_hf_get "$hf" "optional_external_inputs_dir" || true)"
  if [[ -n "$opt_ext" && -d "$opt_ext" ]]; then
    binds+=( --bind "$opt_ext:$opt_ext" )
  fi

  # --------------------------------------------------------
  # Atlas intent from headfile
  # --------------------------------------------------------
  local label_atlas rigid_atlas
  label_atlas="$(_hf_get "$hf" "label_atlas_name" || true)"
  rigid_atlas="$(_hf_get "$hf" "rigid_atlas_name" || true)"

  local atlas_name=""
  if [[ -n "$label_atlas" ]]; then
    atlas_name="$label_atlas"
  elif [[ -n "$rigid_atlas" ]]; then
    atlas_name="$rigid_atlas"
  fi

  local atlas_env=()
  if [[ -n "$atlas_name" ]]; then
    local host_atlas_root=""
    if host_atlas_root="$(_find_atlas_root_for "$atlas_name" "$hf_dir" "$BIGGUS_DISKUS" 2>/dev/null)"; then
      echo "samba-pipe: using HOST atlas root: $host_atlas_root (for atlas $atlas_name)" >&2
      binds+=( --bind "$host_atlas_root:/atlas_host" )
      atlas_env+=( --env ATLAS_FOLDER=/atlas_host )
    else
      echo "samba-pipe: WARNING: could not find host atlas '$atlas_name'; falling back to container /opt/atlases" >&2
      atlas_env+=( --env ATLAS_FOLDER=/opt/atlases )
    fi
  else
    atlas_env+=( --env ATLAS_FOLDER=/opt/atlases )
  fi

  # --------------------------------------------------------
  # Stage headfile
  # --------------------------------------------------------
  local u="${USER:-$(id -un)}"
  local hf_tmp="/tmp/${u}_samba_$(date +%s)_$(basename "$hf")"
  cp "$hf" "$hf_tmp" || { echo "ERROR: could not stage headfile to $hf_tmp" >&2; return 1; }

  # --------------------------------------------------------
  # Container env we explicitly pass (because --cleanenv)
  # --------------------------------------------------------
  local BASE_ENV=(
    --env SAMBA_APPS_DIR="$SAMBA_APPS_IN_CONTAINER"
    --env BIGGUS_DISKUS="$BIGGUS_DISKUS"
    --env HOME="$host_home"
    --env USER="$u"
    --env TMPDIR="/tmp"

    # MCR behavior: keep cache/CTF writable & avoid lock fights
    --env MCR_INHIBIT_CTF_LOCK=1
    --env MCR_CACHE_ROOT="/tmp/mcr_ctf"
    --env MCR_USER_CTF_ROOT="/tmp/mcr_ctf"
  )

  # Pass NOTIFICATION_EMAIL if set on host
  if [[ -n "${NOTIFICATION_EMAIL:-}" ]]; then
    BASE_ENV+=( --env NOTIFICATION_EMAIL="$NOTIFICATION_EMAIL" )
  fi

  # This is used by scheduler wrappers inside SAMBA
  CONTAINER_CMD_PREFIX="$CONTAINER_CMD exec --cleanenv ${BASE_ENV[*]} ${atlas_env[*]} ${binds[*]} $SIF_PATH"
  export CONTAINER_CMD_PREFIX

  # --------------------------------------------------------
  # Launch
  # --------------------------------------------------------
  local HOST_CMD=(
    "$CONTAINER_CMD" exec --cleanenv
    "${BASE_ENV[@]}"
    --env CONTAINER_CMD_PREFIX="$CONTAINER_CMD_PREFIX"
    "${atlas_env[@]}"
    "${binds[@]}"
    "$SIF_PATH"
    /opt/samba/SAMBA/vbm_pipeline_start.pl
    "$hf_tmp"
  )

  echo "samba-pipe: launching:"
  printf '  %q ' "${HOST_CMD[@]}"
  echo

  "${HOST_CMD[@]}"
  local rc=$?

  if [[ $rc -ne 0 ]]; then
    echo "samba-pipe: SAMBA exited with status $rc (shell remains alive)" >&2
  fi
  return $rc
}

export -f samba-pipe
