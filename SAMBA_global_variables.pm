#!/usr/local/pipeline-link/perl
# SAMBA_global_variables.pm 
# Originally written by James Cook & BJ Anderson, CIVM
package SAMBA_global_variables;
use strict;
use warnings;

my $PM = "SAMBA_global_variables.pm";
my $VERSION = "2019/01/16";
my $DESC = "Master list of all global variables to be used by SAMBA, to be called in MAIN.";
my $NAME = $PM =~ s/\.pm//;

BEGIN {
    use Exporter;
    our @ISA = qw(Exporter); # perl critic wants this replaced with use base; not sure why yet.
    #@EXPORT_OK is preferred, as it markes okay to export, HOWEVER our code is dumb and needs to force import all them things...
    # (requires too much brainpower for the time being to implement correctly).

our @EXPORT = qw(
$project_name 
@control_group
$control_comma_list
@compare_group
$compare_comma_list

$complete_comma_list

@group_1
$group_1_runnos
@group_2
$group_2_runnos
$all_groups_comma_list

@channel_array
$channel_comma_list

$custom_predictor_string
$template_predictor
$template_name

$flip_x
$flip_z 
$optional_suffix
$atlas_name
$label_atlas_name
$label_transform_chain
$label_input_file
$label_atlas_nickname
$make_individual_ROIs



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
$fdr_masks
$tfce_extent
$tfce_height
$fsl_cluster_size

$nonparametric_permutations

$convert_labels_to_RAS
$eddy_current_correction
$do_connectivity
$recon_machine

$original_study_orientation
$working_image_orientation

$fixed_image_for_mdt_to_atlas_registratation

$vba_contrast_comma_list
$vba_analysis_software
$smoothing_comma_list

$U_specid
$U_species_m00
$U_code

$image_dimensions

$participants

@comparisons
@predictors

$civm_ecosystem
$ref_runno

$dims
$ants_verbosity
$broken
$permissions
$test_mode
$nodes
$reservation
$Hf
$mdt_to_reg_start_time

$valid_formats_string
 );

my $dirty_eval_string = 'our '.join('; our ',@EXPORT).';';

eval($dirty_eval_string);

foreach my $entry ( keys %SAMBA_global_variables:: )  { # Build a string of all initialized variables, etc, that contain only letters, numbers, or '_'.
    #print "$entry\n";

    #if ($entry =~ /^[A-Za-z0-9_]+$/) {
    #	$kevin_spacey = $kevin_spacey." $entry ";
    #}
}
}