#!/usr/bin/env bash
# script to transform an image set from archived to WHS.
# WARNING: inputs have been given RAS++ nhdrs!
#   ALSO used samba package transforms and data for validation!
#
# For RAS header help see pipeline_utilities
#   prototype_template_nhdr_to_diffusion
#   The "best" headers are RAS + samba manipulations

# This is currently organization specific! that should be enhanced!
# set dir of nhdrs referecing original images
# UGLY specific behavior for our current organization :p

#"R:\18.caron.01\191003-5-1\Slicer\N57647_ad.nhdr"

project_code="19.gaj.43";
#spec_short="200302-1_1";
#runno="N58211NLSAM";
#spec_ref_pad=20
# N58211NLSAM required padding on output

# MDT_name not in current use
#MDT_name="${runno}Rig";

#spec_short="190415-2_1";
#runno="N57205NLSAM";

#spec_short="190108-5_1";
#runno="N58678NLSAM";

#spec_short="200803-12_1";
#runno="N58668NLSAM";

spec_short=$1;
runno=$2;
spec_ref_pad=$3;

#Testmode
#TEST_M="echo";
#normal mode
#TEST_M="";

if [ -z "$spec_ref_pad" ];then
    # our nlsam data are SOOO tightly cropped we fall out of image when we rotate to atlas.
    # Use 0 for no-pad ref(from blank)
    spec_ref_pad=0;
fi;
# should get cooler about finding and fiddling the vox size...
vox_size="0.015";
label_nick="RCCF";

echo "ANTS versino matters! 2021-06-26 required!";
echo "Check correct -> $(which antsRegistration)";

# BETTER inputs
# "input package"
# "unmasked package"(optional) otherwise auto ends up as sub part of curation.
# "curation package"

spec_dir='R:\'"${project_code}"'\'"${spec_short}";
#input_package=$(cygpath -m "$spec_dir"'\Slicer\nhdr');
input_package=$(cygpath -m "$spec_dir"'\Non-Aligned-Data\nhdr');
#input_package=$(cygpath -m 'R:\19.gaj.43\190108-5_1\slicer');
out_pack=$(cygpath -m "$spec_dir"'\Aligned-Data');
out_pack_slicer=$(cygpath -m "$spec_dir"'\Slicer');
# prevent replicatation from old format
if [ -e $out_pack_slicer ];then out_pack=$out_pack_slicer;fi;

out_pack_unmasked=$(cygpath -m "$spec_dir"'\Aligned-Data\Other\unmasked');
# deactivate masking NEED to make this optional...
# Presumably if we have "NLSAM" data we want mask off... maybe we want it more often?
out_pack_unmasked=$out_pack;
other_pack="$out_pack/Other";

###
# Pre-flight feedback
if [ ! -e "$spec_dir" ];then
    echo "Bad input: missing $spec_dir";
    exit 1;
fi;
echo "generate $out_pack";
if [ $out_pack != $out_pack_unmasked ];then
    echo "will leave unmasked in $out_pack_unmasked";
fi;
echo "starting with $input_package";
if [ "$spec_ref_pad" -gt 0 ];then
    echo "using specimen specific padding: $spec_ref_pad";
fi;

if [ "$TEST_M" != "echo" ];then
    echo "short pause before we continue"
    sleep 8;
fi;
###


# add ants tools to path(presuming ANTSPATH exists becuase you've got workstation_code set up.)
# WHICH COMICALLY, DOESN'T SET THIS IN WINDOWS
PATH="$ANTSPATH:$PATH";

# This is to create a reference image.
# THIS IS TERRIBLY CRUDE.
# for the set currently hard coded, a cooler ref was hand crafted which tightly cropped the data.
#input_ref=$(cygpath -m $(find 'K:\workstation\data\atlas\symmetric15um' -iname '*dwi.n*'));
input_ref='DEFUNCT';


# set dir full of samba tforms MESSY!
#Initial Transform dir, we moved them later.
#tdir=$(cygpath -m 'R:\${project_code}\${spec_short}\Slicer\SAMBA_transforms_and_validation_img\_rigid_WHS_transforms')
# Before beginning hand crafted the "RAS_to_WHS" transform stack from SAMBA package
#tdir=$(cygpath -m ${out_pack}'\transforms\RAS_to_WHS')

# WARNING!!!
# !BLARG! This did the wrong job!!!
# The mdt-> atlas has scaling in it! blowing us up!
# New lookup will remove any affines!
# BUT this is NOT a good transform chain!
# WARNING!!!
#tdir=$(cygpath -m 'R:\${project_code}\${spec_short}\slicer\SAMBA_biggus\SAMBA_pack\${runno}\transforms\${runno}_to_symmetric15um');
tdir=$(cygpath -m '${out_pack}\Other\transforms\${runno}_nativenhdr_to_chass_symmetric5') || exit 1;

