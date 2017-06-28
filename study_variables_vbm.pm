#!/usr/local/pipeline-link/perl

# study_variables_vbm.pm 

# Created 2014/12/23 BJ Anderson for use in VBM pipeline.


my $PM = "study_variables_vbm.pm";
my $VERSION = "2015/02/11";
my $NAME = "In lieu of commandline functionality, here is the place to define various variables.";


my $obrien = 0;
my $obrien_invivo=0;
my $colton = 1;
my $colton_invivo = 0;
my $mcnamara = 0;
my $premont = 0;
my $premont_ct = 0;
my $dave = 0;
my $bj = 0;
my $bj_group = 0;
my $agoston = 0;
my $apoe = 0;
my $christmas_rat = 0;
my $mg_enhanced =0;
my $mg_enhanced_youngmice =0;
my $john_multicoil=0;
my $nian_connectome = 0;

my $spectrin = 0;
my $ankB = 0;

my $connectomics_control_test = 0;

use strict;
use warnings;

use vars qw($test_mode);

use vars qw(
$project_name 
@control_group
@compare_group

@group_1
@group_2

@channel_array
$custom_predictor_string
$template_predictor
$template_name

$flip_x
$flip_z 
$optional_suffix
$atlas_name
$label_atlas_name

$skull_strip_contrast
$threshold_code
$do_mask
$pre_masked
$port_atlas_mask
$port_atlas_mask_path
$thresh_ref

$rigid_contrast

$affine_contrast
$affine_metric
$affine_radius
$affine_shrink_factors
$affine_iterations
$affine_gradient_step
$affine_convergence_thresh
$affine_convergence_window
$affine_smoothing_sigmas
$affine_sampling_options
$affine_target

$mdt_contrast
$mdt_creation_strategy
$mdt_iterations
$mdt_convergence_threshold
$initial_template

$compare_contrast

$diffeo_metric
$diffeo_radius
$diffeo_shrink_factors
$diffeo_iterations
$diffeo_transform_parameters
$diffeo_convergence_thresh
$diffeo_convergence_window
$diffeo_smoothing_sigmas
$diffeo_sampling_options

$native_reference_space
$vbm_reference_space
$create_labels
$label_space
$label_reference

$do_vba

$convert_labels_to_RAS
$eddy_current_correction
$do_connectivity
$recon_machine

$fixed_image_for_mdt_to_atlas_registratation

$vba_contrast_comma_list
$vba_analysis_software
$smoothing_comma_list

$nonparametric_permutations

$image_dimensions
); # Need to replace $native_reference_space with $reference_space


