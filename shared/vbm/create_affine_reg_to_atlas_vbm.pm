#!/usr/local/pipeline-link/perl
# create_affine_reg_to_atlas_vbm.pm 





my $PM = "create_affine_reg_to_atlas_vbm.pm";
my $VERSION = "2014/11/25";
my $NAME = "Create bulk rigid/affine registration to a specified atlas";
my $DESC = "ants";
my $ggo = 1;  # Needed for compatability with seg_pipe code

use strict;
use warnings;
no warnings qw(uninitialized bareword);

use vars qw($Hf $BADEXIT $GOODEXIT $test_mode);
require Headfile;
require pipeline_utilities;

my ($atlas,$contrast, $runlist,$work_path,$current_path);
my ($xform_code,$xform_path,$xform_suffix,$domain_dir,$domain_path,$inputs_dir);
my (@array_of_runnos,@jobs);
my (%go_hash,%create_output);
my $go = 1;
my $job;

my $ants_affine_suffix = "0GenericAffine.mat";

# ------------------
sub create_affine_reg_to_atlas_vbm {  # Main code
# ------------------

    create_affine_reg_to_atlas_vbm_Runtime_check();
    foreach my $runno (@array_of_runnos) {
	my $to_xform_path=get_nii_from_inputs($inputs_dir,$runno,$contrast);
	my $result_path_base = "${current_path}/${runno}_";
	$go = $go_hash{$runno};

	$xform_suffix =  $Hf->get_value('rigid_transform_suffix');
	my $pipeline_name = $result_path_base.$xform_suffix;
	#get_target_path($runno,$contrast);

	if ($go) {
	    ($xform_path,$job) = create_affine_transform($go,$xform_code, $domain_path, $to_xform_path,  $result_path_base, '',$PM); # We are setting atlas as fixed and current runno as moving...this is opposite of what happens in seg_pipe_mc, when you are essential passing around the INVERSE of that registration to atlas step, but accounting for it by setting "-i 1" with $do_inverse_bool.
	    
	    if ($job > 1) {
		push(@jobs,$job);
	    }
	    `ln -s ${xform_path}  ${pipeline_name}`;
	}
	
	headfile_list_handler($Hf,"forward_xforms_${runno}","${pipeline_name}",0);
	headfile_list_handler($Hf,"inverse_xforms_${runno}","-i ${pipeline_name}",1);


	# open (FILEHANDLE, $xform_path) or die $!; # Need to figure out best way to calculate inverses of affine transforms.
	# my $string = do { local $/; <FILEHANDLE> };
	# my $fun = unpack('H',*$string);
	# print "Contents of ${xform_path} is:\n$fun}\n";

    }

    if (cluster_check() && ($#jobs != -1)) {
	my $interval = 2;
	my $verbose = 1;
	my $done_waiting = cluster_wait_for_jobs($interval,$verbose,@jobs);

	if ($done_waiting) {
	    print STDOUT  "  All rigid registration jobs have completed; moving on to next step.\n";
	}
    }


    # opendir(DIR,$current_path);
    # my @files_to_rename = grep( m/.*${ants_affine_suffix}/ ,readdir(DIR));

    # foreach my $file (@files_to_rename) {
    # 	my $full_file = $current_path.'/'.$file;
    # 	$full_file =~ /(.*)${ants_affine_suffix}$/;
    # 	print " full_file = ${full_file}\n";
    # 	my $new_file = $1.${xform_suffix};
    # 	print " new_file = ${new_file}\n";
    # 	rename($full_file,$new_file);

    # }

    my $case = 2;
    my ($dummy,$error_message)=create_affine_reg_to_atlas_Output_check($case);

    if ($error_message ne '') {
	error_out("${error_message}",0);
    }


}


# ------------------
sub create_affine_reg_to_atlas_Output_check {
# ------------------
     my ($case) = @_;
     my $message_prefix ='';
     my ($full_file_1);
     my @file_array=();
     if ($case == 1) {
  	$message_prefix = "  Rigid registration to atlas transforms already exist for the following runno(s) and will not be recalculated:\n";
     } elsif ($case == 2) {
 	$message_prefix = "  Unable to rigidly register the following runno(s) to atlas:\n";
     }   # For Init_check, we could just add the appropriate cases.


     my $existing_files_message = '';
     my $missing_files_message = '';
 
     
     foreach my $runno (@array_of_runnos) {
	 $full_file_1 = "${current_path}/${runno}_${xform_suffix}";
	 if (! -e $full_file_1 ) {
	     $go_hash{$runno}=1;
	     push(@file_array,$full_file_1);
	     #push(@files_to_create,$full_file); # This code may be activated for use with Init_check and generating lists of work to be done.
	     $missing_files_message = $missing_files_message."   $runno \n";
	 } else {
	     $go_hash{$runno}=0;
	     $existing_files_message = $existing_files_message."   $runno \n";
	 }
     }
     if (($existing_files_message ne '') && ($case == 1)) {
	 $existing_files_message = $existing_files_message."\n";
     } elsif (($missing_files_message ne '') && ($case == 2)) {
	 $missing_files_message = $missing_files_message."\n";
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
sub create_affine_reg_to_atlas_vbm_Init_check {
# ------------------
    my $init_error_msg='';
    my $message_prefix="$PM:\n";

# check for valid atlas
    $atlas = $Hf->get_value('atlas_name');
    $contrast = $Hf->get_value('rigid_contrast');
 
    $domain_dir   = $Hf->get_value ('rigid_atlas_dir');   
    $domain_path  = "$domain_dir/${atlas}_${contrast}.nii"; 
    if (!-e $domain_path)  {
	$init_error_msg = $init_error_msg."For rigid contrast ${contrast}: missing domain nifti file ${domain_path}\n";
    } else {
	$Hf->set_value('rigid_atlas_path',$domain_path);
    }


    $inputs_dir = $Hf->get_value('inputs_dir');
    if ($init_error_msg ne '') {
	$init_error_msg = $message_prefix.$init_error_msg;
    }
    return($init_error_msg);
}

# ------------------
sub create_affine_reg_to_atlas_vbm_Runtime_check {
# ------------------

# Set up work
    $work_path = $Hf->get_value('dir_work');
    $current_path = $Hf->get_value('rigid_work_dir');

    if ($current_path eq 'NO_KEY') {
	$current_path = "${work_path}/${contrast}";
	$Hf->set_value('rigid_work_dir',$current_path);
	if (! -e $current_path) {
	    mkdir ($current_path,0777);
	}
    }

    $runlist = $Hf->get_value('complete_comma_list');
    @array_of_runnos = split(',',$runlist);


    $xform_code = 'rigid1';
    $xform_suffix = $Hf->get_value('rigid_transform_suffix');
   
    my $case = 1;
    my ($dummy,$skip_message)=create_affine_reg_to_atlas_Output_check($case);

    if ($skip_message ne '') {
	print "${skip_message}";
    }

# check for output files
#     my $full_file;
#     my $existing_files_message_prefix = "  Rigid transform(s) already exist for the following runno(s) and will not be recalculated:\n";
#     my $existing_files_message = '';
#     foreach my $runno (@array_of_runnos) {
# 	if ($xform_suffix ne 'NO_KEY') {
# 	    $full_file = "${current_path}/${runno}_${xform_suffix}";
# 	    if (! -e  $full_file) {
# 		$create_go{$runno}=1;
# 	#	$create_output{$runno} = $full_file; # Don't think this is really useful...
# 	    } else {
# 		$create_go{$runno}=0;
# 		$existing_files_message = $existing_files_message."   $runno \n";
# 	    }
# 	} else {
# 	    $create_go{$runno} = 1;
# 	}
#     }
#     if ($existing_files_message ne '') {
# 	print STDOUT "$PM\n${existing_files_message_prefix}${existing_files_message}";
#     }
# # check for needed input files to produce output files which need to be produced in this step

#     my $missing_files_message_prefix = " Unable to locate input images for the following runno(s):\n";
#     my $missing_files_message = '';
#     my $missing_files_message_postfix = " Process stopped during $PM. Please check input runnos and try again.\n";
#     foreach my $runno (@array_of_runnos) {
# 	if ($create_go{$runno}) {
# 	    my $file_path = get_nii_from_inputs($inputs_dir,$runno,$contrast);
# 	    if ($file_path eq '0') {
# 		$missing_files_message = $missing_files_message."   $runno \n";
# 	    }
# 	}
#     }
#     if ($missing_files_message ne '') {
# 	error_out("$PM:\n${missing_files_message_prefix}${missing_files_message}${missing_files_message_postfix}",0);
#     }
}
1;
