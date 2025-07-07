#!/usr/bin/env bash
# File: install_samba_pipe.sh

SRC_PATH="/full/path/to/samba_pipe_src.sh"  # <-- Customize this as needed
BASHRC="$HOME/.bashrc"

if ! grep -Fxq "source $SRC_PATH" "$BASHRC"; then
  echo "Adding source line to $BASHRC..."
  echo "" >> "$BASHRC"
  echo "# Load SAMBA container launcher" >> "$BASHRC"
  echo "source $SRC_PATH" >> "$BASHRC"
else
  echo "samba-pipe already configured in $BASHRC"
fi

echo "To activate now, run:"
echo "  source $SRC_PATH"