sub study_variables_vbm {
    ## These defaults have been moved to the appropriate Init sections of the various modules ##
    #$diffeo_iterations = "4000,4000,4000,4000";  #Previous default; moved to pairwise_init_check
    #$diffeo_shrink_factors="8,4,2,1"; #Previous default; moved to pairwise_init_check
    #$affine_target = "NO_KEY"; # If not specified, will follow default behaviour of selecting first listed control runno.
    #$affine_contrast = "NO_KEY";
    $vbm_reference_space = "native";# "native"; # Options: "native", "<atlas_name>","<full path to an arbitrary image>"
    $do_vba=1;
    $create_labels = 1;
    $label_space = "pre_affine"; # options are "pre_rigid","pre_affine"/"post_rigid","post_affine". 
    $port_atlas_mask =0; # This is just setting the default.
    $mdt_creation_strategy = 'iterative'; # Options: 'pairwise (old Kochonov method)and 'iterative' (SyGN) Will eventually move to 'iterative'.
## Study variables for O'Brien
    if ($obrien) {
	
	$project_name = "14.obrien.01";
	$custom_predictor_string = "Control_vs_Reacher";
	#$custom_predictor_string = "Control_vs_Phantom";
	$diffeo_transform_parameters = "0.5,3,0.5";#1";
	$vbm_reference_space = "native";
	$create_labels = 1; #1
	#$label_space = "pre_rigid";
	$label_space = "post_affine";

	my $phantom_run = 0;
	$template_name = 'faMDT_Control_n12a';  # This is because analysis was originally performed with a "broken MDT", but could not be
	                                        # designated as such...faMDT_Control_n12 is actually broken, even though I modified the headfile to say otherwise.
                                                # faMDT_Control_n12a is the most kosher set...note that the in vivo registration is driven by fa here 
                                                # faMDT_Control_n12b is the assymetric phantom run
                                                # faMDT_Control_n12c is for rerunning the in vivo with dwi driving the registration
                                                # ...note that the in vivo registration is driven by "fa" here--but in reality I made a copy of the dwi and renamed it "fa"!!!

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
	
	@group_1 = qw(
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

	if ($phantom_run) {
	@compare_group = qw(
        phantomSpring2013_4
        phantomSpring2013_7
        phantomSpring2013_8
        phantomSpring2013_9
        phantomSpring2013_10
        phantomSpring2013_11
        phantomSummer2012_1
        phantomSummer2012_5
        phantomSummer2012_8
        phantomWinter2012_1
        phantomWinter2012_6
        phantomWinter2012_9
        );
	
	@group_2 = qw(
        phantomSpring2013_4
        phantomSpring2013_7
        phantomSpring2013_8
        phantomSpring2013_9
        phantomSpring2013_10
        phantomSpring2013_11
        phantomSummer2012_1
        phantomSummer2012_5
        phantomSummer2012_8
        phantomWinter2012_1
        phantomWinter2012_6
        phantomWinter2012_9
        );
	} else {

	@compare_group = qw(
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
        );

	@group_2 = qw(
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
        );
	}


	@channel_array = qw(dwi fa adc); 
#	@channel_array = qw(dwi fa);


	$flip_x = 0;
	$flip_z = 0;

	#$optional_suffix = 'clean';
	$atlas_name = 'DTI101b';
	$label_atlas_name = 'chass_symmetric2';#'dti148lr';
	$rigid_contrast = 'dwi';
	$mdt_contrast = 'fa'; #WAS fa
	#$compare_contrast = 'dwi';
	$diffeo_metric = 'CC'; # For MDT creation purposes it was CC
	#$diffeo_radius = '32'; # For MDT creation purposes it was 4, here it means Number of Bins

	$skull_strip_contrast = 'dwi';
	$threshold_code = 4;
	$do_mask = 0;
	$pre_masked = 1;

	$vba_analysis_software = 'surfstat';#
	$vba_contrast_comma_list = 'jac'; # Introduced so we could specify that only jac needs to be rerun, but can be used whenever needed.
	$thresh_ref = {};

    } elsif ($obrien_invivo) {
	
	$project_name = "14.obrien.02";
	$custom_predictor_string = "Control_vs_Reacher";
	$diffeo_transform_parameters = "0.5,3,1";
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
            BCW1
            BCW4
            BCW6
            BCW9      
        );
    
	@compare_group = qw(
	    BRS1
	    BRS2
	    BRS3
	    BRS5
	    BRS6
	    BRU2
	    BRU3
            BRU5
            BRW3
            BRW5
            BRW7
            BRW8
	    ICS10
	    ICS11
	    ICS4
	    ICS7
	    ICS8
	    ICS9
	    ICU1
	    ICU7
            ICW1
            ICW4
            ICW6
            ICW9
	    IRS1
	    IRS2
	    IRS3
	    IRS5
	    IRS6
	    IRU2
	    IRU3
            IRU5
            IRW3
            IRW5
            IRW7
            IRW8
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
            TRU5
            TCW1
            TCW4
            TCW6
            TCW9
            TRW3
            TRW5
            TRW7
            TRW8
        );

	@channel_array = qw(T2star); 

	$flip_x = 0;
	$flip_z = 0;

	$optional_suffix = 'SyN3and1';
	$atlas_name = 'DTI101b';
	$label_atlas_name = 'DTI101b';
	$rigid_contrast = 'T2star';
	$mdt_contrast = 'T2star';
	$skull_strip_contrast = 'T2star';
	$threshold_code = 4;
	$do_mask = 0;
	$pre_masked = 1;

	$vba_contrast_comma_list = 'jac';
	$vba_analysis_software = 'spm,surfstat';

	$thresh_ref = {};

    }
    
    elsif ($colton) 
    
### Study variables for Colton.
    {
	$project_name = "13.colton.01";
	$custom_predictor_string = "nos2_vs_cvn";
	#$optional_suffix = '2016analysis'; #'aTest6'
	$optional_suffix='April2017analysis';
	$diffeo_transform_parameters = "0.5,3,0.5";  #"0.5,3,1"
	$vbm_reference_space = "native";
	$create_labels = 1;
	#$label_space = "pre_affine";
	$label_space = "pre_rigid,post_affine";
	$convert_labels_to_RAS = 1;



	$mdt_creation_strategy = 'iterative';
	$mdt_iterations = 6;
	$do_connectivity = 0;

	if ($test_mode) {
	    @control_group = qw(N51386 N51211 N51221);# N51406);
	    @compare_group = qw(N51136 N51201);# N51234 N51392);
	    @channel_array = qw(dwi fa);
	    $affine_target = 'N51211';
	    $label_reference = "";
	} else {
	    #@control_group = qw(N51211 N51221 N51231 N51383 N51386 N51404 N51406 N51193);#N51193-exclude N51404,N51383,N51386-manually z-roll and recalc tensors
	    #@compare_group = qw(N51136 N51201 N51234 N51241 N51252 N51282 N51390 N51392 N51393 N51133 N51388 N51124 N51130 
            #  N51131 N51164 N51182 N51151 N51622 N51620 N51617);

#N51131 does not need any z-flipping, will delete and process manually, and manually edit the sign of the z-component of its bvectors

	    @control_group = qw(N51211 N51221 N51231 N51383 N51386 N51404 N51406 N51193
                                N51136 N51201 N51234 N51241 N51252 N51282 N51390 N51392 N51393 N51133 N51388 N51124 N51130 
                                N51131 N51164 N51182 N51151 N51622 N51620 N51617);
	    @compare_group = @control_group;


	    @group_1 = qw(N51211 N51221 N51231 N51383 N51386 N51404 N51406 N51193);#N51193-exclude N51404,N51383,N51386-manually z-roll and recalc tensors
	    @group_2 = qw(N51136 N51201 N51234 N51241 N51252 N51282 N51390 N51392 N51393 N51133 N51388 N51124 N51130
              N51131 N51164 N51182 N51151 N51622 N51620 N51617);

	    #@channel_array = qw(adc dwi e1 e2 e3 fa);
	    @channel_array = qw(dwi fa);
	    $affine_target = 'N51383';
	}	

	#@channel_array = qw(adc dwi e1 e2 e3 fa); # This will be determined by command line, and will be able to include STI, T1, T2, T2star, etc.
    
	$flip_x = 1;  # Only for N51131 !!!, 1 otherwise
	$flip_z = 0;
	
	
	#$atlas_name = 'DTI101b';
	$atlas_name = 'chass_symmetric2';
	$label_atlas_name = 'chass_symmetric2';#'DTI101b';
	$rigid_contrast = 'dwi';
	$affine_contrast = 'dwi';
	$mdt_contrast = 'fa';
	$skull_strip_contrast = 'dwi';
	$threshold_code = 4;
	$do_mask = 1;
	#$port_atlas_mask = 1;
	$port_atlas_mask = 0;
	$pre_masked = 0;
    
	$vba_analysis_software = 'fsl';
	$nonparametric_permutations = 2035;

#custom thresholds for Colton study
	$thresh_ref = {
	    'N51124'   => 5,#2296,
	    'N51130'   => 4,#2644,
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
    }

    elsif ($colton_invivo) 
    
### Study variables for Colton in vivo.
    {
	$project_name = "13.colton.01";
	$custom_predictor_string = "nos2_vs_cvn";
	$optional_suffix = 'invivo';
	$diffeo_transform_parameters = "0.5,3,1";
	$vbm_reference_space = "native";
	$create_labels = 1;
	$label_space = "pre_affine";


# @control_group = qw(B02335
# B02492
# B02494
# B02497);

	    @control_group = qw(B02335
B02492
B02494
B02497
B02499
B02672
B02674
B02679
B02681
B02683
B02741
B02743
B02804
B02806
B03234
B03236
B03238
B03240
B03242
B03244
B03246
B03248); 
	    @compare_group = qw(dummy); # Just so it doesn't bust...
	    @channel_array = qw(T1);
	   # $affine_target = 'N51383';
		

#	@channel_array = qw(adc dwi e1 e2 e3 fa); # This will be determined by command line, and will be able to include STI, T1, T2, T2star, etc.
    
	$flip_x = 1;
	$flip_z = 0;
	
	
	$atlas_name = 'DTI'; #DTI
	$label_atlas_name = 'DTI'; #DTI
	$rigid_contrast = 'T1';
	$affine_contrast = 'T1';
	$mdt_contrast = 'T1';
	$skull_strip_contrast = 'T1';
	$threshold_code = 3;
	$do_mask = 0;
	$port_atlas_mask = 0;
	$port_atlas_mask_path = '/glusterspace/VBM_13colton01_DTI_invivo-work/preprocess/masks/approx_atl_mask.nii';
	$pre_masked = 0;
 
	
    } elsif ($mcnamara) 

    {

	$project_name = "13.mcnamara.02";
	$create_labels = 1; # Turning this off for phantom analysis -- will turn back on if needed.
	#$custom_predictor_string = "Control_vs_KA";


	$mdt_creation_strategy = 'iterative';
	$mdt_iterations = 6; #6
	#$mdt_convergence_threshold # Need to figure out how to use this!

#	$template_name = 'faMDT_Control_n10';
	my $all =1;
	my $phantom_run =0;
	my $phantom_version = 6;

	# Combinations of SyN parameters: SyN: 0.5,0.25,0.1, reg1: 5,3, reg2: 0.5,0
	#$diffeo_transform_parameters = "0.5,5,0.5"; # control # all # QS Phantom #Yantom #Xantom #Vantom #Xall
	#$diffeo_transform_parameters = "0.5,5,0";  # control #all #QS Phantom #Xantom #Vantom #Xall
	#$diffeo_transform_parameters = "0.5,3,0.5";# control  #all # QS phantom #Xantom #Vantom #Xall
	#$diffeo_transform_parameters = "0.5,3,0";# control #all #Fantom #Xantom #Xall

        #$diffeo_transform_parameters = "0.25,5,0.5"; # control #all #phantom #QS phantom #Fantom (QS, just renamed) #Zantom #Yantom? #Xantom #Vantom #Xall
 	#$diffeo_transform_parameters = "0.25,5,0"; # control #all #Xantom  #Vantom #Xall
	#$diffeo_transform_parameters = "0.25,3,0.5"; # control #all  #phantom #Fantom #Xantom #Vantom #Xall
	#$diffeo_transform_parameters = "0.25,3,0"; # control  #all #Xantom #Vantom? #Xall 

	#$diffeo_transform_parameters = "0.1,5,0.5"; # control  # all #phantom #Fantom #Zantom #Yantom #Xantom #Vantom #Xall 
	#$diffeo_transform_parameters = "0.1,5,0"; # control # all #Fantom #Xantom  #Vantom #Xall (missing labels - progress)
       	###$diffeo_transform_parameters = "0.1,3,0.5"; # control # all #phantom #Fantom #Xantom #Vantom # Xall - active (missing labels)
	$diffeo_transform_parameters = "0.1,3,0"; # control  # all #phantom #Xantom #Xall (missing labels-in progress)


	#$diffeo_transform_parameters = "0.5,3,1"; # For use with producing chass_symmetric2 labels which can be manually corrected.

	#$vbm_reference_space = "/glusterspace/VBM_13mcnamara02_DTI101b_quick-inputs/y_padded.nii";#"DTI101b";
	$vbm_reference_space ="/glusterspace/VBM_13mcnamara02_DTI101b_zippy-work/preprocess/base_images/reference_file_c_ypadded.nii.gz";
	#$label_space = "pre_affine"; # options are "pre_rigid","pre_affine"/"post_rigid","post_affine".
	$label_space = "pre_affine";
	
	if ($all) {
	    if ($phantom_run) {
		if ($phantom_version == 6) {
		    @control_group = qw(S64944 S64953 S64959 S64962 S64968 S64974 S65394 S65408 S65411 S65414 X64944 X64953 X64959 X64962 X64968 X64974 X65394 X65408 X65411 X65414);
		    $template_predictor = 'Xall'; 
		} elsif ($phantom_version == 7) {
		    @control_group = qw(S64944 S64953 S64959 S64962 S64968 S64974 S65394 S65408 S65411 S65414 V64944 V64953 V64959 V64962 V64968 V64974 V65394 V65408 V65411 V65414);
		    $template_predictor = 'Vall';
		}
	    } else {
	    @control_group = qw(S64944 S64953 S64959 S64962 S64968 S64974 S65394 S65408 S65411 S65414 S64745 S64763 S64775 S64778 S64781 S65142 S65145 S65148 S65151 S65154);
	    $template_predictor = 'all';
	    }
	} else {
	    @control_group = qw(S64944 S64953 S64959 S64962 S64968 S64974 S65394 S65408 S65411 S65414);
	    #@compare_group = qw(S64745 S64763 S64775 S64778 S64781 S65142 S65145 S65148 S65151 S65154);
	    $template_predictor = 'controls';
	}
	if ($phantom_run) {
	    if ($phantom_version == 1) {
		@compare_group = qw(PS64944 PS64953 PS64959 PS64962 PS64968 PS64974 PS65394 PS65408 PS65411 PS65414 S64944 S64953 S64959 S64962 S64968 S64974 S65394 S65408 S65411 S65414);
	    } elsif ($phantom_version == 2) {
		@compare_group = qw(QS64944 QS64953 QS64959 QS64962 QS64968 QS64974 QS65394 QS65408 QS65411 QS65414 S64944 S64953 S64959 S64962 S64968 S64974 S65394 S65408 S65411 S65414);
	    } elsif ($phantom_version == 3) {
		@compare_group = qw(F64944 F64953 F64959 F64962 F64968 F64974 F65394 F65408 F65411 F65414 S64944 S64953 S64959 S64962 S64968 S64974 S65394 S65408 S65411 S65414);
	    } elsif ($phantom_version == 4) {
		@compare_group = qw(Z64944 Z64953 Z64959 Z64962 Z64968 Z64974 Z65394 Z65408 Z65411 Z65414 S64944 S64953 S64959 S64962 S64968 S64974 S65394 S65408 S65411 S65414);
	    } elsif ($phantom_version == 5) {
		@compare_group = qw(Y64944 Y64953 Y64959 Y64962 Y64968 Y64974 Y65394 Y65408 Y65411 Y65414 S64944 S64953 S64959 S64962 S64968 S64974 S65394 S65408 S65411 S65414);
	    } elsif ($phantom_version == 6) {
		@compare_group = qw(X64944 X64953 X64959 X64962 X64968 X64974 X65394 X65408 X65411 X65414 S64944 S64953 S64959 S64962 S64968 S64974 S65394 S65408 S65411 S65414);
	    } elsif ($phantom_version == 7) {
		@compare_group = qw(V64944 V64953 V64959 V64962 V64968 V64974 V65394 V65408 V65411 V65414 S64944 S64953 S64959 S64962 S64968 S64974 S65394 S65408 S65411 S65414);
	    }
	} else {
	    @compare_group = qw(S64745 S64763 S64775 S64778 S64781 S65142 S65145 S65148 S65151 S65154 S64944 S64953 S64959 S64962 S64968 S64974 S65394 S65408 S65411 S65414);
	}
	
#	my $cheating = 0; # We are "cheating" to produce chass_symmetric2 labelsets quickly.
#	if ($cheating) {
#	@control_group = qw(S64944);
#	@compare_group = qw(S64953 S64959 S64962 S64968 S64974 S65394 S65408 S65411 S65414 S64745 S64763 S64775 S64778 S64781 S65142 S65145 S65148 S65151 S65154);
#	}

#	my $reverse_polarity = 0;
# Use this to swap polarity for bad Jac exposition.
#	if ($reverse_polarity) {
	#@group_1 = qw(S64745 S64763 S64775 S64778 S64781 S65142 S65145 S65148 S65151 S65154); # 30 November 2016 -- DOH! I have these backwards!  Will need to delete VBM results and rerun, but once all SyNs have completed, so we don't get confused about data consistency.  @group_1 should start with S64944, and @group_2 should start with S64745.
	#@group_2 = qw(S64944 S64953 S64959 S64962 S64968 S64974 S65394 S65408 S65411 S65414);
#	} # 19 Dec 2016 Began running with the proper group assignments.


	@group_1 = qw(S64944 S64953 S64959 S64962 S64968 S64974 S65394 S65408 S65411 S65414);
	if ($phantom_run) {

	    if ($phantom_version == 1) {
		@group_2 = qw(PS64944 PS64953 PS64959 PS64962 PS64968 PS64974 PS65394 PS65408 PS65411 PS65414);
		$custom_predictor_string = "Control_vs_Phantoms";
	    } elsif ($phantom_version == 2) {
		@group_2 = qw(QS64944 QS64953 QS64959 QS64962 QS64968 QS64974 QS65394 QS65408 QS65411 QS65414);
		$custom_predictor_string = "Control_vs_Phantoms2";
	    } elsif ($phantom_version == 3) {
		@group_2 = qw(F64944 F64953 F64959 F64962 F64968 F64974 F65394 F65408 F65411 F65414);
		$custom_predictor_string = "Control_vs_Fantoms";
	    } elsif ($phantom_version == 4) {
		@group_2 = qw(Z64944 Z64953 Z64959 Z64962 Z64968 Z64974 Z65394 Z65408 Z65411 Z65414);
		$custom_predictor_string = "Control_vs_Zantoms";
	    } elsif ($phantom_version == 5) {
		@group_2 = qw(Y64944 Y64953 Y64959 Y64962 Y64968 Y64974 Y65394 Y65408 Y65411 Y65414);
		$custom_predictor_string = "Control_vs_Yantoms";
	    } elsif ($phantom_version == 6) {
		@group_2 = qw(X64944 X64953 X64959 X64962 X64968 X64974 X65394 X65408 X65411 X65414);
		$custom_predictor_string = "Control_vs_Xantoms";
	    } elsif ($phantom_version == 7) {
		@group_2 = qw(V64944 V64953 V64959 V64962 V64968 V64974 V65394 V65408 V65411 V65414);
		$custom_predictor_string = "Control_vs_Vantoms";
	    }

	} else {
	    @group_2 = qw(S64745 S64763 S64775 S64778 S64781 S65142 S65145 S65148 S65151 S65154);
	    $custom_predictor_string = "Control_vs_KA";
	}
	


#	@channel_array = qw(adc dwi e1 e2 e3 fa); # This will be determined by command line, and will be able to include STI, T1, T2, T2star, etc.
    	@channel_array = qw(dwi fa); #Just these two for now so we don't overload glusterspace

#	$vba_contrast_comma_list = 'jac'; # Introduced so we could specify that only jac needs to be rerun, but can be used whenever needed.
#	$vba_analysis_software = 'antsr';
#	$vba_analysis_software = 'spm';
#	$vba_analysis_software = 'surfstat,antsr,spm';
	$vba_analysis_software = 'surfstat';


	$flip_x = 1;
#	$flip_x = 0;
	$flip_z = 0;
	
        $optional_suffix='zippy';#SyN_1_3_1';
	#$optional_suffix='quick';
	$atlas_name = 'DTI101b';
#	$label_atlas_name = 'DTI101b';
	$label_atlas_name = 'chass_symmetric2';
	$rigid_contrast = 'dwi';
	$affine_contrast = 'dwi';
	$mdt_contrast = 'fa';
	$skull_strip_contrast = 'dwi';
	$threshold_code = 2200; #4 didn't seem to work...
	$do_mask = 1;
#	$do_mask = 0;
    
	$pre_masked = 0;
#	$pre_masked = 1;
	$port_atlas_mask = 0;

        # Load McNamara Data
	
    } elsif ($premont)
    
    {
	$project_name = "11.premont.01";
	$custom_predictor_string = "WT_vs_KO";
	$vbm_reference_space = "glusterspace/VBM_11premont01_whs-work/base_images/N38709_T2star.nii.gz";

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
 }  elsif ($premont_ct)
    
 {
     $project_name = "11.premont.01";
     $custom_predictor_string = "WT_vs_KO";
     $vbm_reference_space = "WT_111004_3"; #/glusterspace/VBM_11premont01_whs-work/base_images/N38709_T2star.nii.gz";
     $create_labels = 0;

     @control_group = qw(
WT_110914_2
WT_110921_2
WT_110921_3
WT_111004_3
WT_111024_4
WT_111215_4 );
     @compare_group = qw(
GIT1_110914_3 
GIT1_110914_4
GIT1_110921_4
GIT1_111004_4
GIT1_111004_5
GIT1_111024_5);
     
     
     @channel_array = qw(ct); # This will be determined by command line, and will be able to include STI, T1, T2, T2star, etc.
    
     $flip_x = 1;
     $flip_z = 1;
     
     $optional_suffix = 'CT';
     $atlas_name = 'AWHS';
     $label_atlas_name = '';
     $rigid_contrast = 'ct';
     $affine_contrast = 'ct';
     $mdt_contrast = 'ct';
     $skull_strip_contrast = 'ct';
     $threshold_code = 120;
     $do_mask = 0;
     $port_atlas_mask = 0;    
     $pre_masked = 1;	
 } elsif ($dave)
    
    {
	$project_name = "12.provenzale.02";
	$custom_predictor_string = "control_vs_diseased";
	$vbm_reference_space = "native";
	$create_labels = 0;

	@control_group = qw(S65469 S65519 S65531);
	@compare_group = qw(S65445 S65542 S65545);

	@channel_array = qw(dwi fa);
    
	$flip_x = 0;
	$flip_z = 1;
	
	$optional_suffix = '';
	$atlas_name = 'whs';#
	$label_atlas_name = 'whs';#
	
	$rigid_contrast = 'dwi';
	## $affine_contrast = 'dwi';
	#$affine_radius=32;
	$affine_metric = 'MI';
	$affine_shrink_factors = '6x4x2x1';
	$affine_iterations = '500x500x500x500';
	$affine_gradient_step = 0.05;
	$affine_convergence_thresh = '1e-6';
        $affine_convergence_window = 10;
	$affine_smoothing_sigmas= '0x0x0x0vox';
	$affine_sampling_options = 'Random,0.5';
	$affine_target='S6546at9';

	$mdt_contrast = 'fa';
	$diffeo_metric = 'CC';
	$diffeo_radius = 4;
	$diffeo_shrink_factors = '8x6x4x2x1'; # Commented out to test default behavior.
	$diffeo_iterations = '500x500x500x500x15';
	$diffeo_transform_parameters = '0.6,3,1';
	$diffeo_convergence_thresh = '1e-7';
	$diffeo_convergence_window = 15;
	$diffeo_smoothing_sigmas = '0.9x0.6x0.3,0.15x0mm';
	$diffeo_sampling_options = 'Random,0.5';


	$skull_strip_contrast = 'dwi';
	$threshold_code = 3;
	$do_mask = 0;
	$port_atlas_mask = 0;    
	$pre_masked = 0;	
 }  elsif ($bj)
    
    {
	$project_name = "15.rja.01";
	$custom_predictor_string = "intra_specimen";
	$vbm_reference_space = "native";
	$diffeo_transform_parameters = '0.5,3,1';
	$create_labels = 0;
 
	my $specimen = 6;
	if ($specimen == 1) {
	@control_group = qw(
S65813
S65913
S66013);
	@compare_group = qw(
S65613
S65713
S66113
S66413
N51813
N51814
N52013
N52014
N52113
N52613
N52614
N52813
N52814
);
#	Excluded: N51913/N51914 ("presig: high" issue), N52114 (lost tuning during b0 scan), N52913/N52914 (bad B0 image/loss of tuning?)

	} elsif ($specimen == 2) {
	@control_group = qw(
S65823
S65923
S66023);


	@compare_group = qw(
S65623
S65624
S65723
S65724
S65824
S65924
S66024
S66123
S66124
S66423
S66424
N51823
N52023
N52123
N52623
N52923
);
#	Excluded: N51923 ("presig: high"  issue), N52823 (large 180 artifact)

	}  elsif ($specimen == 3) {
	@control_group = qw(
S65833
S65933
S66033);
	@compare_group = qw(
S65633
S65733
S66133
S66433
N51833
N51834
N51933
N51934
N52033
N52034
N52133
N52134
N52633
N52634
N52833
N52834
N52933
N52934
);
#	Excluded: None

	} elsif ($specimen == 4) {
	@control_group = qw(
S65843
S65943
S66043);
	@compare_group = qw(
S65643
S65644
S65743
S65744
S65844
S65944
S66044
S66143
S66144
S66443
S66444
N51843
N51943
N52043
N52143
N52643
N52843
N52943
);
#	Excluded: None

	} elsif ($specimen == 5) {
	@control_group = qw(
S65853
S65953
S66053);
	@compare_group = qw(
S65653
S65753
S66153
S66453
N51853
N51854
N51953
N51954
N52053
N52054
N52153
N52154
N52653
N52853
N52854
N52953
N52954
);
#	Excluded: N52654 (lost tuning around b5)
	} elsif ($specimen == 6) {
	@control_group = qw(
S65863
S65963
S66063);
	@compare_group = qw(
S65663
S65664
S65763
S65764
S65864
S65964
S66064
S66163
S66164
S66463
S66464
N51863
N51963
N52063
N52163
N52663
N52863
);
#	Excluded: N52963
	}

#	@channel_array = qw(adc dwi e1 e2 e3 fa); # This will be determined by command line, and will be able to include STI, T1, T2, T2star, etc.
    	@channel_array = qw(dwi fa);

	$flip_x = 1;
	$flip_z = 0;
	

	$optional_suffix = 'spec'.$specimen;
	$atlas_name = 'DTI101b';
	$label_atlas_name = 'DTI101b';
	$rigid_contrast = 'dwi';
	$affine_contrast = 'dwi';
	$mdt_contrast = 'fa';
	$skull_strip_contrast = 'dwi';
	$threshold_code = 5500;
	$do_mask = 1;	
	$port_atlas_mask = 1;
	$pre_masked = 0;
 }  elsif ($bj_group)
    
    {
	$project_name = "15.rja.01";
	$custom_predictor_string = "inter_specimen";
	$vbm_reference_space = "native";
	$diffeo_transform_parameters = '0.5,3,1';

	@control_group = qw(
spec1
spec2
spec3
spec4
spec5
spec6
);
	@compare_group = qw(
dummy
);
#	@channel_array = qw(adc dwi e1 e2 e3 fa); # This will be determined by command line, and will be able to include STI, T1, T2, T2star, etc.
    	@channel_array = qw(dwi fa);

	$flip_x = 0;
	$flip_z = 0;
	

	$optional_suffix = 'group';
	$atlas_name = 'DTI101b';
	$label_atlas_name = 'DTI101b';
	$rigid_contrast = 'dwi';
	$affine_contrast = 'dwi';
	$mdt_contrast = 'fa';
	$skull_strip_contrast = 'dwi';
	$threshold_code = 5500;
	$do_mask = 0;	
	$port_atlas_mask = 0;
	$pre_masked = 1;
 }

    elsif ($agoston)
    
    {
	$project_name = "14.agoston.01";
	#$custom_predictor_string = "sham_vs_injured";
	$custom_predictor_string = "sham2_vs_delayed";
	$template_predictor = "sham";

	$vbm_reference_space = "native";
	$create_labels = 1;
	
	@control_group = qw(S65456 S65459 S65466 S65521 S65530 S65533 S65537 S65541);
	#@compare_group = qw(S65453 S65461 S65464 S65467 S65524 S65528 S65535 S65539 S65544);
	@compare_group = qw(S66782 S66784 S66787 S66789 S66791 S66831 S66833 S66835 S66837  S66853 S66855 S66857 S66859 S66861 S66863 S66865 S66867 S66869);

	@group_1 = qw(S66782 S66784 S66787 S66789 S66791 S66831 S66833 S66835 S66837) ;
	@group_2 = qw(S66853 S66855 S66857 S66859 S66861 S66863 S66865 S66867 S66869) ;

	@channel_array = qw(dwi fa adc e1 e2 e3);
    
	$flip_x = 1;
	$flip_z = 0;
	
	$optional_suffix = '';
	$atlas_name = 'rat';#
	$label_atlas_name = 'rat2';#
	
	$rigid_contrast = 'dwi';
	## $affine_contrast = 'dwi';
	$affine_metric = 'MI';
	#$affine_radius=32;
	$affine_sampling_options = 'Regular,0.75';
	$affine_gradient_step = 0.05;
	$affine_iterations = '500x500x500x500';
	$affine_convergence_thresh = '1e-6';
        $affine_convergence_window = 15;
	$affine_smoothing_sigmas= '0x0x0x0vox';
	$affine_shrink_factors = '6x4x2x1';
	##$affine_target;

	$mdt_contrast = 'fa';
	$diffeo_metric = 'CC';
	$diffeo_radius = 4;
	$diffeo_shrink_factors = '8x4x2x1'; # Commented out to test default behavior.
	$diffeo_iterations = '500x500x500x500';
	$diffeo_transform_parameters = '0.4,3,1';
	$diffeo_convergence_thresh = '1e-7';
	$diffeo_convergence_window = 15;
	$diffeo_smoothing_sigmas = '4x2x1x0vox';
	$diffeo_sampling_options = 'Random,1';


	$skull_strip_contrast = 'dwi';
	$threshold_code = 4;
	$do_mask = 0;
	$port_atlas_mask = 0;    
	$pre_masked = 1;	
    } elsif ($apoe)
	
    {
	$project_name = "10.sullivan.01";
	$custom_predictor_string = "control_vs_ApoE";
	$vbm_reference_space = "native";

	@control_group = qw(N33818 N33819 N33820 N33821 N33965 N33968);
	@compare_group = qw(N33823 N33824 N33825 N33964 N33966 N33967);
	

	@channel_array = qw(dwi); # This is actually T2star, but pretending to be dwi
    
	$flip_x = 0;
	$flip_z = 0;
	
	$optional_suffix = '';
	$atlas_name = 'DTI101';
	$label_atlas_name = 'DTI101';
	$rigid_contrast = 'dwi';
	$affine_contrast = 'dwi';
	$mdt_contrast = 'dwi';

	$diffeo_transform_parameters = '1,3,3';

	$skull_strip_contrast = 'dwi';
	$threshold_code = 4;
	$do_mask = 0;    
	$pre_masked = 1;	
    } elsif ($christmas_rat)
     
    {
	$project_name = "15.gaj.36";

	$vbm_reference_space = "native";
	$create_labels = 1;
	$template_predictor = 'UNDEFINED';


	@control_group = qw(S66971);
	@compare_group = qw();#D66971); ## "You can learn a lot from a dummy..."

	@channel_array = qw(dwi fa colorR colorG colorB adc e1 e2 e3);
    
	$flip_x = 1;
	$flip_z = 0;
	
	$optional_suffix = 'v2';
	$atlas_name = 'rat2';#
	$label_atlas_name = 'rat2';#
	
	$rigid_contrast = 'dwi';
	## $affine_contrast = 'dwi';
	$affine_metric = 'MI';
	#$affine_radius=32;
	$affine_sampling_options = 'Regular,0.75';
	$affine_gradient_step = 0.05;
	$affine_iterations = '500x500x500x500';
	$affine_convergence_thresh = '1e-6'; #1e-6
        $affine_convergence_window = 15;
	$affine_smoothing_sigmas= '0x0x0x0vox';
	$affine_shrink_factors = '6x4x2x1';
	##$affine_target;

	$mdt_contrast = 'fa';
	$diffeo_metric = 'CC';
	$diffeo_radius = 4;
	$diffeo_shrink_factors = '8x4x2x1'; # Commented out to test default behavior.
	$diffeo_iterations = '1000x1000x1000x1000';

	$diffeo_transform_parameters = '0.4,3,1';
	#$diffeo_transform_parameters = '0.6,3,2';
	#$diffeo_transform_parameters = '0.8,3,3';
	#$diffeo_transform_parameters = '1,3,1';

	$diffeo_convergence_thresh = '1e-7';
	$diffeo_convergence_window = 15;
	$diffeo_smoothing_sigmas = '4x2x1x0vox';
	$diffeo_sampling_options = 'Random,1';


	$skull_strip_contrast = 'dwi';
	$threshold_code = 4;
	$do_mask = 1;
	$port_atlas_mask = 1;    
	$pre_masked = 0;	
    }    elsif ($mg_enhanced)
    
    {
	$project_name = "15.abb.07";
	
	$custom_predictor_string = "Control_vs_AD";


	$vbm_reference_space = "native";
	$create_labels = 1;
	
	@control_group = qw(B04120 B04123 B04126 B04129 B04132 B04093 B04096 B04026 B04029 B04032 B04035 B04038 B04050);
	@compare_group = qw(B04114 B04076 B04081 B04084 B04087 B04090 B04020 B04023 B04040 B04044 B04047); #B04079 B04117

	@group_1 = qw(B04120 B04123 B04126 B04129 B04132 B04093 B04096 B04026 B04029 B04032 B04035 B04038 B04050);
	@group_2 = qw(B04114 B04076 B04081 B04084 B04087 B04090 B04020 B04023 B04040 B04044 B04047); #B04117  B04079

	@channel_array = qw(T2 T2star X mGRE);
#	@channel_array = qw(T2star X);

    
	$flip_x = 1;
	$flip_z = 0;
	
	$optional_suffix = '';
	$atlas_name = 'chass_symmetric';#
	$label_atlas_name = 'chass_symmetric';#
	
	$rigid_contrast = 'T2';
	## $affine_contrast = 'dwi';
        $affine_metric = 'MI';
	#$affine_radius=32;
	#$affine_sampling_options = 'Regular,0.75';
	#$affine_gradient_step = 0.05;
	$affine_iterations = '3000x3000x3000x0';
	#$affine_convergence_thresh = '1e-6';
        #$affine_convergence_window = 15;
	$affine_smoothing_sigmas= '0x0x0x0vox';
	$affine_shrink_factors = '6x4x2x1';
	##$affine_target;

	$mdt_contrast = 'T2';
	#$diffeo_metric = 'CC';
	#$diffeo_radius = 4;
	#$diffeo_shrink_factors = '8x4x2x1'; # Commented out to test default behavior.
	#$diffeo_iterations = '500x500x500x500';
	$diffeo_transform_parameters = '0.5,3,1';
	#$diffeo_convergence_thresh = '1e-7';
	#$diffeo_convergence_window = 15;
	#$diffeo_smoothing_sigmas = '4x2x1x0vox';
	#$diffeo_sampling_options = 'Random,1';

	$smoothing_comma_list ='1,1.5,2';

	$skull_strip_contrast = 'T2';
	$threshold_code = 4;
	$do_mask = 1; #1
	$port_atlas_mask = 0; #1    
	$pre_masked = 0; #0	
    } elsif ($mg_enhanced_youngmice)
    
    {
	$project_name = "15.abb.07";
	
	$custom_predictor_string = "Unmazed_vs_Mazed"; # Accidentally had it backwards for first 'youngmice' run: 'Mazed_vs_Unmazed'

	$mdt_creation_strategy = 'iterative';
	$mdt_iterations = 6;

	$vbm_reference_space = "native";
	$create_labels = 1;
	
	@control_group =  qw(B03680 B03729 B03734 B03739 B03818 B03852 B03858 B03864 B03870);#qw(B03704 B03709 B03714 B03724 B03719 B03823 B03828 B03834 B03616);
	@compare_group = qw(B03704 B03709 B03714 B03724 B03719 B03823 B03828 B03834 B03616 B03680 B03729 B03734 B03739 B03818 B03852 B03858 B03864 B03870 B04011 B04016 B04251 B04255 B04261 B04006);

	@group_1 = qw(B03680 B03729 B03734 B03739 B03818 B03852 B03858 B03864 B03870);
	@group_2 = qw(B04011 B04016 B04251 B04255 B04261 B04006);

	@channel_array = qw(T2 T2star X);
#	@channel_array = qw(T2star X);

    
	$flip_x = 1;
	$flip_z = 0;
	
	$optional_suffix = 'norm_youngmice';
	$atlas_name = 'chass_symmetric2';#
	$label_atlas_name = 'chass_symmetric2';#
	
	$rigid_contrast = 'T2';
	## $affine_contrast = 'dwi';
        $affine_metric = 'MI';
	#$affine_radius=32;
	#$affine_sampling_options = 'Regular,0.75';
	#$affine_gradient_step = 0.05;
	$affine_iterations = '3000x3000x3000x0';
	#$affine_convergence_thresh = '1e-6';
        #$affine_convergence_window = 15;
	$affine_smoothing_sigmas= '0x0x0x0vox';
	$affine_shrink_factors = '6x4x2x1';
	##$affine_target;

	$mdt_contrast = 'T2';
	#$diffeo_metric = 'CC';
	#$diffeo_radius = 4;
	#$diffeo_shrink_factors = '8x4x2x1'; # Commented out to test default behavior.
	#$diffeo_iterations = '500x500x500x500';
	$diffeo_transform_parameters ='0.3,3,1';#'0.5,3,1';
	#$diffeo_convergence_thresh = '1e-7';
	#$diffeo_convergence_window = 15;
	#$diffeo_smoothing_sigmas = '4x2x1x0vox';
	#$diffeo_sampling_options = 'Random,1';

	$smoothing_comma_list ='1';#,1.5,2';

	$skull_strip_contrast = 'T2';
	$threshold_code = 4;
	$do_mask = 0; #1
	$port_atlas_mask = 0; #1    
	$pre_masked = 1; #0	
    }
elsif ($john_multicoil)
    
    {
	$project_name = "13.gpc.05";
	$custom_predictor_string = "isocenter_vs_offcenter";
	$vbm_reference_space = "native";
	#$vbm_reference_space="/glusterspace/VBM_16gaj38_DTI101b-work/preprocess/base_images/reference_image_native_N54470.nii.gz";
	$create_labels = 1;

	@control_group = qw(B05111);
	@compare_group = qw(B10030 B10031 B10016 B10025 B10032 B10033 B10040 B10046);
#	@control_group = qw(B05111 B10030 B10031 B10016 B10025 B10032 B10033);
#	@compare_group = qw(dummy);

	@channel_array = qw(dwi fa);#e1 e2 e3 adc);
	#@channel_array = qw(mask);
    
	$flip_x = 1;
	$flip_z = 1;
	
	$optional_suffix = 'test';
	$atlas_name = 'chass_symmetric2';#'DTI101b';#
	$label_atlas_name = 'chass_symmetric2';#
	
	$rigid_contrast = 'dwi';
	## $affine_contrast = 'dwi';
	#$affine_radius=32;
	$affine_metric = 'MI';
	$affine_shrink_factors = '6x4x2x1';
	$affine_iterations = '500x500x500x500';
	$affine_gradient_step = 0.05;
	$affine_convergence_thresh = '1e-7';
        $affine_convergence_window = 20;
	$affine_smoothing_sigmas= '0x0x0x0vox';
	#$affine_sampling_options = 'Random,0.5';
	#$affine_target='S6546at9';

	$mdt_contrast = 'fa';
	$diffeo_metric = 'CC';
	$diffeo_radius = 4;
	$diffeo_shrink_factors = '8x4x2x1'; # Commented out to test default behavior.
	$diffeo_iterations = '500x500x500x500';
	$diffeo_transform_parameters = '0.5,3,0.5';
	$diffeo_convergence_thresh = '1e-7';
	$diffeo_convergence_window = 15;
	#$diffeo_smoothing_sigmas = '0.9x0.6x0.3,0.15x0mm';
	#$diffeo_sampling_options = 'Random,0.5';


	$skull_strip_contrast = 'dwi';
	$threshold_code = 3;
	$do_mask = 1;
	$port_atlas_mask = 0;    
	$pre_masked = 0;	
    }
elsif ($nian_connectome)
    
    {
	$project_name = "16.gaj.38";
	#$custom_predictor_string = "isocenter_vs_offcenter";
	#$vbm_reference_space = "native";
	#$vbm_reference_space="/glusterspace/VBM_16gaj38_DTI101b-work/preprocess/base_images/reference_image_native_N54470.nii.gz";
	#$vbm_reference_space="/glusterspace/VBM_16gaj38_DTI101b_42p5um-work/preprocess/base_images/reference_image_native_N54538.nii.gz";
	$vbm_reference_space='/glusterspace/VBM_16gaj38_DTI101b_45p4um-work/preprocess/base_images/reference_image_native_N54633.nii.gz';
	$create_labels = 1;

	@control_group = qw(chass_symmetric2);
	#@compare_group = qw(N54633);
	#@compare_group = qw(N54538 N54539 N54540 N54528_29_1);

	@compare_group = qw(N54627_01 N54598_2000_6_12 N54599_2000_6_12 N54600_2000_6_12 N54601_2000_6_12 N54633 N54634 N54635 N54636 N54637);

	@channel_array = qw(dwi fa);
	#@channel_array = qw(mask);
    
	$flip_x = 0;
	$flip_z = 1;
	
	$optional_suffix = '45p4um';
	$atlas_name = 'DTI101b';#
	$label_atlas_name = 'chass_symmetric2';#
	
	$rigid_contrast = 'dwi';
	$affine_iterations = '500x500x500x500';
	$affine_gradient_step = 0.05;

	$mdt_contrast = 'fa';
	$diffeo_metric = 'CC';
	#$diffeo_radius = 4;
	#$diffeo_shrink_factors = '8x4x2x1'; # Commented out to test default behavior.
	#$diffeo_iterations = '500x500x500x500';
	$diffeo_transform_parameters = '0.5,3,0.5';
	#$diffeo_convergence_thresh = '1e-7';
	#$diffeo_convergence_window = 15;
	#$diffeo_smoothing_sigmas = '0.9x0.6x0.3,0.15x0mm';
	#$diffeo_sampling_options = 'Random,0.5';


	$skull_strip_contrast = 'dwi';
	$threshold_code = 2900;
	# custom thresholds for CS study
#	$thresh_ref = {
#	    'N54538'   => 2600,
#	    'N54539'   => 1600,
#           'N54528_29_1' => 2350,
#	    'N54540'   => 1230
#	};


	$do_mask = 1; #1
	$port_atlas_mask = 0;#1
	$pre_masked = 0;	
    }  elsif ($spectrin) 

    {
	$project_name = "16.bennett.03";
	$create_labels = 1; # Turning this off for phantom analysis -- will turn back on if needed.
	$mdt_creation_strategy = 'iterative';
	$mdt_iterations = 6; #6
	#$mdt_convergence_threshold # Need to figure out how to use this!

	$do_connectivity = 1;
	$recon_machine = 'atlasdb';
	$convert_labels_to_RAS = 1;

	$diffeo_transform_parameters = "0.25,3,0.5"; # control #all  #phantom #Fantom #Xantom #Vantom #Xall
	$diffeo_iterations = '3000x3000x3000x80';

	$vbm_reference_space = 'native';
	$label_space = "post_affine";
	
	@control_group = qw(N54435 N54441 N54443 N54451 N54453 N54455 N54431 N54433 N54437 N54439 N54445 N54447 N54449 );
	@compare_group = @control_group;
	$template_predictor = 'all';

	@group_1 = qw(N54435 N54441 N54443 N54451 N54453 N54455);
	@group_2 = qw(N54431 N54433 N54437 N54439 N54445 N54447 N54449);
	$custom_predictor_string = "WT_vs_spectrinKO";

	
	@channel_array = qw(adc dwi e1 e2 e3 fa); # This will be determined by command line, and will be able to include STI, T1, T2, T2star, etc.
    	#@channel_array = qw(dwi fa); #Just these two for now so we don't overload glusterspace

#	$vba_contrast_comma_list = 'jac'; # Introduced so we could specify that only jac needs to be rerun, but can be used whenever needed.

	$vba_analysis_software = 'surfstat';



	$flip_x = 0;
	$flip_z = 1;
	
        $optional_suffix='spectrin';
	$atlas_name = 'chass_symmetric2';
	$label_atlas_name = 'chass_symmetric2';
	$rigid_contrast = 'dwi';
	$affine_contrast = 'dwi';
	$mdt_contrast = 'fa';
	$skull_strip_contrast = 'dwi';
	$threshold_code = 4; #4 didn't seem to work...
	$do_mask = 1;
    
	$pre_masked = 0;

	$port_atlas_mask = 0;

	
    } elsif ($ankB) 

    {
	$project_name = "16.bennett.03";
	$create_labels = 1; # Turning this off for phantom analysis -- will turn back on if needed.
	$mdt_creation_strategy = 'iterative';
	$mdt_iterations = 6; #6
	#$mdt_convergence_threshold # Need to figure out how to use this!

	$do_connectivity = 1;
	$recon_machine = 'piper';
	$eddy_current_correction = 0; # Was 1, but want to be consistent with spectrin for now...
	$convert_labels_to_RAS = 1;

	$diffeo_transform_parameters = "0.25,3,0.5"; # control #all  #phantom #Fantom #Xantom #Vantom #Xall
	$diffeo_iterations = '3000x3000x3000x80';

	$vbm_reference_space = 'native';
	$label_space = "post_affine,post_rigid,MDT"; #Revisiting this idea after fixing stray $label_space -> $current_label_space
	#$label_space = 'pre_rigid,post_rigid'; # 28 April 2017: Still haven't got this multiple label_space thing perfected...will need to come back to it.
	#$label_space = 'atlas';
	#$label_space= 'pre_rigid';
	
	
	@control_group = qw(N54703 N54694 N54695 N54696 N54697 N54643 N54645 N54647 N54649 N54698 N54701 N54702 );
	@compare_group = @control_group;
	$template_predictor = 'all';

	@group_1 = qw(N54703 N54694 N54695 N54696 N54697);
	@group_2 = qw(N54643 N54645 N54647 N54649 N54698 N54701 N54702 );
	$custom_predictor_string = "WT_vs_ankB";

	
	@channel_array = qw(adc dwi e1 e2 e3 fa); # This will be determined by command line, and will be able to include STI, T1, T2, T2star, etc.
#    	@channel_array = qw(dwi fa); #Just these two for now so we don't overload glusterspace

#	$vba_contrast_comma_list = 'jac'; # Introduced so we could specify that only jac needs to be rerun, but can be used whenever needed.

	$vba_analysis_software = 'surfstat';



	$flip_x = 0;
	$flip_z = 1;
	
        $optional_suffix='ankB';
	$atlas_name = 'chass_symmetric2';
	$label_atlas_name = 'chass_symmetric2';
	$rigid_contrast = 'dwi';
	$affine_contrast = 'dwi';
	$mdt_contrast = 'fa';
	$skull_strip_contrast = 'dwi';
	$threshold_code = 4;
	$do_mask = 1;
    
	$pre_masked = 0;

	$port_atlas_mask = 0;

	
    } elsif ($connectomics_control_test)
  {
	$project_name = "16.gaj.38";
	$create_labels = 1; # Turning this off for phantom analysis -- will turn back on if needed.
	$mdt_creation_strategy = 'iterative';
	$mdt_iterations = 6; #6
	#$mdt_convergence_threshold # Need to figure out how to use this!

	$do_connectivity = 1;
	#$recon_machine = 'piper';
	$eddy_current_correction = 0; # Was 1, but want to be consistent with spectrin for now...
	$convert_labels_to_RAS = 1;

	$diffeo_transform_parameters = "0.25,3,0.5"; # control #all  #phantom #Fantom #Xantom #Vantom #Xall
	$diffeo_iterations = '3000x3000x3000x80';

	$vbm_reference_space = 'native';
	$label_space = 'MDT';#'pre_rigid,atlas,post_rigid,MDT,pre_affine,post_affine';
	
	#$recon_machine = "atlasdb";	

	@control_group = qw(N54730 N54732 N54734 N54737 N54742 N54744);
	@compare_group = (@control_group);#,qw(N54776 N54777 N54779 N54781));
	#@compare_group = @control_group;
	#
	$template_predictor = 'controls';
	$template_predictor = 'all';
	if (1) {
	    @group_1 = qw(N54730 N54732 N54734 N54737 N54742 N54744);
	    @group_2 = ();# qw(N54776 N54777 N54779 N54781);
	    $custom_predictor_string = "C57_vs_DB2";
	} else {
	    $do_vba = 0;
	}
	
#	@channel_array = qw(adc dwi e1 e2 e3 fa); # This will be determined by command line, and will be able to include STI, T1, T2, T2star, etc.
    	@channel_array = qw(dwi fa tensor); #Just these two for now so we don't overload glusterspace

#	$vba_contrast_comma_list = 'jac'; # Introduced so we could specify that only jac needs to be rerun, but can be used whenever needed.

#	$vba_analysis_software = 'surfstat';



	$flip_x = 0;
	$flip_z = 1; #1
	
        $optional_suffix='connectomics';
	$atlas_name = 'chass_symmetric2';
	$label_atlas_name = 'chass_ALS_whole';
	$rigid_contrast = 'dwi';
	$affine_contrast = 'dwi';
	$mdt_contrast = 'fa';
	$skull_strip_contrast = 'dwi';
	$threshold_code = 4;
	$do_mask = 1;
    
	$pre_masked = 0;

	$port_atlas_mask = 0;	
    }
}
sub  load_study_data_vbm {

	my $bd = '/glusterspace'; #bd for Biggus-Diskus
	my $preprocess_path = $Hf->get_value('preprocess_dir');
	my @all_runnos =  split(',',$Hf->get_value('complete_comma_list'));

    if ($obrien) {
	`cp /glusterspace/VBM_14obrien01_DTI101b-work/base_images/* ${preprocess_path}`;
    } elsif ($obrien_invivo) {
	`cp /glusterspace/VBM_14obrien02_DTI101b-work/base_images/* ${preprocess_path}`;
    } elsif ($colton) {
	my $dr =$Hf->get_value('pristine_input_dir');
	foreach my $runno (@all_runnos) {
	    my $path_string = "${bd}/${runno}Labels-inputs/${runno}/";
	    `cp ${path_string}/* $dr/`;
	}
    } elsif ($mcnamara) {
	`cp /glusterspace/VBM_13mcnamara02_DTI101-work/base_images/* ${preprocess_path}`;
#	foreach my $runno (@all_runnos) {
#	    my $path_string = "${bd}/${runno}_m0Labels-results/";
#	    foreach my $contrast (@channel_array){
#	    
#	    `cp ${path_string}/*DTI_${contrast}*.nii ${preprocess_path}/${runno}_${contrast}.nii`;
#	    }	    
#	}

    } elsif ($premont) {
	`cp /glusterspace/VBM_11premont01_whs-work/base_images/* ${preprocess_path}`;
   } elsif ($premont) {
       `cp /glusterspace/VBM_10sullivan01_DTI101-work/preprocess/base_images/* ${preprocess_path}`;
    }

}
1;

