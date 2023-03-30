#!/usr/bin/env perl
#extra step ls *.final.nii; get runnos within directory 
#use 5.014;	# so push/pop/etc work on scalars (experimental)
use warnings;
use strict;

#use Posix; # Not sure why, but it seems like a good idea.
use English; # "America! Heck, yeah!"
use File::Path qw(make_path remove_tree);
require pipeline_utilities;

# generic includes
use Cwd qw(abs_path);
use File::Basename;
use lib dirname(abs_path($0));
use Env qw(RADISH_PERL_LIB);
if (! defined($RADISH_PERL_LIB)) {
    print STDERR "Cannot find good perl directories, quitting\n";
    exit;
}

use lib split(':',$RADISH_PERL_LIB);


my $VERSION = "141022";

my $ANTSPATH = $ENV{'ANTSPATH'};
my $LOCALPATH = "/glusterspace/androsspace/hess/";
my $INPATH_prefix = "/glusterspace/cretespace/hess_vbmpipe_test/";
my ($SOURCEPATH,$INPATH,$in_file,$out_file,$source_name,$ref_file,$warp_file,$affine_file,$current_path);

my $commando;
my @commando_list_1;
my @commando_list_2;
my $annotation_1 = "Registering secondary channels for VBM";
my $annotation_2 = "Averaging secondary channels for VBM";

my $dim = 3; 
my $source_ch = "fa"; 			# Channel used to generate MDT.
my $source_ch_uc = uc($source_ch); 	# Uppercase version of $source_ch for file directory naming purposes.
my @moving_ch=qw(T2star); 		# Channels to which to apply transforms.
my $registered_ch = "T2star";  		# Channel 1 from seg_pipeline.
my $current_ch_uc;
my $new_control_ch_uc;
my $current_outpath;
my $optional_tensor_midfix='';
my $warp_suffix = "avg_Warp.nii";
my $affine_suffix = "initial_Affine.txt";
my $name_suffix = "reg2_${registered_ch}_strip_reg2_whs";


if (1) {
    $optional_tensor_midfix = "_DTI";
}

foreach my $new_control_ch (@moving_ch) {
	$new_control_ch_uc = uc($new_control_ch);
	$current_outpath = "$LOCALPATH/CTRL_${new_control_ch_uc}";
	make_path($current_outpath); 
}

my @runnos = qw( N40310 N40320 N40340 N40350); # N40370 N40270); # Change this to be a function input or part of command line.

foreach my $current_runno (@runnos) {
    my @cr = split('',$current_runno);
    pop(@cr);
    my $cr = join('',@cr);
    my $current_runno_8 = $cr."8";

    foreach my $current_ch (@moving_ch) {

	$current_ch_uc = uc($current_ch);
	$current_outpath = "$LOCALPATH/CTRL_${current_ch_uc}";

	$source_name = "${current_runno}${optional_tensor_midfix}_${source_ch}_${name_suffix}";

	$SOURCEPATH = "$LOCALPATH/CTRL_${source_ch_uc}";
	$INPATH = "${INPATH_prefix}/${current_runno_8}Labels-results";
	$current_outpath = "$LOCALPATH/CTRL_${new_control_ch_uc}/";
	
	if ($current_ch ne $registered_ch) {		# The following is a flawed conditional that is attempting to account for 2 diff’t conditions: 1) Is current_ch the same as registered_ch? and 2) Is current_ch a tensor file?  Need to fix.
	    $in_file = "$INPATH/${current_runno}${optional_tensor_midfix}_${current_ch}_${name_suffix}.nii.gz"; # $current_runno is used for tensor files
	    $out_file = "${current_outpath}/${current_runno}${optional_tensor_midfix}_${current_ch}_${name_suffix}_final.nii";
      	} else {
	    $in_file = "$INPATH/${current_runno_8}_strip_reg2_whs.nii.gz"; # $current_runno_8 is used for non-tensor files…?
	    $out_file = "${current_outpath}/${current_runno}${optional_tensor_midfix}_${current_ch}_${name_suffix}_final.nii";

	    print "\$in_file = ${in_file}\n\n";
	}

	$ref_file = $in_file;
	$warp_file = "$SOURCEPATH/${source_name}/${source_name}_${warp_suffix}";
	$affine_file = "$SOURCEPATH/${source_name}/${source_name}_${affine_suffix}";

	$commando = "$ANTSPATH/WarpImageMultiTransform $dim  ${in_file} ${out_file}  -R ${ref_file} ${warp_file} ${affine_file}";
	#print "   $commando \n\n";
	push(@commando_list_1,$commando);
#	
#system($commando);

    }
}
#print " We would send the first set of commandos to execute at this point. \n\n";
execute(1,$annotation_1,@commando_list_1); # Executes all secondary registration in a batch.

