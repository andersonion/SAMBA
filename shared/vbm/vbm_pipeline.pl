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
use vars qw($Hf $BADEXIT $GOODEXIT $test_mode $intermediate_affine);
use Env qw(ANTSPATH PATH BIGGUS_DISKUS);
$ENV{'PATH'}=$ANTSPATH.':'.$PATH;

$GOODEXIT = 0;
$BADEXIT  = 1;
my $ERROR_EXIT=$BADEXIT;

$intermediate_affine = 1;
$test_mode = 1;
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


my $interval = 1;
# Temporary hardcoded variables

my $project_name = "13.colton.01";
my @control_group = qw(N51193 N51211 N51221 N51406);
my @compare_group = qw(N51136 N51201 N51234 N51392);
my @channel_array = qw(adc dwi e1 e2 e3 fa); # This will be determined by command line, and will be able to include STI, T1, T2, T2star, etc.

my $flip_x = 1;
my $flip_z = 0;

my $optional_suffix = '';
my $atlas_name = 'DTI';
my $rigid_contrast = 'dwi';
my $mdt_contrast = 'fa';
my $atlas_dir = "/home/rja20/cluster_code/data/atlas/DTI";
my $skull_strip_contrast = 'dwi';
my $threshold_code = 2200;
my $do_mask = 1;



## The following are mostly ready-to-go variables (i.e. non hard-coded)

if ($optional_suffix ne '') {
    $optional_suffix = "_${optional_suffix}";
}


my @project_components = split(/[.]/,$project_name); # $project_name =~ s/[.]//g;
my $project_id =  join('',@project_components);
$project_id = "VBM_".$project_id.'_'.$atlas_name.$optional_suffix; #create_identifer($project_name);

my $custom_predictor_string = "Genotype_1_vs_2";
my ($pristine_input_dir,$work_dir,$result_dir,$result_headfile) = make_process_dirs($project_id); #new_get_engine_dependencies($project_id);
$Hf = new Headfile ('rw',$result_headfile );
open_log($result_dir);

my $inputs_dir = $work_dir.'/base_images';

my $control_comma_list = join(',',@control_group);
my $compare_comma_list = join(',',@compare_group);
my $complete_comma_list = $control_comma_list.','.$compare_comma_list;

my $channel_comma_list = join(',',@channel_array);

$Hf->set_value('control_comma_list',$control_comma_list);
$Hf->set_value('compare_comma_list',$compare_comma_list);
$Hf->set_value('complete_comma_list',$complete_comma_list);
$Hf->set_value('channel_comma_list',$channel_comma_list);

$Hf->set_value('atlas_name',$atlas_name);
$Hf->set_value('rigid_contrast',$rigid_contrast);
$Hf->set_value('mdt_contrast',$mdt_contrast);
$Hf->set_value('rigid_atlas_dir',$atlas_dir);
$Hf->set_value('skull_strip_contrast',$skull_strip_contrast);
$Hf->set_value('threshold_code',$threshold_code);
$Hf->set_value('rigid_transform_suffix','rigid.mat');

$Hf->set_value('flip_x',$flip_x);
$Hf->set_value('flip_z',$flip_z);
$Hf->set_value('do_mask',$do_mask);

$Hf->set_value('predictor_id',$custom_predictor_string);

$Hf->set_value('pristine_input_dir',$pristine_input_dir);
$Hf->set_value('inputs_dir',$inputs_dir);
$Hf->set_value('dir_work',$work_dir);
$Hf->set_value('results_dir',$result_dir);

$Hf->set_value('engine_app_matlab','/usr/local/bin/matlab');
$Hf->set_value('engine_app_matlab_opts','-nosplash -nodisplay -nodesktop');
$Hf->set_value('nifti_matlab_converter','civm_to_nii'); # This should stay hardcoded.

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
    my $bd = '/glusterspace'; #bd for Biggus-Diskus
    my $dr = $pristine_input_dir;
    my @all_runnos =  split(',',$complete_comma_list);
    foreach my $runno (@all_runnos) {
	my $path_string = "${bd}/${runno}Labels-inputs/${runno}/";
	`cp ${path_string}/* $dr/`;
    }
##
    if (! -e $inputs_dir) {
	mkdir($inputs_dir,0777);
    }

# Gather all needed data and put in inputs directory
 
    convert_all_to_nifti_vbm();
    sleep($interval);

    mask_images_vbm();
    sleep($interval);

# Convert file names if need be?


# Register all to atlas
   
    create_affine_reg_to_atlas_vbm();
    sleep($interval);

    apply_affine_reg_to_atlas_vbm();
    sleep($interval);

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

## Put this elsewhere
    my @master_contrast_list=qw(adc dwi e1 e2 e3 fa);   
    my @other_contrasts = ();
    foreach my $this_contrast (@master_contrast_list) {
	if ($this_contrast ne $mdt_contrast) {
	    push(@other_contrasts,$this_contrast);
	}
    }
##
    my $group_name = "control";
    apply_mdt_warps_vbm($mdt_contrast,"f",$group_name);
    sleep($interval);

    calculate_mdt_images_vbm($mdt_contrast);
    sleep($interval);

    foreach my $other_contrast (@other_contrasts) {
	apply_mdt_warps_vbm($other_contrast,"f",$group_name);
    }
    calculate_mdt_images_vbm(@other_contrasts);
    sleep($interval);

    compare_reg_to_mdt_vbm("d");
    sleep($interval);
    #create_average_mdt_image_vbm();

    $group_name = "compare";
    apply_mdt_warps_vbm($mdt_contrast,"f",$group_name);
    sleep($interval);
    
    foreach my $other_contrast (@other_contrasts) {
	apply_mdt_warps_vbm($other_contrast,"f",$group_name);
    }
    sleep($interval);


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
