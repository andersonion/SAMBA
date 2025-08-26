#!/usr/bin/env bash
# This file defines the samba-pipe function to launch SAMBA via Apptainer or Singularity

# === Locate the container image ===
if [[ -n "$SAMBA_CONTAINER_PATH" ]]; then
    SIF_PATH="$SAMBA_CONTAINER_PATH"
elif [[ -n "$SINGULARITY_IMAGE_DIR" && -f "$SINGULARITY_IMAGE_DIR/samba.sif" ]]; then
    SIF_PATH="$SINGULARITY_IMAGE_DIR/samba.sif"
elif [[ -f "$HOME/containers/samba.sif" ]]; then
    SIF_PATH="$HOME/containers/samba.sif"
elif [[ -f "/home/apps/singularity/images/samba.sif" ]]; then
    SIF_PATH="/home/apps/singularity/images/samba.sif"
else
    echo "Trying to locate samba.sif using find... (this may take a moment)"
    SEARCH_ROOT="${SAMBA_SEARCH_ROOT:-$HOME}"
    SIF_PATH=$(find "$SEARCH_ROOT" -type f -name "samba.sif" 2>/dev/null | head -n 1)

    if [[ -z "$SIF_PATH" ]]; then
        echo "ERROR: Could not locate samba.sif"
        echo "Set SAMBA_CONTAINER_PATH or place it in one of:"
        echo "  \$SINGULARITY_IMAGE_DIR/samba.sif"
        echo "  \$HOME/containers/samba.sif"
        echo "  /home/apps/singularity/images/samba.sif"
        return 1
    else
        echo "Found samba.sif at: $SIF_PATH"
    fi
fi

export SIF_PATH

# === Determine container runtime (Apptainer preferred) ===
if command -v apptainer &> /dev/null; then
    CONTAINER_CMD=apptainer
elif command -v singularity &> /dev/null; then
    CONTAINER_CMD=singularity
else
    echo "ERROR: Neither Apptainer nor Singularity found in PATH."
    return 1
fi

