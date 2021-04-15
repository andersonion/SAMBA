#!/usr/bin/env bash 
# snippet to transform one image to WHS.
echo "THIS IS A ONE OFF AND HAS BEEN COMPLETED";
exit 1;
# add ants tools to path(presuming ANTSPATH exists becuase you've got workstation_code set up.)
PATH="$ANTSPATH:$PATH";
# set dir of nhdrs referecing original images
out_dir=$(cygpath -m 'R:\18.caron.01\191001-3-1\Slicer');
out_dir_premask=$(cygpath -m 'R:\18.caron.01\191001-3-1\Slicer\unmasked');

# set dir full of samba tforms
#Initial Transform dir, we moved them later.
#tdir=$(cygpath -m 'R:\18.caron.01\191001-3-1\Slicer\SAMBA_transforms_and_validation_img\_rigid_WHS_transforms')
tdir=$(cygpath -m ${out_dir}'\transforms\RAS_to_WHS')
if [ ! -d $out_dir_premask ];then mkdir $out_dir_premask; fi;
nerdier=$(cygpath -m 'R:\18.caron.01\191001-3-1\Slicer\nhdr');
# set the two specific transforms we need.
SPECIMEN_to_MDT="$tdir/_1_N57642_to_CaronC57_rigid.mat";
MDT_to_WHS="$tdir/_2_CaronC57_to_chass_symmetric4_affine.mat";
# put them in the transform chain, Don't get confused, for ANTs they must be in reverse order.
transform_chain="-t \"$MDT_to_WHS\" -t \"$SPECIMEN_to_MDT\"";

atlas_image=$(cygpath -m $(find 'K:\workstation\data\atlas\chass_symmetric5' -iname '*dwi.nii.gz'));
first_input=$(cygpath -m $(find "$nerdier" -iname "*_dwi.nhdr"));
# create blank image of atlas, saving as blank.nhdr
#Usage 1: CreateImage imageDimension referenceImage outputImage constant [random?]
blank=$(cygpath -m "$nerdier/blank.nhdr");
if [ ! -e $blank ];then
	echo "Gen blank: $blank";
	CreateImage 3 $atlas_image $blank 0;
fi;
ref=$(cygpath -m "$nerdier/ref.nhdr");
# IF using the specimen data "blank" to find comprehensive bounding box, we'd use warpimagemulti
#WarpImageMultiTransform ImageDimension moving_image output_image  --tightest-bounding-box --use-NN  
#WarpImageMultitransform 3 $blank $ref --tightest-bounding-box --use-NN $MDT_to_WHS $SPECIMEN_to_MDT
# Insteaad we're gonna use the smaller atlas ref space.
#ResampleImageBySpacing  ImageDimension inputImageFile  outputImageFile outxspc outyspc {outzspacing}  {dosmooth?}  {addvox} {nn-interp?}
if [ ! -e $ref ];then
	echo "Gen ref: $ref"
	ResampleImageBySpacing 3 $blank $ref 0.036 0.036 0.036 0 0 1;
fi;
#
# Transform all to outdir.
#
# Start with the labels so we can get a mask.
SAMBAlabel=$(cygpath -m 'R:\18.caron.01\191001-3-1\Slicer\SAMBA_transforms_and_validation_img\_rigid_WHS_transforms\N57642_labels\WHS4\N57642_WHS4_labels.nii.gz');
fn=N57642_WHS4_labels.nhdr;
ld=$33333333/labels/WHS4;
if [ ! -e $ld ];then mkdir -p $ld;fi;
# out file
of=$ld/$fn;
if [ ! -e $of ];then 
	interp="MultiLabel[0.036,0.072]";
	#interp=NearestNeighbor
	echo "Gen labels: $labels";
	eval antsApplyTransforms -d 3 -e 0 -i $SAMBAlabel -o $of -r $ref -n $interp --float -u ushort $transform_chain -v
fi;

ld=$out_dir/labels/WHS4;
labels=$of;# transformed labels
mask=$out_dir/N57642_mask.nhdr;
if [ ! -e $mask ] ;then
	echo "Gen mask: $mask";
	ImageMath 3 $mask ReplaceVoxelValue $labels 1 65535 1; fi

for nhdr in $nerdier/*nhdr; do
	fn=$(basename $nhdr);
	of=$out_dir_premask/$fn;
	IM_TYPE=0; # 0 SCALAR, 4 multi-channel(color)
	bit_depth=float;
	if [ ! -e $of ];then 
		if echo $of|grep -c 'color' >& /dev/null;then IM_TYPE=4;bit_depth=uchar; fi;
		echo "Tform: $fn"
		eval antsApplyTransforms -d 3 -e $IM_TYPE -i $nhdr -o $of -r $ref -n Linear --float -u $bit_depth $transform_chain -v || break;
	fi;
	# mask image
	unmasked=$of;
	out_im=$out_dir/$fn;
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
		ImageMath $IM_DIM $out_im $OP $unmasked $mask|| break;	fi;
done
