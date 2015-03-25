#!/usr/local/pipeline-link/perl

# study_variables_vbm.pm 

# Created 2014/12/23 BJ Anderson for use in VBM pipeline.


my $PM = "study_variables_vbm.pm";
my $VERSION = "2015/02/11";
my $NAME = "In lieu of commandline functionality, here is the place to define various variables.";


my $obrien = 0;
my $obrien_invivo=0;
my $colton = 1;
my $mcnamara =0;
my $premont = 0;


use strict;
use warnings;

use vars qw($test_mode $combined_rigid_and_affine);

use vars qw(
$project_name 
@control_group
@compare_group
@channel_array
$custom_predictor_string
$flip_x
$flip_z 
$optional_suffix
$atlas_name
$label_atlas_name
$rigid_contrast
$mdt_contrast
$skull_strip_contrast
$threshold_code
$do_mask
$pre_masked
$thresh_ref
$syn_params
$syn_iterations
$diffeo_downsampling
$affine_target
$affine_contrast
$native_reference_space
$vbm_reference_space
$create_labels
$label_space
$label_reference
); # Need to replace $native_reference_space with $reference_space


sub study_variables_vbm {

    $syn_iterations = "4000,4000,4000,4000";
    $diffeo_downsampling="8,4,2,1";
    $affine_target = "NO_KEY"; # If not specified, will follow default behaviour of selecting first listed control runno.
    $affine_contrast = "NO_KEY";
    $vbm_reference_space = "native";# "native"; # Options: "native", "<atlas_name>","<full path to an arbitrary image>"
    # $vbm_reference_space = "/home/rja20/cluster_code/data/atlas/DTI_dwi_55.nii";
    
    $create_labels = 1; ### CHANGE BACK TO ONE
    $label_space = "pre_affine"; # options are "pre_rigid","pre_affine"/"post_rigid","post_affine". 
    # Note: pre_affine/post_rigid is not available with $combined_rigid_and_affine =1 & $old_ants = 1.
    $port_atlas_mask =0; # This is just setting the default.
    $combined_rigid_and_affine = 1; # Will eventually always be "0" (and hardcoded accordingly)
## Study variables for O'Brien
    if ($obrien) {
	
	$project_name = "14.obrien.01";
	$custom_predictor_string = "Control_vs_Reacher";
	$syn_params = "0.5,3,1";
	$combined_rigid_and_affine = 0; # We want to eventually have this set to zero and remove this variable from the code.
	$vbm_reference_space = "/glusterspace/VBM_14obrien01_DTI101b-work/preprocess/DTI101b_recentered_rereffed_dwi.nii";

	@control_group = qw(
        controlSpring2013_4
        controlSpring2013_7
        controlSpring2013_8
        controlSpring2013_9
        controlSpring2013_10
        controlSpring2013_11
        controlSummer2012_1
        controlSummer2012_5
        controlSummer2012_8
        controlWinter2012_1
        controlWinter2012_6
        controlWinter2012_9
        );
    
	@compare_group = qw(
        controlLRSpring2013_4
        controlLRSpring2013_7
        controlLRSpring2013_8
        controlLRSpring2013_9
        controlLRSpring2013_10
        controlLRSpring2013_11
        controlLRSummer2012_1
        controlLRSummer2012_5
        controlLRSummer2012_8
        controlLRWinter2012_1
        controlLRWinter2012_6
        controlLRWinter2012_9
        reacherSpring2013_1
        reacherSpring2013_2
        reacherSpring2013_3
        reacherSpring2013_5
        reacherSpring2013_6
        reacherSummer2012_2
        reacherSummer2012_3
        reacherSummer2012_5
        reacherWinter2012_3
        reacherWinter2012_5
        reacherWinter2012_7
        reacherWinter2012_8
        reacherLRSpring2013_1
        reacherLRSpring2013_2
        reacherLRSpring2013_3
        reacherLRSpring2013_5
        reacherLRSpring2013_6
        reacherLRSummer2012_2
        reacherLRSummer2012_3
        reacherLRSummer2012_5
        reacherLRWinter2012_3
        reacherLRWinter2012_5
        reacherLRWinter2012_7
        reacherLRWinter2012_8
        );

	@channel_array = qw(dwi fa adc); 

	$flip_x = 0;
	$flip_z = 0;

	$optional_suffix = 'v2';
	$atlas_name = 'DTI101b';
	$label_atlas_name = 'DTI101b';
	$rigid_contrast = 'dwi';
	$mdt_contrast = 'dwi'; #WAS fa
	$skull_strip_contrast = 'dwi';
	$threshold_code = 4;
	$do_mask = 0;
	$pre_masked = 1;

	$thresh_ref = {};

    } elsif ($obrien_invivo) {
	
	$project_name = "14.obrien.02";
	$custom_predictor_string = "Control_vs_Reacher";
	$syn_params = "0.5,3,0.5";
	$combined_rigid_and_affine = 0; # We want to eventually have this set to zero and remove this variable from the code.
	$vbm_reference_space = "native";
	$create_labels = 1;
	$label_space = "pre_affine";

	@control_group = qw(
	    BCS10
	    BCS11
	    BCS4
	    BCS7
	    BCS8
	    BCS9
	    BCU1
	    BCU7
        );
    
	@compare_group = qw(
	    BRS1
	    BRS2
	    BRS3
	    BRS5
	    BRS6
	    BRU2
	    BRU3
	    ICS10
	    ICS11
	    ICS4
	    ICS7
	    ICS8
	    ICS9
	    ICU1
	    ICU7
	    IRS1
	    IRS2
	    IRS3
	    IRS5
	    IRS6
	    IRU2
	    IRU3
	    TCS10
	    TCS11
	    TCS4
	    TCS7
	    TCS8
	    TCS9
	    TCU1
	    TCU7
	    TRS1
	    TRS2
	    TRS3
	    TRS5
	    TRS6
	    TRU2
	    TRU3
        );

	@channel_array = qw(T2star); 

	$flip_x = 0;
	$flip_z = 0;

	$optional_suffix = '';
	$atlas_name = 'DTI101b';
	$label_atlas_name = 'DTI101b';
	$rigid_contrast = 'T2star';
	$mdt_contrast = 'T2star';
	$skull_strip_contrast = 'T2star';
	$threshold_code = 4;
	$do_mask = 0;
	$pre_masked = 1;

	$thresh_ref = {};

    }
    
    elsif ($colton) 
    
### Study variables for Colton.
    {
	$project_name = "13.colton.01";
	$custom_predictor_string = "nos2_vs_cvn";
	$optional_suffix = 'aTest2';
	$syn_params = "0.5,3,1";
	$combined_rigid_and_affine = 1; # We want to eventually have this set to zero and remove this variable from the code.
	$vbm_reference_space = "native";
	$create_labels = 1;
	$label_space = "pre_affine";

	if ($test_mode) {
	    @control_group = qw(N51386 N51211 N51221 N51406);
	    @compare_group = qw(N51136 N51201 N51234 N51392);
	    @channel_array = qw(dwi e2 fa);
	    $affine_target = 'N51406';
	} else {
	    @control_group = qw(N51211 N51221 N51231 N51383 N51386 N51404 N51406); #N51193-exclude N51404,N51383,N51386-manually z-roll and recalc tensors
	    @compare_group = qw(N51136 N51201 N51234 N51241 N51252 N51282 N51390 N51392 N51393 N51133 N51388);
	    @channel_array = qw(adc dwi e1 e2 e3 fa);
	    $affine_target = 'N51383';
	}	

#	@channel_array = qw(adc dwi e1 e2 e3 fa); # This will be determined by command line, and will be able to include STI, T1, T2, T2star, etc.
    
	$flip_x = 1;
	$flip_z = 0;
	
	
	$atlas_name = 'DTI';
	$label_atlas_name = 'DTI101b';
	$rigid_contrast = 'dwi';
	$affine_contrast = 'dwi';
	$mdt_contrast = 'fa';
	$skull_strip_contrast = 'dwi';
	$threshold_code = 4;
	$do_mask = 1;
	$port_atlas_mask = 1;
	$pre_masked = 0;
    
#custom thresholds for Colton study
	$thresh_ref = {
	    'N51124'   => 2296,
	    'N51130'   => 2644,
	    'N51393'   => 2034,
	    'N51392'   => 2372,
	    'N51390'   => 2631,
	    'N51388'   => 2298,
	    'N51136'   => 1738,
	    'N51133'   => 1808,
	    'N51282'   => 2131,
	    'N51234'   => 2287,
	    'N51201'   => 1477,
	    'N51241'   => 1694,
	    'N51252'   => 1664,
	    'N51383'   => 1981,
	    'N51386'   => 2444,
	    'N51231'   => 1964,
	    'N51404'   => 2057,
	    'N51406'   => 2004,
	    'N51211'   => 1668,
	    'N51221'   => 2169,
	    'N51193'   => 2709,
	    'N51182'   => 1841,
	    'N51151'   => 2188,
	    'N51131'   => 2098,
	    'N51164'   => 2001,
	    'N51617'   => 2867,
	    'N51620'   => 2853,
	    'N51622'   => 3160,
	};
	
    } elsif ($mcnamara) 

    {
	$project_name = "13.mcnamara.02";
	$custom_predictor_string = "Control_vs_KA";
	# $syn_params = ?;
	$combined_rigid_and_affine = 1; # We want to eventually have this set to zero and remove this variable from the code.

	@control_group = qw(S64944 S64953 S64959 S64962 S64968 S64974 S65394 S65408 S65411 S65414);
	@compare_group = qw(S64745 S64763 S64766 S64769 S64772 S64775 S64778 S64781 S65142 S65145 S65148 S65151 S65154);
	

	@channel_array = qw(adc dwi e1 e2 e3 fa); # This will be determined by command line, and will be able to include STI, T1, T2, T2star, etc.
    
	$flip_x = 0;
	$flip_z = 0;
	
	$optional_suffix = 'dual_channel';
	$atlas_name = 'DTI101';
	$label_atlas_name = 'DTI101';
	$rigid_contrast = 'dwi';
	$affine_contrast = 'dwi';
	$mdt_contrast = 'dwi_fa';
	$skull_strip_contrast = 'dwi';
	$threshold_code = 4;
	$do_mask = 0;    
	$pre_masked = 1;

        # Load McNamara Data
	
    } elsif ($premont)
    
    {
	$project_name = "11.premont.01";
	$custom_predictor_string = "WT_vs_KO";
	$vbm_reference_space = "glusterspace/VBM_11premont01_whs-work/base_images/N38709_T2star.nii.gz";
	# $syn_params = ?;
	$combined_rigid_and_affine = 1; # We want to eventually have this set to zero and remove this variable from the code.

	@control_group = qw(N38845 N38851 N38761 N38721 N38714 N38709);
	@compare_group = qw(N38848 N38767 N38764 N38717 N38693 N38699);
	

	@channel_array = qw(T2star); # This will be determined by command line, and will be able to include STI, T1, T2, T2star, etc.
    
	$flip_x = 0;
	$flip_z = 0;
	
	$optional_suffix = '';
	$atlas_name = 'whs';
	$label_atlas_name = 'whs';
	$rigid_contrast = 'T2star';
	$affine_contrast = 'T2star';
	$mdt_contrast = 'T2star';
	$skull_strip_contrast = 'T2star';
	$threshold_code = 4;
	$do_mask = 0;    
	$pre_masked = 1;	
 }




    
}

