#!/usr/local/pipeline-link/perl
# vbm_pipeline_workflow.pm
# vbm_pipeline created 2014/11/17 BJ Anderson CIVM
# vbm_pipeline_workflow created 2017/03/14 BJ Anderson CIVM
#
# Roughly modeled after seg_pipe_mc structure. (For better or for worse.)
# Was formerly vbm_pipeline, with study_variables.pm providing vast majority of user input
# Ironically, it is being split so we can reuse this same code as a segmentation pipeline


# All my includes and uses are belong to us.
# use ...

my $PM = 'vbm_pipeline_workflow.pm'; 

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename;
use List::Util qw(min max reduce);
use List::MoreUtils qw(uniq);

use Env qw(RADISH_PERL_LIB);
if (! defined($RADISH_PERL_LIB)) {
    print STDERR "Cannot find good perl directories, quitting\n";
    exit;
}
use lib split(':',$RADISH_PERL_LIB);

#use vars used to be here
use Env qw(ANTSPATH PATH BIGGUS_DISKUS WORKSTATION_DATA WORKSTATION_HOME);

use text_sheet_utils;

## This may be hacky, but I'm sick of trying to point this to the right place. 19 December 2017
if (! -d $WORKSTATION_DATA) {
if ($WORKSTATION_DATA =~ s/\.\.\/data/\.\.\/CIVMdata/) {}
}
#print "WORKSTATION_DATA = ${WORKSTATION_DATA}\n\n\n";

$ENV{'PATH'}=$ANTSPATH.':'.$PATH;
$ENV{'WORKSTATION_HOME'}="/cm/shared/workstation_code_dev";
$GOODEXIT = 0;
$BADEXIT  = 1;
my $ERROR_EXIT=$BADEXIT;
$permissions = 0755;
my $interval = 0.1; ##Normally 1
$valid_formats_string = 'hdr|img|nii|nhdr|nrrd';

$civm_ecosystem = 1; # Begin implementing handling of code that is CIVM-specific
if ( $ENV{'BIGGUS_DISKUS'} =~ /gluster/) {
    $civm_ecosystem = 1;
} elsif ( $ENV{'BIGGUS_DISKUS'} =~ /civmnas4/) {
    $civm_ecosystem = 1;
}


# a do it again variable, will allow you to pull data from another vbm_run
my $import_data = 1;

$test_mode = 0;

umask(002);

use lib dirname(abs_path($0));
use Env qw(RADISH_PERL_LIB);
if (! defined($RADISH_PERL_LIB)) {
    print STDERR "Cannot find good perl directories, quitting\n";
    exit;
}
use lib split(':',$RADISH_PERL_LIB);


# use ...
use Headfile;
use civm_simple_util qw(sleep_with_countdown    );
use retrieve_archived_data;
use study_variables_vbm;
use ssh_call;
use pull_civm_tensor_data;

use convert_all_to_nifti_vbm;
use set_reference_space_vbm;
use create_rd_from_e2_and_e3_vbm;
use mask_images_vbm;
use create_affine_reg_to_atlas_vbm;
use iterative_pairwise_reg_vbm;
use pairwise_reg_vbm;
use calculate_mdt_warps_vbm;
use iterative_calculate_mdt_warps_vbm;
use apply_mdt_warps_vbm;
use calculate_mdt_images_vbm;
use compare_reg_to_mdt_vbm;
use mdt_reg_to_atlas_vbm;
use warp_atlas_labels_vbm;
use calculate_individual_label_statistics_vbm;
use	tabulate_label_statistics_by_contrast_vbm;
use label_stat_comparisons_between_groups_vbm;
use mask_for_mdt_vbm;
use calculate_jacobians_vbm;
use smooth_images_vbm;
use vbm_analysis_vbm;
use vbm_write_stats_for_pm;

# Temporary hardcoded variables

# variables, set up by the study vars script(study_variables_vbm.pm)

$schedule_backup_jobs=0;

