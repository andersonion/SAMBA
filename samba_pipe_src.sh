#!/usr/bin/env bash
#
# samba_pipe_src.sh — clean, portable SAMBA launcher
#   + proxy-safe container prefix rehydration
#   + compact sbatch scripts via host-side wrapper + env/binds files
#
# Usage:
#   source samba_pipe_src.sh
#   samba-pipe path/to/startup.headfile
#
# Notes:
# - DO NOT use set -e here (failures must not kill login shells).
# - We do NOT override HOME inside container (Apptainer/Singularity can forbid it under --cleanenv).
# - We DO pass USER explicitly and bind HOME plus critical IPC/cache dirs.
# - We generate a HOST wrapper script in ~/.samba_sched that sbatch can execute.
#

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
    return 0
  fi
  if [[ -n "${SINGULARITY_IMAGE_DIR:-}" && -f "$SINGULARITY_IMAGE_DIR/samba.sif" ]]; then
    echo "$SINGULARITY_IMAGE_DIR/samba.sif"
    return 0
  fi
  if [[ -f "$HOME/containers/samba.sif" ]]; then
    echo "$HOME/containers/samba.sif"
    return 0
  fi
  local root="${SAMBA_SEARCH_ROOT:-$HOME}"
  local found
  found="$(find "$root" -maxdepth 6 -type f -name samba.sif 2>/dev/null | head -n 1 || true)"
  [[ -n "$found" ]] && { echo "$found"; return 0; }
  return 1
}

SIF_PATH="$(_samba_find_sif)" || { echo "ERROR: samba.sif not found" >&2; return 1; }
[[ -f "$SIF_PATH" ]] || { echo "ERROR: samba.sif not found at: $SIF_PATH" >&2; return 1; }
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

  [[ -n "${ATLAS_FOLDER_HOST:-}" ]] && roots+=( "$ATLAS_FOLDER_HOST" )
  [[ -n "${ATLAS_FOLDER:-}"      ]] && roots+=( "$ATLAS_FOLDER" )

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
# Bind planning helpers
# ------------------------------------------------------------
_normpath() {
  local p="$1"
  while [[ "$p" != "/" && "$p" == */ ]]; do p="${p%/}"; done
  echo "$p"
}

_resolve_if_exists() {
  local p="$1"
  if [[ -e "$p" ]] && command -v readlink >/dev/null 2>&1; then
    local rp
    rp="$(readlink -f "$p" 2>/dev/null || true)"
    [[ -n "$rp" ]] && { echo "$rp"; return 0; }
  fi
  echo "$p"
}

_bindable_dir_for() {
  local p="$(_normpath "$1")"
  p="$(_resolve_if_exists "$p")"

  if [[ -d "$p" ]]; then
    echo "$p"; return 0
  fi
  if [[ -f "$p" ]]; then
    echo "$(dirname "$p")"; return 0
  fi

  local cur="$p"
  while [[ "$cur" != "/" ]]; do
    cur="$(dirname "$cur")"
    cur="$(_resolve_if_exists "$cur")"
    [[ -d "$cur" ]] && { echo "$cur"; return 0; }
  done
  echo "/"
  return 0
}

_minimize_dirs() {
  local -a in=("$@")
  local -a uniq=()
  local d u

  for d in "${in[@]}"; do
    [[ -n "$d" ]] || continue
    d="$(_normpath "$d")"
    local seen=0
    for u in "${uniq[@]}"; do
      [[ "$u" == "$d" ]] && { seen=1; break; }
    done
    [[ $seen -eq 0 ]] && uniq+=("$d")
  done

  local -a sorted=()
  for d in "${uniq[@]}"; do sorted+=("$d"); done
  IFS=$'\n' sorted=($(printf "%s\n" "${sorted[@]}" | awk '{ print length($0) "\t" $0 }' | sort -n | cut -f2-))
  unset IFS

  local -a out=()
  for d in "${sorted[@]}"; do
    local covered=0
    local p
    for p in "${out[@]}"; do
      [[ "$d" == "$p" ]] && { covered=1; break; }
      [[ "$p" == "/" ]] && { covered=1; break; }
      [[ "$d" == "$p/"* ]] && { covered=1; break; }
    done
    [[ $covered -eq 0 ]] && out+=("$d")
  done

  printf "%s\n" "${out[@]}"
}

