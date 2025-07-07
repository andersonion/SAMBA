#!/usr/bin/env bash
# File: install_samba_pipe.sh

# Resolve the directory where this script lives
INSTALL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Define the full path to the source file
SAMBA_PIPE_SRC="${INSTALL_DIR}/samba_pipe_src.sh"

# Check that the file exists
if [[ ! -f "$SAMBA_PIPE_SRC" ]]; then
    echo "ERROR: Expected samba_pipe_src.sh in the same directory as install script, but not found."
    exit 1
fi

# Add to ~/.bashrc if not already present
if ! grep -Fxq "source $SAMBA_PIPE_SRC" ~/.bashrc; then
    echo "" >> ~/.bashrc
    echo "# Load SAMBA pipe launcher" >> ~/.bashrc
    echo "source $SAMBA_PIPE_SRC" >> ~/.bashrc
    echo "Added source command to ~/.bashrc"
else
    echo "samba_pipe_src.sh already sourced in ~/.bashrc"
fi
