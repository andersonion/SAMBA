#!/usr/local/pipeline-link/perl
# vbm_pipeline_start.pl
# originally created as vbm_pipeline, 2014/11/17 BJ Anderson CIVM
# vbm_pipeline_start spun off on 2017/03/14 BJ Anderson CIVM
#
# Roughly modeled after seg_pipe_mc structure. (For better or for worse.)
#


# All my includes and requires are belong to us.
# use ...

my $PM = 'vbm_pipeline_start.pl'; 

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


$intermediate_affine = 0;
$test_mode = 0;

$nodes = shift(@ARGV);

$reservation='';

if (! defined $nodes) {
    $nodes = 4 ;}
else {
    if ($nodes =~ /[^0-9]/) { # Test to see if this is not a number; if so, assume it to be a reservation.
	$reservation = $nodes;
	my $reservation_info = `scontrol show reservation ${reservation}`;
	if ($reservation_info =~ /NodeCnt=([0-9]*)/m) { # Unsure if I need the 'm' option)
	    $nodes = $1;
	} else {
	    $nodes = 4;
	    print "\n\n\n\nINVALID RESERVATION REQUESTED: unable to find reservation \"$reservation\".\nProceeding with NO reservation, and assuming you want to run on ${nodes} nodes.\n\n\n"; 
	    $reservation = '';
	    sleep(5);
	}
    }
}


print "nodes = $nodes; reservation = \"$reservation\".\n\n\n";
if (! defined $broken) { $broken = 0 ;} 

umask(002);

use lib dirname(abs_path($0));
use Env qw(RADISH_PERL_LIB);
if (! defined($RADISH_PERL_LIB)) {
    print STDERR "Cannot find good perl directories, quitting\n";
    exit;
}
my $custom_pipeline_utilities_path ="${WORKSTATION_HOME}/shared/cluster_pipeline_utilities/";
$RADISH_PERL_LIB=$custom_pipeline_utilities_path.':'.$RADISH_PERL_LIB;
use lib split(':',$RADISH_PERL_LIB);

# require ...
require study_variables_vbm;
require vbm_pipeline_workflow;
# require Headfile;
# require retrieve_archived_data;
# require study_variables_vbm;

# require convert_all_to_nifti_vbm;
# require set_reference_space_vbm;
# require create_rd_from_e2_and_e3_vbm;
# require mask_images_vbm;
# require create_affine_reg_to_atlas_vbm;
# require apply_affine_reg_to_atlas_vbm;
# require iterative_pairwise_reg_vbm;
# require pairwise_reg_vbm;
# require calculate_mdt_warps_vbm;
# require iterative_calculate_mdt_warps_vbm;
# require iterative_apply_mdt_warps_vbm;
# require apply_mdt_warps_vbm;
# require calculate_mdt_images_vbm;
# require compare_reg_to_mdt_vbm;
# require mdt_reg_to_atlas_vbm;
# require warp_atlas_labels_vbm;
# require mask_for_mdt_vbm;
# require calculate_jacobians_vbm;
# require smooth_images_vbm;
# require vbm_analysis_vbm;

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

$vba_contrast_comma_list
$vba_analysis_software
$smoothing_comma_list

$image_dimensions
 );

{
    study_variables_vbm();
    $do_vba = 1;
    vbm_pipeline_workflow();

} #end main
