#!/usr/bin/env bash
set -euo pipefail

# === Settings ===
STAGES=("base" "itk" "ants" "fsl_mcr" "final")
IMAGES=("base.sif" "itk.sif" "ants.sif" "fsl_mcr.sif" "samba.sif")

# Pick a container tool
# Prefer Apptainer, else Singularity; capture the actual binary path
# --- Container runtime detection (Apptainer preferred, then Singularity) ---

# Normalize PATH if running via sudo (avoid secure_path surprises)
if [ -n "${SUDO_USER-}" ]; then
  # Prepend a sane default if PATH is too minimal
  case ":$PATH:" in
    *:/usr/local/bin:*) : ;;
    *) PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH" ;;
  esac
  export PATH
fi

CT=""

# 1) Explicit override envs (let admins/users pin the binary)
if [ -n "${SAMBA_CONTAINER_RUNTIME-}" ] && [ -x "${SAMBA_CONTAINER_RUNTIME}" ]; then
  CT="${SAMBA_CONTAINER_RUNTIME}"
elif [ -n "${APPTAINER_PATH-}" ] && [ -x "${APPTAINER_PATH}" ]; then
  CT="${APPTAINER_PATH}"
elif [ -n "${SINGULARITY_PATH-}" ] && [ -x "${SINGULARITY_PATH}" ]; then
  CT="${SINGULARITY_PATH}"

# 2) Look in PATH
elif CT_BIN="$(command -v apptainer 2>/dev/null)"; then
  CT="$CT_BIN"
elif CT_BIN="$(command -v singularity 2>/dev/null)"; then
  CT="$CT_BIN"

# 3) Probe common install locations
else
  for cand in \
    /usr/local/bin/apptainer /usr/bin/apptainer \
    /usr/local/bin/singularity /usr/bin/singularity \
    /home/apps/ubuntu-22.04/singularity/bin/singularity
  do
    if [ -x "$cand" ]; then CT="$cand"; break; fi
  done
fi

if [ -z "${CT}" ]; then
  echo "ERROR: Could not find apptainer/singularity. PATH='$PATH'" >&2
  echo "Hint: set SAMBA_CONTAINER_RUNTIME or APPTAINER_PATH or SINGULARITY_PATH to the absolute binary." >&2
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
