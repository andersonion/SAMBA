#!/usr/bin/env perl
# smooth_images_vbm.pm 
# Originally written by BJ Anderson, CIVM




my $PM = "smooth_images_vbm.pm";
my $VERSION = "2015/08/06";
my $NAME = "Smooth all images in a directory and/or list of files.";
my $DESC = "ants";

use strict;
use warnings;
#no warnings qw(uninitialized bareword);

#use vars used to be here
require Headfile;
require pipeline_utilities;

if (! defined $valid_formats_string) {$valid_formats_string = 'hdr|img|nii';}

if (! defined $dims) {$dims = 3;}

my ($runlist,$work_path,$current_path,$write_path_for_Hf);
my (@array_of_runnos,@files_to_check,@files_to_process);
my @jobs=();
my ($smoothing_parameter,$smoothing_radius,$destination_directory,$suffix,@input_files_or_directories);
my $job;
my $go = 1;
my ($log_msg);
my $mem_request;
my @channel_array;  ##IN PROGRESS--ONLY SMOOTH CONTRASTS IN CHANNEL ARRAY
# ------------------
sub smooth_images_vbm {  # Main code
# ------------------
    ($smoothing_parameter,$destination_directory,$suffix,@input_files_or_directories) = @_;
    my $start_time = time;
    smooth_images_vbm_Runtime_check();

    if (! defined $nodes) {$nodes = 2;}

    my $coeff = 2;
    my $total_files = $#files_to_process + 1;  

    my $batch_size = int(int($total_files/$nodes + 0.99999)/$coeff + 0.999999);

    my $num_batches;
    if ($total_files) {
	$num_batches = int($total_files/$batch_size+0.999999);
	$mem_request = memory_estimator($num_batches,$nodes); 
    } else {
	$num_batches = 0;
    }

    print "Total files = ${total_files}\nNodes = $nodes\nBatch size = ${batch_size}\n";

    my $count_up = 0;
    my $count_down = $total_files;

    my $batch_number = 1;
    my @current_file_list;

    foreach my $in_file (@files_to_process) {
	$count_up++;
	$count_down--;
	push(@current_file_list,$in_file);
	
	if (($count_up == $batch_size) || (! $count_down)) {
	    ($job) = smooth_images($smoothing_parameter,$suffix,$destination_directory,$batch_number,@current_file_list);
	    
	    if ($job) {
		    push(@jobs,$job);
	    } 
	    $count_up = 0;
	    @current_file_list = ();
	    $batch_number++;
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

    my $real_time = vbm_write_stats_for_pm($PM,$Hf,$start_time,@jobs);
    print "$PM took ${real_time} seconds to complete.\n";
    
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
		foreach my $current_file (@files_in_dir) {
		    my $full_file = $file_or_directory.'/'.$current_file;
		    push (@files_to_check,$full_file);
		}		
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
	my ($file_path,$file_name,$file_ext) = fileparts($input_file,2);
#	if ($file_path =~ s/(\.[A-Za-z0-9]*)$//) {
#	    $file_ext = $1.$file_ext;
#	}


	# BJA 25 September 2019: Updated surfstat_exec to read directly from nii.gz, will try to store on disk as nii.gz instead of .gz
	# It is surmised that if the load_niigz code fails, surfstat will try to gunzip the files so it can still read the files;
	# but this will leave them in the gunzipped state on the disk indefinitely;
	# We are quashing the auto gunzip code below...

	#if ($file_ext =~ s/\.gz//) {}#Do Nothing More
	
	$out_file = "${destination_directory}/${file_name}_${suffix}${file_ext}";

	#if (($case == 2) && (! data_double_check($out_file.'.gz'))) {
	#    `gunzip ${out_file}.gz`;  # We expect that smoothed files will need to be decompressed for VBM analysis (our primary use).
	#}
	
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
sub smooth_images {
# ------------------
    my ($smoothing_param,$suffix,$out_directory,$batch_number,@in_files) = @_;

    my $cmd;
    
    my $mm_not_voxels = 0;
    my $units = 'vox';
    
    # Strip off units and white space (if any).
    if ($smoothing_param =~ s/[\s]*(vox|voxel|voxels|mm)$//) {
	$units = $1;
	if ($units eq 'mm') {	
	    ${mm_not_voxels} = 1;
	}
    }
    
    my $last_in_file;
    foreach my $in_file (@in_files) {
	my ($file_path,$file_name,$file_ext) = fileparts($in_file,2);
#	if ($file_path =~ s/(\.[A-Za-z0-9]*)$//) {
#	    $file_ext = $1.$file_ext;
#	}

	
	# BJA 25 September 2019: Updated surfstat_exec to read directly from nii.gz, will try to store on disk as nii.gz instead of .gz
	# It is surmised that if the load_niigz code fails, surfstat will try to gunzip the files so it can still read the files;
	# but this will leave them in the gunzipped state on the disk indefinitely;
	#if ($file_ext =~ s/\.gz$//) {}

	my $out_file = "${destination_directory}/${file_name}_${suffix}${file_ext}";
	
	$cmd = $cmd."SmoothImage ${dims} ${in_file} ${smoothing_param} ${out_file} ${mm_not_voxels} ;\n";
	$last_in_file = $in_file;
    }
    
    my $go_message =  "$PM: Smoothing images with sigma=${smoothing_param} ${units}: ${out_directory}";
    my $stop_message = "$PM:  Unable to smooth image with sigma=${smoothing_param} ${units} :\n${cmd}\n";

    my @test=(0);
    if (defined $reservation) {
	@test =(0,$reservation);
    }

    my $jid = 0;
    if (cluster_check) {
	my $home_path = $out_directory;
	my $Id= "smooth_image_with_sigma_${smoothing_param}${units}_${batch_number}";
	my $verbose = 2; # Will print log only for work done.
	$jid = cluster_exec($go, $go_message, $cmd ,$home_path,$Id,$verbose,$mem_request,@test);     
	if (not $jid) {
	    error_out($stop_message);
	}
    } else {
	my @cmds = split("\n",$cmd);
	if (! execute($go, $go_message, @cmds) ) {
	    error_out($stop_message);
	}
    }

    if ((!-e $last_in_file) && (not $jid)) {
	error_out("$PM: missing smoothed image: ${last_in_file} (and probably others from the same batch)");
    }
    print "** $PM expected output: ${last_in_file}\n";
  
    return($jid);
 }


# ------------------
sub smooth_images_vbm_Init_check {
# ------------------
    my $init_error_msg='';
    my $message_prefix="$PM initialization check:\n";

    my $vba_contrast_comma_list = $Hf->get_value('vba_contrast_comma_list');
	if ($vba_contrast_comma_list eq 'NO_KEY') { ## Should this go in init_check? # New feature to allow limited VBA/VBM analysis, 
	    # used for reproccessing corrected Jacobians (07 Dec 2015);
	    $vba_contrast_comma_list = $Hf->get_value('channel_comma_list');
	}
   @channel_array = split(',',$vba_contrast_comma_list);
   
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