tdir=$(eval echo $tdir);
if [ ! -d $out_pack_unmasked ];then mkdir $out_pack_unmasked; fi;
# set the two specific transforms we need.
# WAIT A MINUTE! Affine is WRONG we would ONLY WANT RIGID! We DO NOT want scale etc transforms!!!
#SPECIMEN_to_MDT="$tdir/_1_${runno}_to_${MDT_name}_rigid.mat";
#MDT_to_WHS="$tdir/_2_${MDT_name}_to_chass_symmetric4_affine.mat";
# put them in the transform chain var, Don't get confused,
# for ANTs they must be in reverse order.
#transform_chain="-t \"$MDT_to_WHS\" -t \"$SPECIMEN_to_MDT\"";
# get chain the easy way... wait... this includes warps! blergh!!!
#transform_chain=$(for t in $(ls -r $tdir/_*); do echo "-t $t";done)
# lets strip warps :D
# Also this is ready-made for WarpImageMultiTransform not antsApplyTransforms
# We fix that latter by inserting the -t's.
transform_chain=$(ls -r $tdir/_*|grep -vie '(warp|affine)');

cd $input_package;
#
# Generate a ref at appropriate vox size(supposing we dont have it yet)
#
# Need help for "custom ref" support.
# will use spec_ref bool to use specimen specific reference space
vx_X2=$(awk "BEGIN{print $vox_size*2}");
vx_X3=$(awk "BEGIN{print $vox_size*3}");
vx_0p5=$(awk "BEGIN{print $vox_size/2}");
vx_0p333=$(awk "BEGIN{print $vox_size/3}");
# create blank of in proper ref space(at OUR voxel size), saving as blank.nhdr
#Usage 1: CreateImage imageDimension referenceImage outputImage constant [random?]
#${vox_size:3}
first_input=$(cygpath -m $(find "$input_package" -iname "*_dwi.nhdr"));
if [  -e "$input_ref" ]; then
    spec_ref=0;
    ref_pack=$(dirname $input_ref);
    if [ "$spec_ref_pad" -gt 0 ];then
        echo "Warning: ref padding requested but we're using atlas reference! That is probably a mistake"
        exit 1;
    fi;
else
    spec_ref=1;
    ref_pack="$out_pack"
    aligned_other="$ref_pack/Other";
    if [ ! -e $aligned_other ];then
        mkdir $aligned_other;
    fi;
    ref_pack="$aligned_other";
    input_ref="$first_input";
fi;

#blank=$(cygpath -m "$input_package/blank.nhdr");
blank=$(cygpath -m "$ref_pack/blank.nhdr");
#ref=$(cygpath -m "$input_package/ref.nhdr");
 # echo "${string//,/$'\n'}
ref=$(cygpath -m "$ref_pack/ref_${vox_size//./p}mm.nhdr");
refX2=$(cygpath -m "$ref_pack/ref_${vx_0p5//./p}mm.nhdr");
refX3=$(cygpath -m "$ref_pack/ref_${vx_0p333//./p}mm.nhdr");
# FIND CUSTOM REFERENCE!
# Some kinda auto-cropping should be made standard!
# decided that our custom ref will be placed into "ref_pack"
# AND THAT ref_pack is outpack for custom ref!
#if [ -e $input_package/ref.nhdr -o $spec_ref -eq 1 ];then
#    ref=$input_package/ref.nhdr;
#    refX2="$input_package/ref_${vx_0p5//./p}mm.nhdr";
#    refX3="$input_package/ref_${vx_0p333//./p}mm.nhdr";
#fi;

b_input=$(cygpath -m "$input_package/blank_input.nhdr");
if [ ! -e "$ref" -a ! -e "$blank" ];then
    echo "Gen blank: $blank";
    if [ $spec_ref -eq 0 ];then
        $TEST_M CreateImage 3 $input_ref "$blank" 0;
    else
        $TEST_M CreateImage 3 $input_ref "$b_input" 0;
        #b_orient=$(cygpath -m "$ref_pack/blank_orient.nhdr");
        d=3;
        #WarpImageMultitransform $d $b_input $b_orient --use-NN --reslice-by-header  --tightest-bounding-box;
        # for now we'll do this instead of adding cropping.
        #WarpImageMultitransform $d $b_input $blank --use-NN --reslice-by-header  --tightest-bounding-box;
        $TEST_M WarpImageMultitransform $d $b_input $blank $transform_chain --use-NN --tightest-bounding-box;
        # Could insert ants crop via  ExtractRegionFromImage
    fi;