sub load_study_data_vbm {

	my $bd = '/glusterspace'; #bd for Biggus-Diskus
	my $preprocess_path = $Hf->get_value('preprocess_dir');
	my @all_runnos =  split(',',$Hf->get_value('complete_comma_list'));

    if ($obrien) {
	`cp /glusterspace/VBM_14obrien01_DTI101b-work/base_images/* ${preprocess_path}`
    } elsif ($obrien_invivo) {
	`cp /glusterspace/VBM_14obrien02_DTI101b-work/base_images/* ${preprocess_path}`
    } elsif ($colton) {
	my $dr =$Hf->get_value('pristine_input_dir');
	foreach my $runno (@all_runnos) {
	    my $path_string = "${bd}/${runno}Labels-inputs/${runno}/";
	    `cp ${path_string}/* $dr/`;
	}
    } elsif ($mcnamara) {
	`cp /glusterspace/VBM_13mcnamara02_DTI101-work/base_images/* ${preprocess_path}`
#	foreach my $runno (@all_runnos) {
#	    my $path_string = "${bd}/${runno}_m0Labels-results/";
#	    foreach my $contrast (@channel_array){
#	    
#	    `cp ${path_string}/*DTI_${contrast}*.nii ${preprocess_path}/${runno}_${contrast}.nii`;
#	    }	    
#	}

    } elsif ($premont) {
	`cp /glusterspace/VBM_11premont01_whs-work/base_images/* ${preprocess_path}`
    }

}
1;

