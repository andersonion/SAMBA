#!/usr/bin/env bash
#
# SAMBA container wrapper:
#   source this file, then use:
#       samba-pipe /path/to/headfile.hf
#
# This wrapper:
#   - figures out BIGGUS_DISKUS
#   - auto-binds atlas folder if ATLAS_FOLDER is set
#   - auto-binds Slurm bits + host glibc/lib dirs (Option 2)
#   - builds a singularity exec prefix and launches SAMBA_startup inside the container.

# ----------------------------------------------------------------------
# Container command + image
# ----------------------------------------------------------------------

# Allow caller to override, otherwise pick reasonable defaults.
: "${CONTAINER_CMD:=singularity}"

# If SIF_PATH isn’t set, try some typical locations (last one wins if multiple exist).
if [[ -z "${SIF_PATH:-}" ]]; then
    if [[ -f "/home/apps/ubuntu-22.04/singularity/images/samba.sif" ]]; then
        SIF_PATH="/home/apps/ubuntu-22.04/singularity/images/samba.sif"
    elif [[ -f "/opt/containers/samba.sif" ]]; then
        SIF_PATH="/opt/containers/samba.sif"
    elif [[ -f "/opt/samba/samba.sif" ]]; then
        SIF_PATH="/opt/samba/samba.sif"
    fi
fi

if [[ -z "${SIF_PATH:-}" ]]; then
    echo "ERROR: SIF_PATH is not set and samba.sif could not be autodetected." >&2
    echo "       Please export SIF_PATH=/full/path/to/samba.sif and re-source this file." >&2
fi

export CONTAINER_CMD
export SIF_PATH

# ----------------------------------------------------------------------
# Extra bind detection (Slurm + host libs: Option 2)
# ----------------------------------------------------------------------

# Use a bash array so we can append safely.
declare -a EXTRA_BINDS=()

# --- Slurm-related binds (host → container) ---

# Slurm config.
if [[ -d /etc/slurm ]]; then
    EXTRA_BINDS+=( --bind /etc/slurm:/etc/slurm )
fi

# sbatch/scancel etc. Often in /usr/local/bin, sometimes /usr/bin.
if command -v sbatch >/dev/null 2>&1; then
    # Prefer binding /usr/local/bin if it exists.
    if [[ -d /usr/local/bin ]]; then
        EXTRA_BINDS+=( --bind /usr/local/bin:/usr/local/bin )
    fi
    # If sbatch lives in /usr/bin and you want to be extra-safe, you could also bind that,
    # but usually /usr/bin inside the container is fine. Uncomment if needed:
    # if [[ -d /usr/bin ]]; then
    #     EXTRA_BINDS+=( --bind /usr/bin:/usr/bin )
    # fi
fi

# Slurm plugin/libs.
if [[ -d /usr/local/lib/slurm ]]; then
    EXTRA_BINDS+=( --bind /usr/local/lib/slurm:/usr/local/lib/slurm )
elif [[ -d /usr/lib/slurm ]]; then
    EXTRA_BINDS+=( --bind /usr/lib/slurm:/usr/lib/slurm )
fi

# --- Option 2: host glibc + system libs (critical for sbatch GLIBC errors) ---

# On Ubuntu / Debian-style systems.
if [[ -d /lib/x86_64-linux-gnu ]]; then
    EXTRA_BINDS+=( --bind /lib/x86_64-linux-gnu:/lib/x86_64-linux-gnu )
fi

if [[ -d /usr/lib/x86_64-linux-gnu ]]; then
    EXTRA_BINDS+=( --bind /usr/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu )
fi

# Optionally, if you ever need RHEL-style dirs on another cluster:
# if [[ -d /lib64 ]]; then
#     EXTRA_BINDS+=( --bind /lib64:/lib64 )
# fi
# if [[ -d /usr/lib64 ]]; then
#     EXTRA_BINDS+=( --bind /usr/lib64:/usr/lib64 )
# fi

# Allow user to inject additional binds via a plain string env var:
#   export SAMBA_EXTRA_BINDS="--bind /foo:/foo --bind /bar:/bar"
if [[ -n "${SAMBA_EXTRA_BINDS:-}" ]]; then
    # shellcheck disable=SC2206
    ADDL=( ${SAMBA_EXTRA_BINDS} )
    EXTRA_BINDS+=( "${ADDL[@]}" )
fi

export EXTRA_BINDS

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

  # Warn if directory is not group-writable (more accurate than -g/setgid).
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

  # Build command prefix (include BIGGUS & HF dir binds, atlas, slurm + glibc binds)
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
  for var in USER BIGGUS_DISKUS SIF_PATH ATLAS_FOLDER \
             NOTIFICATION_EMAIL PIPELINE_QUEUE SLURM_RESERVATION \
             CONTAINER_CMD_PREFIX; do
    val="${!var:-}"
    if [[ -n "$val" ]]; then
      printf '%s=%s\n' "$var" "$val" >> "$ENV_FILE"
    fi
  done

  # Finally run inside the container
  eval "$CONTAINER_CMD_PREFIX" SAMBA_startup "$hf_tmp"
}
