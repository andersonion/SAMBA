#!/usr/local/pipeline-link/perl
# vbm_pipeline.pl
# created 2014/11/17 BJ Anderson CIVM
#
# Roughly modeled after seg_pipe_mc structure. (For better or for worse.)
#
#
#
#
#
#
#
#


# All my includes and requires are belong to us.
# use ...

my $PM = 'vbm_pipeline.pl'; 

use strict;
use warnings;
no warnings qw(uninitialized bareword);

use Cwd qw(abs_path);
use File::Basename;
use vars qw($Hf $BADEXIT $GOODEXIT $test_mode $intermediate_affine $syn_params $permissions);
use Env qw(ANTSPATH PATH BIGGUS_DISKUS WORKSTATION_DATA);

$ENV{'PATH'}=$ANTSPATH.':'.$PATH;

$GOODEXIT = 0;
$BADEXIT  = 1;
my $ERROR_EXIT=$BADEXIT;
$permissions = '0755';
my $interval = 1;

my $import_data = 0;

$intermediate_affine = 0;
$test_mode = 0;
$syn_params = "0.5,3,0"; # Normally use 0.5,3,0

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
#require create_labels;  #when will I need this?

require convert_all_to_nifti_vbm;
require mask_images_vbm;
require create_affine_reg_to_atlas_vbm;
require apply_affine_reg_to_atlas_vbm;
require pairwise_reg_vbm;
require calculate_mdt_warps_vbm;
require apply_mdt_warps_vbm;
require calculate_mdt_images_vbm;
require compare_reg_to_mdt_vbm;
require mdt_reg_to_atlas_vbm;
require warp_atlas_labels_vbm;


# Temporary hardcoded variables

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
$thresh_ref
$syn_iterations
$diffeo_downsampling
$affine_target
$affine_contrast
$native_reference_space
$create_labels
 );

study_variables_vbm();

## The following are mostly ready-to-go variables (i.e. non hard-coded)

if ($optional_suffix ne '') {
    $optional_suffix = "_${optional_suffix}";
}

my $reference_space='';
if ($native_reference_space) {
    $reference_space = 'native';
} else {
    $reference_space = $atlas_name;
}


my @project_components = split(/[.]/,$project_name); # $project_name =~ s/[.]//g;
my $project_id =  join('',@project_components);
$project_id = "VBM_".$project_id.'_'.$atlas_name.$optional_suffix; #create_identifer($project_name);

my ($pristine_input_dir,$work_dir,$result_dir,$result_headfile) = make_process_dirs($project_id); #new_get_engine_dependencies($project_id);
$Hf = new Headfile ('rw',$result_headfile );
open_log($result_dir);

my $inputs_dir = $work_dir.'/base_images';
my $atlas_dir = "${WORKSTATION_DATA}/atlas/${atlas_name}";
my $label_atlas_dir = "${WORKSTATION_DATA}/atlas/${label_atlas_name}";
my $control_comma_list = join(',',@control_group);
my $compare_comma_list = join(',',@compare_group);
my $complete_comma_list = $control_comma_list.','.$compare_comma_list;

my $channel_comma_list = join(',',@channel_array);

$Hf->set_value('control_comma_list',$control_comma_list);
$Hf->set_value('compare_comma_list',$compare_comma_list);
$Hf->set_value('complete_comma_list',$complete_comma_list);
$Hf->set_value('channel_comma_list',$channel_comma_list);

$Hf->set_value('atlas_name',$atlas_name);
$Hf->set_value('label_atlas_name',$label_atlas_name);
$Hf->set_value('rigid_contrast',$rigid_contrast);
$Hf->set_value('mdt_contrast',$mdt_contrast);
$Hf->set_value('rigid_atlas_dir',$atlas_dir);
$Hf->set_value('label_atlas_dir',$label_atlas_dir);
$Hf->set_value('skull_strip_contrast',$skull_strip_contrast);
$Hf->set_value('threshold_code',$threshold_code);
$Hf->set_value('rigid_transform_suffix','rigid.mat');
$Hf->set_value('affine_transform_suffix','affine.mat');
$Hf->set_value('affine_target_image',$affine_target);
$Hf->set_value('full_affine_contrast',$affine_contrast);