# === Define the samba-pipe function ===
function samba-pipe {
    local hf="$1"

    if [[ -z "$hf" ]]; then
        echo "Usage: samba-pipe headfile.hf"
        return 1
    fi

    # Make headfile absolute
    if [[ "${hf:0:1}" != "/" && "${hf:0:2}" != "~/" ]]; then
        hf="${PWD}/${hf}"
    fi

    # Auto-assign BIGGUS_DISKUS if not set
    if [[ -z "$BIGGUS_DISKUS" ]]; then
        if [[ -d "$SCRATCH" ]]; then
            export BIGGUS_DISKUS="$SCRATCH"
        elif [[ -d "$WORK" ]]; then
            export BIGGUS_DISKUS="$WORK"
        else
            export BIGGUS_DISKUS="$HOME/samba_scratch"
            mkdir -p "$BIGGUS_DISKUS"
        fi
    fi

    # Validate BIGGUS_DISKUS
    if [[ ! -d "$BIGGUS_DISKUS" || ! -w "$BIGGUS_DISKUS" ]]; then
        echo "ERROR: BIGGUS_DISKUS ('$BIGGUS_DISKUS') is not writable or does not exist."
        return 1
    fi

    # Optional group-writability warning
    if [[ ! -g "$BIGGUS_DISKUS" ]]; then
        echo "Warning: $BIGGUS_DISKUS is not group-writable. Multi-user workflows may fail."
    fi

    # Optional ATLAS_FOLDER binding
    local BIND_ATLAS=""
    if [[ -n "$ATLAS_FOLDER" && -d "$ATLAS_FOLDER" ]]; then
        BIND_ATLAS="--bind $ATLAS_FOLDER:$ATLAS_FOLDER"
    else
        echo "Warning: ATLAS_FOLDER not set or does not exist. Proceeding with default atlas."
    fi
    
    # Export for building $container_cmd in Perl
	export SAMBA_CONTAINER_RUNTIME="$CONTAINER_CMD";
	export SAMBA_SIF_PATH="$SIF_PATH";
	export SAMBA_ATLAS_BIND="$BIND_ATLAS";
	export SAMBA_BIGGUS_BIND="$BIGGUS_DISKUS:$BIGGUS_DISKUS";

	# === Headfile preparation ===
	
	# Resolve absolute path to the input headfile
	if [[ "${hf:0:1}" != "/" && "${hf:0:2}" != "~/" ]]; then
	  hf="${PWD}/${hf}"
	fi
	
	# Copy to /tmp with a unique name (user-specific and timestamped)
	hf_basename=$(basename "$hf")
	hf_tmp="/tmp/${USER}_samba_$(date +%s)_${hf_basename}"
	cp "$hf" "$hf_tmp"
	
	# === Build environment file for passing variables into container ===
	ENV_FILE=$(mktemp /tmp/samba_env.XXXXXX)
	
	# Detect and bind SLURM if available
	if command -v sbatch &>/dev/null; then
	  SLURM_BIN_DIR=$(dirname "$(which sbatch)")
	  BIND_SCHEDULER+=" --bind $SLURM_BIN_DIR:$SLURM_BIN_DIR"
	
	  # Handle SLURM_CONF
	  if [[ -n "$SLURM_CONF" && -f "$SLURM_CONF" ]]; then
		SLURM_CONF_DIR=$(dirname "$SLURM_CONF")
		BIND_SCHEDULER+=" --bind $SLURM_CONF_DIR:$SLURM_CONF_DIR"
		echo "SLURM_CONF=$SLURM_CONF" >> "$ENV_FILE"
	  elif [[ -f /etc/slurm/slurm.conf ]]; then
		export SLURM_CONF="/etc/slurm/slurm.conf"
		BIND_SCHEDULER+=" --bind /etc/slurm:/etc/slurm"
		echo "SLURM_CONF=$SLURM_CONF" >> "$ENV_FILE"
	  else
		echo "Warning: sbatch found but SLURM_CONF not set and default path missing."
	  fi
	fi

	# Detect and bind SGE if available
	if command -v qsub &>/dev/null; then
	  SGE_BIN_DIR=$(dirname "$(which qsub)")
	  BIND_SCHEDULER+=" --bind $SGE_BIN_DIR:$SGE_BIN_DIR"
	
	  if [[ -n "$SGE_ROOT" && -d "$SGE_ROOT" ]]; then
		BIND_SCHEDULER+=" --bind $SGE_ROOT:$SGE_ROOT"
		echo "SGE_ROOT=$SGE_ROOT" >> "$ENV_FILE"
	  fi
	fi


	# Export CONTAINER_CMD_PREFIX for reuse inside the container
	CONTAINER_CMD_PREFIX="$CONTAINER_CMD exec \
	  --env-file \"$ENV_FILE\" \
	  --bind \"$BIGGUS_DISKUS:$BIGGUS_DISKUS\" \
	  $BIND_ATLAS \
	  $BIND_SCHEDULER \
	  \"$SIF_PATH\""
	
	export CONTAINER_CMD_PREFIX
	
	# Write all relevant env vars to the env file
	for var in USER BIGGUS_DISKUS SIF_PATH ATLAS_FOLDER NOTIFICATION_EMAIL PIPELINE_QUEUE SLURM_RESERVATION CONTAINER_CMD_PREFIX; do
	  val="${!var}"
	  if [[ -n "$val" ]]; then
		echo "$var=$val" >> "$ENV_FILE"
	  fi
	done
	
	# Launch the container with the SAMBA_startup script inside the container
	# Note: This runs the container's internal SAMBA_startup, not this external samba-pipe function
	
	eval $CONTAINER_CMD_PREFIX SAMBA_startup "$hf_tmp"
