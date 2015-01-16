#!/usr/local/pipeline-link/perl
# apply_affine_reg_to_atlas_vbm.pm 


# THIS CODE WILL PROBABLY NOT BE USED--no need for intermediate application of affine transform!
# Check to make sure that there is no other work being done here (or variables being set) before removing from pipeline.




my $PM = "apply_affine_reg_to_atlas_vbm.pm";
my $VERSION = "2014/11/20";
my $NAME = "Apply bulk rigid/affine registration to a specified atlas";
my $DESC = "ants";

use strict;
use warnings;
no warnings qw(uninitialized);

use vars qw($Hf $BADEXIT $GOODEXIT $test_mode $intermediate_affine $native_reference_space $permissions);
require Headfile;
require pipeline_utilities;

my $do_inverse_bool = 0; # Reset to 0...This is the opposite of how seg_pipe_mc handles it...be careful!
my ($atlas,$rigid_contrast,$moving_contrast, $runlist,$work_path,$current_path);
my ($xform_path,$xform_suffix,$domain_dir,$domain_path,$inputs_dir);
my (@array_of_runnos,@jobs,@files_to_create,@files_needed);
my (%go_hash);
my $go = 1;
my $job;
# my @parents = qw(create_affine_reg_to_atlas_vbm);
# my @children = qw(pairwise_reg_vbm reg_template_vbm);

# ------------------
sub apply_affine_reg_to_atlas_vbm {  # Main code
# ------------------

    if (! $intermediate_affine) {
       print "$PM: Skipped creation of intermediate images from affine registration to atlas step.\n";
       return(0);
    }

    apply_affine_reg_to_atlas_vbm_Runtime_check();

    foreach my $runno (@array_of_runnos) {
	my $to_xform_path=get_nii_from_inputs($inputs_dir,$runno,$moving_contrast);
	my $result_path = "${current_path}/${runno}_${moving_contrast}.nii";
	$go = $go_hash{$runno};
	$xform_path = "${current_path}/${runno}_${xform_suffix}";
	#get_target_path($runno,$rigid_contrast);

	($job) = apply_affine_transform($go,$to_xform_path, $result_path,$do_inverse_bool,$xform_path, $domain_path,'','',$PM,$native_reference_space);

	if ($job > 1) {
	    push(@jobs,$job);
	}
    }

    if (cluster_check() && ($jobs[0] ne '')) {
	my $interval = 2;
	my $verbose = 1;
	my $done_waiting = cluster_wait_for_jobs($interval,$verbose,@jobs);

	if ($done_waiting) {
	    print STDOUT  "  All apply affine registration jobs have completed; moving on to next step.\n";
	}
    }
}



# ------------------
sub apply_affine_Output_check {
# ------------------
    my ($case) = @_;
    my $message_prefix ='';

# check for output files
    my $full_file;
    my @file_array=();
    if ($case == 1) {
	$message_prefix = "  Rigidly transformed ${moving_contrast} image(s) already exist for the following runno(s) and will not be recalculated:\n";
    } elsif ($case == 2) {
	$message_prefix = "  Unable to create transformed ${moving_contrast} image(s) for the following runno(s):\n";
    }   # For Init_check, we could just add the appropriate cases.


    my $existing_files_message = '';
    my $missing_files_message = '';

    foreach my $runno (@array_of_runnos) {
	$full_file = "${current_path}/${runno}_${moving_contrast}.nii";
	if (data_double_check($full_file)) {
	   $go_hash{$runno}=1;
	   # push(@files_to_create,$full_file); # This code may be activated for use with Init_check and generating lists of work to be done.
	    push(@file_array,$full_file);
	    $missing_files_message = $missing_files_message."   $runno \n";
	} else {
	    $go_hash{$runno}=0;
	    $existing_files_message = $existing_files_message."   $runno \n";
	}
    }
    my $error_msg='';

    if (($existing_files_message ne '') && ($case == 1)) {
	$error_msg =  "$PM:\n${message_prefix}${existing_files_message}";
    } elsif (($missing_files_message ne '') && ($case == 2)) {
	$error_msg =  "$PM:\n${message_prefix}${missing_files_message}";
    }

    my $file_array_ref = \@file_array;
    return($file_array_ref,$error_msg);
}

# ------------------
sub apply_affine_Input_check {
# ------------------

    return('');

}


# ------------------
sub apply_affine_reg_to_atlas_vbm_Init_check {
# ------------------
    if (! $intermediate_affine) {
	return('');
    }
    #return("$PM:\nYour mom is only a test.\n");
    return('');
}

# ------------------
sub apply_affine_reg_to_atlas_vbm_Runtime_check {
# ------------------

# Set up work
    $moving_contrast = $Hf->get_value('mdt_contrast'); #  Will modify to pull in arbitrary contrast, since will reuse this code for all contrasts, not just mdt contrast.
    $rigid_contrast = $Hf->get_value('rigid_contrast');
    $domain_path =$Hf->get_value('rigid_atlas_path');
    $inputs_dir = $Hf->get_value('inputs_dir');
    $work_path = $Hf->get_value('dir_work');
    $current_path = $Hf->get_value('rigid_work_dir');
    if ($current_path eq 'NO_KEY') {
	$current_path = "${work_path}/${rigid_contrast}";
	$Hf->set_value('rigid_work_dir',$current_path);
	if (! -e $current_path) {
	    mkdir ($current_path,$permissions);
	}
    }
    $runlist = $Hf->get_value('complete_comma_list');
    @array_of_runnos = split(',',$runlist);


    $xform_suffix =  $Hf->get_value('rigid_transform_suffix');


# check for output files

    my ($to_create_array_ref,$skip_message) = apply_affine_Output_check(1);

    if ($skip_message ne '') {
	print "${skip_message}";
    }

# check for needed input files to produce output files which need to be produced in this step

    # apply_affine_Input_check($to_create_array_ref);

    # my $missing_files_message_prefix = " Unable to locate input images for the following runno(s):\n";
    # my $missing_files_message = '';
    # my $missing_files_message_postfix = " Process stopped during $PM. Please check input runnos and try again.\n";
    # foreach my $runno (@array_of_runnos) {
    # 	opendir(DIR, $inputs_dir);
    # 	if ($create_go{$runno}) {
    # 	    my @input_files = grep(/^$runno.*${rigid_contrast}/ ,readdir(DIR));
    # 	    if ($input_files[0] eq '') {
    # 		$missing_files_message = $missing_files_message."   $runno \n";
    # 	    }
    # 	}
    # }
    # if ($missing_files_message ne '') {
    # 	error_out("$PM:\n${missing_files_message_prefix}${missing_files_message}${missing_files_message_postfix}");
    # }
}

1;
