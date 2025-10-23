#!/usr/bin/env bash
set -euo pipefail

# === Settings ===
STAGES=("base" "itk" "ants" "fsl_mcr" "final")
IMAGES=("base.sif" "itk.sif" "ants.sif" "fsl_mcr.sif" "samba.sif")

# Pick a container tool
# Prefer Apptainer, else Singularity; capture the actual binary path
CT=""
if CT_BIN="$(command -v apptainer 2>/dev/null)"; then
  CT="$CT_BIN"
elif CT_BIN="$(command -v singularity 2>/dev/null)"; then
  CT="$CT_BIN"
fi

if [ -z "$CT" ]; then
  echo "ERROR: Neither Apptainer nor Singularity found in PATH." >&2
  exit 1
fi
echo "Using container runtime: $CT"

# Flags
FORCE_FROM="${1:-}"   # usage: ./build_samba_staged.sh [stage-name-to-rebuild-from]
BUILD_DIR="${BUILD_DIR:-.}"

# Helper to build one stage
build_stage () {
  local idx="$1" name="${STAGES[$idx]}" img="${IMAGES[$idx]}"
  local def="${name}.def"

  echo "=== [${idx}/${#STAGES[@]}] Building ${name} -> ${img} ==="
  time sudo "$CT" build "${BUILD_DIR}/${img}" "${def}"
  echo "=== OK: ${img} ==="
}

# Resolve rebuild-from index (if any)
START_INDEX=0
if [[ -n "$FORCE_FROM" ]]; then
  for i in "${!STAGES[@]}"; do
    if [[ "${STAGES[$i]}" == "$FORCE_FROM" ]]; then START_INDEX="$i"; break; fi
  done
fi

# Build loop with resume semantics
for i in "${!STAGES[@]}"; do
  if (( i < START_INDEX )); then
    echo "--- Skipping ${STAGES[$i]} (resume from ${STAGES[$START_INDEX]})"
    continue
  fi
  build_stage "$i"
done

echo "All done. Final image: ${BUILD_DIR}/samba.sif"
