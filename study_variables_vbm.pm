#!/usr/local/pipeline-link/perl

# study_variables_vbm.pm 

# Created 2014/12/23 BJ Anderson for use in VBM pipeline.


my $PM = "study_variables_vbm.pm";
my $VERSION = "2015/02/11";
my $NAME = "In lieu of commandline functionality, here is the place to define various variables.";


my $obrien = 0;
my $obrien_invivo=0;
my $colton = 0;
my $colton_invivo = 0;
my $mcnamara = 0;
my $premont = 0;
my $premont_ct = 0;
my $dave = 0;
my $bj = 0;
my $bj_group = 0;
my $agoston = 1;
my $apoe = 0;
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

$image_dimensions
); # Need to replace $native_reference_space with $reference_space


sub study_variables_vbm {
    ## These defaults have been moved to the appropriate Init sections of the various modules ##
    #$diffeo_iterations = "4000,4000,4000,4000";  #Previous default; moved to pairwise_init_check
    #$diffeo_shrink_factors="8,4,2,1"; #Previous default; moved to pairwise_init_check
    #$affine_target = "NO_KEY"; # If not specified, will follow default behaviour of selecting first listed control runno.
    #$affine_contrast = "NO_KEY";
    $vbm_reference_space = "native";# "native"; # Options: "native", "<atlas_name>","<full path to an arbitrary image>"
    
    $create_labels = 1;
    $label_space = "pre_affine"; # options are "pre_rigid","pre_affine"/"post_rigid","post_affine". 
    # Note: pre_affine/post_rigid is not available with $combined_rigid_and_affine =1 & $old_ants = 1.
    $port_atlas_mask =0; # This is just setting the default.
    $combined_rigid_and_affine = 0; # Will eventually always be "0" (and hardcoded accordingly)
## Study variables for O'Brien
    if ($obrien) {
	
	$project_name = "14.obrien.01";
	$custom_predictor_string = "Control_vs_Reacher";
	$diffeo_transform_parameters = "0.5,3,1";#0.5";
	$combined_rigid_and_affine = 0; # We want to eventually have this set to zero and remove this variable from the code.
	$vbm_reference_space = "native";
	$create_labels = 0; #1
	$label_space = "pre_affine";

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


	# @compare_group = qw(
	#     BCS10
	#     BCS11
	#     BCS4
	#     BCS7
	#     BCS8
	#     BCS9
	#     BCU1
	#     BCU7
        #     BCW1
        #     BCW4
        #     BCW6
        #     BCW9      
	#     BRS1
	#     BRS2
	#     BRS3
	#     BRS5
	#     BRS6
	#     BRU2
	#     BRU3
        #     BRU5
        #     BRW3
        #     BRW5
        #     BRW7
        #     BRW8
	#     ICS10
	#     ICS11
	#     ICS4
	#     ICS7
	#     ICS8
	#     ICS9
	#     ICU1
	#     ICU7
        #     ICW1
        #     ICW4
        #     ICW6
        #     ICW9
	#     IRS1
	#     IRS2
	#     IRS3
	#     IRS5
	#     IRS6
	#     IRU2
	#     IRU3
        #     IRU5
        #     IRW3
        #     IRW5
        #     IRW7
        #     IRW8
	#     TCS10
	#     TCS11
	#     TCS4
	#     TCS7
	#     TCS8
	#     TCS9
	#     TCU1
	#     TCU7
	#     TRS1
	#     TRS2
	#     TRS3
	#     TRS5
	#     TRS6
	#     TRU2
	#     TRU3
        #     TRU5
        #     TCW1
        #     TCW4
        #     TCW6
        #     TCW9
        #     TRW3
        #     TRW5
        #     TRW7
        #     TRW8
        # );

	@channel_array = qw(dwi fa adc); 
#	@channel_array = qw(dwi fa);


	$flip_x = 0;
	$flip_z = 0;

	$optional_suffix = 'SyN3and1';
	$atlas_name = 'DTI101b';
	$label_atlas_name = 'chass_symmetric';#'dti148lr';
	$rigid_contrast = 'dwi';
	$mdt_contrast = 'fa'; #WAS fa
	$skull_strip_contrast = 'dwi';
	$threshold_code = 4;
	$do_mask = 0;
	$pre_masked = 1;

	$thresh_ref = {};

    } elsif ($obrien_invivo) {
	
	$project_name = "14.obrien.02";
	$custom_predictor_string = "Control_vs_Reacher";
	$diffeo_transform_parameters = "0.5,3,0.5";
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
	$optional_suffix = 'aTest6';
	$diffeo_transform_parameters = "0.5,3,1";
	$combined_rigid_and_affine = 1; # We want to eventually have this set to zero and remove this variable from the code.
	$vbm_reference_space = "native";
	$create_labels = 1;
	$label_space = "pre_affine";

	if ($test_mode) {
	    @control_group = qw(N51386 N51211 N51221);# N51406);
	    @compare_group = qw(N51136 N51201);# N51234 N51392);
	    @channel_array = qw(dwi fa);
	    $affine_target = 'N51211';
	    $label_reference = "";
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
    }

    elsif ($colton_invivo) 
    
### Study variables for Colton in vivo.
    {
	$project_name = "13.colton.01";
	$custom_predictor_string = "nos2_vs_cvn";
	$optional_suffix = 'invivo';
	$diffeo_transform_parameters = "0.5,3,1";
	$combined_rigid_and_affine = 0; # We want to eventually have this set to zero and remove this variable from the code.
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
#	$custom_predictor_string = "Control_vs_Phantoms";
	$custom_predictor_string = "Control_vs_KA";
##	$diffeo_transform_parameters = "0.5,3,0.5"; Not used for paper

#	$diffeo_transform_parameters = "1,3,1"; # COMPLETED -- Have LR labelset
#	$diffeo_transform_parameters = "5,3,1"; # COMPLETED -- Have LR labelset
#	$diffeo_transform_parameters = "0.5,3,1"; # COMPLETED 8 Sept 15 -- Have LR labelset

#	$diffeo_transform_parameters = "1,3,3"; # COMPLETED -- Have LR labelset
#	$diffeo_transform_parameters = "5,3,3"; # COMPLETED -- Have LR labelset
#	$diffeo_transform_parameters = "0.5,3,3";  # COMPLETED 16 Sept 15 ~ 12 am -- Have LR labelset

#	$diffeo_transform_parameters = "1,1,0"; # COMPLETED 19 Sept 15 ~ 12:30 pm , didn't start next one until 9 pm -- Have LR labelset
#	$diffeo_transform_parameters = "5,1,0"; # COMPLETED 20 Sept 15 ~ 8:45 pm -- Have LR labelset
	$diffeo_transform_parameters = "0.5,1,0"; # NEED TO RUN!!!


	$vbm_reference_space = "DTI101b";
	$combined_rigid_and_affine = 0; # Was 1 for January runs.  We want to eventually have this set to zero and remove this variable from the code.
	$label_space = "pre_affine"; # options are "pre_rigid","pre_affine"/"post_rigid","post_affine".

	@control_group = qw(S64944 S64953 S64959 S64962 S64968 S64974 S65394 S65408 S65411 S65414);
	@compare_group = qw(S64745 S64763 S64775 S64778 S64781 S65142 S65145 S65148 S65151 S65154);

#	@control_group = qw(S64944 S64953 S64959 S64962 S64968 S64974);# S65394 S65408 S65411 S65414);
#	@compare_group = qw(W64944 W64953 W64959 W64962 W64968 W64974 W65394 W65408 W65411 W65414);
#	@compare_group = qw(S64781);
#	@compare_group = qw(S64745 S64763 S64766 S64769 S64772 S64775 S64778 S64781 S65142 S65145 S65148 S65151 S65154);
	

	@channel_array = qw(adc dwi e1 e2 e3 fa); # This will be determined by command line, and will be able to include STI, T1, T2, T2star, etc.
#    	@channel_array = qw(dwi fa);

	$flip_x = 1;
#	$flip_x = 0;
	$flip_z = 0;
	
        $optional_suffix='SyN_1_3_1';
	$atlas_name = 'DTI101b';
	$label_atlas_name = 'DTI101b';
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
	# $diffeo_transform_parameters = ?;
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
 }  elsif ($premont_ct)
    
 {
     $project_name = "11.premont.01";
     $custom_predictor_string = "WT_vs_KO";
     $vbm_reference_space = "WT_111004_3"; #/glusterspace/VBM_11premont01_whs-work/base_images/N38709_T2star.nii.gz";
     # $diffeo_transform_parameters = ?;
     $combined_rigid_and_affine = 0; # We want to eventually have this set to zero and remove this variable from the code.
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
	$combined_rigid_and_affine = 0; # We want to eventually have this set to zero and remove this variable from the code.
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
	$combined_rigid_and_affine = 0; # We want to eventually have this set to zero and remove this variable from the code.
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
#	Excluded: N51913/N51914 ("presig: high" issue), N52114 (lost tuning during b0 scan)

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
N51823
N52023
N52123
N52623
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
N51843
N51943
N52043
N52143
N52643
N52843
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
N51863
N51963
N52063
N52163
N52663
N52863
);
#	Excluded: None
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
	$combined_rigid_and_affine = 0; # We want to eventually have this set to zero and remove this variable from the code.


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
	$custom_predictor_string = "sham_vs_injured";
	$vbm_reference_space = "native";
	$combined_rigid_and_affine = 0; # We want to eventually have this set to zero and remove this variable from the code.
	$create_labels = 1;

	@control_group = qw(S65456 S65459 S65466 S65521 S65530 S65533 S65537 S65541);
	#@compare_group = qw(S65453 S65461 S65464 S65467 S65524 S65528 S65535 S65539 S65544);
	@compare_group = qw(S66782 S66784 S66787 S66789 S66791 S66831 S66833 S66835 S66837  S66853 S66855 S66857 S66859 S66861 S66863 S66865 S66867 S66869);

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
	$combined_rigid_and_affine = 0;

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

