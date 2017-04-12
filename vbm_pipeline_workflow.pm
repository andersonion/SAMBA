#!/usr/local/pipeline-link/perl
# vbm_pipeline_workflow.pm
# vbm_pipeline created 2014/11/17 BJ Anderson CIVM
# vbm_pipeline_workflow created 2017/03/14 BJ Anderson CIVM
#
# Roughly modeled after seg_pipe_mc structure. (For better or for worse.)
# Was formerly vbm_pipeline, with study_variables.pm providing vast majority of user input
# Ironically, it is being split so we can reuse this same code as a segmentation pipeline


# All my includes and requires are belong to us.
# use ...

my $PM = 'vbm_pipeline_workflow.pm'; 

use strict;
use warnings;
no warnings qw(uninitialized bareword);

use Cwd qw(abs_path);
use File::Basename;
use List::MoreUtils qw(uniq);
use vars qw($Hf $BADEXIT $GOODEXIT $test_mode $combined_rigid_and_affine $syn_params $permissions $intermediate_affine $valid_formats_string $nodes $reservation $broken  $mdt_to_reg_start_time);
use Env qw(ANTSPATH PATH BIGGUS_DISKUS WORKSTATION_DATA WORKSTATION_HOME);

$ENV{'PATH'}=$ANTSPATH.':'.$PATH;
$ENV{'WORKSTATION_HOME'}="/cm/shared/workstation_code_dev";
$GOODEXIT = 0;
$BADEXIT  = 1;
my $ERROR_EXIT=$BADEXIT;
$permissions = 0755;
my $interval = 0.1; ##Normally 1
$valid_formats_string = 'hdr|img|nii';

# a do it again variable, will allow you to pull data from another vbm_run
my $import_data = 1;
$broken = 0;


$intermediate_affine = 0;
$test_mode = 0;

#$nodes = shift(@ARGV);
# $reservation='';

# if (! defined $nodes) {
#     $nodes = 4 ;}
# else {
#     if ($nodes =~ /[^0-9]/) { # Test to see if this is not a number; if so, assume it to be a reservation.
# 	$reservation = $nodes;
# 	my $reservation_info = `scontrol show reservation ${reservation}`;
# 	if ($reservation_info =~ /NodeCnt=([0-9]*)/m) { # Unsure if I need the 'm' option)
# 	    $nodes = $1;
# 	} else {
# 	    $nodes = 4;
# 	    print "\n\n\n\nINVALID RESERVATION REQUESTED: unable to find reservation \"$reservation\".\nProceeding with NO reservation, and assuming you want to run on ${nodes} nodes.\n\n\n"; 
# 	    $reservation = '';
# 	    sleep(5);
# 	}
#     }
# }


# print "nodes = $nodes; reservation = \"$reservation\".\n\n\n";
# if (! defined $broken) { $broken = 0 ;} 

umask(002);

use lib dirname(abs_path($0));
use Env qw(RADISH_PERL_LIB);
if (! defined($RADISH_PERL_LIB)) {
    print STDERR "Cannot find good perl directories, quitting\n";
    exit;
}
use lib split(':',$RADISH_PERL_LIB);

# require ...
require Headfile;
require retrieve_archived_data;
require study_variables_vbm;

require convert_all_to_nifti_vbm;
require set_reference_space_vbm;
require create_rd_from_e2_and_e3_vbm;
require mask_images_vbm;
require create_affine_reg_to_atlas_vbm;
require apply_affine_reg_to_atlas_vbm;
require iterative_pairwise_reg_vbm;
require pairwise_reg_vbm;
require calculate_mdt_warps_vbm;
require iterative_calculate_mdt_warps_vbm;
require iterative_apply_mdt_warps_vbm;
require apply_mdt_warps_vbm;
require calculate_mdt_images_vbm;
require compare_reg_to_mdt_vbm;
require mdt_reg_to_atlas_vbm;
require warp_atlas_labels_vbm;
require mask_for_mdt_vbm;
require calculate_jacobians_vbm;
require smooth_images_vbm;
require vbm_analysis_vbm;

# Temporary hardcoded variables

# variables, set up by the study vars script(study_variables_vbm.pm)
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

$vbm_reference_space
$reference_path
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

$image_dimensions
 );