#/Applications/SegmentationSoftware/ANTS/WarpImageMultiTransform 3 /Volumes/androsspace/hess/CTRL_FA/N40270_DTI_fa_reg2_T2star_strip_reg2_whs.nii /Volumes/androsspace/hess/CTRL_FA/N40270_DTI_fa_reg2_T2star_strip_reg2_whs_final.nii -R /Volumes/androsspace/hess/CTRL_FA/N40270_DTI_fa_reg2_T2star_strip_reg2_whs.nii /Volumes/androsspace/hess/CTRL_FA/N40270_DTI_fa_reg2_T2star_strip_reg2_whs/N40270_DTI_fa_reg2_T2star_strip_reg2_whs_avg_Warp.nii /Volumes/androsspace/hess/CTRL_FA/N40270_DTI_fa_reg2_T2star_strip_reg2_whs/N40270_DTI_fa_reg2_T2star_strip_reg2_whs_initial_Affine.txt

my $current_volume;
my @volume_list;
my $list_of_volumes;

foreach my $new_control_ch (@moving_ch) {
	
    $new_control_ch_uc = uc($new_control_ch);
    $current_path = "$LOCALPATH/CTRL_${new_control_ch_uc}";
    foreach my $current_runno (@runnos) {
	$current_volume = "${current_path}/${current_runno}${optional_tensor_midfix}_${new_control_ch}_${name_suffix}_final.nii";
	push(@volume_list,$current_volume);
    }
    $list_of_volumes = join(' ',@volume_list);
    $commando = "$ANTSPATH/AverageImages $dim ${current_path}/final_average.nii 0 ${list_of_volumes}";
    #print "   $commando\n\n";
    push(@commando_list_2,$commando);
#    system($commando);
 
}

#print "   And now we would send the second set of commandos off to execute and be done with it!\n\n";
execute(1,$annotation_2,@commando_list_2); # Executes all secondary registration in a batch.

#/Applications/SegmentationSoftware/ANTS/AverageImages 3 final_average.nii 0 /Volumes/androsspace/hess/CTRL_FA/N40270_DTI_fa_reg2_T2star_strip_reg2_whs_final.nii /Volumes/androsspace/hess/CTRL_FA/N40310_DTI_fa_reg2_T2star_strip_reg2_whs_final.nii /Volumes/androsspace/hess/CTRL_FA/N40320_DTI_fa_reg2_T2star_strip_reg2_whs_final.nii /Volumes/androsspace/hess/CTRL_FA/N40330_DTI_fa_reg2_T2star_strip_reg2_whs_final.nii /Volumes/androsspace/hess/CTRL_FA/N40340_DTI_fa_reg2_T2star_strip_reg2_whs_final.nii /Volumes/androsspace/hess/CTRL_FA/N40350_DTI_fa_reg2_T2star_strip_reg2_whs_final.nii /Volumes/androsspace/hess/CTRL_FA/N40370_DTI_fa_reg2_dwi_strip_reg2_DTI_final.nii




