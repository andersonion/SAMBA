#!/usr/local/pipeline-%link/perl
# smooth_images_vbm.pm 
# Originally written by BJ Anderson, CIVM




my $PM = "smooth_images_vbm.pm";
my $VERSION = "2015/08/06";
my $NAME = "Smooth all images in a directory and/or list of files.";
my $DESC = "ants";

use strict;
use warnings;
no warnings qw(uninitialized bareword);

use vars qw($Hf $BADEXIT $GOODEXIT  $permissions $valid_formats_string $dims);
require Headfile;
require pipeline_utilities;

if (! defined $valid_formats_string) {$valid_formats_string = 'hdr|img|nii';}

if (! defined $dims) {$dims = 3;}

my ($runlist,$work_path,$current_path,$write_path_for_Hf);
my (@array_of_runnos,@jobs,@files_to_check,@files_to_process);
my ($smoothing_parameter,$smoothing_radius,$destination_directory,$suffix,@input_files_or_directories);
my $job;
my $go = 1;
my ($log_msg);
my ($current_contrast,$group,$gid);


# ------------------
sub smooth_images_vbm {  # Main code
# ------------------
    ($smoothing_parameter,$destination_directory,$suffix,@input_files_or_directories) = @_;

    smooth_images_vbm_Runtime_check();

    foreach my $in_file (@files_to_process) {
	my ($file_name,$file_path,$file_ext) = fileparts($in_file);
	my $out_file = "${destination_directory}/${file_name}_${suffix}.${file_ext}";
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

    my $case = 2;
    my ($dummy,$error_message)=smooth_images_Output_check($case);

    if ($error_message ne '') {
	error_out("${error_message}",0);
    } else {
	my $write_path_for_Hf = "${destination_directory}/smoothing_temp.headfile";
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
	
	if (($case == 1) && (data_double_check($out_file.'.gz'))) {
	    `gunzip ${out_file}.gz`;  # We expect that smoothed files will need to be decompressed for VBM analysis (our primary use).
	}
	
	if (data_double_check($out_file)) {
	    push(@files_to_process,$input_file);
	    push(@file_array,$out_file);
	    $missing_files_message = $missing_files_message."\t${out_file}\n";
	} else {
	    $existing_files_message = $existing_files_message."\t${out_file}\n";
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


# ------------------
sub smooth_image {
# ------------------
    my ($smoothing_param,$out_file,$in_file) = @_;
    my $mm_not_voxels = 0;
    my $units = 'voxels';
    my ($file_name,$file_path,$file_ext) = fileparts($in_file);

    # Strip off units and white space (if any).
    if ($smoothing_param =~ s/[\s]*(vox|voxel|voxels|mm)$//) {
	$units = $1;
	if ($units eq 'mm') {	
	    ${mm_not_voxels} = 1;
	}
    }

    my $cmd = "SmoothImage ${dims} ${in_file} ${smoothing_param} ${out_file} ${mm_not_voxels} ;\n";

    my $go_message =  "$PM: Smooth image with sigma=${smoothing_param} ${units}: ${file_name}";
    my $stop_message = "$PM:  Unable to smooth image with sigma=${smoothing_param} ${units}: ${file_name} :\n${cmd}\n";

    my $jid = 0;
    if (cluster_check) {
	my $home_path = $current_path;
	my $Id= "smooth_image_with_sigma_${smoothing_param}_${units}_${file_name}";
	my $verbose = 2; # Will print log only for work done.
	$jid = cluster_exec($go, $go_message, $cmd ,$home_path,$Id,$verbose);     
	if (! $jid) {
	    error_out($stop_message);
	}
    } else {
	my @cmds = ($cmd);
	if (! execute($go, $go_message, @cmds) ) {
	    error_out($stop_message);
	}
    }

    if ((!-e $out_file) && ($jid == 0)) {
	error_out("$PM: missing smoothed image: ${out_file}");
    }
    print "** $PM created ${out_file}\n";
  
    return($jid,$out_file);
 }


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
    my ($dummy,$skip_message)=smooth_images_Output_check($case);

    if ($skip_message ne '') {
	print "${skip_message}";
    }

}

1;
