#!/usr/bin/env bash
# script to transform an image set from archived to WHS.
# WARNING: inputs have been given RAS++ nhdrs!
#   ALSO used samba package transforms and data for validation!
#
# For RAS header help see pipeline_utilities
#   prototype_template_nhdr_to_diffusion
#   The headers are RAS + samba manipulations

# set dir of nhdrs referecing original images
# UGLY specific behavior for our current organization :p

#"R:\18.caron.01\191003-5-1\Slicer\N57647_ad.nhdr"

project_code="19.gaj.43";
spec_short="190415-2_1";
runno="N57205NLSAM";
MDT_name="${runno}Rig";

label_nick=RCCF

# BETTER inputs
# "input package"
# "unmasked package"(optional) otherwise auto ends up as sub part of curation.
# "curation package"

spec_dir='R:\'"${project_code}"'\'"${spec_short}";
input_package=$(cygpath -m "$spec_dir"'\Slicer\nhdr');
out_pack=$(cygpath -m "$spec_dir"'\Slicer');
out_pack_unmasked=$(cygpath -m "$spec_dir"'\Slicer\unmasked');

echo "generate $out_pack";
echo "will leave unmasked in $out_pack_unmasked";
echo "starting with $input_package";

#Testmode
#TEST_M="echo";
#normal mode
#TEST_M="";

# add ants tools to path(presuming ANTSPATH exists becuase you've got workstation_code set up.)
PATH="$ANTSPATH:$PATH";

# This is to create a reference image.
# THIS IS TERRIBLY CRUDE.
# for the set currently hard coded, a cooler ref was hand crafted which tightly cropped the data.
#atlas_image=$(cygpath -m $(find 'K:\workstation\data\atlas\symmetric15um' -iname '*dwi.n*'));
atlas_image='DEFUNCT';



# set dir full of samba tforms MESSY!
#Initial Transform dir, we moved them later.
#tdir=$(cygpath -m 'R:\${project_code}\${spec_short}\Slicer\SAMBA_transforms_and_validation_img\_rigid_WHS_transforms')
# Before beginning hand crafted the "RAS_to_WHS" transform stack from SAMBA package
#tdir=$(cygpath -m ${out_pack}'\transforms\RAS_to_WHS')
tdir=$(cygpath -m 'R:\${project_code}\${spec_short}\slicer\SAMBA_biggus\SAMBA_pack\${runno}\transforms\${runno}_to_symmetric15um');
tdir=$(eval echo $tdir);
if [ ! -d $out_pack_unmasked ];then mkdir $out_pack_unmasked; fi;
# set the two specific transforms we need.
#SPECIMEN_to_MDT="$tdir/_1_${runno}_to_${MDT_name}_rigid.mat";
#MDT_to_WHS="$tdir/_2_${MDT_name}_to_chass_symmetric4_affine.mat";
# put them in the transform chain var, Don't get confused,
# for ANTs they must be in reverse order.
#transform_chain="-t \"$MDT_to_WHS\" -t \"$SPECIMEN_to_MDT\"";
# get chain the easy way... wait... this includes warps! blergh!!!
#transform_chain=$(for t in $(ls -r $tdir/_*); do echo "-t $t";done)
# lets strip warps :D
transform_chain=$(for t in $(ls -r $tdir/_*|grep -vi warp); do echo "-t $t";done)

cd $input_package;
#
# Generate atlas ref at appropriate vox size
#
first_input=$(cygpath -m $(find "$input_package" -iname "*_dwi.nhdr"));
vox_size="0.015";
vx_X2=$(awk "BEGIN{print $vox_size*2}");
vx_X3=$(awk "BEGIN{print $vox_size*3}");
vx_0p5=$(awk "BEGIN{print $vox_size/2}");
vx_0p333=$(awk "BEGIN{print $vox_size/3}");
# create blank image of atlas, saving as blank.nhdr
#Usage 1: CreateImage imageDimension referenceImage outputImage constant [random?]
#${vox_size:3}
atd=$(dirname $atlas_image);
#blank=$(cygpath -m "$input_package/blank.nhdr");
blank=$(cygpath -m "$atd/blank.nhdr");
#ref=$(cygpath -m "$input_package/ref.nhdr");
 # echo "${string//,/$'\n'}
