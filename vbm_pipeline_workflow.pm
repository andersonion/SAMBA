#!/usr/bin/env perl
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

use Env qw(HOSTNAME);

use Env qw(RADISH_PERL_LIB);
if (! defined($RADISH_PERL_LIB)) {
    print STDERR "Cannot find good perl directories, quitting\n";
    exit;
}
use lib split(':',$RADISH_PERL_LIB);

#use vars used to be here
use Env qw(ANTSPATH PATH BIGGUS_DISKUS WORKSTATION_DATA WORKSTATION_HOME HOME);

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
my $interval = 1; ##Normally 1, changed to 0.1, but don't know if non-integers are allowed.
$valid_formats_string = 'hdr|img|nii|nii.gz|ngz|nhdr|nrrd';

$civm_ecosystem = 1; # Begin implementing handling of code that is CIVM-specific
if ( $ENV{'BIGGUS_DISKUS'} =~ /gluster/) {
    $civm_ecosystem = 1;
} elsif ( $ENV{'BIGGUS_DISKUS'} =~ /civmnas4/) {
    $civm_ecosystem = 1;
}

our ($log_file,$stats_file,$timestamped_inputs_file,$project_id,$all_groups_comma_list );
our ($pristine_input_dir,$dir_work,$results_dir,$result_headfile);
our ($rigid_transform_suffix,$affine_transform_suffix, $affine_identity_matrix, $preprocess_dir,$inputs_dir);
# a do it again variable, will allow you to pull data from another vbm_run

$test_mode = 0;

umask(002);

use lib dirname(abs_path($0));
use Env qw(RADISH_PERL_LIB WORKSTATION_DATA);
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
use tabulate_label_statistics_by_contrast_vbm;
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


my @variables_to_headfile=qw(
start_file project_id optional_external_inputs_dir image_dimensions
control_comma_list compare_comma_list complete_comma_list channel_comma_list
pristine_input_dir preprocess_dir inputs_dir dir_work results_dir timestamped_inputs_file
flip_x flip_z original_study_orientation working_image_orientation
do_mask pre_masked skull_strip_contrast threshold_code port_atlas_mask port_atlas_mask_path
vbm_reference_space force_isotropic_resolution resample_images resample_factor
rigid_atlas_name rigid_contrast rigid_transform_suffix
affine_contrast
affine_identity_matrix affine_transform_suffix affine_contrast affine_target affine_gradient_step 
affine_metric affine_sampling_options affine_iterations affine_smoothing_sigmas affine_shrink_factors affine_radius affine_convergence_window 
affine_convergence_thresh
diffeo_metric diffeo_sampling_options diffeo_iterations diffeo_smoothing_sigmas diffeo_shrink_factors diffeo_radius diffeo_convergence_window 
diffeo_convergence_thresh diffeo_transform_parameters
initial_template template_predictor template_name mdt_creation_strategy mdt_iterations mdt_contrast mdt_convergence_threshold stop_after_mdt_creation
compare_contrast  
register_MDT_to_atlas fixed_image_for_mdt_to_atlas_registratation
create_labels label_space label_atlas_dir label_atlas_name label_input_file label_transform_chain label_atlas_nickname convert_labels_to_RAS make_individual_ROIs
do_connectivity eddy_current_correction
do_vba  vba_contrast_comma_list vba_analysis_software
smoothing_comma_list
nonparametric_permutations fdr_masks tfce_extent tfce_height fsl_cluster_size 
U_specid U_species_m00 U_code
stats_file no_new_inputs
);

if (defined $label_reference) {
    $Hf->set_value('label_reference_space',$label_reference);
}



## Need to throw errors for empty lists, maybe dump headers for case of header not found; dump values from column in case of existing header

if (! @group_1) { # if (! defined @group_1) {
    if (defined $group_1_runnos) {
        @group_1 = split(',',$group_1_runnos);
    } else {
        @group_1=();
    }
}

