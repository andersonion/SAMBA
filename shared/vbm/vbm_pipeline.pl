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
no warnings qw(uninitialized);

use Cwd qw(abs_path);
use File::Basename;
use vars qw($Hf $BADEXIT $GOODEXIT $test_mode $intermediate_affine);
use Env qw(ANTSPATH PATH BIGGUS_DISKUS);
$ENV{'PATH'}=$ANTSPATH.':'.$PATH;

$GOODEXIT = 0;
$BADEXIT  = 1;
my $ERROR_EXIT=$BADEXIT;

$intermediate_affine = 0;

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

require create_affine_reg_to_atlas_vbm;
require apply_affine_reg_to_atlas_vbm;
require pairwise_reg_vbm;
require calculate_mdt_warps_vbm;

my $interval = 0.5;
# Temporary hardcoded variables

my $project_name = "13.colton.01";
my @control_group = qw(N51136 N51201 N51234 N51392);
my @compare_group = qw(N51193 N51211 N51221 N51406); 
my $optional_suffix = '';
my $atlas_name = 'whs';
my $rigid_contrast = 'dwi';
my $mdt_contrast = 'fa';
my $atlas_dir = "/home/rja20/cluster_code/data/atlas/whs";

if ($optional_suffix ne '') {
    $optional_suffix = "_${optional_suffix}";
}


my @project_components = split(/[.]/,$project_name); # $project_name =~ s/[.]//g;
my $project_id =  join('',@project_components);
$project_id = "VBM_".$project_id.'_'.$atlas_name.$optional_suffix; #create_identifer($project_name);

my $custom_predictor_string = "Genotype_1_vs_2";
my ($input_dir,$work_dir,$result_dir,$result_headfile) = make_process_dirs($project_id); #new_get_engine_dependencies($project_id);
$Hf = new Headfile ('rw',$result_headfile );
open_log($result_dir);

my $control_comma_list = join(',',@control_group);
my $compare_comma_list = join(',',@compare_group);
my $complete_comma_list = $control_comma_list.','.$compare_comma_list;

$Hf->set_value('control_comma_list',$control_comma_list);
$Hf->set_value('compare_comma_list',$compare_comma_list);
$Hf->set_value('complete_comma_list',$complete_comma_list);
$Hf->set_value('atlas_name',$atlas_name);
$Hf->set_value('rigid_contrast',$rigid_contrast);
$Hf->set_value('mdt_contrast',$mdt_contrast);
$Hf->set_value('rigid_atlas_dir',$atlas_dir);
$Hf->set_value('rigid_transform_suffix','0GenericAffine.mat');

$Hf->set_value('predictor_id',$custom_predictor_string);

$Hf->set_value('inputs_dir',$input_dir);
$Hf->set_value('work_dir',$work_dir);
$Hf->set_value('results_dir',$result_dir);

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
     create_affine_reg_to_atlas_vbm
     apply_affine_reg_to_atlas_vbm
     pairwise_reg_vbm
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
# Gather all needed data and put in inputs directory

# Convert file names if need be?


# Register all to atlas
   
    create_affine_reg_to_atlas_vbm();
    sleep($interval);

    apply_affine_reg_to_atlas_vbm();
    sleep($interval);
    
    pairwise_reg_vbm();
    sleep($interval);
    
    calculate_mdt_warps_vbm("i");
    sleep($interval);

    # calculate_mdt_warps_vbm($inverse=1);
    # apply_mdt_warps_vbm();
    # create_average_mdt_image_vbm();

    $Hf->write_headfile($result_headfile);
 
} #end main

sub sub1 {
}