# ------------------------------------------------------------
# Write compact container config into host_sched_dir
#   - container.env   (KEY=VAL for --env-file)
#   - binds.txt       (SRC:DST one per line)
#   - container.meta  (RUNTIME=..., SIF=...)
#   - samba_container_exec.sh  (HOST wrapper executable)
#   - CONTAINER_CMD_PREFIX     (one line: path to wrapper)
# ------------------------------------------------------------
_write_container_config() {
  local host_sched_dir="$1"
  local runtime="$2"
  local sif="$3"
  local env_file="$4"
  local binds_file="$5"
  local meta_file="$6"
  local wrapper="$7"

  mkdir -p "$host_sched_dir" || return 1

  # meta (simple KEY=VALUE; wrapper 'source's it)
  cat > "$meta_file" <<EOF
RUNTIME='${runtime}'
SIF='${sif}'
ENVFILE='${env_file}'
BINDSFILE='${binds_file}'
EOF

  # Host wrapper script that sbatch can execute
  cat > "$wrapper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

sched_dir="${SAMBA_SCHED_DIR:-${HOME}/.samba_sched}"
meta="${sched_dir%/}/container.meta"

# Load RUNTIME, SIF, ENVFILE, BINDSFILE (quoted)
# shellcheck disable=SC1090
source "$meta"

# Expand binds file into --bind args
bind_args=()
if [[ -f "$BINDSFILE" ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    bind_args+=( --bind "$line" )
  done < "$BINDSFILE"
fi

exec "${RUNTIME}" exec --cleanenv --env-file "${ENVFILE}" "${bind_args[@]}" "${SIF}" "$@"
EOF
  chmod 0755 "$wrapper" || return 1

  # Persist prefix for proxy backend: host-visible executable path
  printf '%s\n' "$wrapper" > "${host_sched_dir%/}/CONTAINER_CMD_PREFIX"

  return 0
}

# ------------------------------------------------------------
# Main entry
# ------------------------------------------------------------
samba-pipe() {
  local hf="${1:-}"
  [[ -n "$hf" ]] || { echo "Usage: samba-pipe headfile.hf" >&2; return 1; }

  [[ "$hf" = /* || "$hf" = ~/* ]] || hf="$PWD/$hf"
  [[ -f "$hf" ]] || { echo "ERROR: headfile not found: $hf" >&2; return 1; }

  local hf_dir
  hf_dir="$(dirname "$hf")"

  # Resolve a stable host HOME path (do NOT export it into container; just bind it)
  local u="${USER:-$(id -un)}"
  local host_home="${HOME:-/home/$u}"
  [[ -d "$host_home" ]] || { echo "ERROR: HOME not found on host: $host_home" >&2; return 1; }

  # --------------------------------------------------------
  # Resolve BIGGUS_DISKUS (CRITICAL)
  # --------------------------------------------------------
  if [[ -z "${BIGGUS_DISKUS:-}" ]]; then
    if [[ -d "${SCRATCH:-}" ]]; then
      BIGGUS_DISKUS="$SCRATCH"
    elif [[ -d "${WORK:-}" ]]; then
      BIGGUS_DISKUS="$WORK"
    else
      BIGGUS_DISKUS="$host_home/samba_scratch"
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
  # MCR CTF cache bind
  # --------------------------------------------------------
  local host_mcr_ctf="${BIGGUS_DISKUS%/}/.mcr_ctf"
  mkdir -p "$host_mcr_ctf" || { echo "ERROR: could not mkdir -p $host_mcr_ctf" >&2; return 1; }

  # --------------------------------------------------------
  # Scheduler proxy dir (daemon-backed)
  # --------------------------------------------------------
  local host_sched_dir="$host_home/.samba_sched"
  mkdir -p "$host_sched_dir" || { echo "ERROR: could not mkdir -p $host_sched_dir" >&2; return 1; }

  # --------------------------------------------------------
  # Optional external inputs
  # --------------------------------------------------------
  local opt_ext
  opt_ext="$(_hf_get "$hf" "optional_external_inputs_dir" || true)"

  # --------------------------------------------------------
  # Stage headfile
  # --------------------------------------------------------
  local hf_tmp="/tmp/${u}_samba_$(date +%s)_$(basename "$hf")"
  cp "$hf" "$hf_tmp" || { echo "ERROR: could not stage headfile to $hf_tmp" >&2; return 1; }

  # --------------------------------------------------------
  # Collect deep bind candidates
  # --------------------------------------------------------
  local -a cand_paths=()
  cand_paths+=( "$hf_dir" )
  cand_paths+=( "$BIGGUS_DISKUS" )
  cand_paths+=( "$host_home" )
  cand_paths+=( "$host_mcr_ctf" )

  if [[ -n "$opt_ext" && -d "$opt_ext" ]]; then
    cand_paths+=( "$opt_ext" )
  fi

  # Scrape absolute paths from headfile values (best effort)
  local -a hf_abs=()
  while IFS= read -r v; do
    [[ -n "$v" ]] || continue
    v="${v%\"}"; v="${v#\"}"
    v="${v%\'}"; v="${v#\'}"
    if [[ "$v" == /* ]]; then
      hf_abs+=( "$v" )
      local rv
      rv="$(_resolve_if_exists "$v")"
      [[ "$rv" == /* && "$rv" != "$v" ]] && hf_abs+=( "$rv" )
    fi
  done < <(
    grep -E '^[[:space:]]*[A-Za-z0-9_]+[[:space:]]*=' "$hf" \
      | sed -E 's/^[[:space:]]*[A-Za-z0-9_]+[[:space:]]*=[[:space:]]*//' \
      | sed -E 's/[[:space:]]*$//'
  )

  local p
  for p in "${hf_abs[@]}"; do
    cand_paths+=( "$(_bindable_dir_for "$p")" )
  done

  # Minimize dirs
  local -a final_dirs=()
  while IFS= read -r p; do final_dirs+=( "$p" ); done < <(_minimize_dirs "${cand_paths[@]}")

  # Build --bind args
  local -a binds=()
  for p in "${final_dirs[@]}"; do
    [[ -n "$p" ]] || continue
    binds+=( --bind "$p:$p" )
  done

  # Explicit binds: sched + mcr
  binds+=( --bind "$host_sched_dir:$host_sched_dir" )
  binds+=( --bind "$host_mcr_ctf:/tmp/mcr_ctf" )

  # --------------------------------------------------------
  # Atlas intent from headfile (host-first)
  # --------------------------------------------------------
  local label_atlas rigid_atlas atlas_name=""
  label_atlas="$(_hf_get "$hf" "label_atlas_name" || true)"
  rigid_atlas="$(_hf_get "$hf" "rigid_atlas_name" || true)"
  [[ -n "$label_atlas" ]] && atlas_name="$label_atlas"
  [[ -z "$atlas_name" && -n "$rigid_atlas" ]] && atlas_name="$rigid_atlas"

  local atlas_folder_val="/opt/atlases"
  if [[ -n "$atlas_name" ]]; then
    local host_atlas_root=""
    if host_atlas_root="$(_find_atlas_root_for "$atlas_name" "$hf_dir" "$BIGGUS_DISKUS" 2>/dev/null)"; then
      echo "samba-pipe: using HOST atlas root: $host_atlas_root (for atlas $atlas_name)" >&2
      binds+=( --bind "$host_atlas_root:/atlas_host" )
      atlas_folder_val="/atlas_host"
    else
      echo "samba-pipe: WARNING: could not find host atlas '$atlas_name'; using container /opt/atlases" >&2
      atlas_folder_val="/opt/atlases"
    fi
  fi

  # --------------------------------------------------------
  # Container env we explicitly pass (because --cleanenv)
  # --------------------------------------------------------
  local sched_backend="${SAMBA_SCHED_BACKEND:-proxy}"

  # We will store these in a file for clean sbatch scripts
  local env_file="${host_sched_dir%/}/container.env"
  : > "$env_file" || { echo "ERROR: cannot write $env_file" >&2; return 1; }

  printf '%s\n' "SAMBA_APPS_DIR=$SAMBA_APPS_IN_CONTAINER" >> "$env_file"
  printf '%s\n' "BIGGUS_DISKUS=$BIGGUS_DISKUS" >> "$env_file"
  printf '%s\n' "USER=$u" >> "$env_file"
  printf '%s\n' "TMPDIR=/tmp" >> "$env_file"
  printf '%s\n' "SAMBA_SCHED_BACKEND=$sched_backend" >> "$env_file"
  printf '%s\n' "SAMBA_SCHED_DIR=$host_sched_dir" >> "$env_file"
  printf '%s\n' "MCR_INHIBIT_CTF_LOCK=1" >> "$env_file"
  printf '%s\n' "MCR_CACHE_ROOT=/tmp/mcr_ctf" >> "$env_file"
  printf '%s\n' "MCR_USER_CTF_ROOT=/tmp/mcr_ctf" >> "$env_file"
  printf '%s\n' "ATLAS_FOLDER=$atlas_folder_val" >> "$env_file"
  if [[ -n "${NOTIFICATION_EMAIL:-}" ]]; then
    printf '%s\n' "NOTIFICATION_EMAIL=$NOTIFICATION_EMAIL" >> "$env_file"
  fi

  # Bind pairs file for wrapper
  local binds_file="${host_sched_dir%/}/binds.txt"
  : > "$binds_file" || { echo "ERROR: cannot write $binds_file" >&2; return 1; }
  local i=0
  while [[ $i -lt ${#binds[@]} ]]; do
    if [[ "${binds[$i]}" == "--bind" ]]; then
      printf '%s\n' "${binds[$((i+1))]}" >> "$binds_file"
      i=$((i+2))
    else
      i=$((i+1))
    fi
  done

  # Write meta + wrapper; set CONTAINER_CMD_PREFIX to host wrapper path
  local meta_file="${host_sched_dir%/}/container.meta"
  local wrapper="${host_sched_dir%/}/samba_container_exec.sh"
  _write_container_config "$host_sched_dir" "$CONTAINER_CMD" "$SIF_PATH" \
    "$env_file" "$binds_file" "$meta_file" "$wrapper" \
    || { echo "ERROR: could not write container config into $host_sched_dir" >&2; return 1; }

  # This is what SAMBA's wrap_in_container() should use.
  # IMPORTANT: host path (sbatch can execute it).
  CONTAINER_CMD_PREFIX="$wrapper"
  export CONTAINER_CMD_PREFIX

  # --------------------------------------------------------
  # Debug binds if requested
  # --------------------------------------------------------
  if [[ -n "${SAMBA_DEBUG_BINDS:-}" ]]; then
    echo "samba-pipe: bind plan (mode=deep):" >&2
    local b
    for b in "${binds[@]}"; do echo "  $b" >&2; done
    echo "samba-pipe: env-file: $env_file" >&2
    echo "samba-pipe: binds-file: $binds_file" >&2
    echo "samba-pipe: wrapper: $wrapper" >&2
  fi

  # --------------------------------------------------------
  # Launch (call SAMBA_startup)
  # --------------------------------------------------------
  # For the top-level pipeline, we can still pass env directly; jobs will use wrapper+envfile.
  local HOST_CMD=(
    "$CONTAINER_CMD" exec --cleanenv
    --env "SAMBA_APPS_DIR=$SAMBA_APPS_IN_CONTAINER"
    --env "BIGGUS_DISKUS=$BIGGUS_DISKUS"
    --env "USER=$u"
    --env "TMPDIR=/tmp"
    --env "SAMBA_SCHED_BACKEND=$sched_backend"
    --env "SAMBA_SCHED_DIR=$host_sched_dir"
    --env "MCR_INHIBIT_CTF_LOCK=1"
    --env "MCR_CACHE_ROOT=/tmp/mcr_ctf"
    --env "MCR_USER_CTF_ROOT=/tmp/mcr_ctf"
    --env "ATLAS_FOLDER=$atlas_folder_val"
    --env "CONTAINER_CMD_PREFIX=$CONTAINER_CMD_PREFIX"
  )
  if [[ -n "${NOTIFICATION_EMAIL:-}" ]]; then
    HOST_CMD+=( --env "NOTIFICATION_EMAIL=$NOTIFICATION_EMAIL" )
  fi

  HOST_CMD+=( "${binds[@]}" "$SIF_PATH" /opt/samba/SAMBA/SAMBA_startup "$hf_tmp" )

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