ref=$(cygpath -m "$atd/ref_${vox_size//./p}mm.nhdr");
refX2=$(cygpath -m "$atd/ref_${vx_0p5//./p}mm.nhdr");
refX3=$(cygpath -m "$atd/ref_${vx_0p333//./p}mm.nhdr");
# FIND CUSTOM REFERENCE!
# Some kinda auto-cropping should be made standard!
if [ -e $input_package/ref.nhdr ];then
    ref=$input_package/ref.nhdr;
    refX2="$input_package/ref_${vx_0p5//./p}mm.nhdr";
    refX3="$input_package/ref_${vx_0p333//./p}mm.nhdr";
fi;

if [ ! -e "$ref" -a ! -e "$blank" ];then
    echo "Gen blank: $blank";
    $TEST_M CreateImage 3 $atlas_image "$blank" 0;
fi;
# IF using the specimen data "blank" to find comprehensive bounding box, we'd use warpimagemulti
#WarpImageMultiTransform ImageDimension moving_image output_image  --tightest-bounding-box --use-NN
#WarpImageMultitransform 3 $blank $ref --tightest-bounding-box --use-NN $MDT_to_WHS $SPECIMEN_to_MDT
# Insteaad we're gonna use the smaller atlas ref space.
#ResampleImageBySpacing  ImageDimension inputImageFile  outputImageFile outxspc outyspc {outzspacing}  {dosmooth?}  {addvox} {nn-interp?}
if [ ! -e "$ref" ];then
    echo "Gen ref: $ref"
    $TEST_M ResampleImageBySpacing 3 $blank $ref ${vox_size} ${vox_size} ${vox_size} 0 0 1;
fi;
if [ ! -e "$refX2" ];then
    echo "Gen refX2: $refX2"
    $TEST_M ResampleImageBySpacing 3 $ref $refX2 ${vx_0p5} ${vx_0p5} ${vx_0p5} 0 0 1;
fi;
if [ ! -e "$refX3" ];then
    echo "Gen refX3: $refX3"
    $TEST_M ResampleImageBySpacing 3 $ref $refX3 ${vx_0p333} ${vx_0p333} ${vx_0p333} 0 0 1;
fi;

#
# clean out the blank we dont need any more.
#
if [ ! -z "$blank" -a -e "$blank" ];then
    rm -v "$blank" "${blank%.*}.raw";
fi;

#
# Transform all to outdir.
#
# Starting with the labels so we can convert it to a mask for remainder.
#SAMBAlabel=$(cygpath -m 'R:\${project_code}\${spec_short}\Slicer\SAMBA_transforms_and_validation_img\_rigid_WHS_transforms\${runno}_labels\${label_nick}\${runno}_${label_nick}_labels.nii.gz');
SAMBAlabel=$(cygpath -m 'R:\${project_code}\${spec_short}\slicer\SAMBA_biggus\SAMBA_pack\${runno}\labels\${label_nick}\${runno}_${label_nick}_labels.nhdr');
SAMBAlabel=$(eval echo $SAMBAlabel)
fn=${runno}_${label_nick}_labels.nhdr;
ld=$out_pack/labels/${label_nick};
# out file
of=$ld/$fn;
if [ ! -e $of -a -e "$SAMBAlabel" ];then
    if [ ! -e $ld ];then $TEST_M mkdir -p $ld;fi;
    interp="MultiLabel[${vox_size},${vx_X2}]";
    #interp=NearestNeighbor
    echo "Gen labels: $labels";
    $TEST_M eval antsApplyTransforms -d 3 -e 0 -i $SAMBAlabel -o $of -r $ref -n $interp --float -u ushort $transform_chain -v
fi;