$Hf->set_value('flip_x',$flip_x);
$Hf->set_value('flip_z',$flip_z);

$Hf->set_value('do_mask',$do_mask);
if (defined $thresh_ref) {
    $Hf->set_value('threshold_hash_reference',$thresh_ref);
}



$Hf->set_value('predictor_id',$custom_predictor_string);

$Hf->set_value('pristine_input_dir',$pristine_input_dir);
$Hf->set_value('inputs_dir',$inputs_dir);
$Hf->set_value('dir_work',$work_dir);
$Hf->set_value('results_dir',$result_dir);

$Hf->set_value('engine_app_matlab','/usr/local/bin/matlab');
$Hf->set_value('engine_app_matlab_opts','-nosplash -nodisplay -nodesktop');
$Hf->set_value('nifti_matlab_converter','civm_to_nii'); # This should stay hardcoded.



my @iterations = split(',',$diffeo_downsampling);
my $levels = $#iterations + 1;
my $sigma_string = "0";

if ($test_mode) {
    $Hf->set_value('test_mode','on');
    my $new_syn_iter = "1";
   
    for (my $ii = 2; $ii <= $levels; $ii++) {
	$new_syn_iter = $new_syn_iter.',0'; # $diffsyn_iter="1x0x0x0";
    }
    $syn_iterations = $new_syn_iter;
} else {
    $Hf->set_value('test_mode','off');

}

for (my $jj = 2; $jj <= $levels; $jj++) {
	$sigma_string = $sigma_string.'x0';
}

my $syn_iter_string = join('x',split(',',$syn_iterations));
my $downsample_string = join('x',split(',',$diffeo_downsampling));

$Hf->set_value('syn_iteration_string',$syn_iter_string);
$Hf->set_value('diffeo_downsampling',$downsample_string);
$Hf->set_value('smoothing_sigmas',$sigma_string);
$Hf->set_value('SyN_parameters', $syn_params);

$Hf->set_value('reference_space',$reference_space);

