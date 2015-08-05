#!/usr/local/pipeline-%link/perl
# smooth_images_vbm.pm 
# Originally written by BJ Anderson, CIVM




my $PM = "smooth_images_vbm.pm";
my $VERSION = "2015/06/24";
my $NAME = "Smooth all contrasts in preparation for VBM.";
my $DESC = "ants";

use strict;
use warnings;
no warnings qw(uninitialized bareword);

use vars qw($Hf $BADEXIT $GOODEXIT  $permissions $valid_formats_string);
require Headfile;
require pipeline_utilities;

if (! defined $valid_formats_string) {$valid_formats_string = 'hdr|img|nii';}

# my ($runlist,$work_path,$current_path,$write_path_for_Hf);
my (@array_of_runnos,@jobs,@files_to_check,@files_to_process);
my ($smoothing_parameter,$destination_directory,$suffix,@input_files_or_directories);
my $job;

my ($current_contrast,$group,$gid);


# ------------------
sub smooth_images_vbm {  # Main code
# ------------------
    ($smoothing_parameter,$destination_directory,$suffix,@input_files_or_directories) = @_;

    smooth_images_vbm_Runtime_check();

    foreach my $in_file (@files_to_process) {
	my ($file_name,$file_path,$file_ext) = fileparts($in_file);
	$out_file = "${destination_directory}/${file_name}_${suffix}.${file_ext}";
	($job) = smooth_image($smoothing_parameter,$out_file,$in_file);
	
	if ($job > 1) {
	    push(@jobs,$job);
	} 
    }
    
    my $done_waiting = 1;
    if (cluster_check()) {
 	my $interval = 1;
 	my $verbose = 1;
 	$done_waiting = cluster_wait_for_jobs($interval,$verbose,@jobs);
     }
    if ($done_waiting) {
	print STDOUT  "  Smoothing specified images complete; moving on to next step.\n";
    }
}
    my $case = 2;
    my ($dummy,$error_message)=smooth_images_Output_check($case,$direction);

    if ($error_message ne '') {
	error_out("${error_message}",0);
    } else {
	my $write_path_for_Hf = "${destination_directory}/${predictor_id}_temp.headfile";
 	return($write_path_for_Hf);
    }
 
 }



# ------------------
sub smooth_images_Output_check {
# ------------------
    my ($case) = @_;
    my $message_prefix ='';
    my $out_file;
    my @nonexistent_files;
    
    if ($case == 1){    
	foreach my $file_or_directory (@input_files_or_directories) {
	    if (-d $file_or_directory) {
		opendir(DIR, $file_or_directory);
		my @files_in_dir = grep(/(\.${valid_formats_string})+(\.gz)*$/ ,readdir(DIR));# @input_files;
		push (@files_to_check,@files_in_dir);		
	    } elsif (-e $file_or_directory) {
		push(@files_to_check,$file_or_directory);
	    } else {
		push(@nonexistent_files ,$file_or_directory);
	    }
	}
    }

     my @file_array=();
     if ($case == 1) {
  	$message_prefix = "  The following files have already been smoothed and will not be resmoothed:\n";
     } elsif ($case == 2) {
 	$message_prefix = "  Unable to smooth the following files:\n";
     }  
    
    my $existing_files_message = '';
    my $missing_files_message = '';
    
    foreach my $input_file (@files_to_check) {
	my ($file_name,$file_path,$file_ext) = fileparts($input_file);
	$out_file = "${destination_directory}/${file_name}_${suffix}.${file_ext}";

	if ($case == 1) && (data_double_check($out_file.'.gz')) {
	    `gunzip ${out_file}.gz`;  # We expect that smoothed files will need to be decompressed for VBM analysis (our primary use).
	}

	 if (data_double_check($out_file)) {
	     push(@files_to_process,$input_file);
	     push(@file_array,$out_file);
	     $missing_files_message = $missing_files_message."\t${output_file}\n";
	 } else {
	     $existing_files_message = $existing_files_message."\t${output_file}\n";
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

# # # ------------------
# # sub smooth_images_Input_check {
# # # ------------------

# # }


# # ------------------
# sub smooth_images {
# # ------------------
#     my ($runno,$direction) = @_;
#     my ($cmd,$input_warp);
#     my ($jac_command,$unzip_command);
#     my $out_file = '';
#     my $space_string = '';

#     if ($direction eq 'f') {
# 	$out_file = "${current_path}/${runno}_jac_to_MDT.nii"; # Need to settle on exact file name format...
# 	$space_string = 'individual_image';
# 	$input_warp = "${diffeo_path}/${runno}_to_MDT_warp.nii";
#     } else {
# 	$out_file = "${current_path}/${runno}_jac_from_MDT.nii"; # I don't think this will be the proper implementation of the "inverse" option.
# 	$space_string = 'MDT';
# 	$input_warp = "${diffeo_path}/MDT_to_${runno}_warp.nii";
#     }
#     $jac_command = "CreateJacobianDeterminantImage 3 ${input_warp} ${out_file} 1 1 ;\n";
#     $unzip_command = "ImageMath 3 ${out_file} m ${out_file} ${mask_path};\n";

# #    $jac_command = "ANTSJacobian 3 ${input_warp} ${out_file} 1 ${mask_path} 1;\n"; # Older ANTS command
# #    $unzip_command = "gunzip -c ${out_file}logjacobian.nii.gz > ${out_file}.nii;\n";  

#     $cmd=$jac_command.$unzip_command;
#     my $go_message =  "$PM: calculate jacobian images in ${space_string} for ${runno}";
#     my $stop_message = "$PM:  calculate jacobian images in ${space_string} for ${runno}:\n${cmd}\n";

#     my $jid = 0;
#     if (cluster_check) {
# 	my $home_path = $current_path;
# 	my $Id= "${runno}_calculate_jacobian_in_${space_string}_space";
# 	my $verbose = 2; # Will print log only for work done.
# 	$jid = cluster_exec($go, $go_message, $cmd ,$home_path,$Id,$verbose);     
# 	if (! $jid) {
# 	    error_out($stop_message);
# 	}
#     } else {
# 	my @cmds = ($jac_command,$unzip_command);
# 	if (! execute($go, $go_message, @cmds) ) {
# 	    error_out($stop_message);
# 	}
#     }

#     if ((!-e $out_file) && ($jid == 0)) {
# 	error_out("$PM: missing jacobian image in ${space_string} space for ${runno}: ${out_file}");
#     }
#     print "** $PM created ${out_file}.nii\n";
  
#     return($jid,$out_file);
#  }


# ------------------
sub smooth_images_vbm_Init_check {
# ------------------
    my $init_error_msg='';
    my $message_prefix="$PM initialization check:\n";
   
    $smoothing_radius=$Hf->get_value('preVBM_smoothing_radius');
    if (($smoothing_radius eq 'NO_KEY') || (! defined $smoothing_radius))  {
	$smoothing_radius=3;
	$Hf->set_value('preVBM_smoothing_radius',$smoothing_radius);
    }

    if ($log_msg ne '') {
	log_info("${message_prefix}${log_msg}");
    }

    if ($init_error_msg ne '') {
	$init_error_msg = $message_prefix.$init_error_msg;
    }

    return($init_error_msg);

}


# ------------------
sub smooth_images_vbm_Runtime_check {
# ------------------

    if (! -e $destination_directory) {
 	mkdir ($destination_directory,$permissions);
    }

    my $case = 1;
    my ($dummy,$skip_message)=smooth_images_Output_check($case,$direction);

    if ($skip_message ne '') {
	print "${skip_message}";
    }

}

1;