#
# create mask
#
labels=$of;# transformed labels
mask=$out_pack/${runno}_mask.nhdr;
maskX2=$out_pack/${runno}_mask${vx_0p5//./p}mm.nhdr;
maskX3=$out_pack/${runno}_mask${vx_0p333//./p}mm.nhdr;
if [ ! -e $mask -a -e "$labels" ] ;then
    echo "Gen mask: $mask";
    $TEST_M ImageMath 3 $mask ReplaceVoxelValue $labels 1 65535 1; fi
if [ ! -e $maskX2 -a -e "$mask" ] ;then
    echo "Gen maskX2: $maskX2";
    $TEST_M ResampleImageBySpacing 3 $mask $maskX2 ${vx_0p5} ${vx_0p5} ${vx_0p5} 0 0 1; fi
if [ ! -e $maskX3 -a -e "$mask" ] ;then
    echo "Gen maskX3: $maskX3";
    $TEST_M ResampleImageBySpacing 3 $mask $maskX3 ${vx_0p333} ${vx_0p333} ${vx_0p333} 0 0 1; fi

#
# for each found input, apply transforms, and then mask
# NOW with Color!
#
refX1=$ref;
maskX1=$mask;


for nhdr in $input_package/*tdiX3_color*nhdr; do
    ref=$refX1
    mask=$maskX1;
    fn=$(basename $nhdr);
    of=$out_pack_unmasked/$fn;
    skip=$(echo $fn|grep -cE 'ref|template')
    if [ $skip -ge 1 ];then
        echo "#SKIPPING $fn";
        continue;
    fi;
    if [ "$TEST_M" == "echo" ];then
      process_script=$input_package/process_${fn%.*}.bash
      #exec 1>&3
      exec 1>$process_script
      exec 2>&1
    fi;
    echo "#Transforming and processing $fn";
    rX2=$(echo $fn|grep -cE 'tdiX2|tdi2')
    rX3=$(echo $fn|grep -cE 'tdiX3|tdi3')
    if [ $rX2 -ge 1 ];then
        ref=$refX2;
        mask=$maskX2;
    elif [ $rX3 -ge 1 ];then
        ref=$refX3;
        mask=$maskX3;
    fi;
    IM_TYPE=0; # 0 SCALAR, 4 multi-channel(color)
    bit_depth=float;
    if [ ! -e $of -o $nhdr -nt $of ];then
        if echo $of|grep -c 'color' >& /dev/null;then IM_TYPE=4;bit_depth=uchar; fi;
        echo "#Tform: $fn"
        $TEST_M eval antsApplyTransforms -d 3 -e $IM_TYPE -i $nhdr -o $of -r $ref -n Linear --float -u $bit_depth $transform_chain -v || break;
    fi;
    #
    # cleanup operations
    #
    unmasked=$of;
    nhdr=$unmasked;
    IM_DIM=3;
    # normalize "special" images
    # tdi floats need to be noramlized for reasonable display.
    isSpecial=$(echo $fn|grep -cE 'tdi|tdi')
    isColor=$(echo $fn|grep -icE 'color')
    if [ $isSpecial -ge 1 -a $isColor -le 0 ];then
        of=$out_pack_unmasked/NORM1_$fn;
        if [ ! -e $of -o $nhdr -nt $of ];then
            $TEST_M ImageMath $IM_DIM $of Normalize $nhdr || break; fi;
        n1=$of;

        nhdr=$n1;
        of=$out_pack_unmasked/NORM65k_$fn
        if [ ! -e $of -o $nhdr -nt $of ];then
            $TEST_M ImageMath $IM_DIM $of m $nhdr 65535|| break; fi;
        n65k=$of;

        nhdr=$n65k;
        fi;
    # mask image
    of=$out_pack/$fn;
    OP=m
    if [ ! -e $of -o $nhdr -nt $of ];then
        if echo $of|grep -c 'color' >& /dev/null;
        then IM_DIM=4; OP=vm;
            echo "# CANNOT MASK DATA DUE TO IMAGEMATH FAILURES. YOU WILL HAVE TO MASK MANUALLY VIA IMAGEJ(may need to adjust color order too)";
            sleep 5;
            continue;
        fi;
        echo "# Mask: $fn";
        $TEST_M ImageMath $IM_DIM $of $OP $nhdr $mask|| break;    fi;
    #exec 3>&1
done
