#!/usr/local/pipeline-link/perl

# convert_all_to_nifti_vbm.pm 

# modified 2014/12/12 BJ Anderson for use in VBM pipeline.
# Based on convert_all_to_nifti.pm, as implemented by seg_pipe_mc
# modified 20130730 james cook, renamed flip_y to flip_x to be more accurate.
# modified 2012/04/27 james cook. Tried to make this generic will special handling for dti from archive cases.
# calls nifti code that can get dims from header
# created 2010/11/02 Sally Gewalt CIVM

my $PM = "convert_all_to_nifti_vbm.pm";
my $VERSION = "2014/12/16";
my $NAME = "Convert input data into the proper format, flipping x and/or z if need be.";

use strict;
use warnings;
no warnings qw(uninitialized bareword);

use vars qw($Hf $BADEXIT $GOODEXIT $test_mode $permissions $civm_ecosystem);
require Headfile;
require pipeline_utilities;
require pull_civm_tensor_data;
#require convert_to_nifti_util;


my ($current_path, $work_dir,$runlist,$ch_runlist,$in_folder,$out_folder,$flip_x,$flip_z,$do_mask);
my (@array_of_runnos,@channel_array);
my (%go_hash,%go_mask,%mask_hash);
my $skip=0;
my $log_msg='';
my (@jobs);
my ($dummy,$error_message);


my $working_image_orientation;
my $matlab_path = "/cm/shared/apps/MATLAB/R2015b/";
#my $img_transform_executable_path = "/glusterspace/BJ/img_transform_executable/AE/run_img_transform_exe.sh";
my $img_transform_executable_path ="/cm/shared/workstation_code_dev/matlab_execs/img_transform_executable/20170403_1100/run_img_transform_exe.sh";

# ------------------
sub convert_all_to_nifti_vbm {
# ------------------
# convert the source image volumes used in this SOP to nifti format (.nii)
# could use image name (suffix) to figure out datatype
    ($skip) = @_;
    if ($skip eq '') {$skip = 0;}
    my $start_time = time;
    my $run_again = 1;  
    my $second_run=0;  
    while ($run_again) {
	convert_all_to_nifti_vbm_Runtime_check();

	my @nii_cmds;
	my @nii_files;


	foreach my $runno (@array_of_runnos) {
	    foreach my $ch (@channel_array) {
		my $go = $go_hash{$runno}{$ch};
		if ($go) {
		    my $job;
		    my $current_file=get_nii_from_inputs($in_folder,$runno,$ch);
		    my $Hf_key = "original_orientation_${runno}";
		    #my $Hf_key = "original_orientation_${runno}_${ch}";# May need to evolve to where each image is checked for proper orientation.
		    my $current_orientation= $Hf->get_value($Hf_key);# Insert orientation finder function here? No, want to out-source, I think.
		    if ($current_orientation eq 'NO_KEY') {
			$Hf_key = "original_study_orientation";
			$current_orientation= $Hf->get_value($Hf_key);
			if ($current_orientation eq 'NO_KEY') {
			    if ((defined $flip_x) || ($flip_z)) { # Going to assume that these archaic notions will come in pairs.
				if (($flip_x) && ($flip_z)) {
				    $current_orientation = 'PLI';
				} elsif ($flip_x) {
				    $current_orientation = 'PRS';
				} elsif ($flip_z) {
				    $current_orientation = 'ARI';
				} else {
				    $current_orientation = 'ALS';
				}
			    } else {
				$current_orientation = 'ALS';
			    }
			}
		    } else {
			print "Using custom orientation for runno $runno: $current_orientation.\n\n";
		    }


		    if ($current_file =~ /[\n]+/) {
			print "Unable to find input image for $runno and $ch in folder: ${in_folder}.\n";
		    } else {
			# push(@nii_files,$current_file);
			my $please_recenter=1; # Currently, this is stuck "on", as we can't turn it off in our function.
			($job) =  set_center_and_orientation_vbm($current_file,$current_path,$current_orientation,$working_image_orientation,$please_recenter);
			if ($job) {
			    push(@jobs,$job);
			}
		    }
		}
	    }
	}
	# if ($nii_files[0] ne '') {
	# 	my $message="\n$PM:\nThe following files will be prepared by Matlab for the VBM pipeline:\n".
	# 	    join("\n",@nii_files)."\n\n";
	# 	print "$message";
	# }
	# foreach my $file (@nii_files) {
	# 	recenter_nii_function($file,$current_path,$skip,$Hf);
	# }
	

	if (cluster_check() && (@jobs)) {
	    my $interval = 2;
	    my $verbose = 1;
	    my $done_waiting = cluster_wait_for_jobs($interval,$verbose,@jobs);
	    
	    if ($done_waiting) {
		print STDOUT  " Reorienting and recentering for all input images is complete; moving on to next step.\n";
	    }
	}

	my $case = 2;
	($dummy,$error_message)=convert_all_to_nifti_Output_check($case);

	
	#my $real_time = write_stats_for_pm($PM,$Hf,$start_time); #moved outside of while loop.
	#print "$PM took ${real_time} seconds to complete.\n";

	if (($error_message eq '') || ($second_run)) {
	    $run_again = 0;
	} else {
	    if ($civm_ecosystem) {
		print STDOUT " Several jobs have failed, possibly because the input files were not in the right place.\nAttempting to automatically find inputs...\n";
		pull_civm_tensor_data();
		$second_run=1;
	    } else {
		error_out("${error_message}",0);
	    }
	}

    }

    my $real_time = write_stats_for_pm($PM,$Hf,$start_time);
    print "$PM took ${real_time} seconds to complete.\n";
    if ($error_message ne '') {
	error_out("${error_message}",0);
    } 
    # else { # Deprecated with advent of matlab executables. #BJA, 11 August 2017
    # # Clean up matlab junk
    # 	my $test_string = `ls ${work_dir} `;
    # 	if ($test_string =~ /.m$/) {
    # 	    `rm ${work_dir}/*.m`;
    # 	}
    # 	if ($test_string =~ /matlab/) {
    # 	    `rm ${work_dir}/*matlab*`;
    # 	}
    # }
}