sub vbm_pipeline_workflow { 
if (! defined $do_vba) {
    $do_vba = 0;
}


# $label_reference_path

#study_variables_vbm();  14 March 2017 -- Commenting this line is the main conversion from vbm_pipeline to vbm_pipeline_workflow

# if (($diffeo_transform_parameters eq '') || (! defined $diffeo_transform_parameters)) {
#     $diffeo_transform_parameters = "0.5,3,0"; # Should decide on default values...
# }

## The following are mostly ready-to-go variables (i.e. non hard-coded)

if ($optional_suffix ne '') {
    $optional_suffix = "_${optional_suffix}";
}
my $main_folder_prefix;
if ($do_vba) {
    $main_folder_prefix = 'VBM_';
} else  {
    $main_folder_prefix = 'SingleSegmentation_';
}
my @project_components = split(/[.]/,$project_name); # $project_name =~ s/[.]//g;
my $project_id =  join('',@project_components);
$project_id = $main_folder_prefix.$project_id.'_'.$atlas_name.$optional_suffix; #create_identifer($project_name);


my ($pristine_input_dir,$work_dir,$result_dir,$result_headfile) = make_process_dirs($project_id); #new_get_engine_dependencies($project_id);

## Mini-kludge...until we can get a proper data importer in place...
my $test_for_inputs = `ls ${pristine_input_dir}`;
if ($test_for_inputs eq '') {
    $import_data = 1;
} 


$import_data = 0;

#  Mini-kludge


## Headfile setup code starts here

$Hf = new Headfile ('rw',$result_headfile );
my $log_file = open_log($result_dir);
my $stats_file = $log_file;
if ($stats_file =~ s/pipeline_info/job_stats/) {
    $Hf->set_value('stats_file',$stats_file);
}


my $preprocess_dir = $work_dir.'/preprocess';
my $inputs_dir = $preprocess_dir.'/base_images';


## The following work is to remove duplicates from processing lists (adding the 'uniq' subroutine). 15 June 2016

my @all_runnos = uniq(@control_group,@compare_group);

my $control_comma_list = join(',',uniq(@control_group));
my $compare_comma_list = join(',',uniq(@compare_group));
#my $complete_comma_list = $control_comma_list.','.$compare_comma_list;
my $complete_comma_list =join(',',uniq(@all_runnos));
my $channel_comma_list = join(',',uniq(@channel_array));

if ($do_vba) {
    my $group_1_runnos;
    my $group_2_runnos;
    if (defined @group_1) {
	$group_1_runnos = join(',',uniq(@group_1));
	$Hf->set_value('group_1_runnos',$group_1_runnos);
    }

    if (defined @group_2) {
	$group_2_runnos = join(',',uniq(@group_2));
	$Hf->set_value('group_2_runnos',$group_2_runnos);
    }
    
    if ((defined @group_1)&&(defined @group_2)) { 
	my @all_in_groups = uniq(@group_1,@group_2);
	#my $all_groups_comma_list = $group_1_runnos.','.$group_2_runnos;
	my $all_groups_comma_list = join(',',@all_in_groups) ;
	$Hf->set_value('all_groups_comma_list',$all_groups_comma_list);
    }
}


## End duplication control


$Hf->set_value('project_id',$project_id);

if (defined $image_dimensions) {
    $Hf->set_value('image_dimensions',$image_dimensions);
} else {
    $Hf->set_value('image_dimensions',3);
}

$Hf->set_value('vbm_reference_space',$vbm_reference_space);
if ($label_reference ne '') {
    $Hf->set_value('label_reference_space',$label_reference);
}

$Hf->set_value('control_comma_list',$control_comma_list);
$Hf->set_value('compare_comma_list',$compare_comma_list);
$Hf->set_value('complete_comma_list',$complete_comma_list);
$Hf->set_value('channel_comma_list',$channel_comma_list);

if (($combined_rigid_and_affine eq '') || (! defined $combined_rigid_and_affine)) {
    $combined_rigid_and_affine=0; # Temporary default--> will eventually always be set to "0"
}

$Hf->set_value('combined_rigid_and_affine',$combined_rigid_and_affine);


if (defined $affine_contrast) {
    $Hf->set_value('affine_contrast',$affine_contrast);
}

if (defined $affine_metric) {
    $Hf->set_value('affine_metric',$affine_metric);
}

if (defined $affine_radius) {
    $Hf->set_value('affine_radius',$affine_radius);
}

if (defined $affine_shrink_factors) {
    $Hf->set_value('affine_shrink_factors',$affine_shrink_factors);
}

if (defined $affine_iterations) {
    $Hf->set_value('affine_iterations',$affine_iterations);
}

if (defined $affine_gradient_step) {
    $Hf->set_value('affine_gradient_step',$affine_gradient_step);
}

if (defined $affine_convergence_thresh) {
    $Hf->set_value('affine_convergence_thresh',$affine_convergence_thresh);
}

if (defined $affine_convergence_window) {
    $Hf->set_value('affine_convergence_window',$affine_convergence_window);
}

if (defined $affine_smoothing_sigmas) {
    $Hf->set_value('affine_smoothing_sigmas',$affine_smoothing_sigmas);
}

if (defined $affine_sampling_options) {
    $Hf->set_value('affine_sampling_options',$affine_sampling_options);
}

if (defined $affine_target) {
    $Hf->set_value('affine_target',$affine_target);
}


if (defined $diffeo_metric) {
    $Hf->set_value('diffeo_metric',$diffeo_metric);
}

if (defined $diffeo_radius) {
    $Hf->set_value('diffeo_radius',$diffeo_radius);
}

if (defined $diffeo_shrink_factors) {
    $Hf->set_value('diffeo_shrink_factors',$diffeo_shrink_factors);}

if (defined $diffeo_iterations) {
    $Hf->set_value('diffeo_iterations',$diffeo_iterations);
}

if (defined $diffeo_transform_parameters) {
    $Hf->set_value('diffeo_transform_parameters',$diffeo_transform_parameters);
}

if (defined $diffeo_convergence_thresh) {
    $Hf->set_value('diffeo_convergence_thresh',$diffeo_convergence_thresh);
}

if (defined $diffeo_convergence_window) {
    $Hf->set_value('diffeo_convergence_window',$diffeo_convergence_window);
}

if (defined $diffeo_smoothing_sigmas) {
    $Hf->set_value('diffeo_smoothing_sigmas',$diffeo_smoothing_sigmas);
}

if (defined $diffeo_sampling_options) {
    $Hf->set_value('diffeo_sampling_options',$diffeo_sampling_options);
}

if (defined $smoothing_comma_list) {
    $Hf->set_value('smoothing_comma_list',$smoothing_comma_list);
}

if (defined $eddy_current_correction) {
    $Hf->set_value('eddy_current_correction',$eddy_current_correction);
}

if (defined $do_connectivity) {
    $Hf->set_value('do_connectivity',$do_connectivity);
}

$Hf->set_value('rigid_atlas_name',$atlas_name);
$Hf->set_value('rigid_contrast',$rigid_contrast);


$Hf->set_value('mdt_contrast',$mdt_contrast);

if (defined $mdt_creation_strategy) {
    $Hf->set_value('mdt_creation_strategy',$mdt_creation_strategy);
}

if (defined $mdt_iterations) {
 $Hf->set_value('mdt_iterations',$mdt_iterations);
}

if (defined $mdt_convergence_threshold) {
    $Hf->set_value('mdt_convergence_threshold',$mdt_convergence_threshold);
}

if (defined $initial_template) {
    $Hf->set_value('initial_template',$initial_template);
}

if (defined $fixed_image_for_mdt_to_atlas_registratation) {
    $Hf->set_value('fixed_image_for_mdt_to_atlas_registratation',$fixed_image_for_mdt_to_atlas_registratation);
}

$Hf->set_value('number_of_nodes_used',$nodes);

if ($create_labels) {
    my $label_atlas_dir = "${WORKSTATION_DATA}/atlas/${label_atlas_name}";
    $Hf->set_value('label_atlas_dir',$label_atlas_dir);
    $Hf->set_value('label_atlas_name',$label_atlas_name);
    if (! defined $label_space) {
	$label_space = "pre_affine"; # Pre-affine is the tentative default label space.
    }
    $Hf->set_value('label_space',$label_space);
}
$Hf->set_value('create_labels',$create_labels);
if (defined $convert_labels_to_RAS) {
    $Hf->set_value('convert_labels_to_RAS',$convert_labels_to_RAS);
} else {
    $Hf->set_value('convert_labels_to_RAS',0);
}

$Hf->set_value('skull_strip_contrast',$skull_strip_contrast);
$Hf->set_value('pre_masked',$pre_masked);
$Hf->set_value('threshold_code',$threshold_code);
$Hf->set_value('port_atlas_mask',$port_atlas_mask);
if (defined $port_atlas_mask_path) {
    $Hf->set_value('port_atlas_mask_path',$port_atlas_mask_path);
}

$Hf->set_value('rigid_transform_suffix','rigid.mat');

$Hf->set_value('affine_transform_suffix','affine.mat');
$Hf->set_value('affine_target_image',$affine_target);

if (defined $affine_contrast) {
    $Hf->set_value('affine_contrast',$affine_contrast);
}

if (defined $compare_contrast) {
    $Hf->set_value('compare_contrast',$compare_contrast);
}

$Hf->set_value('affine_identity_matrix',"$WORKSTATION_DATA/identity_affine.mat");

if (! defined $flip_x) {
    $flip_x = 0;
}

if (! defined $flip_z) {
    $flip_z = 0;
}

$Hf->set_value('flip_x',$flip_x);
$Hf->set_value('flip_z',$flip_z);

$Hf->set_value('do_mask',$do_mask);
if (defined $thresh_ref) {
    $Hf->set_value('threshold_hash_reference',$thresh_ref);
}


$Hf->set_value('predictor_id',$custom_predictor_string);

if (defined $template_predictor) {
    $Hf->set_value('template_predictor',$template_predictor);
}

if (defined $template_name) {
    $Hf->set_value('template_name',$template_name);
}

$Hf->set_value('pristine_input_dir',$pristine_input_dir);
$Hf->set_value('preprocess_dir',$preprocess_dir);
$Hf->set_value('inputs_dir',$inputs_dir);
$Hf->set_value('dir_work',$work_dir);
$Hf->set_value('results_dir',$result_dir);

$Hf->set_value('engine_app_matlab','/usr/local/bin/matlab');
$Hf->set_value('engine_app_matlab_opts','-nosplash -nodisplay -nodesktop');
$Hf->set_value('nifti_matlab_converter','civm_to_nii'); # This should stay hardcoded.


if ($test_mode) {
    $Hf->set_value('test_mode','on');
} else {
    $Hf->set_value('test_mode','off');    
}

$Hf->set_value('vbm_reference_space',$vbm_reference_space);

if (defined $vba_contrast_comma_list) {
    $Hf->set_value('vba_contrast_comma_list',$vba_contrast_comma_list);
}

if (defined $vba_analysis_software) {
    $Hf->set_value('vba_analysis_software',$vba_analysis_software);
}


#maincode

print STDOUT " Running the main code of $PM. \n";


## Initilization code starts here.

# Check command line options and report related errors

    # Check backwards.  This will avoid replicating the check for needed input data at every step.
    # Report errors forwards, since this is more user friendly.
    my $init_error_msg='';
    

    my @modules_for_Init_check = qw(
     convert_all_to_nifti_vbm
     create_rd_from_e2_and_e3_vbm
     mask_images_vbm
     set_reference_space_vbm
     create_affine_reg_to_atlas_vbm
     apply_affine_reg_to_atlas_vbm
     pairwise_reg_vbm
     iterative_pairwise_reg_vbm
     calculate_mdt_warps_vbm
     iterative_calculate_mdt_warps_vbm
     apply_mdt_warps_vbm
     iterative_apply_mdt_warps_vbm
     calculate_mdt_images_vbm
     mask_for_mdt_vbm
     compare_reg_to_mdt_vbm
     mdt_reg_to_atlas_vbm
     warp_atlas_labels_vbm
     calculate_jacobians_vbm
     vbm_analysis_vbm
     apply_warps_to_bvecs
      );
#     smooth_images_vbm
#     );
    
    
    my $checkCall; # Using camelCase here to avoid the potential need for playing the escape character game when calling command with backticks, etc.
    my $Init_suffix = "_Init_check()";
    
   
   # for (my $mm = $#modules_for_Init_check; $mm >=0; $mm--)) { # This checks backwards
    for (my $mm = 0; $mm <= $#modules_for_Init_check; $mm++) { # This checks forwards
	my $module = $modules_for_Init_check[$mm];	 
	$checkCall = "${module}${Init_suffix}";
	print STDOUT "Check call is $checkCall\n";
	my $temp_error_msg = '';

	($temp_error_msg) = eval($checkCall);
	
	if ($temp_error_msg ne '') {
	    if ($init_error_msg ne '') {
		$init_error_msg = "${init_error_msg}\n------\n\n${temp_error_msg}"; # This prints the results forwards
		# $init_error_msg = "${temp_error_msg}\n------\n\n${init_error_msg}"; # This prints the results backwards
	    } else {
		$init_error_msg = $temp_error_msg;
	    }
	}
    }
    
    if ($init_error_msg ne '') {
	log_info($init_error_msg,0);
	error_out("\n\nPrework errors found:\n${init_error_msg}\nNo work has been performed!\n");
    } else {
	log_info("No errors found during initialization check stage.\nLet the games begin!\n");
    }
    
  
# Finish headfile


# Begin work:

    if (! -e $inputs_dir) {
	mkdir($inputs_dir,0777);
    }
    if ($import_data) { 
	load_study_data_vbm(); #$PM_code = 11
    }

my $nii4D = 0;
if ($do_connectivity) {
    $nii4D = 1;
}
pull_data_for_connectivity();


# Need to pass the nii4D flag in a more elegant manner...
#my $nii4D = 1;
my $original_channel_comma_list = $channel_comma_list;
my @original_channel_array = @channel_array;

if ($nii4D) {
    push(@channel_array,'nii4D');
    $channel_comma_list = $channel_comma_list.',nii4D';
    $Hf->set_value('channel_comma_list',$channel_comma_list);
}
# Gather all needed data and put in inputs directory
convert_all_to_nifti_vbm(); #$PM_code = 12
sleep($interval);

# if ($nii4D) {  # Not needed if we are going to mask the nii4D along with other contrasts
#     @channel_array = @original_channel_array;
#     $channel_comma_list = $original_channel_comma_list;
#     $Hf->set_value('channel_comma_list',$channel_comma_list);
# }


if (create_rd_from_e2_and_e3_vbm()) { #$PM_code = 13
    push(@channel_array,'rd');
    push(@original_channel_array,'rd');
    $original_channel_comma_list = $original_channel_comma_list.',rd';
    $channel_comma_list = $original_channel_comma_list;
    $Hf->set_value('channel_comma_list',$channel_comma_list);
}
    sleep($interval);
    # Before 11 April 2017: nii4Ds were not masked; After 11 April 2017: nii4Ds are masked for processing/storage/reading/writing efficiency
    mask_images_vbm(); #$PM_code = 14
    sleep($interval);

# if ($nii4D) {  # Not needed if we are going to mask the nii4D along with other contrasts
#     push(@channel_array,'nii4D');
#     $channel_comma_list = $channel_comma_list.',nii4D';
#     $Hf->set_value('channel_comma_list',$channel_comma_list);
# }
    set_reference_space_vbm(); #$PM_code = 15
    sleep($interval);

if ($nii4D) {
    @channel_array = @original_channel_array;
    $channel_comma_list = $original_channel_comma_list;
    $Hf->set_value('channel_comma_list',$channel_comma_list);
}


# Register all to atlas
    my $do_rigid = 1;   
    create_affine_reg_to_atlas_vbm($do_rigid); #$PM_code = 21
    sleep($interval);

#    apply_affine_reg_to_atlas_vbm(); #UNUSED
#   sleep($interval);

    if (1) { #  Need to take out this hardcoded bit!
	$do_rigid = 0;
	create_affine_reg_to_atlas_vbm($do_rigid); #$PM_code = 39
	sleep($interval);
    }

   # pairwise_reg_vbm("a");
   # sleep($interval);    

   # calculate_mdt_warps_vbm("f","affine");
   # sleep($interval);
    
    my $group_name='';

## Different approaches to MDT creation start to diverge here. ## 2 November 2016
    if ($mdt_creation_strategy eq 'iterative') {

	#if (0) {
	#    iterative_template_construction_vbm("d"); # To Temporarily handle calling Nick/Brian's script (04 Nov 2016...will ultimately remove
	#} else {
	    my $starting_iteration=$Hf->get_value('starting_iteration');

	    if ($starting_iteration =~ /([1-9]{1}|[0-9]{2,})/) {
	    } else {
		$starting_iteration = 0;
	    }
	   # print "starting_iteration = ${starting_iteration}";
	   # die;

	    for (my $ii = $starting_iteration; $ii <= $mdt_iterations; $ii++) {  # Will need to add a "while" option that runs to a certain point of stability; We don't really count the 0th iteration because normally this is just the averaging of the affine-aligned images. 

		$ii = iterative_pairwise_reg_vbm("d",$ii); #$PM_code = 41 # This returns $ii in case it is determined that some iteration levels can/should be skipped.
		sleep($interval);

		iterative_calculate_mdt_warps_vbm("f","diffeo"); #$PM_code = 42
		sleep($interval);

		$group_name = "control";
		foreach my $a_contrast (@channel_array) {
		    apply_mdt_warps_vbm($a_contrast,"f",$group_name); #$PM_code = 43
		}
		calculate_mdt_images_vbm($ii,@channel_array); #$PM_code = 44
		sleep($interval);	    
	    }

	    mask_for_mdt_vbm(); #$PM_code = 45
	    sleep($interval);
	#}
    } else {
	pairwise_reg_vbm("d"); #$PM_code = 41
	sleep($interval);
	
	calculate_mdt_warps_vbm("f","diffeo"); #$PM_code = 42
	sleep($interval);

	calculate_mdt_warps_vbm("i","diffeo"); #$PM_code = 42
	sleep($interval);

	$group_name = "control";
	foreach my $a_contrast (@channel_array) {
	    apply_mdt_warps_vbm($a_contrast,"f",$group_name); #$PM_code = 43
	}
	calculate_mdt_images_vbm(@channel_array); #$PM_code = 44
	sleep($interval);

	mask_for_mdt_vbm(); #$PM_code = 45
	sleep($interval);
 
	if ($do_vba) {
#    calculate_jacobians_vbm('i','control'); #$PM_code = 47 (or 46) ## Goddam ANTs changed the fundamental definition of Jacobian, need to use forward 26 July 2016
	    calculate_jacobians_vbm('f','control'); #$PM_code = 47 (or 46) ## BAD code! Don't use this unless you are trying to make a point! #Just kidding its the right thing to do after all--WTH?!?
	    sleep($interval);
	}
    }

# Things can get parallel right about here...
    
# Branch one: 
    if ($create_labels) {
	$do_rigid = 0;
	my $mdt_to_atlas = 1;
	create_affine_reg_to_atlas_vbm($do_rigid,$mdt_to_atlas);  #$PM_code = 61
	sleep($interval);
	
	mdt_reg_to_atlas_vbm(); #$PM_code = 62
	sleep($interval);
    }

# Branch two:
    compare_reg_to_mdt_vbm("d"); #$PM_code = 51
    sleep($interval);
    #create_average_mdt_image_vbm(); ### What the heck was this?
    
    $group_name = "compare";    
    foreach my $a_contrast (@channel_array) {
	apply_mdt_warps_vbm($a_contrast,"f",$group_name); #$PM_code = 52 
    }
    sleep($interval);
    

# Remerge before ending pipeline
    
    if ($create_labels) {
	my $MDT_to_atlas_JobID = $Hf->get_value('MDT_to_atlas_JobID');
	my $real_time;
	if (cluster_check() && ($MDT_to_atlas_JobID ne 'NO_KEY') && ($MDT_to_atlas_JobID ne 'UNDEFINED_VALUE' )) {
	    my $interval = 15;
	    my $verbose = 1;
	    my $label_xform_dir=$Hf->get_value('label_transform_dir');
	    my $batch_folder = $label_xform_dir.'/sbatch/';
	    my $done_waiting = cluster_wait_for_jobs($interval,$verbose,$batch_folder,$MDT_to_atlas_JobID);
	    print " Waiting for Job ${MDT_to_atlas_JobID}\n";
	    if ($done_waiting) {
		print STDOUT  " Diffeomorphic registration from MDT to label atlas ${label_atlas_name} job has completed; moving on to next serial step.\n";
	    }
	    my $case = 2;
	    my ($dummy,$error_message)=mdt_reg_to_atlas_Output_check($case);

	    $real_time = write_stats_for_pm(62,$Hf,$mdt_to_reg_start_time,$MDT_to_atlas_JobID);
	    
	    if ($error_message ne '') {
		error_out("${error_message}",0);
	    }
	}
    
	if (($MDT_to_atlas_JobID eq 'NO_KEY') || ($MDT_to_atlas_JobID eq 'UNDEFINED_VALUE')) {
	    $real_time = write_stats_for_pm(62,$Hf,$mdt_to_reg_start_time);
	}
	print "mdt_reg_to_atlas.pm took ${real_time} seconds to complete.\n";

	warp_atlas_labels_vbm('MDT'); #$PM_code = 63
	sleep($interval);

	warp_atlas_labels_vbm(); #$PM_code = 63
	sleep($interval);

	$group_name = "all";    
	foreach my $a_contrast (@channel_array) {
	    apply_mdt_warps_vbm($a_contrast,"f",$group_name); #$PM_code = 64
	}
	sleep($interval);
	
	# label_statistics_vbm();#$PM_code = 65
	#sleep($interval);
    }   

if ($do_vba) {
#    my $new_contrast = calculate_jacobians_vbm('i','compare'); #$PM_code = 53 # Nope, this is bad--26 July 2016
    my $new_contrast = calculate_jacobians_vbm('f','compare'); #$PM_code = 53 # BAD code. Don't this unless trying to prove a point. # JK Kidding this code is right believe it or not.
    
    push(@channel_array,$new_contrast);
    $channel_comma_list = $channel_comma_list.','.$new_contrast;
    $Hf->set_value('channel_comma_list',$channel_comma_list);
    sleep($interval);
#    die;####
    vbm_analysis_vbm(); #$PM_code = 72
    sleep($interval);

   # smooth_images_vbm(); #$PM_code = 71 (now called from vbm_analysis_vbm)
    sleep($interval);
}

    $Hf->write_headfile($result_headfile);

    print "\n\nVBM Pipeline has completed successfully.  Great job, you.\n\n";

	
#    use civm_simple_util qw(whowasi whoami);	
#    my $process = whowasi();
#    my @split = split('::',$process);
#    $process = pop(@split);
    my $process = "vbm_pipeline";
    
    my $completion_message ="Congratulations, master scientist. Your VBM pipeline process has completed.  Hope you find something interesting.\n";
    my $time = time;
    my $email_folder = '/home/rja20/cluster_code/workstation_code/analysis/vbm_pipe/email/';			
    my $email_file="${email_folder}/VBM_pipeline_completion_email_for_${time}.txt";
    
    my $local_time = localtime();
    my $local_time_stamp = "This file was generated on ${local_time}, local time.\n";
    my $time_stamp = "Completion time stamp = ${time} seconds since January 1, 1970 (or some equally asinine date).\n";
   

    my $subject_line = "Subject: VBM Pipeline has finished!!!\n";

			
    #my $email_content = $subject_line.$completion_message.$time_stamp;
    my $email_content = $subject_line.$completion_message.$local_time_stamp.$time_stamp;
    `echo "${email_content}" > ${email_file}`;
    `sendmail -f $process.civmcluster1\@dhe.duke.edu rja20\@duke.edu < ${email_file}`;
    `sendmail -f $process.civmcluster1\@dhe.duke.edu 9196128939\@vtext.com < ${email_file}`;




} #end main