fi;
transform_chain=$(for t in $transform_chain; do echo "-t $t";done)
# IF using the specimen data "blank" to find comprehensive bounding box, we'd use WarpImageMultitransform
#WarpImageMultiTransform ImageDimension moving_image output_image  --tightest-bounding-box --use-NN
#WarpImageMultitransform 3 $blank $ref --tightest-bounding-box --use-NN $MDT_to_WHS $SPECIMEN_to_MDT
# It's nice to use the smaller ref space, atlas/specimen...
#ResampleImageBySpacing  ImageDimension inputImageFile  outputImageFile outxspc outyspc {outzspacing}  {dosmooth?}  {addvox} {nn-interp?}

pad_record="$ref_pack/ref_padding.log";
if [ "$spec_ref" -ge 1 -a ! -e "$pad_record" ];then
    # This is only active when using a specimen reference, but we'll still specify what data.
    # In theory we could find optimal padding by:
    #   looping until good, preparing the labels,
    #   checking if there any voxels in the exterior(5?)
    #   pad by at least 5, and try again...
    # could get more intelligent on amount to pad by using a maxwidth measurement of original,
    # that would probably allow us to at most loop 3 times...
    key="${spec_short}_${runno}_pad";
    prev_pad="$spec_ref_pad";
    spec_pad_written=0;
    if [ -e "$pad_record" ];then
        prev_pad=$(grep "$key" |cut -d '=' -f2);
        if [ ! -z "$prev_pad" ];then
            spec_pad_written=1;
        fi;
    fi;
    if [ "$spec_ref_pad" -ne "$prev_pad"  ];then
        echo "ERROR refernce padding change! That is probably a mistake!";
        echo "You asked for: $spec_ref_pad, but we found: $prev_pad";
        echo "    file:$ref, + ref_padding.log";
        exit 1;
    fi;
    if [ ! -e "$pad_record" -o "$spec_pad_written" -lt 1 ] && [ "$TEST_M" != "echo" ];then
        echo "${key}=${spec_ref_pad}" |tee -a "$pad_record";
    fi;
fi;

if [ ! -e "$ref" ];then
    echo "Gen ref: $ref"
    $TEST_M ResampleImageBySpacing 3 $blank $ref ${vox_size} ${vox_size} ${vox_size} 0 $spec_ref_pad 1;
fi;

# x2 as in 2x spatial res, but the var setup is confusing
gen_refx2=$(find $input_package/ -maxdepth 1 -iname "*x2*"|wc -l);
if [ ! -e "$refX2" -a $gen_refx2 -gt 0 ];then
    echo "Gen refX2: $refX2"
    $TEST_M ResampleImageBySpacing 3 $ref $refX2 ${vx_0p5} ${vx_0p5} ${vx_0p5} 0 0 1;
fi;
# x3 as in 3x spatial res, but the var setup is confusing
gen_refx3=$(find $input_package/ -maxdepth 1 -iname "*x3*"|wc -l);
if [ ! -e "$refX3" -a $gen_refx3 -gt 0 ];then
    echo "Gen refX3: $refX3"
    $TEST_M ResampleImageBySpacing 3 $ref $refX3 ${vx_0p333} ${vx_0p333} ${vx_0p333} 0 0 1;
fi;

#
# clean out the blank we dont need any more.
#
if [ -e "$ref" -a ! -z "$blank" -a -e "$blank" ];then
    rm -v "$blank" "${blank%.*}.raw" "${blank%.*}.raw.gz";
fi;
if [ -e "$ref" -a ! -z "$b_input" -a -e "$b_input" ];then
    rm -v "$b_input" "${b_input%.*}.raw" "${b_input%.*}.raw.gz";
fi;

#
# Transform all to outdir.
#
# Starting with the labels so we can convert it to a mask for remainder.
#SAMBAlabel=$(cygpath -m 'R:\${project_code}\${spec_short}\Slicer\SAMBA_transforms_and_validation_img\_rigid_WHS_transforms\${runno}_labels\${label_nick}\${runno}_${label_nick}_labels.nii.gz');
#SAMBAlabel=$(cygpath -m 'R:\${project_code}\${spec_short}\slicer\SAMBA_biggus\SAMBA_pack\${runno}\labels\${label_nick}\${runno}_${label_nick}_labels.nhdr');
#SAMBAlabel=$(eval echo $SAMBAlabel)