# ------------------
sub convert_all_to_nifti_Output_check {
# ------------------

    my ($case) = @_;
    my $message_prefix ='';
    my ($file_1);
    my @file_array=();

    my $existing_files_message = '';
    my $missing_files_message = '';

    
    if ($case == 1) {
	$message_prefix = "  Prepared niftis have been found for the following runnos and will not be re-prepared:\n";
    } elsif ($case == 2) {
	 $message_prefix = "  Unable to properly prepare niftis for the following runnos and channels:\n";
    }   # For Init_check, we could just add the appropriate cases.
    
    foreach my $runno (@array_of_runnos) {
	my $sub_existing_files_message='';
	my $sub_missing_files_message='';
	foreach my $ch (@channel_array) {
	    $file_1 = get_nii_from_inputs($current_path,$runno,$ch);
	   # print "File_1 = ${file_1}\n\n";
	    my $unfounded =0;
	    if ($file_1 =~ /[\n]+/) {
		$file_1 = "${current_path}/${runno}_${ch}.nii";
		$unfounded = 1;
	    }
	    if ((data_double_check($file_1) && data_double_check($file_1.'.gz')) || ((! $pre_masked) && $unfounded &&  ($file_1 !~ /.*masked\.nii/))) { # 15 January 2016: Trying this instead, below fails for mixed masked/pre_masked (phantoms, for example).
	   # if ((data_double_check($file_1) ) || ((! $do_mask) &&  (($file_1 =~ /.*masked\.nii/) || ($file_1 =~ /.*masked\.nii\.gz/)))) { # 6 January 2016: updated to look for .nii.gz as well.
		$go_hash{$runno}{$ch}=1;
		push(@file_array,$file_1);
		$sub_missing_files_message = $sub_missing_files_message."\t$ch";
	    } else {
		$go_hash{$runno}{$ch}=0;
		$sub_existing_files_message = $sub_existing_files_message."\t$ch";
	    }
	}
	if (($sub_existing_files_message ne '') && ($case == 1)) {
	    $existing_files_message = $existing_files_message.$runno."\t".$sub_existing_files_message."\n";
	} elsif (($sub_missing_files_message ne '') && ($case == 2)) {
	    $missing_files_message =$missing_files_message. $runno."\t".$sub_missing_files_message."\n";
	}
    }
     
    my $error_msg='';
    
    if (($existing_files_message ne '') && ($case == 1)) {
	$error_msg =  "$PM:\n${message_prefix}${existing_files_message}\n";
    } elsif (($missing_files_message ne '') && ($case == 2)) {
	$error_msg =  "$PM:\n${message_prefix}${missing_files_message}\n";
    }
     
    my $file_array_ref = \@file_array;
    return($file_array_ref,$error_msg);
}

