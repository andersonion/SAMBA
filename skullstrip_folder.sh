#!/usr/bin/env bash
set -uo pipefail

usage() {
    cat <<EOF
Usage:
    $(basename "$0") INPUT_DIR [OUTPUT_DIR] [--methods bet,ants,afni,synthstrip,hdbet] [--bet-f 0.30]

Description:
    Run skull-stripping methods across all .nii / .nii.gz files in INPUT_DIR
    and save ONLY the resulting brain masks.

Arguments:
    INPUT_DIR      Folder containing input NIfTI files
    OUTPUT_DIR     Optional output folder
                   Default: INPUT_DIR/skullstrip_masks

Options:
    --methods      Comma-separated list of methods to run
                   Default: bet,ants,afni,synthstrip,hdbet
    --bet-f        BET fractional intensity threshold
                   Default: 0.30
    -h, --help     Show this help

ANTs:
    If using ANTs, set:
        export ANTS_TEMPLATE=/path/to/T_template0.nii.gz
        export ANTS_MASK=/path/to/T_template0_BrainCerebellumProbabilityMask.nii.gz

Examples:
    $(basename "$0") /path/to/input
    $(basename "$0") /path/to/input /path/to/output
    $(basename "$0") /path/to/input /path/to/output --methods bet,afni,synthstrip
    $(basename "$0") /path/to/input --methods bet,ants --bet-f 0.25
EOF
}