#---------------------
sub some_subroutine {
#---------------------

}
    
    
#---------------------
sub pull_data_for_connectivity {
#---------------------
    my $complete_runno_list=$Hf->get_value('complete_comma_list');
    my @array_of_runnos = split(',',$complete_runno_list);

    my $complete_channel_list=$Hf->get_value('channel_comma_list');
    my @array_of_channels = split(',',$complete_channel_list);

    my $inputs_dir = $Hf->get_value('pristine_input_dir');
    my $message_prefix="single_segmentation_start::pull_data_for_connectivity:\n";
    my $message_body;

    foreach my $runno(@array_of_runnos) {
	my $local_message_prefix="Attempting to retrieve data for runno: ${runno}\n";
	my $log_msg;
	my $tmp_log_msg;
	my $look_in_local_folder = 0;
	my $local_folder = "${inputs_dir}/tmp_folder/";
	my $number_of_headfiles;

	my $archive_prefix = '';
	my $machine_suffix = '';
	if ($recon_machine eq 'atlasdb') {
	    $archive_prefix = "${project_name}/research/";
	} else {
	    $machine_suffix = "-DTI-results"
	}

	# Look for more then two xform_$runno...mat files (ecc affine transforms)
	if ($do_connectivity){
	    if ((defined $eddy_current_correction) && ($eddy_current_correction ne 'NO_KEY') && ($eddy_current_correction == 1)) {
		my $temp_runno = $runno;
		if ($temp_runno =~ s/(\_m[0]+)$//){}
		my $number_of_ecc_xforms =  `ls ${inputs_dir}/xform_${temp_runno}*.mat | wc -l`;
		
		print "number_of_ecc_xforms = ${number_of_ecc_xforms}\n\n";
		if ($number_of_ecc_xforms < 6) { # For DTI, the minimum number of non-b0's is 6!
		    $tmp_log_msg = `puller_simple  -or ${recon_machine} ${archive_prefix}tensor${runno}*${machine_suffix}/ ${local_folder}/`;
		    $log_msg = $log_msg.$tmp_log_msg;
		    $tmp_log_msg = `mv ${local_folder}/xform*mat ${inputs_dir}`;
		    $log_msg = $log_msg.$tmp_log_msg;
		    $look_in_local_folder = 1;
		}
		
	    }
	}

	# get any specified "traditional" dti images
	foreach my $contrast (@array_of_channels) {
	    my $test_file =  get_nii_from_inputs($inputs_dir,$runno,$contrast);
	    my $pull_file_cmd = "puller_simple -f file -or ${recon_machine} ${archive_prefix}tensor${runno}*${machine_suffix}/${runno}*${contrast}.nii* ${inputs_dir}/";
	    
	    if ($test_file =~ /[\n]+/) {
		if ($look_in_local_folder) {
		    $test_file =  get_nii_from_inputs($local_folder,$runno,$contrast);
		    if ($test_file =~ /[\n]+/) {
			$tmp_log_msg = `${pull_file_cmd}`;
			$log_msg = $log_msg.$tmp_log_msg;
		    } else {
			$tmp_log_msg = `mv ${test_file} ${inputs_dir}`;
			$log_msg = $log_msg.$tmp_log_msg;
		    }
		} else {
		    $tmp_log_msg = `${pull_file_cmd}`;
		    $log_msg = $log_msg.$tmp_log_msg;
		}
	    }
	}
	
	if ($do_connectivity){
	    # get nii4D
	    my $nii4D = get_nii_from_inputs($inputs_dir,$runno,'nii4D');
	    my $orig_nii4D;
	    if ($nii4D =~ /[\n]+/) {
		$orig_nii4D =  get_nii_from_inputs($inputs_dir,'nii4D',$runno); # tensor_create outputs nii4D_$runno.nii.gz
		if ($orig_nii4D =~ /[\n]+/) {
		    my $pull_nii4D_cmd = `puller_simple -f file -or ${recon_machine} ${archive_prefix}/tensor${runno}*${machine_suffix}/nii4D_${runno}*.nii ${inputs_dir}/`; #Removed * after .nii so we don't accidentally pull fiber tracking results.  Let's just hope what we want is uncompressed. 11 April 2017, BJA
		    if ($look_in_local_folder) {
			my $test_file =  get_nii_from_inputs($local_folder,'nii4D',$runno);
			if ($test_file =~ /[\n]+/) {
			    $tmp_log_msg = `${pull_nii4D_cmd}`;
			    $log_msg = $log_msg.$tmp_log_msg;
			} else {
			    $tmp_log_msg = `mv ${test_file} ${inputs_dir}`;
			    $log_msg = $log_msg.$tmp_log_msg;
			}
		    } else {
			$tmp_log_msg = `${pull_nii4D_cmd}`;
			$log_msg = $log_msg.$tmp_log_msg;
		    }
		}
		$orig_nii4D =  get_nii_from_inputs($inputs_dir,'nii4D',$runno); # tensor_create outputs nii4D_$runno.nii.gz
		
		my $new_nii4D = "${inputs_dir}/${runno}_nii4D.nii";
		if ($orig_nii4D =~ /'.gz'/) {
		    $new_nii4D = $new_nii4D.'.gz';
		}
		$tmp_log_msg = `mv ${orig_nii4D} ${new_nii4D}`;
		$log_msg = $log_msg.$tmp_log_msg;
	    }
	
	
	    # get headfile
	    my $head_file = "${inputs_dir}/tensor${runno}*.headfile";
	    $number_of_headfiles =  `ls ${head_file} | wc -l`;
	    if ($number_of_headfiles < 1) {
		my $pull_headfile_cmd = "puller_simple -f file -or ${recon_machine} ${archive_prefix}tensor${runno}*${machine_suffix}/tensor${runno}*headfile ${inputs_dir}/";
		if ($look_in_local_folder) {
		    $head_file = "${local_folder}/tensor${runno}*.headfile";
		    $number_of_headfiles =  `ls ${head_file} | wc -l`;
		    if ($number_of_headfiles < 1) {
			$tmp_log_msg = `${pull_headfile_cmd}`;
			$log_msg = $log_msg.$tmp_log_msg;
		    } else {
			$tmp_log_msg = `mv ${head_file} ${inputs_dir}`;
			$log_msg = $log_msg.$tmp_log_msg;
		    }
		} else {
		    $tmp_log_msg = `${pull_headfile_cmd}`;
		    $log_msg = $log_msg.$tmp_log_msg;
		}
		
	    }
	}
	# Clean up temporary results folder
	if ($look_in_local_folder) {
	    #my $temp_folder = "${inputs_dir}/tensor${runno}*${machine_suffix}/";
	    #my $number_of_temp_results_folders =  `ls -d ${head_file} | wc -l`; # Not sure what I was doing with this...
	    if ($number_of_headfiles > 0) {
		$tmp_log_msg = `rm -r ${local_folder}`;
		$log_msg = $log_msg.$tmp_log_msg;
	    }
	}


	if ($do_connectivity) {
	    # Figure out which bvecs/bvals file to get
	    my @headfiles = `ls ${inputs_dir}/tensor${runno}*headfile`;
	    
	    my $current_headfile = $headfiles[0];
	    #my $current_Hf = read_headfile($current_headfile);
	    my $current_Hf = new Headfile ('rw', $current_headfile);
	    $current_Hf->read_headfile;
	    
	    # 10 April 2017, BJA: it's too much of a hassle to pull the bvecs file then try to figure out how to incorporate the bvals...
	    #     From now on we'll process these ourselves from the tensor headfile.
	    
	    my $original_gradient_location = $current_Hf->get_value('dti-recon-gradmat-file'); ## Unsure if this will work for Bruker...
	    my ($o_grad_path,$grad_filename,$grad_ext) = fileparts($original_gradient_location,2);
	    my $gradient_file = "${inputs_dir}/${runno}_${grad_filename}${grad_ext}";
	    # if (data_double_check($gradient_file)) { # Try pulling from tensor work folder first
	    #     my $bvec_machine;
	    #     if ($o_grad_path =~ s/^(\/){1}([A-Za-z1-9]*)(space\/)//){
	    # 	$bvec_machine = $2;
	    #     } else {
	    # 	$bvec_machine = $recon_machine;
	    #     }
	    #     my $pull_bvecs_cmd = "puller_simple -f file -or ${bvec_machine} ${o_grad_path}/${grad_filename}${grad_ext} ${inputs_dir};";
	    #     my $rename_bvecs_cmd ="mv ${inputs_dir}/${grad_filename}${grad_ext} ${gradient_file};";
	    #     $tmp_log_msg = `${pull_bvecs_cmd} ${rename_bvecs_cmd}`;
	    #     $log_msg = $log_msg.$tmp_log_msg;
	    # }
	
	    if (data_double_check($gradient_file)) { #If unable to pull in from tensor work folder, create bvecs from info in headfile 
		# This code is based on the shenanigans of tensor_create, as found in main_tensor.pl
		my $Hf_grad_info =  $current_Hf->get_value("gradient_matrix_auto");
		#parse bvecs
		my ($grad_dim_info,$Hf_grad_string) = split(',',$Hf_grad_info);
		my @Hf_gradients = split(' ',$Hf_grad_string);
		my ($num_bvecs,$v_dim) = split(':',$grad_dim_info);
		
		#parse bvals
		my $Bruker_data = 0; ### Temporarily only supporting Agilent data!
		
		my $approx_Hf_bval_handle;
		my $Hf_bval_handle;
		if (! $Bruker_data) { # Right now (06 April 2017) we're assuming Agilent data
		    $approx_Hf_bval_handle = "z_Agilent_bvalue";
		}
		my $Hf_bval_info = $current_Hf->get_value_like($approx_Hf_bval_handle);
		my ($bval_dim_info,$Hf_bval_string) = split(',',$Hf_bval_info);
		my @Hf_bvals = split(' ',$Hf_bval_string);
		my ($num_bvals,$bval_dim) = split(':',$bval_dim_info);
		my $single_bval =0;
		if ($num_bvals != $num_bvecs) { # If stuff blows up, let's default to assuming a single max_bvalue
		    $single_bval=1;
		    $approx_Hf_bval_handle = "max_bval";
		    $Hf_bval_info = $current_Hf->get_value_like($approx_Hf_bval_handle);
		    $Hf->set_value("max_bvalue_${runno}",$Hf_bval_info);
		}

		# combine bvals and bvecs into one table

		my @gradient_matrix;
		for (my $bb=0;($bb < $num_bvecs); $bb++) {
		    $tmp_log_msg = "Creating combined bval/bvec b-table from headfile: ${current_headfile}.";
		    $log_msg = $tmp_log_msg;
		    
		    my @temp_array;
		    my $nonzero_test = 0;
		    for (my $ii=0; ($ii < $v_dim); $ii++) {
			my $temp_val = shift(@Hf_gradients);
			push(@temp_array,$temp_val);
			if (! $nonzero_test) {
			    if ($temp_val ne '0') { # We are assuming that zero will always be stored in headfile as '0' (nor '0.0', '0.000', etc.
				$nonzero_test = 1;
			    }
			}
		    }
		    my $current_bval=0;
		    if ($single_bval) {
			if ($nonzero_test) {
			    $current_bval = $Hf_bval_info;
			}
		    } else {
			my $new_bval = shift(@Hf_bvals);
			if ($nonzero_test) {
			    $current_bval = $new_bval;
			}
		    }
		    
		    my $b_string = join(', ',($current_bval,@temp_array));
		    push(@gradient_matrix,$b_string."\n");
		    $tmp_log_msg = ".";
		    $log_msg = $tmp_log_msg;
		}
		$tmp_log_msg = "\nDone creating b-table: ${gradient_file} for ${num_bvecs} bval/bvec entries.\n";
		$log_msg = $tmp_log_msg;
		
		write_array_to_file($gradient_file,\@gradient_matrix);
	    }
	    $Hf->set_value("original_bvecs_${runno}",$gradient_file);
	    # log any messages
	}
	if ($log_msg ne '') {
	    $message_body=$message_body."\n".$local_message_prefix.$log_msg;
	}
    }
    if ($message_body ne '') {
	log_info("${message_prefix}${message_body}");
    }
}