#maincode
{
    print STDOUT " Running the main code of $PM. \n";
# Set up needed variables


# Set up headfile
#HfResult='';

# Parse command line


# Check command line options and report related errors

    # Check backwards.  This will avoid replicating the check for needed input data at every step.
    # Report errors forwards, since this is more user friendly.
    my $init_error_msg='';
    

    my @modules_for_Init_check = qw(
     convert_all_to_nifti_vbm
     mask_images_vbm
     create_affine_reg_to_atlas_vbm
     apply_affine_reg_to_atlas_vbm
     pairwise_reg_vbm
     calculate_mdt_warps_vbm
     apply_mdt_warps_vbm
     calculate_mdt_images_vbm
     compare_reg_to_mdt_vbm
     mdt_reg_to_atlas_vbm
     warp_atlas_labels_vbm
     );


     my $checkCall; # Using camelCase here to avoid the potential need for playing the escape character game when calling command with backticks, etc.
     my $Init_suffix = "_Init_check()";

     for (my $mm = $#modules_for_Init_check; $mm >=0; $mm=($mm-1)) {
	 my $module = $modules_for_Init_check[$mm];	 
	 $checkCall = "${module}${Init_suffix}";
	 print STDOUT "Check call is $checkCall\n";
	 my $temp_error_msg = '';

	 ($temp_error_msg) = eval($checkCall);

	 if ($temp_error_msg ne '') {
	     if ($init_error_msg ne '') {
		 $init_error_msg = "${temp_error_msg}\n------\n\n${init_error_msg}";
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
## Stopgap business
    # if ($import_data) {
    # 	my $bd = '/glusterspace'; #bd for Biggus-Diskus
    # 	my $dr = $pristine_input_dir;
    # 	my @all_runnos =  split(',',$complete_comma_list);
    # 	foreach my $runno (@all_runnos) {
    # 	    my $path_string = "${bd}/${runno}Labels-inputs/${runno}/";
    # 	    `cp ${path_string}/* $dr/`;
    # 	}
    # }
##
    if (! -e $inputs_dir) {
	mkdir($inputs_dir,0777);
    }
    if ($import_data) { 
	load_study_data_vbm();
    }
# Gather all needed data and put in inputs directory
    convert_all_to_nifti_vbm();
    sleep($interval);

    mask_images_vbm();
    sleep($interval);

# Convert file names if need be?


# Register all to atlas
    my $do_rigid = 1;   
    create_affine_reg_to_atlas_vbm($do_rigid);
    sleep($interval);

    apply_affine_reg_to_atlas_vbm();
    sleep($interval);

    if (1) { #  Need to take out this hardcoded bit!
	$do_rigid = 0;
	create_affine_reg_to_atlas_vbm($do_rigid);
	sleep($interval);
    }

   # pairwise_reg_vbm("a");
   # sleep($interval);    

   # calculate_mdt_warps_vbm("f","affine");
   # sleep($interval);

    pairwise_reg_vbm("d");
    sleep($interval);
    
    calculate_mdt_warps_vbm("f","diffeo");
    sleep($interval);

    calculate_mdt_warps_vbm("i","diffeo");
    sleep($interval);

    my $group_name = "control";
    foreach my $a_contrast (@channel_array) {
	apply_mdt_warps_vbm($a_contrast,"f",$group_name);
    }
    calculate_mdt_images_vbm(@channel_array);
    sleep($interval);

# Things can get parallel right about here...

# Branch one: 
   if ($create_labels) {
	$do_rigid = 0;
	my $mdt_to_atlas = 1;
	create_affine_reg_to_atlas_vbm($do_rigid,$mdt_to_atlas);
	sleep($interval);

	mdt_reg_to_atlas_vbm();
	sleep($interval);
    }

# Branch two:
    compare_reg_to_mdt_vbm("d");
    sleep($interval);
    #create_average_mdt_image_vbm();

    $group_name = "compare";    
    foreach my $a_contrast (@channel_array) {
	apply_mdt_warps_vbm($a_contrast,"f",$group_name);
    }
    sleep($interval);


# Remerge before ending pipeline

    my $MDT_to_atlas_JobID = $Hf->get_value('MDT_to_atlas_JobID');
    if (cluster_check() && ($MDT_to_atlas_JobID ne 'NO_KEY')) {
    	my $interval = 15;
    	my $verbose = 1;
    	my $done_waiting = cluster_wait_for_jobs($interval,$verbose,$MDT_to_atlas_JobID);
	print " Waiting for Job ${MDT_to_atlas_JobID}\n";
    	if ($done_waiting) {
    	    print STDOUT  " Diffeomorphic registration from MDT to label atlas ${label_atlas_name} job has completed; moving on to next serial step.\n";
    	}
    }
    my $case = 2;
    my ($dummy,$error_message)=mdt_reg_to_atlas_Output_check($case);

    if ($error_message ne '') {
    	error_out("${error_message}",0);
    }

    warp_atlas_labels_vbm();
    sleep($interval);

#



    $Hf->write_headfile($result_headfile);
# Not part of official code:
    if (0) {
	foreach my $runno (@control_group) {
	    my @forward_array = split(',',$Hf->get_value("forward_xforms_${runno}"));
	    my @inverse_array = split(',',$Hf->get_value("inverse_xforms_${runno}"));
	    
	    print " The forward transforms for control runno $runno are:\n";
	    foreach my $f_xform (@forward_array) {
		print "\t${f_xform}\n";
	    }
	    print "\n The inverse transforms for control runno $runno are:\n";
	    foreach my $i_xform (@inverse_array) {
		print "\t${i_xform}\n";
	    }
	    
	    
	}
    }

    print "\n\nVBM Pipeline has completed successfully.  Great job, you.\n\n";
} #end main

sub sub1 {
}