# ------------------
sub set_center_and_orientation_vbm {
# ------------------
    my ($input_file,$output_folder,$current_orientation,$desired_orientation,$recenter) = @_;
    if (! defined $recenter) {$recenter=1;} # Unused for now.

    if ($output_folder !~ /\/$/) {
	$output_folder=$output_folder.'/';
    }

    my $matlab_exec_args='';

    my $jid = 0;
    my ($go_message, $stop_message);

#    if ($current_orientation eq $desired_orientation) {
    # Hope to have a function that easily and quickly diddles with the header to recenter it...may incorporate into matlab exec instead, though.
#    } else {
	$matlab_exec_args="${input_file} ${current_orientation} ${desired_orientation} ${output_folder}";
	$go_message = "$PM: Reorienting from ${current_orientation} to ${desired_orientation}, and recentering image: ${input_file}\n" ;
	$stop_message = "$PM: Failed to properly reorientate to ${desired_orientation} and recenter file: ${input_file}\n" ;
#    }
    my @test=(0);
    if (defined $reservation) {
	@test =(0,$reservation);
    }
    my $mem_request = '40000'; # Should test to get an idea of actual mem usage.

    if (cluster_check) {
	my $go =1;	    
#	my $cmd = $pairwise_cmd.$rename_cmd;
	my $cmd = "${img_transform_executable_path} ${matlab_path} ${matlab_exec_args}";
	
	my $home_path = $current_path;
	my $Id= "recentering_and_setting_image_orientation_to_${desired_orientation}";
	my $verbose = 2; # Will print log only for work done.
	$jid = cluster_exec($go,$go_message , $cmd ,$home_path,$Id,$verbose,$mem_request,@test);     
	if (not $jid) {
	    error_out($stop_message);
	}
    }

    return($jid);
}


# ------------------
sub convert_all_to_nifti_vbm_Init_check {
# ------------------

    my $init_error_msg='';
    my $message_prefix="$PM initialization check:\n";

    my $optional_runno_string;
    my $orientation_type = 'working_image_orientation';
    my $orientation_error_msg_prefix="I'm sorry, but an invalid ${orientation_type} has been requested${optional_runno_string}: ";    
    my $orientation_error_msg_suffix=".\n\tOrientation must be allcaps and contain 3 of the following letters: A or P, L or R, S or I.\n"; 
    my $desired_orientation = $Hf->get_value($orientation_type);
    my $da = $desired_orientation;
    my $error_flag=0;
    if ($da  eq 'NO_KEY') {
	$da = 'ALS'; # This will soon change to RAS as the default, 'ALS' is historically what we've used.
	$Hf->set_value($orientation_type,$da);
	$log_msg = $log_msg."\nNo ${orientation_type}${optional_runno_string} has been specified; using default orientation of ${da}. \n";   
    } elsif ($da =~ /[^ALSRPI]/ ) {
	$error_flag=1;
    } elsif (($da =~ /[A]/)&& ($da =~ /[P]/)) {
	$error_flag=1;
    } elsif (($da =~ /[I]/)&& ($da =~ /[S]/)) {
	$error_flag=1;
    } elsif (($da =~ /[L]/)&& ($da =~ /[R]/)) {
	$error_flag=1;
    } else {
	$Hf->set_value($orientation_type,$da);
	$log_msg = $log_msg."\nUsing ${da} for {orientation_type}${optional_runno_string}, as requested. \n";
    }

    if ($error_flag) {
	$init_error_msg=$init_error_msg.$orientation_error_msg_prefix.$da.$orientation_error_msg_suffix;
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
sub convert_all_to_nifti_vbm_Runtime_check {
# ------------------

# # Set up work
    $in_folder = $Hf->get_value('pristine_input_dir');
    $work_dir = $Hf->get_value('dir_work');
#    $work_dir = $Hf->get_value('preprocess_dir');
#   $current_path = $Hf->get_value('inputs_dir');
    $current_path = $Hf->get_value('preprocess_dir');

    $working_image_orientation = $Hf->get_value('working_image_orientation');
    my $original_study_orientation = $Hf->get_value('original_study_orientation');

    if ($original_study_orientation eq 'NO_KEY') {
	$flip_x = $Hf->get_value('flip_x'); # Will phase out soon...
	if ($flip_x eq 'NO_KEY') {
	    undef $flip_x;
	}
	$flip_z = $Hf->get_value('flip_z'); # Will phase out soon...
	if ($flip_z eq 'NO_KEY') {
	    undef $flip_z;
	}
    }

    $do_mask = $Hf->get_value('do_mask');

#    opendir(DIR,$in_folder) or die ("$PM: could not open project inputs folder!";
#    my @nii_files = grep(/\.nii$/,readdir(DIR));

    if ($current_path eq 'NO_KEY') {
#	$current_path = "${work_dir}/base_images";
	$current_path = "${work_dir}/preprocess";
# 	$Hf->set_value('inputs_dir',$current_path); 	
	$Hf->set_value('preprocess_dir',$current_path);
    }
    if (! -e $current_path) {
	mkdir ($current_path,$permissions);
    }

    $runlist = $Hf->get_value('complete_comma_list');

    if ($runlist eq 'EMPTY_VALUE') {
	@array_of_runnos = ();
    } else {
	@array_of_runnos = split(',',$runlist);
    }



 
    $ch_runlist = $Hf->get_value('channel_comma_list');
    @channel_array = split(',',$ch_runlist);

    my $case = 1;
    my ($dummy,$skip_message)=convert_all_to_nifti_Output_check($case);

    if ($skip_message ne '') {
	print "${skip_message}";
    }

    ($dummy,$skip_message)=convert_all_to_nifti_Output_check($case);
    if ($skip_message ne '') {
	print "${skip_message}";
    }
}


1;