if [[ $# -lt 1 ]]; then
    usage
    exit 1
fi

INPUT_DIR="$1"
shift

OUTPUT_DIR=""
if [[ $# -gt 0 && "${1:0:2}" != "--" ]]; then
    OUTPUT_DIR="$1"
    shift
else
    OUTPUT_DIR="${INPUT_DIR%/}/skullstrip_masks"
fi

METHODS="bet,ants,afni,synthstrip,hdbet"
BET_F="0.30"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --methods)
            METHODS="$2"
            shift 2
            ;;
        --bet-f)
            BET_F="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 2
            ;;
    esac
done

ANTS_TEMPLATE="${ANTS_TEMPLATE:-}"
ANTS_MASK="${ANTS_MASK:-}"

mkdir -p "$OUTPUT_DIR"/{bet,ants,afni,synthstrip,hdbet,logs,tmp}

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

run_bet() {
    local img="$1"
    local stem="$2"
    local logbase="$3"

    if ! have_cmd bet; then
        echo "  [BET] not found"
        return 0
    fi

    local tmpbase="$OUTPUT_DIR/tmp/${stem}_BET_tmp"

    bet "$img" "$tmpbase" -R -f "$BET_F" -g 0 -m \
        > "${logbase}.bet.stdout" \
        2> "${logbase}.bet.stderr"
    local status=$?

    if [[ $status -ne 0 ]]; then
        echo "  [BET] failed"
        rm -f "${tmpbase}"*.nii "${tmpbase}"*.nii.gz
        return 0
    fi

    if [[ -f "${tmpbase}_mask.nii.gz" ]]; then
        mv -f "${tmpbase}_mask.nii.gz" "$OUTPUT_DIR/bet/${stem}_BET_mask.nii.gz"
    elif [[ -f "${tmpbase}_mask.nii" ]]; then
        mv -f "${tmpbase}_mask.nii" "$OUTPUT_DIR/bet/${stem}_BET_mask.nii"
    else
        echo "  [BET] failed to produce mask"
    fi

    rm -f "${tmpbase}.nii.gz" "${tmpbase}.nii"
    echo "  [BET] ok"
    return 0
}

run_ants() {
    local img="$1"
    local stem="$2"
    local logbase="$3"

    if ! have_cmd antsBrainExtraction.sh; then
        echo "  [ANTs] not found"
        return 0
    fi

    if [[ ! -f "$ANTS_TEMPLATE" || ! -f "$ANTS_MASK" ]]; then
        echo "  [ANTs] skipped (set valid ANTS_TEMPLATE and ANTS_MASK)"
        return 0
    fi

    local outprefix="$OUTPUT_DIR/tmp/${stem}_ANTS_"

    antsBrainExtraction.sh \
        -d 3 \
        -a "$img" \
        -e "$ANTS_TEMPLATE" \
        -m "$ANTS_MASK" \
        -o "$outprefix" \
        > "${logbase}.ants.stdout" \
        2> "${logbase}.ants.stderr"
    local status=$?

    if [[ $status -ne 0 ]]; then
        echo "  [ANTs] failed"
        rm -f "$OUTPUT_DIR/tmp/${stem}_ANTS_"*
        return 0
    fi

    local ants_mask="${outprefix}BrainExtractionMask.nii.gz"
    if [[ -f "$ants_mask" ]]; then
        mv -f "$ants_mask" "$OUTPUT_DIR/ants/${stem}_ANTS_mask.nii.gz"
        rm -f "$OUTPUT_DIR/tmp/${stem}_ANTS_"*
        echo "  [ANTs] ok"
    else
        echo "  [ANTs] failed to produce mask"
        rm -f "$OUTPUT_DIR/tmp/${stem}_ANTS_"*
    fi

    return 0
}

run_afni() {
    local img="$1"
    local stem="$2"
    local logbase="$3"

    if ! have_cmd 3dSkullStrip; then
        echo "  [AFNI] 3dSkullStrip not found"
        return 0
    fi

    if ! have_cmd 3dcalc; then
        echo "  [AFNI] 3dcalc not found"
        return 0
    fi

    local tmpbrain="$OUTPUT_DIR/tmp/${stem}_AFNI_brain.nii.gz"
    local outmask="$OUTPUT_DIR/afni/${stem}_AFNI_mask.nii.gz"

    3dSkullStrip \
        -input "$img" \
        -prefix "$tmpbrain" \
        > "${logbase}.afni.stdout" \
        2> "${logbase}.afni.stderr"
    local status=$?

    if [[ $status -ne 0 ]]; then
        echo "  [AFNI] failed"
        rm -f "$tmpbrain"
        return 0
    fi

    3dcalc \
        -a "$tmpbrain" \
        -expr 'step(a)' \
        -prefix "$outmask" \
        >> "${logbase}.afni.stdout" \
        2>> "${logbase}.afni.stderr"
    status=$?

    rm -f "$tmpbrain"

    if [[ $status -ne 0 ]]; then
        echo "  [AFNI] failed to produce mask"
    else
        echo "  [AFNI] ok"
    fi

    return 0
}

run_synthstrip() {
    local img="$1"
    local stem="$2"
    local logbase="$3"

    local tmpbrain="$OUTPUT_DIR/tmp/${stem}_SynthStrip_brain.nii.gz"
    local outmask="$OUTPUT_DIR/synthstrip/${stem}_SynthStrip_mask.nii.gz"

    if have_cmd mri_synthstrip; then
        mri_synthstrip \
            -i "$img" \
            -o "$tmpbrain" \
            -m "$outmask" \
            > "${logbase}.synthstrip.stdout" \
            2> "${logbase}.synthstrip.stderr"
    elif have_cmd synthstrip; then
        synthstrip \
            -i "$img" \
            -o "$tmpbrain" \
            -m "$outmask" \
            > "${logbase}.synthstrip.stdout" \
            2> "${logbase}.synthstrip.stderr"
    else
        echo "  [SynthStrip] not found"
        return 0
    fi

    local status=$?
    rm -f "$tmpbrain"

    if [[ $status -ne 0 ]]; then
        echo "  [SynthStrip] failed"
    else
        echo "  [SynthStrip] ok"
    fi

    return 0
}

run_hdbet() {
    local img="$1"
    local stem="$2"
    local logbase="$3"

    local tmpbase="$OUTPUT_DIR/tmp/${stem}_HDBET"
    local outmask="$OUTPUT_DIR/hdbet/${stem}_HDBET_mask.nii.gz"

    if have_cmd hd-bet; then
        hd-bet \
            -i "$img" \
            -o "$tmpbase" \
            -device cpu \
            > "${logbase}.hdbet.stdout" \
            2> "${logbase}.hdbet.stderr"
    elif have_cmd hd_bet; then
        hd_bet \
            -i "$img" \
            -o "$tmpbase" \
            -device cpu \
            > "${logbase}.hdbet.stdout" \
            2> "${logbase}.hdbet.stderr"
    else
        echo "  [HD-BET] not found"
        return 0
    fi

    local status=$?
    if [[ $status -ne 0 ]]; then
        echo "  [HD-BET] failed"
        rm -f "${tmpbase}"*.nii "${tmpbase}"*.nii.gz
        return 0
    fi

    # HD-BET commonly emits a mask alongside the output with a _mask suffix.
    local found_mask=""
    for candidate in \
        "${tmpbase}_mask.nii.gz" \
        "${tmpbase}_mask.nii" \
        "${tmpbase}.nii.gz_mask.nii.gz" \
        "${tmpbase}.nii_mask.nii.gz"
    do
        if [[ -f "$candidate" ]]; then
            found_mask="$candidate"
            break
        fi
    done

    if [[ -n "$found_mask" ]]; then
        mv -f "$found_mask" "$outmask"
        rm -f "${tmpbase}"*.nii "${tmpbase}"*.nii.gz
        echo "  [HD-BET] ok"
    else
        echo "  [HD-BET] failed to produce mask"
        rm -f "${tmpbase}"*.nii "${tmpbase}"*.nii.gz
    fi

    return 0
}

IFS=',' read -r -a METHOD_LIST <<< "$METHODS"

echo "Input:   $INPUT_DIR"
echo "Output:  $OUTPUT_DIR"
echo "Methods: $METHODS"
echo ""

find "$INPUT_DIR" -maxdepth 1 -type f \( -name "*.nii" -o -name "*.nii.gz" \) | sort | while read -r img; do
    bn="$(basename "$img")"
    stem="$bn"
    stem="${stem%.nii.gz}"
    stem="${stem%.nii}"
    logbase="$OUTPUT_DIR/logs/$stem"

    echo "Processing $bn"

    for method in "${METHOD_LIST[@]}"; do
        case "$method" in
            bet)
                run_bet "$img" "$stem" "$logbase"
                ;;
            ants)
                run_ants "$img" "$stem" "$logbase"
                ;;
            afni)
                run_afni "$img" "$stem" "$logbase"
                ;;
            synthstrip)
                run_synthstrip "$img" "$stem" "$logbase"
                ;;
            hdbet)
                run_hdbet "$img" "$stem" "$logbase"
                ;;
            *)
                echo "  [WARN] unknown method: $method"
                ;;
        esac
    done

    echo ""
done

rmdir "$OUTPUT_DIR/tmp" 2>/dev/null || true
echo "Done."