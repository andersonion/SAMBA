#!/usr/bin/env bash
#
# Source this file to get the `samba-pipe` function in your shell.

# ----------------------------------------------------------------------
# Container command & image (override via env if desired)
# ----------------------------------------------------------------------
: "${CONTAINER_CMD:=/home/apps/ubuntu-22.04/singularity/bin/singularity}"
: "${SIF_PATH:=/home/apps/ubuntu-22.04/singularity/images/samba.sif}"

# Optional: default atlas inside the container (can be overridden by env)
: "${ATLAS_FOLDER:=/opt/atlases/chass_symmetric3}"

# You can also export NOTIFICATION_EMAIL, PIPELINE_QUEUE, SLURM_RESERVATION
# in your own shell/profile; we just pass them through if set.

# ----------------------------------------------------------------------
# Build EXTRA_BINDS: host GLIBC + Slurm bits
# ----------------------------------------------------------------------
declare -a EXTRA_BINDS=()

# 1) Host GLIBC / core system libs
#    We bind these so host-compiled Slurm tools (sbatch, squeue, etc.)
#    see the host's libc and libstdc++ instead of the container's older ones.
if [[ -d /lib/x86_64-linux-gnu ]]; then
  EXTRA_BINDS+=( --bind /lib/x86_64-linux-gnu:/lib/x86_64-linux-gnu )
fi

if [[ -d /usr/lib/x86_64-linux-gnu ]]; then
  EXTRA_BINDS+=( --bind /usr/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu )
fi

# 2) Slurm client binaries (sbatch, squeue, scancel, etc.)
#    Prefer /usr/local/bin if that’s where you install Slurm, otherwise
#    fall back to whatever `command -v sbatch` finds.
if [[ -x /usr/local/bin/sbatch ]]; then
  EXTRA_BINDS+=( --bind /usr/local/bin:/usr/local/bin )
elif command -v sbatch >/dev/null 2>&1; then
  sbatch_path="$(command -v sbatch)"
  sbatch_dir="$(dirname "$sbatch_path")"
  EXTRA_BINDS+=( --bind "$sbatch_dir":"$sbatch_dir" )
fi

# 3) Slurm config
if [[ -d /etc/slurm ]]; then
  EXTRA_BINDS+=( --bind /etc/slurm:/etc/slurm )
fi

# 4) Slurm libs (your libslurmfull.so lives here)
if [[ -d /usr/local/lib/slurm ]]; then
  EXTRA_BINDS+=( --bind /usr/local/lib/slurm:/usr/local/lib/slurm )
fi

# ----------------------------------------------------------------------
# Main user-facing entry point: samba-pipe
# ----------------------------------------------------------------------
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
  local var val
  for var in USER BIGGUS_DISKUS SIF_PATH ATLAS_FOLDER NOTIFICATION_EMAIL \
             PIPELINE_QUEUE SLURM_RESERVATION CONTAINER_CMD_PREFIX; do
    val="${!var:-}"
    if [[ -n "$val" ]]; then
      printf '%s=%s\n' "$var" "$val" >> "$ENV_FILE"
    fi
  done

  # Run inside the container
  eval "$CONTAINER_CMD_PREFIX" SAMBA_startup "$hf_tmp"
}