if (! @group_2) { #if (! defined @group_2) {
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


## The following are mostly ready-to-go variables (i.e. non hard-coded)


if ($optional_suffix ne '') {
    $optional_suffix = "_${optional_suffix}";
}
my $main_folder_prefix;
if ($single_seg) {
    $main_folder_prefix = 'SingleSegmentation_';
} else  {
    $main_folder_prefix = 'VBM_';  ## Want to switch these all to 'SAMBA'
}
my @project_components = split(/[.]/,$project_name); # $project_name =~ s/[.]//g;
$project_id =  join('',@project_components);
$project_id = $main_folder_prefix.$project_id.'_'.$rigid_atlas_name.$optional_suffix; #create_identifer($project_name);

($pristine_input_dir,$dir_work,$results_dir,$result_headfile) = make_process_dirs($project_id); #new_get_engine_dependencies($project_id);


## 23 January 2020 (Thursday), BJA: This code is expected to point the -inputs directory as an arbitrarily defined folder, via a symbolic link.
# Good luck, Chuck.

if ( defined $optional_external_inputs_dir) {
    print "Testing ${optional_external_inputs_dir}\n\n";
    #`ls -artlh  ${optional_external_inputs_dir}`;
    #print "dangling link at ${optional_external_inputs_dir}" if (lstat ${optional_external_inputs_dir});
    #my $OEID =  ${optional_external_inputs_dir} =~ s/[\\]+//g;
    #print "fuck this shit at ${optional_external_inputs_dir}" if (lstat ${optional_external_inputs_dir});
    #die;
    if (( -l ${optional_external_inputs_dir}) || ( -d ${optional_external_inputs_dir}) ){
    #if ( -e "${optional_external_inputs_dir}") {
    #print "OEID = ${optional_external_inputs_dir}\n\n\n";
    #die;
	my $contents=`ls -1 ${pristine_input_dir} | wc -l`;
	if (( $contents == '0' ) || ($contents == 0) ) {
	    # We don't want to accidentally destroy a linked inputs dir.
	    if (-l ${pristine_input_dir}) {
		`rm -f ${pristine_input_dir}`;
	    } else {
		`rm -fr ${pristine_input_dir}`;
	    }
	    symlink(${optional_external_inputs_dir}, ${pristine_input_dir});
	   # `ln -s ${optional_external_inputs_dir} ${pristine_input_dir}`;
	}	    
    }
}
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
        my $old_work_dir=$dir_work;
        if ($dir_work =~ s/^${BIGGUS_DISKUS}/\/glusterspace/){}
        if (! -l $dir_work) {
             `ln -s $old_work_dir $dir_work`;
        }
        my $old_results_dir=$results_dir;
        if ($results_dir =~ s/^${BIGGUS_DISKUS}/\/glusterspace/){}
        if (! -l $results_dir) {
             `ln -s $old_results_dir $results_dir`;
        }
        if ($result_headfile =~ s/^${BIGGUS_DISKUS}/\/glusterspace/){}
    }

}

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

my $papertrail_dir="${results_dir}/papertrail";
if (! -e $papertrail_dir) {
    mkdir($papertrail_dir,0777);
}


$log_file = open_log($papertrail_dir); # 26 Feb 2019--changed from results_dir to "papertrail" subfolder

#($stats_file) = $log_file =~ s/pipeline_info/job_stats/;
$stats_file = $log_file =~ s/pipeline_info/job_stats/r;

$preprocess_dir = $dir_work.'/preprocess';
$inputs_dir = $preprocess_dir.'/base_images';


## The following work is to remove duplicates from processing lists (adding the 'uniq' subroutine). 15 June 2016

$control_comma_list = join(',',uniq(@control_group));
$compare_comma_list = join(',',uniq(@compare_group));
$complete_comma_list =join(',',uniq(@all_runnos));
$channel_comma_list = join(',',uniq(@channel_array));

if ($do_vba  || $create_labels) {
    my $group_1_runnos;
    my $group_2_runnos;

    if (@group_1)  {
        $group_1_runnos = join(',',uniq(@group_1));
        #$Hf->set_value('group_1_runnos',$group_1_runnos);
        push (@variables_to_headfile,'group_1_runnos');
    }


    if (@group_2) {
        $group_2_runnos = join(',',uniq(@group_2));
        #$Hf->set_value('group_2_runnos',$group_2_runnos);
        push (@variables_to_headfile,'group_2_runnos');
    }
    
    #   if ((defined @group_1)&&(defined @group_2)) {
    if ((@group_1) && (@group_2)) { 
        my @all_in_groups = uniq(@group_1,@group_2);
        $all_groups_comma_list = join(',',@all_in_groups) ;
        #$Hf->set_value('all_groups_comma_list',$all_groups_comma_list);
        push (@variables_to_headfile,'all_groups_comma_list');
    }
}


my $runlist;
if (defined $all_groups_comma_list){
	$runlist = $all_groups_comma_list;
} else {
    $runlist = $complete_comma_list;
}

my $multiple_runnos = 0;

if ($runlist =~ /,/) {
    $multiple_runnos = 1;
}

my $multiple_groups=0;
if ((scalar @group_2)>0) {$multiple_groups = 1;}


## End duplication control

