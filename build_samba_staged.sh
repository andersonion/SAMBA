#!/usr/bin/env bash
set -euo pipefail


# --- user toggles (optional) ---
# FORCE=1          # rebuild even if image exists
# USE_FAKEROOT=1   # use --fakeroot instead of sudo
# ELEVATE=0        # do NOT use sudo for the build

# Example: export from env or set defaults here
: "${FORCE:=}"         # empty by default
: "${USE_FAKEROOT:=}"  # empty by default
: "${ELEVATE:=1}"      # default to sudo



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
  local idx="$1"
  # Basic arg/sanity checks
  if [[ -z "${idx:-}" ]]; then
    echo "ERROR: build_stage <index> required" >&2
    return 2
  fi
  if (( idx < 0 || idx >= ${#STAGES[@]} )); then
    echo "ERROR: stage index $idx out of range" >&2
    return 2
  fi

  local name="${STAGES[$idx]}"
  # Allow DEFS[] to be optional; fall back to "<stage>.def"
  local def="${DEFS[$idx]:-${name}.def}"
  local img="${IMAGES[$idx]}"

  echo "=== Stage [$idx] $name ==="
  echo "DEF: $def"
  echo "SIF: $img"

  # If this stage uses Bootstrap: localimage, make sure previous SIF exists
  if (( idx > 0 )); then
    local prev_img="${IMAGES[$((idx-1))]}"
    if [[ ! -f "$prev_img" ]]; then
      echo "ERROR: prerequisite image missing: $prev_img" >&2
      echo "Hint: run previous stages or set START_INDEX accordingly." >&2
      return 3
    fi
  fi

  # Skip if target image already exists (unless FORCE=1)
  if [[ -f "$img" && -z "${FORCE:-}" ]]; then
    echo "SKIP: $img already exists (set FORCE=1 to rebuild)"
    return 0
  fi

  # Build command (supports fakeroot + optional sudo elevation)
  local build_cmd=( "$CT" build )
  if [[ -n "${USE_FAKEROOT:-}" ]]; then
    build_cmd+=( --fakeroot )
  fi

  # Some environments need sudo; default ELEVATE=1 (on) unless set to 0
  local runner=()
  if [[ "${ELEVATE:-1}" == "1" ]]; then
    runner=( sudo )
  fi

  # Do the build with timing
  set -o pipefail
  time "${runner[@]}" "${build_cmd[@]}" "$img" "$def" |& tee "build_${name}.log"
  local rc=${PIPESTATUS[0]}
  if (( rc != 0 )); then
    echo "FATAL: build failed for stage '$name' (rc=$rc)" >&2
    return "$rc"
  fi
  echo "OK: built $img"
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
