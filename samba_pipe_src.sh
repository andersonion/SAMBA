#!/usr/bin/env bash
# This file defines the samba-pipe function to launch SAMBA via Singularity

function samba-pipe {
	# Check for headfile input
	hf=$1
	if [[ -z "$hf" ]]; then
		echo "Usage: samba-pipe headfile.hf"
		return 1
	fi

	# Make headfile absolute if needed
	if [[ "${hf:0:1}" != "/" && "${hf:0:2}" != "~/" ]]; then
		hf="${PWD}/${hf}"
	fi

	# Auto-select BIGGUS_DISKUS if not set
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

	# Optional warning for group-writability
	if [[ ! -g "$BIGGUS_DISKUS" ]]; then
		echo "Warning: $BIGGUS_DISKUS is not group-writable. Multi-user workflows may fail."
	fi

	# Locate the container image
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
	
	# Optional binding for ATLAS_FOLDER
	BIND_ATLAS=""
	if [[ -n "$ATLAS_FOLDER" && -d "$ATLAS_FOLDER" ]]; then
		BIND_ATLAS="--bind $ATLAS_FOLDER:$ATLAS_FOLDER"
	else
		echo "Warning: ATLAS_FOLDER not set or does not exist. Proceeding with default mouse atlas data."
	fi


	# Launch the container
	singularity exec \
		--bind "$BIGGUS_DISKUS:$BIGGUS_DISKUS" \
		--bind "$(dirname $hf):$(dirname $hf)" \
		$BIND_ATLAS \
		"$SIF_PATH" \
		bash -c "export BIGGUS_DISKUS=$BIGGUS_DISKUS; samba-pipe $hf"
}