sub vbm_pipeline_workflow { 
## The following work is to remove duplicates from processing lists (adding the 'uniq' subroutine). 15 June 2016


# Define template group

# Create [stat] comparison groups
# Figure out better method than "group_1" "group_2" etc, maybe a hash structure with group_name/group_description/group_members, etc


# Concatanate and uniq comparison list to create reg_to_mdt(?) group list

# Create a master list of all specimen that are to be pre-processed and rigid/affinely aligned


## Need to throw errors for empty lists, maybe dump headers for case of header not found; dump values from column in case of existing header

if (! @group_1) {
    if (defined $group_1_runnos) {
        @group_1 = split(',',$group_1_runnos);
    } else {
        @group_1=();
    }
}

if (! @group_2) {
    if (defined $group_2_runnos) {
        @group_2 = split(',',$group_2_runnos);
    } else {
        @group_2=();
    }
}

if (! @control_group) {
    if (defined $control_comma_list) {
        @control_group = split(',',$control_comma_list);
    } elsif ((@group_1) && (@group_2)) {
        @control_group = uniq(@group_1,@group_2);
    } elsif (@group_1) {
        @control_group = uniq(@group_1)
    }
}

if (! @compare_group) {
    if (defined $compare_comma_list) {
        @compare_group = split(',',$compare_comma_list);
    } else {
        @compare_group = @control_group;
    }
 
    if ( scalar (@group_1) && $group_1[0] ne '') {
        @compare_group=uniq(@compare_group,@group_1);
    } 
    
    if ( scalar (@group_2) && $group_2[0] ne '') {
        @compare_group=uniq(@compare_group,@group_2);
    }
}

my @all_runnos = uniq(@control_group,@compare_group);
my $single_seg=0;
if ($#all_runnos < 1) {
    $do_vba = 0;
    $single_seg=1;
    if (! $optional_suffix) {
        $optional_suffix = $all_runnos[0];
    }

    $mdt_creation_strategy='pairwise';
}

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
if ($single_seg) {
    $main_folder_prefix = 'SingleSegmentation_';
} else  {
    $main_folder_prefix = 'VBM_';
}
my @project_components = split(/[.]/,$project_name); # $project_name =~ s/[.]//g;
my $project_id =  join('',@project_components);
$project_id = $main_folder_prefix.$project_id.'_'.$atlas_name.$optional_suffix; #create_identifer($project_name);


my ($pristine_input_dir,$work_dir,$result_dir,$result_headfile) = make_process_dirs($project_id); #new_get_engine_dependencies($project_id);

## Backwards compatability for rerunning work initially ran on glusterspace

# search start headfile for references to '/glusterspace/'
if ((defined $start_file) && ( -f $start_file)) {

    my $start_contents=`cat $start_file`;

    if ($start_contents =~ /\/glusterspace\//) {
        my $old_pristine_input_dir=$pristine_input_dir;
        if ($pristine_input_dir =~ s/^${BIGGUS_DISKUS}/\/glusterspace/){}

        if (! -l $pristine_input_dir) {
             `ln -s $old_pristine_input_dir $pristine_input_dir`;
        }

        my $old_work_dir=$work_dir;
        if ($work_dir =~ s/^${BIGGUS_DISKUS}/\/glusterspace/){}
        if (! -l $work_dir) {
             `ln -s $old_work_dir $work_dir`;
        }


        my $old_result_dir=$result_dir;
        if ($result_dir =~ s/^${BIGGUS_DISKUS}/\/glusterspace/){}
        if (! -l $result_dir) {
             `ln -s $old_result_dir $result_dir`;
        }

        if ($result_headfile =~ s/^${BIGGUS_DISKUS}/\/glusterspace/){}
    }

}

## Mini-kludge...until we can get a proper data importer in place...
my $test_for_inputs = `ls ${pristine_input_dir}`;
if ($test_for_inputs eq '') {
    $import_data = 1;
} 


$import_data = 0;

## Headfile setup code starts here
if ( -e $result_headfile) {
    my $last_result_headfile = $result_headfile =~ s/\.headfile/_last\.headfile/;
    `mv -f ${result_headfile} ${last_result_headfile}`;
}
$Hf = new Headfile ('nf',$result_headfile );
if (! $Hf->check()){
    # We expect this to happen when a file with the same name as $result_headfile was not successfully moved a few lines above-
    # probably due to permissions issues, which is a huge red flag.
    croak("Is this your data? If not, you will need the original owner to run the pipeline.")
}


my $log_file = open_log($result_dir);
my $stats_file = $log_file;
if ($stats_file =~ s/pipeline_info/job_stats/) {
    $Hf->set_value('stats_file',$stats_file);
}


my $preprocess_dir = $work_dir.'/preprocess';
my $inputs_dir = $preprocess_dir.'/base_images';


## The following work is to remove duplicates from processing lists (adding the 'uniq' subroutine). 15 June 2016

# if (! @group_1) {
#     if (defined $group_1_runnos) {
# 	@group_1 = split(',',$group_1_runnos);
#     }
# }

# if (! @group_2) {
#     if (defined $group_2_runnos) {
# 	@group_2 = split(',',$group_2_runnos);
#     }
# }

# if (! @control_group) {
#     if (defined $control_comma_list) {
# 	@control_group = split(',',$control_comma_list);
#     } elsif ((@group_1) && (@group_2)) {
# 	@control_group = uniq(@group_1,@group_2);
#     }
# }

# if (! @compare_group) {
#     if (defined $compare_comma_list) {
# 	@compare_group = split(',',$compare_comma_list);
#     } else {
# 	@compare_group = @control_group;
#     }
# }

# my @all_runnos = uniq(@control_group,@compare_group);

$control_comma_list = join(',',uniq(@control_group));
$compare_comma_list = join(',',uniq(@compare_group));
#my $complete_comma_list = $control_comma_list.','.$compare_comma_list;
$complete_comma_list =join(',',uniq(@all_runnos));
$channel_comma_list = join(',',uniq(@channel_array));

if ($do_vba) {
    my $group_1_runnos;
    my $group_2_runnos;
    #if (defined @group_1)  {
    if (@group_1)  {
	$group_1_runnos = join(',',uniq(@group_1));
	$Hf->set_value('group_1_runnos',$group_1_runnos);
    }

    #if (defined @group_2) {
    if (@group_2) {
	$group_2_runnos = join(',',uniq(@group_2));
	$Hf->set_value('group_2_runnos',$group_2_runnos);
    }
    
    #   if ((defined @group_1)&&(defined @group_2)) {
    if ((@group_1) && (@group_2)) { 
	my @all_in_groups = uniq(@group_1,@group_2);
	#my $all_groups_comma_list = $group_1_runnos.','.$group_2_runnos;
	my $all_groups_comma_list = join(',',@all_in_groups) ;
	$Hf->set_value('all_groups_comma_list',$all_groups_comma_list);
    }
}



my $runlist = $Hf->get_value('all_groups_comma_list');
if ($runlist eq 'NO_KEY') {
    $runlist = $Hf->get_value('complete_comma_list');
}

my $multiple_runnos = 0;
if ($runlist =~ /,/) {
    $multiple_runnos = 1;
}

my $multiple_groups=0;
if (@group_2) {$multiple_groups = 1;}


## End duplication control

if ((defined $start_file) && ($start_file ne '')) {
    $Hf->set_value('start_file',$start_file);
}


$Hf->set_value('project_id',$project_id);

if (defined $image_dimensions) {
    $Hf->set_value('image_dimensions',$image_dimensions);
} else {
    $Hf->set_value('image_dimensions',3);
}

if (defined $vbm_reference_space) {
    $Hf->set_value('vbm_reference_space',$vbm_reference_space);
}

if (defined $label_reference) {
    $Hf->set_value('label_reference_space',$label_reference);
}

if (defined $do_vba) {
    $Hf->set_value('do_vba',$do_vba);
}



$Hf->set_value('control_comma_list',$control_comma_list);
$Hf->set_value('compare_comma_list',$compare_comma_list);
$Hf->set_value('complete_comma_list',$complete_comma_list);
$Hf->set_value('channel_comma_list',$channel_comma_list);


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

if (defined $atlas_name) {
    $Hf->set_value('rigid_atlas_name',$atlas_name);
}

if (defined $rigid_contrast) {
    $Hf->set_value('rigid_contrast',$rigid_contrast);
}

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


if ((! defined $create_labels) && (defined $label_atlas_name)){
    $create_labels = 1;
} elsif (! defined $label_atlas_name) {
    $create_labels = 0;
}

if ($create_labels) {
    my $label_atlas_dir = "${WORKSTATION_DATA}/atlas/${label_atlas_name}";
    if (! -d $label_atlas_dir) {
	if ($label_atlas_dir =~ s/\/data/\/CIVMdata/) {}
    }

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

if (defined $flip_x) {
    $Hf->set_value('flip_x',$flip_x);
}

if (defined $flip_z) {
    $Hf->set_value('flip_z',$flip_z);
}

if (defined $original_study_orientation) {
    $Hf->set_value('original_study_orientation',$original_study_orientation);
}


##

if ((defined $start_file) && ($start_file ne '')) {

    my $tempHf = new Headfile ('rw', "${start_file}");
    if (! $tempHf->check()) {
	error_out(" Unable to open SAMBA parameter file ${start_file}.");
	return(0);
    }
    if (! $tempHf->read_headfile) {
	error_out(" Unable to read SAMBA parameter file ${start_file}."); 
	return(0);
   }



    foreach my $c_runno (@all_runnos) {
	my $c_key = "original_orientation_${c_runno}";
	my $temp_orientation = $tempHf->get_value($c_key);
	if (($temp_orientation ne 'NO_KEY')  &&  ($temp_orientation ne 'UNDEFINED_VALUE')) {
	    $Hf->set_value($c_key,$temp_orientation);
	} 
    }
}

# Check for previous run (startup headfile in inputs?)

my $c_input_headfile="${pristine_input_dir}/current_inputs.headfile";

if ( -f ${c_input_headfile}) {
# If exists, compare with current inputs

    my $tempHf = new Headfile ('rw', "${start_file}");
    $tempHf->read_headfile;

    my $ci_Hf = new Headfile ('rw', "${c_input_headfile}");
    if (! ${ci_Hf}->check()) {
        error_out(" Unable to open current inputs parameter file ${c_input_headfile}.");
        return(0);
    }
    if (! ${ci_Hf}->read_headfile) {
        error_out(" Unable to read current inputs parameter file ${c_input_headfile}."); 
        return(0);
   }

    my @excluded_keys=qw(hfpcmt);
    my $include=0;
    my $Hf_comp = '';
    $Hf_comp = compare_headfiles($ci_Hf,$tempHf,$include,@excluded_keys);		    
	if ($Hf_comp eq '') {
        print "Input headfile matches current headfile!\n\n";
	} else {
        # If different, warn with 10 sec pause or need to press Enter
	    log_info(" $PM: ${Hf_comp}\nARE YOU ABSOLUTELY SURE YOU WANT TO CONTINUE?\n(If not, cancel now)"); # Is this the right place for this?
        sleep_with_countdown(10);
	}
}
# Save current to inputs and results, renaming as necessary

my $pipeline_inputs_file = $log_file;
if ($pipeline_inputs_file =~ s/pipeline_info/input_parameters/) {
    if ($pipeline_inputs_file =~ s/\.txt$/\.headfile/) {
        `cp -p ${start_file} ${pipeline_inputs_file}`;
        $Hf->set_value('timestamped_inputs_file',${pipeline_inputs_file});
    }
}

`cp -p ${start_file} ${c_input_headfile}`;

##
if (defined $working_image_orientation) {
    $Hf->set_value('working_image_orientation',$working_image_orientation);
}


$Hf->set_value('do_mask',$do_mask);
if (defined $thresh_ref) {
    $Hf->set_value('threshold_hash_reference',$thresh_ref);
}

if (defined $custom_predictor_string) {
    $Hf->set_value('predictor_id',$custom_predictor_string);
}

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

if (defined $nonparametric_permutations) {
    $Hf->set_value('nonparametric_permutations',$nonparametric_permutations);
}

if (defined $fdr_masks) {
    $Hf->set_value('fdr_masks',$fdr_masks);
}


if (defined $tfce_extent){
    $Hf->set_value('tfce_extent',$tfce_extent);
}

if (defined $tfce_height){
    $Hf->set_value('tfce_extent',$tfce_height);
}


if (defined $fsl_cluster_size){
    $Hf->set_value('fsl_cluster_size',$fsl_cluster_size);
}

if (defined $U_specid){
    $Hf->set_value('U_specid',$U_specid);
}

if (defined $U_species_m00){
    $Hf->set_value('U_species_m00',$U_species_m00); # Temporary fix, assumes 10-99 DTI directions
}

if (defined $U_code){
    $Hf->set_value('U_code',$U_code);
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
     pull_civm_tensor_data
     create_rd_from_e2_and_e3_vbm
     set_reference_space_vbm
     mask_images_vbm
     create_affine_reg_to_atlas_vbm
     pairwise_reg_vbm
     iterative_pairwise_reg_vbm
     calculate_mdt_warps_vbm
     iterative_calculate_mdt_warps_vbm
     apply_mdt_warps_vbm
     calculate_mdt_images_vbm
     mask_for_mdt_vbm
     compare_reg_to_mdt_vbm
     mdt_reg_to_atlas_vbm
     warp_atlas_labels_vbm
     calculate_individual_label_statistics_vbm
     tabulate_label_statistics_by_contrast_vbm
     label_stat_comparisons_between_groups_vbm
     calculate_jacobians_vbm
     vbm_analysis_vbm
     apply_warps_to_bvecs
      );
    # 20 July 2017, BJA: swapped check order of mask images and set reference space
    
    my %init_dispatch_table;
    

    my $checkCall; # Using camelCase here to avoid the potential need for playing the escape character game when calling command with backticks, etc.
    my $Init_suffix = "_Init_check";
    
   
   # for (my $mm = $#modules_for_Init_check; $mm >=0; $mm--)) { # This checks backwards
    for (my $mm = 0; $mm <= $#modules_for_Init_check; $mm++) { # This checks forwards
    my $module = $modules_for_Init_check[$mm];
		 
	$checkCall = "${module}${Init_suffix}";
    $init_dispatch_table{$checkCall}=eval('\&$checkCall'); # MUST USE SINGLE QUOTES on RHS!!!


	print STDOUT "Check call is $checkCall\n";
	my $temp_error_msg = '';
    $temp_error_msg=$init_dispatch_table{$checkCall}();
        #$temp_error_msg=set_reference_space_vbm_Init_check();

 #if ( $module =~ /set_ref/) {die $module."____".$temp_error_msg;}

	if ((defined $temp_error_msg) && ($temp_error_msg ne '')  ) {
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
if ($import_data) { # This should be deprecated
    load_study_data_vbm(); #$PM_code = 11
}

my $nii4D = 0;
if ($do_connectivity) {
    $nii4D = 1;
}

#if ($civm_ecosystem) { # Moved to be called within convert_all_to_nifti_vbm, so will only run as necessary. # BJA, 11 August 2017
#   pull_civm_tensor_data(); # Commented only for testing
#}


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
    #$channel_comma_list = $original_channel_comma_list;
    $channel_comma_list = $channel_comma_list.',rd';
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

	    my $starting_iteration=$Hf->get_value('starting_iteration');

	    if ($starting_iteration =~ /([1-9]{1}|[0-9]{2,})/) {
	    } else {
		$starting_iteration = 0;
	    }
	   # print "starting_iteration = ${starting_iteration}";

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

	    $real_time = vbm_write_stats_for_pm(62,$Hf,$mdt_to_reg_start_time,$MDT_to_atlas_JobID);
	    
	    if ($error_message ne '') {
		error_out("${error_message}",0);
	    }
	}
    
	if (($MDT_to_atlas_JobID eq 'NO_KEY') || ($MDT_to_atlas_JobID eq 'UNDEFINED_VALUE')) {
	    $real_time = vbm_write_stats_for_pm(62,$Hf,$mdt_to_reg_start_time);
	}
	print "mdt_reg_to_atlas.pm took ${real_time} seconds to complete.\n";

	my @label_spaces = split(',',$label_space);

	warp_atlas_labels_vbm('MDT'); #$PM_code = 63
	sleep($interval);

	#warp_atlas_labels_vbm(); #$PM_code = 63
	#sleep($interval);

	$group_name = "all";

	my @current_channel_array = @channel_array;
	if ($do_connectivity) {
	    push (@current_channel_array,'nii4D');
	}
	
	@current_channel_array = uniq(@current_channel_array);

	foreach my $a_label_space (@label_spaces) {

	    warp_atlas_labels_vbm('all',$a_label_space); #$PM_code = 63
	    sleep($interval);

	    foreach my $a_contrast (@current_channel_array) {
    		apply_mdt_warps_vbm($a_contrast,"f",$group_name,$a_label_space); #$PM_code = 64
	    }
	    
	    calculate_individual_label_statistics_vbm($a_label_space); #$PM_code = 65

	    if ($multiple_runnos) { # Temporarily commented out UNDO IMMEDIATELY
        #   tabulate_label_statistics_by_contrast_vbm($a_label_space,@current_channel_array); #$PM_code = 66 
		#   if ($multiple_groups) {	
		#       label_stat_comparisons_between_groups_vbm($a_label_space,@current_channel_array); #$PM_code = 67
		#   }
	    }
	    if ($do_connectivity) { # 21 April 2017, BJA: Moved this code from external _start.pl code
    		apply_warps_to_bvecs($a_label_space);	
	    }
	}
	sleep($interval);

    }   

if ($do_vba) {
#    my $new_contrast = calculate_jacobians_vbm('i','compare'); #$PM_code = 53 # Nope, this is bad--26 July 2016
    my $new_contrast = calculate_jacobians_vbm('f','compare'); #$PM_code = 53 # BAD code. Don't this unless trying to prove a point. # JK Kidding this code is right believe it or not.
    
    push(@channel_array,$new_contrast);
    $channel_comma_list = $channel_comma_list.','.$new_contrast;
    $Hf->set_value('channel_comma_list',$channel_comma_list);
    sleep($interval);
    
    if ($multiple_groups) {
	vbm_analysis_vbm(); #$PM_code = 72
	sleep($interval);
    }
    # smooth_images_vbm(); #$PM_code = 71 (now called from vbm_analysis_vbm)
    #sleep($interval);
    
    # if ($do_nonparametric_testing) {
    # 	nonparametric_prep_vbm(); #$PM_code = 81
    # 	sleep($interval);

    # 	nonparametric_permutations_vbm(); #$PM_code = 82
    # 	sleep($interval);
	
    # 	nonparametric_postprocessing_vbm(); #$PM_code = 83
    # 	sleep($interval);
    # }

}

$Hf->write_headfile($result_headfile);

print "\n\nVBM Pipeline has completed successfully.  Great job, you.\n\n";

	
#    use civm_simple_util qw(whowasi whoami);	
#    my $process = whowasi();
#    my @split = split('::',$process);
#    $process = pop(@split);
my $process = "vbm_pipeline";
    
my $completion_message ="Congratulations, master scientist. Your VBM pipeline process has completed.  Hope you find something interesting.\n";
my $results_message = "Results are available for your perusal in: ${result_dir}.\n";
my $time = time;
my $email_folder = '/home/rja20/cluster_code/workstation_code/analysis/vbm_pipe/email/';			
my $email_file="${email_folder}/VBM_pipeline_completion_email_for_${time}.txt";

my $local_time = localtime();
my $local_time_stamp = "This file was generated on ${local_time}, local time.\n";
my $time_stamp = "Completion time stamp = ${time} seconds since January 1, 1970 (or some equally asinine date).\n";


my $subject_line = "Subject: VBM Pipeline has finished!!!\n";

			
#my $email_content = $subject_line.$completion_message.$time_stamp;
my $email_content = $subject_line.$completion_message.$results_message.$local_time_stamp.$time_stamp;
`echo "${email_content}" > ${email_file}`;
#`sendmail -f $process.civmcluster1\@dhe.duke.edu rja20\@duke.edu < ${email_file}`;
my $pwuid = getpwuid( $< );
my $pipe_adm="";
$pipe_adm=",9196128939\@vtext.com,rja20\@duke.edu";
my $USER_LIST="$pwuid\@duke.edu$pipe_adm";
`sendmail -f $process.civmcluster1\@dhe.duke.edu $USER_LIST < ${email_file}`;

} #end main

#---------------------
sub find_group_in_tsv {
#---------------------

my ($tsv_file,$report_field,$_ref_to_criteria_array)=(@_);


return();

}

#---------------------
#sub load_tsv {

#if (! exists $csv_data_file->{"t_line"}) {
#todo: clobber line endings, run again.
#my $tmp_path="/tmp/.pipetmp.csv";
#my $cmd = "sed -E \'s/[\\r]/\\n/g\' ${csv_path} > ${tmp_path}";
#print "\n\n$cmd\n\n\n";
#qx($cmd);
#$csv_data_file=text_sheet_utils::loader($tmp_path,$h_info);
#`rm $tmp_path`;
#}
#}
1;
