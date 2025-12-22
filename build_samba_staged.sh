#!/usr/bin/env bash
set -euo pipefail

# --- user toggles (optional) ---
# FORCE=1          # rebuild even if image exists
# USE_FAKEROOT=1   # use --fakeroot instead of sudo
# ELEVATE=0        # do NOT use sudo for the build

: "${FORCE:=}"
: "${USE_FAKEROOT:=}"
: "${ELEVATE:=1}"

# Optional: override runtime explicitly
: "${SAMBA_CONTAINER_RUNTIME:=}"

# ===== Stages =====
# NOTE: stage name must match a file "<stage>.def"
STAGES=( base itk ants fsl_mcr final samba_python )

# ===== Images =====
# One output SIF per stage (same length/order as STAGES)
IMAGES=( base.sif itk.sif ants.sif fsl_mcr.sif semifinal.sif samba.sif )

if (( ${#STAGES[@]} != ${#IMAGES[@]} )); then
  echo "ERROR: STAGES and IMAGES arrays must be the same length" >&2
  echo "STAGES=${#STAGES[@]} IMAGES=${#IMAGES[@]}" >&2
  exit 2
fi

# ===== Normalize PATH if invoked via sudo (avoid secure_path surprises) =====
if [[ -n "${SUDO_USER-}" ]]; then
  case ":$PATH:" in
    *:/usr/local/bin:*) : ;;
    *) PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH" ;;
  esac
  export PATH
fi

# ===== Container runtime detection (Apptainer preferred) =====
CT=""
if [[ -n "${SAMBA_CONTAINER_RUNTIME}" ]]; then
  if [[ -x "${SAMBA_CONTAINER_RUNTIME}" ]]; then
    CT="${SAMBA_CONTAINER_RUNTIME}"
  else
    echo "ERROR: SAMBA_CONTAINER_RUNTIME set but not executable: ${SAMBA_CONTAINER_RUNTIME}" >&2
    exit 1
  fi
elif CT_BIN="$(command -v apptainer 2>/dev/null)"; then
  CT="$CT_BIN"
elif CT_BIN="$(command -v singularity 2>/dev/null)"; then
  CT="$CT_BIN"
else
  for cand in /usr/local/bin/apptainer /usr/bin/apptainer /usr/local/bin/singularity /usr/bin/singularity; do
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

stage_index() {
  local name="${1-}" i
  for i in "${!STAGES[@]}"; do
    [[ "${STAGES[$i]}" == "$name" ]] && { echo "$i"; return 0; }
  done
  echo -1
  return 1
}

build_stage() {
  local idx="$1"

  if (( idx < 0 || idx >= ${#STAGES[@]} )); then
    echo "ERROR: stage index $idx out of range" >&2
    return 2
  fi

  local name="${STAGES[$idx]}"
  local def="${name}.def"
  local img="${IMAGES[$idx]}"

  echo "=== Stage [$idx] $name ==="
  echo "DEF: $def"
  echo "SIF: $img"

  if [[ ! -f "$def" ]]; then
    echo "ERROR: missing def file: $def" >&2
    return 2
  fi

  # If this stage uses Bootstrap: localimage, ensure previous SIF exists
  if (( idx > 0 )); then
    local prev_img="${IMAGES[$((idx-1))]}"
    if [[ ! -f "$prev_img" ]]; then
      echo "ERROR: prerequisite image missing: $prev_img" >&2
      return 3
    fi
  fi

  if [[ -f "$img" && -z "${FORCE:-}" ]]; then
    echo "SKIP: $img already exists (set FORCE=1 to rebuild)"
    return 0
  fi

  local build_cmd=( "$CT" build )
  if [[ -n "${USE_FAKEROOT:-}" ]]; then
    build_cmd+=( --fakeroot )
  fi

  local runner=()
  if [[ "${ELEVATE:-1}" == "1" ]]; then
    runner=( sudo )
  fi

  local log="build_${name}.log"
  echo "LOG: $log"

  set +e
  ( time "${runner[@]}" "${build_cmd[@]}" "$img" "$def" ) 2>&1 | tee "$log"
  local rc=${PIPESTATUS[0]}
  set -e

  if (( rc != 0 )); then
    echo "FATAL: build failed for stage '$name' (rc=$rc). See $log" >&2
    return "$rc"
  fi

  echo "OK: built $img"
  return 0
}

START_INDEX=0
if [[ -n "$RESUME_FROM" ]]; then
  si="$(stage_index "$RESUME_FROM" || true)"
  if [[ "$si" == "-1" ]]; then
    echo "ERROR: Unknown stage '$RESUME_FROM'. Valid: ${STAGES[*]}" >&2
    exit 1
  fi
  START_INDEX="$si"
fi

for i in "${!STAGES[@]}"; do
  if (( i < START_INDEX )); then
    echo "--- Skipping ${STAGES[$i]} (resume from ${STAGES[$START_INDEX]})"
    continue
  fi
  build_stage "$i"
done

FINAL_IMG="${IMAGES[$((${#IMAGES[@]}-1))]}"
echo "All done. Final image: ./${FINAL_IMG}"
