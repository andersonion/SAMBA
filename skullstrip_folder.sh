#!/usr/bin/env bash

set -euo pipefail

# ==========================
# Usage
# ==========================
# skullstrip_folder.sh <input_folder> <output_folder>

INPUT_DIR="$1"
OUTPUT_DIR="$2"

mkdir -p "$OUTPUT_DIR"

echo "Input:  $INPUT_DIR"
echo "Output: $OUTPUT_DIR"
echo ""

# ==========================
# Loop through NIFTIs
# ==========================
find "$INPUT_DIR" -type f \( -name "*.nii" -o -name "*.nii.gz" \) | while read -r img
do
    base=$(basename "$img")
    base=${base%.nii}
    base=${base%.gz}

    echo "Processing $base"

    # --------------------------
    # FSL BET
    # --------------------------
    bet "$img" \
        "$OUTPUT_DIR/${base}_BET" \
        -R -f 0.3 -g 0 -m

    # --------------------------
    # ANTs Brain Extraction
    # --------------------------
    if command -v antsBrainExtraction.sh &> /dev/null
    then
        antsBrainExtraction.sh \
            -d 3 \
            -a "$img" \
            -e "$ANTSPATH/../templates/OASIS/T_template0.nii.gz" \
            -m "$ANTSPATH/../templates/OASIS/T_template0_BrainCerebellumProbabilityMask.nii.gz" \
            -o "$OUTPUT_DIR/${base}_ANTS_"
    fi

done

echo ""
echo "Finished skull stripping."