# plumbing a samba pack is probably a bad idea... lets hope for labels in our package.
fn=${runno}_${label_nick}_labels.nhdr;
SAMBAlabel=$(find $input_package -maxdepth 1 -iname "$fn"|head -n1);
if [ ! -e "$SAMBAlabel" -o -z "$SAMBAlabel" ];then
    echo "Label not found in $input_package (${runno}_${label_nick}_labels)";
    echo "    (please link any custom label name to the defacto name)"; exit 1;fi;
while [ -L "$SAMBAlabel" -a -e "$SAMBAlabel" ];do
    SAMBAlabel=$(readlink $SAMBAlabel);
    fn=$(basename $SAMBAlabel);
done;
# NOT updateing label_nick in the case of tricky linkity loos becuase that is too hard to generalize.
# Perhaps there will be future inspiration.
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
m_input=$other_pack/${runno}_lbl_mask.nhdr;
if [ ! -d $other_pack ];then
    $TEST_m mkdir $other_pack;
fi;
mask=$other_pack/${runno}_mask.nhdr;
maskX2=$other_pack/${runno}_mask${vx_0p5//./p}mm.nhdr;
maskX3=$other_pack/${runno}_mask${vx_0p333//./p}mm.nhdr;
if [ ! -e $mask -a -e "$labels" ] ;then
    echo "Gen mask: $mask";
    $TEST_M ImageMath 3 $m_input ReplaceVoxelValue $labels 1 65535 1;
    $TEST_M ImageMath 3 $mask MD $m_input 5
    fi
if [ -e "$mask" -a ! -z "$m_input" -a -e "$m_input" ];then
    rm -v "$m_input" "${m_input%.*}.raw" "${m_input%.*}.raw.gz";
fi;
if [ ! -e $maskX2 -a -e "$mask" -a $gen_refx2 -gt 0 ] ;then
    echo "Gen maskX2: $maskX2";
    $TEST_M ResampleImageBySpacing 3 $mask $maskX2 ${vx_0p5} ${vx_0p5} ${vx_0p5} 0 0 1;
fi
if [ ! -e $maskX3 -a -e "$mask" -a $gen_refx3 -gt 0  ] ;then
    echo "Gen maskX3: $maskX3";
    $TEST_M ResampleImageBySpacing 3 $mask $maskX3 ${vx_0p333} ${vx_0p333} ${vx_0p333} 0 0 1;
fi

#
# for each found input, apply transforms, and then mask
# NOW with Color!
#
refX1=$ref;
maskX1=$mask;

# Because color is a constant thorn, split them.
# going UGLY parallel here becuase matlab forces a wait, bad form but okay with loads of memory
for inc in $input_package/*color.nhdr; do
    fn="$(basename $inc)";
    of=$out_pack_unmasked/$fn;
    if [ -e "$of" ];then
        echo "    $of found, presuming good enough";
        continue;
    fi;
    # first try with complex grep to ignore the component channels in input didnt work,
    # went more explicit instead.
    #isColor="$(echo $fn|grep -icE 'color(^_?(red|green|blue))?' )"
    isColor="$(echo $fn|grep -viE 'red|green|blue' |grep -icE 'color' )"
    if [ $isColor -lt 1 ];then
        echo "Skip $fn"; continue; fi;
    n="$(basename $inc)";
    outc="$(dirname $inc)/${n%.*}";
    (cd "$WKS_SHARED/pipeline_utilities"; $TEST_M matlab -batch "i='$inc';o='$outc';image_channel_split(i,o); quit;" )&
done

if [ "$TEST_M" != "echo" -a $(jobs |wc -l ) -gt 0 ];then
    echo "Waiting for matlab image_channel_split calls to complete"
    # due to some kinda high-speed run through issues the wait was stuck forever
    # this while was hopped to solve it, but didnt work out immediately
    #while [ $(jobs|wc -l) -ge 1 ]; do sleep 1; done
    wait;
fi;

# Could switch this to a find based loop to catch
# deeper files, eg while read line; do ... done < <(find blarg -iname "*nhdr");
for nhdr in $input_package/*nhdr; do
    ref=$refX1
    mask=$maskX1;
    fn=$(basename $nhdr);
    of=$out_pack_unmasked/$fn;
    echo "# check $fn";
    skip=$(echo $fn|grep -cE 'ref|template|blank')
    interp="Linear";
    isLabel=$(echo $fn|grep -icE 'label')
    isSpecial=$(echo $fn|grep -v 'color'|grep -cE 'tdi|tdi')
    # first try with complex grep to ignore the component channels in input didnt work,
    # went more explicit instead.
    #isColor="$(echo $fn|grep -icE 'color(^_?(red|green|blue))?' )"
    isColor="$(echo $fn|grep -viE 'red|green|blue' |grep -icE 'color' )"
    if [ $isLabel -ge 1 ];then
        interp="MultiLabel[${vox_size},${vx_X2}]";
        of=$out_pack/labels/${label_nick}/$fn;
    fi;
    if [ $isColor -ge 1 -o $skip -ge 1 ];then
        echo "#    SKIPPING"; continue; fi;
    # this is/was neat, but it made output silent,
    # making it more of a pain to inspect.
    #if [ "$TEST_M" == "echo" ];then
    #  process_script=$input_package/process_${fn%.*}.bash
    #  #exec 1>&3
    #  exec 1>$process_script
    #  exec 2>&1
    #fi;
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
        if echo $of|grep -c 'color' >& /dev/null;then bit_depth=uchar; fi;
        if [ $isColor -ge 1 ]; then IM_TYPE=4;bit_depth=uchar; fi;
            echo "#    Tform"
            $TEST_M eval antsApplyTransforms -d 3 -e $IM_TYPE -i $nhdr -o $of -r $ref -n $interp --float -u $bit_depth $transform_chain -v || continue;
    fi;
    #
    # cleanup operations
    #
    unmasked=$of;
    nhdr=$unmasked;
    IM_DIM=3;
    # normalize "special" images
    # tdi floats "need" to be noramlized for reasonable display.
    # it'd be nice to log scale them, but we're missing the terminal tool for that.
    if [ $isSpecial -ge 1 -a $isColor -le 0 ];then
        of=$out_pack_unmasked/NORM1_$fn;
        if [ ! -e $of -o $nhdr -nt $of ];then
            echo "#    norm1";
            $TEST_M ImageMath $IM_DIM $of Normalize $nhdr || continue; fi;
        n1=$of;
        nhdr=$n1;
        of=$out_pack_unmasked/NORM65k_$fn
        if [ ! -e $of -o $nhdr -nt $of ];then
            echo "#    norm65k";
            $TEST_M ImageMath $IM_DIM $of m $nhdr 65535|| continue; fi;
        n65k=$of;
        nhdr=$n65k;
    fi;
    # mask image, this is defacto disabled by setting mask_pack equal to out_pack.
    of=$out_pack/$fn;
    OP=m
    if [ ! -e $of -o $nhdr -nt $of ] && [ $isLabel -le 0 ];then
        if [  $isColor -ge 1 ];then
            IM_DIM=4; OP=vm;
            echo "# CANNOT MASK DATA DUE TO IMAGEMATH FAILURES. YOU WILL HAVE TO MASK MANUALLY VIA IMAGEJ(may need to adjust color order too)";
            sleep 5;
            continue;
        fi;
        echo "#    Mask";
        $TEST_M ImageMath $IM_DIM $of $OP $nhdr $mask|| continue;
    fi;
    #exec 3>&1
    #echo "EARLY EXIT for just do one"
    #exit 1
done

for nhdr in $input_package/*.nhdr; do
    fn=$(basename $nhdr);
    of="$out_pack/$fn";
    tmp="$out_pack/${fn%.*}.nhdrtmp";
    of_red="$out_pack/${fn%.*}_red.nhdr";
    isColor="$(echo $fn|grep -viE 'red|green|blue' |grep -icE 'color' )"
    if [ $isColor -ge 1 ];then
        echo "# color check $fn";
        if [ ! -e $of_red ];then
            echo "#    skip $of because no $of_red";
            continue;
        fi;
        if [ ! -e $of ]; then
            echo "#    gen nhdr from $of_red +green +blue";
            sed -E 's/dimension: 3/dimension: 4/' $of_red > $tmp || continue;
            sed -Ei 's/(sizes: .*)/\1 3/' $tmp || continue;
            sed -Ei'' 's/(space directions.*)/\1 none/' $tmp || continue;
            sed -Ei'' 's/(kinds.*)/\1 RGB-color/' $tmp || continue;
            sed -Ei'' 's/(data[ ]?file:).*/\1 LIST 4/' $tmp || continue;
            (cd $out_pack; ls ${fn%.*}_red*raw* >> $tmp) || continue;
            (cd $out_pack; ls ${fn%.*}_green*raw* >> $tmp) || continue;
            (cd $out_pack; ls ${fn%.*}_blue*raw* >> $tmp) || continue;
            mv $tmp $of;
        else
            echo "#    existing";
        fi;
    fi;
done
