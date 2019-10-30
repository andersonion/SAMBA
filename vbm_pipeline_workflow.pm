#!/usr/bin/false
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

use lib dirname(abs_path($0));
BEGIN {
    use Env qw(RADISH_PERL_LIB WORKSTATION_DATA BIGGUS_DISKUS);
    if (! defined($RADISH_PERL_LIB)) {
        print STDERR "Cannot find good perl directories, quitting\n";
        die;
    }
}
use lib split(':',$RADISH_PERL_LIB);
# use ...
# CIVM standard req
use Headfile;
use text_sheet_utils;

# retrieve_archived_data is largely retired. 
# use retrieve_archived_data;
# in prep for never useing it again commented study variables
# use study_variables_vbm;
# Neither pull_civm_tensor nor ssh_call used directly here, 
# but keeping them here to centralize includes.
use pull_civm_tensor_data;
use ssh_call;

# VBM work proper (aproximately in order).
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

use apply_warps_to_bvecs;

our ($log_file,$stats_file,$timestamped_inputs_file,$project_id,$all_groups_comma_list );
our ($pristine_input_dir,$dir_work,$results_dir,$result_headfile);
our ($rigid_transform_suffix,$affine_transform_suffix, $affine_identity_matrix, $preprocess_dir,$inputs_dir);
# a do it again variable, will allow you to pull data from another vbm_run

$test_mode = 0;

# A forced wait time after starting each bit. (also used when we're doing check and wait operations.)
my $interval = 0.1; ##Normally 1
$valid_formats_string = 'hdr|img|nii|nii.gz|ngz|nhdr|nrrd';
$samba_label_types='labels|quagmire|mess';

# a flag to indicate we're in the civm eco system so all the parts should work
# and we try to resolve all the funny things.
$civm_ecosystem = 1; 
if ( $ENV{'BIGGUS_DISKUS'} =~ /gluster/) {
    $civm_ecosystem = 1;
} elsif ( $ENV{'BIGGUS_DISKUS'} =~ /civmnas4/) {
    $civm_ecosystem = 1;
} elsif (! exists $ENV{'WORKSTATION_HOSTNAME'} 
	 || ! defined load_engine_deps() ) {
    $civm_ecosystem = 0;
    printd(5,"WARNING: appears to be outside the full eco-system. Disabling overly specific bits\n");
    sleep_with_countdown(3);
}



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

    
    my $pipe_adm="";
    my $grp=getgrgid((getpwuid($<))[3]);
    if(! defined $CODE_DEV_GROUP
       || $CODE_DEV_GROUP ne $grp ) {
	$pipe_adm=",9196128939\@vtext.com,rja20\@duke.edu";
    } 
    # the components could be made responsible for filling this in by passing the array reference to their init routines
    my @variables_to_headfile=qw(
start_file project_id image_dimensions
control_comma_list compare_comma_list complete_comma_list channel_comma_list
pristine_input_dir preprocess_dir inputs_dir dir_work results_dir timestamped_inputs_file
flip_x flip_z original_study_orientation working_image_orientation
do_mask pre_masked skull_strip_contrast threshold_code port_atlas_mask port_atlas_mask_path
vbm_reference_space resample_images resample_factor
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
);

    if (defined $label_reference) {
        $Hf->set_value('label_reference_space',$label_reference);
    }

    ###
    #GROUP SORTING
    ###
    # on inspection no arrays could be defined yet here. 
    # SO, it is now an error for them to be defined.
    die if scalar(@group_1);
    die if scalar(@group_2);
    die if scalar(@control_group);
    die if scalar(@compare_group);
    # Slopilly, all_runnos also populates the group arrays. 
    # Due to how sloppy global_vars is (and how satisfying it is to call it all_runnos) 
    # that has been conceeded, instead of renaming to group_resolve.
    my @all_runnos=SAMBA_global_variables::all_runnos();
    if (scalar(@all_runnos) == 1) {
	# Single input == singleseg mode. 
	# If we dont have a suffix we use our runno.
        if (! $optional_suffix) {
            $optional_suffix = $all_runnos[0];
        }
	# vba doesn't make sense
        $do_vba = 0;
	# force pairwise
        $mdt_creation_strategy='pairwise';
    }

    if (! defined $do_vba) {
        $do_vba = 0;
    } elsif($do_vba) {
	carp "VBA has not been tested recently, and there have been MANY changes in structure! We apologize in advance if this doesnt work, AND we dont have time allocated to fix it. Please feel free to clone the code, repair it, and issue a pull request";
	sleep_with_countdown(45);
    }

    $project_id=SAMBA_structure::main_dir($project_name,scalar(@all_runnos),$rigid_atlas_name,$optional_suffix);
    ($pristine_input_dir,$dir_work,$results_dir,$result_headfile) = make_process_dirs($project_id); 

