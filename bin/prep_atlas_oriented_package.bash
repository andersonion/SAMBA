#!/usr/bin/env bash
# script to transform an image set from archived to WHS.
# WARNING: inputs have been given RAS nhdrs!
#   ALSO used samba package transforms and data for validation!
#
# For RAS header help see pipeline_utilities
#   prototype_template_nhdr_to_diffusion
#

# set dir of nhdrs referecing original images
# UGLY specific behavior for our current organization :p

#"R:\18.caron.01\191003-5-1\Slicer\N57647_ad.nhdr"

project_code="18.caron.01";
MDT_name="CaronC57";
spec_short="191003-5-1";
runno="N57647";


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
TEST_M="echo";
#normal mode
# TEST_M="";

# add ants tools to path(presuming ANTSPATH exists becuase you've got workstation_code set up.)
PATH="$ANTSPATH:$PATH";
atlas_image=$(cygpath -m $(find 'K:\workstation\data\atlas\chass_symmetric5' -iname '*dwi.nii.gz'));



# set dir full of samba tforms MESSY!
#Initial Transform dir, we moved them later.
#tdir=$(cygpath -m 'R:\${project_code}\${spec_short}\Slicer\SAMBA_transforms_and_validation_img\_rigid_WHS_transforms')
# Before beginning hand crafted the "RAS_to_WHS" transform stack from SAMBA package
tdir=$(cygpath -m ${out_pack}'\transforms\RAS_to_WHS')
if [ ! -d $out_pack_unmasked ];then mkdir $out_pack_unmasked; fi;
# set the two specific transforms we need.
SPECIMEN_to_MDT="$tdir/_1_${runno}_to_${MDT_name}_rigid.mat";
MDT_to_WHS="$tdir/_2_${MDT_name}_to_chass_symmetric4_affine.mat";
# put them in the transform chain var, Don't get confused,
# for ANTs they must be in reverse order.
transform_chain="-t \"$MDT_to_WHS\" -t \"$SPECIMEN_to_MDT\"";

cd $input_package;
#
# Generate atlas ref at appropriate vox size
#
first_input=$(cygpath -m $(find "$input_package" -iname "*_dwi.nhdr"));
vox_size="0.036";
vx_X2=$(awk "BEGIN{print $vox_size*2}");
# create blank image of atlas, saving as blank.nhdr
#Usage 1: CreateImage imageDimension referenceImage outputImage constant [random?]
#${vox_size:3}
atd=$(dirname $atlas_image);
#blank=$(cygpath -m "$input_package/blank.nhdr");
blank=$(cygpath -m "$atd/blank.nhdr");
#ref=$(cygpath -m "$input_package/ref.nhdr");
 # echo "${string//,/$'\n'}
ref=$(cygpath -m "$atd/ref_${vox_size//./p}mm.nhdr");
if [ ! -e "$ref" -a ! -e "$blank" ];then
	echo "Gen blank: $blank";
	CreateImage 3 $atlas_image "$blank" 0;
fi;
# IF using the specimen data "blank" to find comprehensive bounding box, we'd use warpimagemulti
#WarpImageMultiTransform ImageDimension moving_image output_image  --tightest-bounding-box --use-NN
#WarpImageMultitransform 3 $blank $ref --tightest-bounding-box --use-NN $MDT_to_WHS $SPECIMEN_to_MDT
# Insteaad we're gonna use the smaller atlas ref space.
#ResampleImageBySpacing  ImageDimension inputImageFile  outputImageFile outxspc outyspc {outzspacing}  {dosmooth?}  {addvox} {nn-interp?}
if [ ! -e "$ref" ];then
	echo "Gen ref: $ref"
	ResampleImageBySpacing 3 $blank $ref ${vox_size} ${vox_size} ${vox_size} 0 0 1;
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
SAMBAlabel=$(cygpath -m 'R:\${project_code}\${spec_short}\Slicer\SAMBA_transforms_and_validation_img\_rigid_WHS_transforms\${runno}_labels\WHS4\${runno}_WHS4_labels.nii.gz');
fn=${runno}_WHS4_labels.nhdr;
ld=$out_pack/labels/WHS4;
if [ ! -e $ld ];then mkdir -p $ld;fi;
# out file
of=$ld/$fn;
if [ ! -e $of ];then
	interp="MultiLabel[${vox_size},${vx_X2}]";
	#interp=NearestNeighbor
	echo "Gen labels: $labels";
	$TEST_M eval antsApplyTransforms -d 3 -e 0 -i $SAMBAlabel -o $of -r $ref -n $interp --float -u ushort $transform_chain -v
fi;

#
# create mask
#
ld=$out_pack/labels/WHS4;
labels=$of;# transformed labels
mask=$out_pack/${runno}_mask.nhdr;
if [ ! -e $mask ] ;then
	echo "Gen mask: $mask";
	$TEST_M ImageMath 3 $mask ReplaceVoxelValue $labels 1 65535 1; fi

#
# for each found input, apply transforms, and then mask
# NOW with Color!
#
for nhdr in $input_package/*nhdr; do
	fn=$(basename $nhdr);
	of=$out_pack_unmasked/$fn;
	IM_TYPE=0; # 0 SCALAR, 4 multi-channel(color)
	bit_depth=float;
	if [ ! -e $of ];then
		if echo $of|grep -c 'color' >& /dev/null;then IM_TYPE=4;bit_depth=uchar; fi;
		echo "Tform: $fn"
		$TEST_M eval antsApplyTransforms -d 3 -e $IM_TYPE -i $nhdr -o $of -r $ref -n Linear --float -u $bit_depth $transform_chain -v || break;
	fi;
	# mask image
	unmasked=$of;
	out_im=$out_pack/$fn;
	IM_DIM=3;
	OP=m
	if [ ! -e $out_im ];then
		if echo $of|grep -c 'color' >& /dev/null;
		then IM_DIM=4; OP=vm;
			echo "CANNOT MASK DATA DUE TO IMAGEMATH FAILURES. YOU WILL HAVE TO MASK MANUALLY VIA IMAGEJ(may need to adjust color order too)";
			sleep 5;
			continue;
		fi;
		echo "Mask: $fn";
		$TEST_M ImageMath $IM_DIM $out_im $OP $unmasked $mask|| break;	fi;
done