if (! defined $image_dimensions) {
    $image_dimensions=3;
}

$Hf->set_value('number_of_nodes_used',$nodes);

$rigid_transform_suffix='rigid.mat';
$affine_transform_suffix='affine.mat';
$affine_identity_matrix="$WORKSTATION_DATA/identity_affine.mat";
if (! -f $affine_identity_matrix) {
    my $SAMBA_PATH = dirname(__FILE__);
    #$affine_identity_matrix="${HOME}/SAMBA/identity_affine.mat"; # Need better handling of SAMBA directory
    $affine_identity_matrix="${SAMBA_PATH}/identity_affine.mat"; # Hopefully this is better handling of the SAMBA directory. 3 December 2019, BJA
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

# Save current to inputs and results, renaming on the way
$log_file =~ s/pipeline_info/input_parameters/;
our $timestamped_inputs_file = $log_file;
$timestamped_inputs_file =~ s/\.txt$/\.headfile/;

`cp -p ${start_file} ${timestamped_inputs_file}`;
`cp -p ${start_file} ${c_input_headfile}`;
# caching inputs to common location for all to admire
{
    my ($p,$n,$e)=fileparts($start_file,3);
    my $u_name=(getpwuid $>)[0];
    my $cached_path=File::Spec->catfile($WORKSTATION_DATA,'samba_startup_cache',$u_name.'_'.$n.$e);
    my $cached_folder=File::Spec->catfile($WORKSTATION_DATA,'samba_startup_cache');

    if ( ! -d ${cached_folder} ) {
	print "Cached folder does not exist. Attempting to create:\n\t${cached_folder}.\n";
	`mkdir -p -m 775 ${cached_folder}`;
    }
    
    if ( ! -d ${cached_folder} ) {
	print "Unable to create public cached folder: ${cached_folder}.\n\tWill not copy start file ${start_file}.\n";
    } else {
        `cp -p $start_file $cached_path`;
    }
}

add_defined_variables_to_headfile($Hf,@variables_to_headfile); 

if (defined $thresh_ref) {
    $Hf->set_value('threshold_hash_reference',$thresh_ref);
}
if (defined $custom_predictor_string) {
    $Hf->set_value('predictor_id',$custom_predictor_string);
}

if ($test_mode) {
    $Hf->set_value('test_mode','on');
} else {
    $Hf->set_value('test_mode','off');    
}
$Hf->set_value('engine_app_matlab','/usr/local/bin/matlab');
$Hf->set_value('engine_app_matlab_opts','-nosplash -nodisplay -nodesktop');
$Hf->set_value('nifti_matlab_converter','civm_to_nii'); # This should stay hardcoded.

# Finished setting up headfile

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
    
# Begin work:

if (! -e $inputs_dir) {
    mkdir($inputs_dir,0777);
}


my $nii4D = 0;
if ($do_connectivity) {
    $nii4D = 1;
}


# Need to pass the nii4D flag in a more elegant manner...
#my $nii4D = 1;

if ($nii4D) {
    push(@channel_array,'nii4D');
    $channel_comma_list = $channel_comma_list.',nii4D';
    $Hf->set_value('channel_comma_list',$channel_comma_list);
}
# Gather all needed data and put in inputs directory
if ( ! $no_new_inputs ) {
convert_all_to_nifti_vbm(); #$PM_code = 12
sleep($interval);
}
if (create_rd_from_e2_and_e3_vbm()) { #$PM_code = 13
    push(@channel_array,'rd');
    $channel_comma_list = $channel_comma_list.',rd';
    $Hf->set_value('channel_comma_list',$channel_comma_list);
}
    sleep($interval);
    # Before 11 April 2017: nii4Ds were not masked; After 11 April 2017: nii4Ds are masked for processing/storage/reading/writing efficiency
    mask_images_vbm(); #$PM_code = 14
    sleep($interval);

    set_reference_space_vbm(); #$PM_code = 15
    sleep($interval);


    @channel_array = grep {$_ ne 'mask' } @channel_array;
    @channel_array = grep {$_ ne 'nii4D' } @channel_array;

    $channel_comma_list = join(',', @channel_array);
    $Hf->set_value('channel_comma_list',$channel_comma_list);


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

            # In theory, iterative_pairwise_reg_vbm and apply_mdt_warps_vbm can be combined into a 
            # "packet": as soon as a registration is completed, those warps can be immediately applied to
            # that contrast's images, independent of other registration jobs.

            $ii = iterative_pairwise_reg_vbm("d",$ii); #$PM_code = 41 # This returns $ii in case it is determined that some iteration levels can/should be skipped.
            sleep($interval);

            $group_name = "control";
            foreach my $a_contrast (@channel_array) {
                apply_mdt_warps_vbm($a_contrast,"f",$group_name); #$PM_code = 43
            }

            # 12 Feb 2019, BJA: moved this from before apply_mdt_warps_vbm to here, reorganizing to move towards making "packets"
            # of independent work 
            
            
            iterative_calculate_mdt_warps_vbm("f","diffeo"); #$PM_code = 42
        	sleep($interval);

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
 
	# 4 August 2020, BJA: We may very well want jacobians even if we arent' doing VBA.
    	#if ($do_vba) {
            calculate_jacobians_vbm('f','control'); #$PM_code = 47 (or 46) ## BAD code! Don't use this unless you are trying to make a point! #Just kidding its the right thing to do after all--WTH?!?
            sleep($interval);
        #}
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
    my $compare_reg_type="d";
    if ( $stop_after_mdt_creation ) {
        $compare_reg_type="skip"
    }
    compare_reg_to_mdt_vbm(${compare_reg_type}); #$PM_code = 51
    sleep($interval);
    #create_average_mdt_image_vbm(); ### What the heck was this?
    
    if ( ! $stop_after_mdt_creation ) {
        $group_name = "compare";    
        foreach my $a_contrast (@channel_array) {
            apply_mdt_warps_vbm($a_contrast,"f",$group_name); #$PM_code = 52 
        }
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

        if ( ! $stop_after_mdt_creation ) {
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

                if ($multiple_runnos) {
                   tabulate_label_statistics_by_contrast_vbm($a_label_space,@current_channel_array); #$PM_code = 66 
                   if ($multiple_groups) {	
                       label_stat_comparisons_between_groups_vbm($a_label_space,@current_channel_array); #$PM_code = 67
                   }
                }
                if ($do_connectivity) { # 21 April 2017, BJA: Moved this code from external _start.pl code
                    apply_warps_to_bvecs($a_label_space);	
                }
            }
            sleep($interval);
	    
        }   
}

    # 4 August 2020, BJA: We may very well want jacobians even if we arent' doing VBA.
    # if ($do_vba) {
        my $new_contrast = calculate_jacobians_vbm('f','compare'); #$PM_code = 53 
        push(@channel_array,$new_contrast);
        $channel_comma_list = $channel_comma_list.','.$new_contrast;
        $Hf->set_value('channel_comma_list',$channel_comma_list);
        sleep($interval);
