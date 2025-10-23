#!/usr/bin/env bash
set -euo pipefail

# ===== Stages =====
STAGES=( base itk ants fsl_mcr final )
IMAGES=( base.sif itk.sif ants.sif fsl_mcr.sif samba.sif )

# ===== Container runtime detection (Apptainer preferred) =====
# Normalize PATH if invoked via sudo (avoid secure_path surprises)
if [[ -n "${SUDO_USER-}" ]]; then
  case ":$PATH:" in
    *:/usr/local/bin:*) : ;;
    *) PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH" ;;
  esac
  export PATH
fi

CT=""
if [[ -n "${SAMBA_CONTAINER_RUNTIME-}" && -x "${SAMBA_CONTAINER_RUNTIME}" ]]; then
  CT="${SAMBA_CONTAINER_RUNTIME}"
elif CT_BIN="$(command -v apptainer 2>/dev/null)"; then
  CT="$CT_BIN"
elif CT_BIN="$(command -v singularity 2>/dev/null)"; then
  CT="$CT_BIN"
else
  # common site paths fallback
  for cand in \
    /usr/local/bin/apptainer /usr/bin/apptainer \
    /usr/local/bin/singularity /usr/bin/singularity \
    /home/apps/ubuntu-22.04/singularity/bin/singularity
  do
    if [[ -x "$cand" ]]; then CT="$cand"; break; fi
  done
fi

if [[ -z "$CT" ]]; then
  echo "ERROR: Neither apptainer nor singularity found in PATH ($PATH)" >&2
  exit 1
fi
echo "Using container runtime: $CT"

# ===== Args =====
# Optional: ./build_samba_staged.sh [stage-name-to-rebuild-from]
RESUME_FROM="${1-}"  # empty means build all from start

# Map a stage name to its index in STAGES array; echoes index or -1
stage_index() {
  local name="${1-}" i
  for i in "${!STAGES[@]}"; do
    [[ "${STAGES[$i]}" == "$name" ]] && { echo "$i"; return 0; }
  done
  echo -1
  return 1
}

# Build one stage by numeric index (0..N-1)
build_stage() {
  local idx="${1-}"
  if [[ -z "$idx" ]]; then
    echo "INTERNAL: build_stage requires an index" >&2
    exit 1
  fi

  # Bounds check
  if (( idx < 0 || idx >= ${#STAGES[@]} )); then
    echo "INTERNAL: stage index out of range: $idx" >&2
    exit 1
  fi

  local name="${STAGES[$idx]}"
  local img="${IMAGES[$idx]}"
  local def="${name}.def"

  if [[ ! -f "$def" ]]; then
    echo "ERROR: Missing definition file: $def" >&2
    exit 1
  fi

  echo "=== [$(($idx+1))/${#STAGES[@]}] Building ${name} -> ${img} ==="
  time sudo "$CT" build "./${img}" "./${def}"
  echo "=== OK: ${img} ==="
}

# ===== Determine starting index =====
START_INDEX=0
if [[ -n "$RESUME_FROM" ]]; then
  si="$(stage_index "$RESUME_FROM" || true)"
  if [[ "$si" == "-1" ]]; then
    echo "ERROR: Unknown stage '$RESUME_FROM'. Valid: ${STAGES[*]}" >&2
    exit 1
  fi
  START_INDEX="$si"
fi

# ===== Build loop =====
for i in "${!STAGES[@]}"; do
  if (( i < START_INDEX )); then
    echo "--- Skipping ${STAGES[$i]} (resume from ${STAGES[$START_INDEX]})"
    continue
  fi
  build_stage "$i"
done

echo "All done. Final image: ./samba.sif"