## Backwards compatability for rerunning work initially ran on glusterspace
# search start headfile for references to '/glusterspace/'
    if ((defined $start_file) && ( -f $start_file)) {
        my $start_contents=`cat $start_file`;
        if ($start_contents =~ /\/glusterspace\//) {
            carp("OLD FASHIONED DATA DETECTED! WARNING THIS IS NOT WELL TESTED");
            sleep_with_countdown(5);
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
        (my $last_result_headfile = $result_headfile )=~ s/\.headfile/_last\.headfile/;
        run_and_watch("mv -f ${result_headfile} ${last_result_headfile}");
    }
    $Hf = new Headfile ('nf',$result_headfile );
    if (! $Hf->check()){
        # We expect this to happen when a file with the same name as $result_headfile was not successfully moved a few lines above-
        # probably due to permissions issues, which is a huge red flag.
        croak("Is this your data? If not, you will need the original owner to run the pipeline.")
    }

    my $papertrail_dir="${results_dir}/papertrail";
    if (! -e $papertrail_dir) {
        mkdir($papertrail_dir);
    }

    $log_file = open_log($papertrail_dir); # 26 Feb 2019--changed from results_dir to "papertrail" subfolder
    printd(1000,"\tlog is $log_file\n");
    ( $stats_file = $log_file ) =~ s/pipeline_info/job_stats/;
    printd(1000,"\tlog is $log_file\n");
    printd(1000,"\tstats are $stats_file\n");
    
    $preprocess_dir = $dir_work.'/preprocess';
    #Poor form co-opting inputs-dir nomenclature to switch what we're up to
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
    if ((scalar @group_2)>0) {
	$multiple_groups = 1;
	carp "Multi-group support out of date! you may experience trailing crashes";
    }
## End duplication control
    
    if (! defined $image_dimensions) {
        $image_dimensions=3;
    }
    
    $Hf->set_value('number_of_nodes_used',$nodes);
    
    $rigid_transform_suffix='rigid.mat';
    $affine_transform_suffix='affine.mat';
    $affine_identity_matrix="$WORKSTATION_DATA/identity_affine.mat";
    
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
    ($timestamped_inputs_file = $log_file ) =~ s/pipeline_info/input_parameters/;
    $timestamped_inputs_file =~ s/\.txt$/\.headfile/;
    if( defined $timestamped_inputs_file  && $timestamped_inputs_file ne "" ) {
        run_and_watch("cp -pv ${start_file} ${timestamped_inputs_file}");
    } else {
        carp "failure to set timestampted_inputs_file from log $log_file";
        sleep_with_countdown(2);
    }
    if( defined $c_input_headfile && $c_input_headfile ne "" ) { 
        `cp -pv ${start_file} ${c_input_headfile}|| echo "Couldnt preserve current inputs to work!"`;
    } else {
        confess "failure to set current_inputs headfile!";
    }
# caching inputs to common location for all to admire
    {
        my ($p,$n,$e)=fileparts($start_file,3);
        my $u_name=(getpwuid $>)[0];
        my $cached_path=File::Spec->catfile($WORKSTATION_DATA,'samba_startup_cache',$u_name.'_'.$n.$e);
        if( defined $cached_path && $cached_path ne "" ) {
            run_and_watch("cp -pv $start_file $cached_path");
        }
    }
    if ( defined $convert_labels_to_RAS
	 && defined $working_image_orientation ) {
	if ( $working_image_orientation =~ /RAS/ix 
	    && $convert_labels_to_RAS ) {
	    $convert_labels_to_RAS=0;
	    printd(5,"convert_labels_to_RAS was on, but we're working RAS.\n"
		   ."\tWe're going to ignore it\n");
	    sleep(2);
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

###    
# maincode
### 
    
    print STDOUT " Running the main code of $PM. \n";
    
    ## Initilization code starts here.
# Check command line options and report related errors
# WAFFELED ON FORWARDS OR BACKWARDS:
#   Check backwards will avoid replicating the check for needed input data at every step.
#   Report errors forwards, since this is more user friendly.
#   CAUSES PROBLEMS WITH SOME MODULES WHO SET VARIABLES IN THEIR INIT CODE FOR LATER MODULES TO USE!
# So we're actually checking forwards.
#   Forwards seems the correct direction to init, but we should then run 
#   outputchecks starting at the back, ... and somehow only complete trailing work.
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

    my %init_dispatch_table;
    # Using camelCase here to avoid the potential need for playing the escape 
    # character game when calling command with backticks, etc.
    my $checkCall; 
    my $Init_suffix = "_Init_check";
    # for (my $mm = $#modules_for_Init_check; $mm >=0; $mm--)) { # This checks backwards
    for (my $mm = 0; $mm <= $#modules_for_Init_check; $mm++) { # This checks forwards
        my $module = $modules_for_Init_check[$mm];
	$checkCall = "${module}${Init_suffix}";
        $init_dispatch_table{$checkCall}=eval('\&$checkCall'); # MUST USE SINGLE QUOTES on RHS!!!
	print STDOUT "Check call is $checkCall\n";
        my $temp_error_msg = '';
        $temp_error_msg=$init_dispatch_table{$checkCall}();
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
        mkdir($inputs_dir);
    }
    
# nii4D to keep track of nii4d specific things separate from the larger 
# do_connectivity tasks
    my $nii4D = 0;
    if ($do_connectivity) {
        $nii4D = 1;
    }
    
# Need to pass the nii4D flag in a more elegant manner...
    if ($nii4D) {
        push(@channel_array,'nii4D');
        $channel_comma_list = $channel_comma_list.',nii4D';
        $Hf->set_value('channel_comma_list',$channel_comma_list);
    }
# Gather all needed data and put in inputs directory
# AND reorient/recenter
# POORLY NAMED As it runs off to get data in addition to
# RE-CREATING all nifti files while re-orienting them
# Certainly should be broken into the two parts, 
# get all the data called ... pull_multi?
# and
# nifti_header_capitulator... or nifti_unifier ... 
# perhaps nifti_capitulator is most unclearly clear.
    convert_all_to_nifti_vbm(); #$PM_code = 12
    sleep($interval);
    if (create_rd_from_e2_and_e3_vbm()) { #$PM_code = 13
        printd(5,"Tensor create data will invent rd from mean(e2+e3)\n");
	push(@channel_array,'rd');
        $channel_comma_list = $channel_comma_list.',rd';
        $Hf->set_value('channel_comma_list',$channel_comma_list);
    }
    sleep($interval);
# Before 11 April 2017: nii4Ds were not masked; After 11 April 2017: nii4Ds are masked for processing/storage/reading/writing efficiency
# mask is rather dirty it overwrites and removes its working images.
    mask_images_vbm(); #$PM_code = 14
    sleep($interval);

    set_reference_space_vbm(); #$PM_code = 15
    sleep($interval);
    
    # Force mask and nii4D out of channel array becuase they require special handling.
    @channel_array = grep {$_ ne 'mask' } @channel_array;
    @channel_array = grep {$_ ne 'nii4D' } @channel_array;
    $channel_comma_list = join(',', @channel_array);
    $Hf->set_value('channel_comma_list',$channel_comma_list);
    
###
# Register all to atlas
# First as rigid, then not
    my $do_rigid = 1;   
    create_affine_reg_to_atlas_vbm($do_rigid); #$PM_code = 21
    sleep($interval);
    
    if (1) { #  Need to take out this hardcoded bit!
        $do_rigid = 0;
        create_affine_reg_to_atlas_vbm($do_rigid); #$PM_code = 39
        sleep($interval);
    }
###
    

# pairwise_reg_vbm("a");
# sleep($interval);    
    
# calculate_mdt_warps_vbm("f","affine");
# sleep($interval);

    my $group_name='';
    
## Different approaches to MDT creation start to diverge here. ## 2 November 2016
    if ($mdt_creation_strategy eq 'iterative') {
        my ($use_st_i,$starting_iteration)=$Hf->get_value_check('starting_iteration');
        if ($use_st_i && $starting_iteration =~ /([1-9]{1}|[0-9]{2,})/) {
        } elsif($use_st_i ) { 
            error_out("Bad starting iteration found! $starting_iteration");
        } else {
            $starting_iteration = 0;
        }
        # print "starting_iteration = ${starting_iteration}";
        
        # TODO? Conver to "while" loop that runs to a certain point of stability(isntead of always prescribed mdt_iterations).
        # We don't really count the 0th iteration because normally this is just the averaging of the affine-aligned images. 
        my $temp_test=4;
        for (my $ii = $starting_iteration; $ii <= $mdt_iterations; $ii++) {
            # In theory, iterative_pairwise_reg_vbm and apply_mdt_warps_vbm can be combined into a 
            # "packet": as soon as a registration is completed, those warps can be immediately applied to
            # that contrast's images, independent of other registration jobs.
            
            # This set's $ii in case it is determined that some iteration levels can/should be skipped.
            $ii = iterative_pairwise_reg_vbm("d",$ii); #$PM_code = 41
            sleep($interval);
            ####
            # slick nonsense here where we skip all contrasts except the operational one 
            # (until the final iteration)
            my @op_cont;
            if($ii<$mdt_iterations) {
                @op_cont=($mdt_contrast);
            } else {
                @op_cont=@channel_array;
            }
            ###
            
            $group_name = "control";
            # TODO: this loop belongs in the PM in some fashion
            foreach my $a_contrast (@op_cont) {
                apply_mdt_warps_vbm($a_contrast,"f",$group_name); #$PM_code = 43
            }
            
            iterative_calculate_mdt_warps_vbm("f","diffeo"); #$PM_code = 42
            sleep($interval);
            
            calculate_mdt_images_vbm($ii,@op_cont); #$PM_code = 44
            sleep($interval);
        }
        
	if ($do_vba ) {
	    # I think this is a Only need this if VBA
	    # Let's omit
	    mask_for_mdt_vbm(); #$PM_code = 45
	    sleep($interval);
	}
    } else {
	printd(5,"WARNING: This code has not been tested in quite some time!\n"
	       ."If you test it sucessfully, let the sloppy programmer know he can remove this wait\n"
	       ."Please enjoy the next 30 seconds ... " );
	sleep_with_countdown(30);
    #
    # PAIRWISE VERSION
    #
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
        calculate_jacobians_vbm('f','control'); #$PM_code = 47 (or 46) ## BAD code! Don't use this unless you are trying to make a point! #Just kidding its the right thing to do after all--WTH?!?
        sleep($interval);
    }
    }
    
# Things can get parallel right about here...
   
# Branch one: 
# create MDT to atlas "transforms"
#   also sets our output structure formerly thte stats_by_region/labels/transforms
# Now , transforms, vox_measure/labels
    if ($create_labels || $register_MDT_to_atlas) {
        $do_rigid = 0;
        my $mdt_to_atlas = 1;
        create_affine_reg_to_atlas_vbm($do_rigid,$mdt_to_atlas);  #$PM_code = 61
        sleep($interval);
        mdt_reg_to_atlas_vbm(); #$PM_code = 62
        sleep($interval);
    }
# Branch two:
# create RUNNO to MDT (reg_diffeo and reg_images)
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
    if ($create_labels || $register_MDT_to_atlas ) {
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
        if ( $create_labels ) {
            # label_space is comma sep global
            my @label_spaces = split(',',$label_space);
	    my $qa_space='MDT';
	    my $qa_only_mdt=0;
	    if( $label_space !~ /$qa_space/ ){
		push(@label_spaces,'MDT');
		$qa_only_mdt=1;
	    }
            warp_atlas_labels_vbm('MDT','MDT'); #$PM_code = 63
            sleep($interval);
	    # It would be nice to run the calc stats on our vbm dataset...
	    # the function interface doesnt exist, but the internal call has one.
	    #calculate_individual_label_statistics_vbm($a_label_space);
	    # so roughly, that is
	    #my $label_measure_jid = calculate_label_statistics($runno,$input_labels,$lookup_table);
            #my $label_measure_jid = calculate_label_statistics('MDT',$Hf->get_value("MDT_${label_atlas_nickname}_".$Hf->get_value("label_type")),
	    #                     $Hf->get_value("MDT_${label_atlas_nickname}_labels_lookup_table"));
	    # Quick check didnt work due to the horrfic hard cody nature , tried after the loop of work also and it failed too.
	    #
	    
=item
# Here's an ugly breakdown of the call and args to that funtion. Maybe we can do an inline sbatch call.
stat_exec="/cm/shared/workstation_code_dev/matlab_execs/write_individual_stats_executable/stable/run_write_individual_stats_exec.sh";
mat_runtime="/cm/shared/apps/MATLAB/R2015b";
template_dir=/mnt/civmbigdata/civmBigDataVol/jjc29/VBM_16gaj38_chass_symmetric3_RAS_CodeTest_CE-work/dwi/SyN_0p23_3_0p5_fa/faMDT_NoNameYet_n6_i4
median_images=$template_dir/median_images

/mnt/civmbigdata/civmBigDataVol/jjc29/VBM_16gaj38_chass_symmetric3_RAS_CodeTest_CE-work/dwi/SyN_0p23_3_0p5_fa/faMDT_NoNameYet_n6_i4/vox_measure/atlas_native_space 
label_file=$Hf->get_value("MDT_${label_atlas_nickname}_".$Hf->get_value("label_type"));
lookup_file=$Hf->get_value("MDT_${label_atlas_nickname}_labels_lookup_table"));
command=$stat_exec, $mat_runtime, MDT, $label_file, "dwi,fa,adc,e1,e2,e3,rd", $median_images/labels_MDT, $stat_dir, "MDT", "WHS",$lookup_file, 1
$stat_dir
atlas WHS NO_KEY 1

write_individual_stats_exec(runno,label_file,contrast_list,image_dir,output_dir,space,atlas_id,lookup,mask_with_contrast1


=cut
	    if ( ! $stop_after_mdt_creation ) {
                $group_name = "all";
                my @current_channel_array = @channel_array;
                if ($do_connectivity) {
                    push (@current_channel_array,'nii4D');
                }
                @current_channel_array = uniq(@current_channel_array);
                #foreach my $a_label_space (@label_spaces) {
		my @prev_channel=@current_channel_array;
                while (my $a_label_space= shift(@label_spaces) ) {
                    #warp_atlas_labels_vbm('all',$a_label_space); #$PM_code = 63
		    warp_atlas_labels_vbm($group_name,$a_label_space); #$PM_code = 63
                    sleep($interval);
		    if ( $qa_only_mdt && $a_label_space =~ /MDT/ ) { 
			@current_channel_array=qw(dwi fa);
		    }
		    foreach my $a_contrast (@current_channel_array) {
                        apply_mdt_warps_vbm($a_contrast,"f",$group_name,$a_label_space); #$PM_code = 64
                    }
		    if ( ! ( $qa_only_mdt && $a_label_space =~ /MDT/ ) ) { 
			calculate_individual_label_statistics_vbm($a_label_space); #$PM_code = 65
		    } else {
			calculate_individual_label_statistics_vbm($a_label_space,@current_channel_array); #$PM_code = 65
		    }
		    if ($multiple_runnos) {
                        tabulate_label_statistics_by_contrast_vbm($a_label_space,@current_channel_array); #$PM_code = 66 
                        if ($multiple_groups) {
			    label_stat_comparisons_between_groups_vbm($a_label_space,@current_channel_array); #$PM_code = 67
                        }
                    }
		    if ( $qa_only_mdt && $a_label_space =~ /MDT/ ) { 
			# intentionally skipping bvec if we just quietly insisted on making a bigger mess.
			next;
		    }
                    if ($do_connectivity) { # 21 April 2017, BJA: Moved this code from external _start.pl code
                        apply_warps_to_bvecs($a_label_space);
                    }
		    @current_channel_array=@prev_channel;
                }
                sleep($interval);
            }
	}
    }
    if ($do_vba) {
	carp "VBA has not been tested recently, and there have been MANY changes in structure! We apologize in advance if this doesnt work, AND we dont have time allocated to fix it. Please feel free to clone the code, repair it, and issue a pull request";
        my $new_contrast = calculate_jacobians_vbm('f','compare'); #$PM_code = 53 
        push(@channel_array,$new_contrast);
        $channel_comma_list = $channel_comma_list.','.$new_contrast;
        $Hf->set_value('channel_comma_list',$channel_comma_list);
        sleep($interval);
	if ($multiple_groups) {
            vbm_analysis_vbm(); #$PM_code = 72
            sleep($interval);
        }
    }
    
    $Hf->write_headfile($result_headfile);
    print "\n\nVBM Pipeline has completed successfully.  Great job, you.\n\n";
    
    
    my $process = "vbm_pipeline";
    my $completion_message ="Congratulations, master scientist. Your VBM pipeline process has completed.  Hope you find something interesting.\n";
    my $results_message = "Results are available for your perusal in: ${results_dir}.\n";
    my $time = time;
    my $email_folder = '/home/rja20/cluster_code/workstation_code/analysis/vbm_pipe/email/';                        
    my $email_file="${email_folder}/VBM_pipeline_completion_email_for_${time}.txt";
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
    my $nice_timestamp = sprintf ( "%04d-%02d-%02d_%02d:%02d:%02d",
                                   $year+1900,$mon+1,$mday,$hour,$min,$sec);
    my $local_time = localtime();
    my $local_time_stamp = "This file was generated on ${local_time}, local time.\n";
    my $time_stamp = "Completion time stamp = ${time} seconds since the Unix Epoc (or $nice_timestamp if you prefer).\n";
#January 1, 1970 (or some equally asinine date).\n" <--- said the ignorant programmmer :p
    my $subject_line = "Subject: VBM Pipeline has finished!!!\n";
    
    my $email_content = $subject_line.$completion_message.$results_message.$local_time_stamp.$time_stamp;
    `echo "${email_content}" > ${email_file}`;
    my $pwuid = getpwuid( $< );
    my $USER_LIST="$pwuid\@duke.edu$pipe_adm";
    `sendmail -f $process.civmcluster1\@dhe.duke.edu $USER_LIST < ${email_file}`;
    
} #end main

#---------------------
sub add_defined_variables_to_headfile {
#---------------------

    my ($Hf,@variable_names)=@_;
    for my $variable_name (@variable_names) {
	my $variable_value = eval("\$".${variable_name});
	$Hf->set_value($variable_name,$variable_value) if (defined $variable_value );
    }
    return;
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