if ($do_vba) {
        if ($multiple_groups) {
            vbm_analysis_vbm(); #$PM_code = 72
            sleep($interval);
        }
    }

    $Hf->write_headfile($result_headfile);

    print "\n\nSAMBA Pipeline has completed successfully.  Great job, you.\n\n";


    my $process = "SAMBA_pipeline";

    my $completion_message ="Congratulations, master scientist. Your SAMBA pipeline process has completed.  Hope you find something interesting.\n";
    my $results_message = "Results are available for your perusal in: ${results_dir}.\n";
    my $time = time;
    my $email_folder = '~/SAMBA_email/';
    if ( ! -d $email_folder ) {
	mkdir($email_folder,0777);
    }
    my $email_file="${email_folder}/SAMBA_completion_email_for_${time}.txt";

    my $local_time = localtime();
    my $local_time_stamp = "This file was generated on ${local_time}, local time.\n";
    my $time_stamp = "Completion time stamp = ${time} seconds since January 1, 1970 (or some equally asinine date).\n";


    my $subject_line = "Subject: SAMBA Pipeline has finished!!!\n";


    my $email_content = $subject_line.$completion_message.$results_message.$local_time_stamp.$time_stamp;
    `echo "${email_content}" > ${email_file}`;
    my $pwuid = getpwuid( $< );
    my $pipe_adm="";
    $pipe_adm=",rja20\@duke.edu";
    my $USER_LIST="$pwuid\@duke.edu$pipe_adm";
    `sendmail -f $process.${HOSTNAME}\@dhe.duke.edu $USER_LIST < ${email_file}`;

} #end main

#---------------------
sub add_defined_variables_to_headfile {
#---------------------

my ($Hf,@variable_names)=@_;

    for my $variable_name (@variable_names) {
        
        if (defined eval("\$".$variable_name)) {
            my $variable_value = eval("\$".${variable_name});
            $Hf->set_value($variable_name,$variable_value);
        }
    }
    #$Hf->print();die;
    return();

}

#---------------------
sub find_group_in_tsv {
#---------------------

my ($tsv_file,$report_field,$_ref_to_criteria_array)=@_;


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
