#!/usr/bin/env bash
# SAMBA launcher for Apptainer/Singularity with env handoff for Perl jobs.

# ---------- Container runtime ----------
if command -v apptainer >/dev/null 2>&1; then
  CONTAINER_CMD="$(command -v apptainer)"
elif command -v singularity >/dev/null 2>&1; then
  CONTAINER_CMD="$(command -v singularity)"
else
  echo "ERROR: Neither Apptainer nor Singularity found in PATH." >&2
  return 1
fi

# ---------- Locate samba.sif ----------
if [[ -n "${SAMBA_CONTAINER_PATH:-}" && -f "$SAMBA_CONTAINER_PATH" ]]; then
  SIF_PATH="$SAMBA_CONTAINER_PATH"
elif [[ -n "${SINGULARITY_IMAGE_DIR:-}" && -f "$SINGULARITY_IMAGE_DIR/samba.sif" ]]; then
  SIF_PATH="$SINGULARITY_IMAGE_DIR/samba.sif"
elif [[ -f "$HOME/containers/samba.sif" ]]; then
  SIF_PATH="$HOME/containers/samba.sif"
elif [[ -f "/home/apps/singularity/images/samba.sif" ]]; then
  SIF_PATH="/home/apps/singularity/images/samba.sif"
else
  echo "Trying to locate samba.sif using find... (this may take a moment)"
  SEARCH_ROOT="${SAMBA_SEARCH_ROOT:-$HOME}"
  SIF_PATH="$(find "$SEARCH_ROOT" -type f -name 'samba.sif' 2>/dev/null | head -n 1)"
  if [[ -z "$SIF_PATH" ]]; then
    echo "ERROR: Could not locate samba.sif" >&2
    echo "Set SAMBA_CONTAINER_PATH or place it in one of:" >&2
    echo "  \$SINGULARITY_IMAGE_DIR/samba.sif" >&2
    echo "  \$HOME/containers/samba.sif" >&2
    echo "  /home/apps/singularity/images/samba.sif" >&2
    return 1
  else
    echo "Found samba.sif at: $SIF_PATH"
  fi
fi
export SIF_PATH

# Export for Perl (kept from your version)
export SAMBA_CONTAINER_RUNTIME="$CONTAINER_CMD"
export SAMBA_SIF_PATH="$SIF_PATH"

# ---------- Optional: cluster client binds ----------
EXTRA_BINDS=()

# SLURM
if command -v sbatch >/dev/null 2>&1; then
  SBATCH_BIN="$(command -v sbatch)"
  SBATCH_DIR="$(dirname "$SBATCH_BIN")"

  # Bind the directory containing sbatch/scancel/etc.
  EXTRA_BINDS+=( --bind "$SBATCH_DIR:$SBATCH_DIR" )

  # Bind slurm.conf / /etc/slurm if present
  if [[ -n "${SLURM_CONF:-}" && -f "$SLURM_CONF" ]]; then
    EXTRA_BINDS+=( --bind "$(dirname "$SLURM_CONF")":"$(dirname "$SLURM_CONF")" )
  elif [[ -f /etc/slurm/slurm.conf ]]; then
    EXTRA_BINDS+=( --bind /etc/slurm:/etc/slurm )
  fi

  # Try to locate libslurmfull.so or libslurm.so from ldd output and bind its directory
  SLURM_LIB_PATH="$(ldd "$SBATCH_BIN" 2>/dev/null | awk '/libslurm(full)?\.so/ {print $3; exit}')"
  if [[ -n "$SLURM_LIB_PATH" && -f "$SLURM_LIB_PATH" ]]; then
    SLURM_LIB_DIR="$(dirname "$SLURM_LIB_PATH")"
    EXTRA_BINDS+=( --bind "$SLURM_LIB_DIR:$SLURM_LIB_DIR" )
    export SAMBA_SLURM_LIB_DIR="$SLURM_LIB_DIR"
  fi
fi

# SGE
if command -v qsub >/dev/null 2>&1; then
  QSUB_DIR="$(dirname "$(command -v qsub)")"
  EXTRA_BINDS+=( --bind "$QSUB_DIR:$QSUB_DIR" )
  if [[ -n "${SGE_ROOT:-}" && -d "$SGE_ROOT" ]]; then
    EXTRA_BINDS+=( --bind "$SGE_ROOT:$SGE_ROOT" )
  fi
fi

# ---------- Main ----------
function samba-pipe {
  local hf="$1"
  if [[ -z "$hf" ]]; then
    echo "Usage: samba-pipe headfile.hf" >&2
    return 1
  fi

  # Make headfile absolute once
  if [[ "${hf:0:1}" != "/" && "${hf:0:2}" != "~/" ]]; then
    hf="${PWD}/${hf}"
  fi
  if [[ ! -f "$hf" ]]; then
    echo "ERROR: headfile not found: $hf" >&2
    return 1
  fi

  # BIGGUS_DISKUS selection & validation
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
  # Warn if directory is not group-writable (more accurate than -g/setgid)
  if ! perl -e 'exit((stat($ARGV[0]))[2] & 0020 ? 0 : 1)' "$BIGGUS_DISKUS"; then
    echo "Warning: $BIGGUS_DISKUS is not group-writable. Multi-user workflows may fail."
  fi

  # Atlas bind (array-safe)
  local BIND_ATLAS=()
  if [[ -n "${ATLAS_FOLDER:-}" && -d "$ATLAS_FOLDER" ]]; then
    BIND_ATLAS=( --bind "$ATLAS_FOLDER:$ATLAS_FOLDER" )
  else
    echo "Warning: ATLAS_FOLDER not set or does not exist. Proceeding with default atlas."
  fi

  # Export for Perl glue (kept from your version)
  export SAMBA_ATLAS_BIND="${BIND_ATLAS[*]}"
  export SAMBA_BIGGUS_BIND="$BIGGUS_DISKUS:$BIGGUS_DISKUS"

  # Stage HF to /tmp for stable path
  local hf_tmp="/tmp/${USER}_samba_$(date +%s)_$(basename "$hf")"
  cp "$hf" "$hf_tmp"

  # Env-file for container
  local ENV_FILE
  ENV_FILE="$(mktemp /tmp/samba_env.XXXXXX)"

  # Build command prefix (include BIGGUS & HF dir binds, atlas, schedulers)
  local BIND_HF_DIR=( --bind "$(dirname "$hf")":"$(dirname "$hf")" )
  local CMD_PREFIX_A=(
    "$CONTAINER_CMD" exec
    --env-file "$ENV_FILE"
    --bind "$BIGGUS_DISKUS:$BIGGUS_DISKUS"
    "${BIND_HF_DIR[@]}"
    "${BIND_ATLAS[@]}"
    "${EXTRA_BINDS[@]}"
    "$SIF_PATH"
  )
  export CONTAINER_CMD_PREFIX="${CMD_PREFIX_A[*]}"

  # Write selected env vars to ENV_FILE
  for var in USER BIGGUS_DISKUS SIF_PATH ATLAS_FOLDER NOTIFICATION_EMAIL \
             PIPELINE_QUEUE SLURM_RESERVATION SAMBA_SLURM_LIB_DIR \
             CONTAINER_CMD_PREFIX; do
    val="${!var:-}"
    if [[ -n "$val" ]]; then
      printf '%s=%s\n' "$var" "$val" >> "$ENV_FILE"
    fi
  done

  # Run inside the container
  eval "$CONTAINER_CMD_PREFIX" SAMBA_startup "$hf_tmp"
}
