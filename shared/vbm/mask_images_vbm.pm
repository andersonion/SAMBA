#!/usr/local/pipeline-link/perl

# mask_images_vbm.pm 

# modified 2014/12/12 BJ Anderson for use in VBM pipeline.
# Based on convert_all_to_nifti.pm, as implemented by seg_pipe_mc
# modified 20130730 james cook, renamed flip_y to flip_x to be more accurate.
# modified 2012/04/27 james cook. Tried to make this generic will special handling for dti from archive cases.
# calls nifti code that can get dims from header
# created 2010/11/02 Sally Gewalt CIVM

my $PM = "mask_images_vbm.pm";
my $VERSION = "2014/12/12";
my $NAME = "Convert input data into the proper format, flipping x and/or z if need be.";

use strict;
use warnings;
no warnings qw(uninitialized bareword);

use vars qw($Hf $BADEXIT $GOODEXIT $test_mode);
require Headfile;
require pipeline_utilities;
#require convert_to_nifti_util;


my ($current_path, $work_dir,$runlist,$ch_runlist,$in_folder,$out_folder,$do_mask,$mask_dir,$template_contrast);
my ($mask_threshold, $num_morphs,$morph_radius,$dim_divisor, $status_display_level);
my (@array_of_runnos,@channel_array,@jobs);
my (%go_hash,%make_hash,%mask_hash);
my $go=1;


# ------------------
sub mask_images_vbm {
# ------------------

    mask_images_vbm_Runtime_check();

    my @nii_cmds;
    my @nii_files;


## Make masks for each runno using the template contrast (usually dwi).
    foreach my $runno (@array_of_runnos) {
	my $go = $make_hash{$runno};
	if ($go) {
	    my $current_file=get_nii_from_inputs($current_path,$runno,$template_contrast);
	    my ($name,$in_path,$ext) = fileparts($current_file);
	    my $mask_path     = "${mask_dir}/${runno}_${template_contrast}_mask\.nii";
	    $mask_hash{$runno} = $mask_path;
	    if (! -e $mask_path) {
		my $nifti_args ="\'$current_file\', $dim_divisor, $mask_threshold, \'$mask_path\',$num_morphs , $morph_radius,$status_display_level";
		my $nifti_command = make_matlab_command('strip_mask',$nifti_args,"${runno}_${template_contrast}_",$Hf,0); # 'center_nii'
		execute(1, "Creating mask for $runno using ${template_contrast} channel", $nifti_command);
	    }
	}
    }


## Apply masks to all imaages in each runno set.
    foreach my $runno (@array_of_runnos) {
	if ($make_hash{$runno}) {
	    foreach my $ch (@channel_array) {
		my $go = $go_hash{$runno}{$ch};
		if ($go) {
		    my ($job) = mask_one_image($runno,$ch);
		    if ($job > 1) {
			push(@jobs,$job);
		    }
		}
	    }
	}
    }

    if (cluster_check() && ($jobs[0] ne '')) {
	my $interval = 1;
	my $verbose = 1;
	my $done_waiting = cluster_wait_for_jobs($interval,$verbose,@jobs);

	if ($done_waiting) {
	    print STDOUT  "  All input images have been masked; moving on to next step.\n";
	}
    }
    my $case = 2;
    my ($dummy,$error_message)=mask_images_Output_check($case);

    if ($error_message ne '') {
	error_out("${error_message}",0);
    }

}


# ------------------
sub mask_images_Output_check {
# ------------------

    my ($case) = @_;
    my $message_prefix ='';
    my ($file_1);
    my @file_array=();

    my $existing_files_message = '';
    my $missing_files_message = '';

    
    if ($case == 1) {
	$message_prefix = "  Masked images have been found for the following runno(s) and will not be re-processed:\n";
    } elsif ($case == 2) {
	 $message_prefix = "  Unable to properly mask images for the following runno(s) and channel(s):\n";
    }   # For Init_check, we could just add the appropriate cases.
    
    foreach my $runno (@array_of_runnos) {
	my $sub_existing_files_message='';
	my $sub_missing_files_message='';
	
	foreach my $ch (@channel_array) {
	    $file_1 = "${current_path}/${runno}_${ch}_masked.nii";
	    if (! -e $file_1 ) {
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

	if (($sub_missing_files_message ne '') && ($case == 1)) {
	    $make_hash{$runno} = 1;
	} else {
	    $make_hash{$runno} = 0;
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
sub mask_one_image {
# ------------------
    my ($runno,$ch) = @_;
    my $runno_mask = $mask_hash{$runno};
    my $out_path = "${current_path}/${runno}_${ch}_masked.nii";
    my $centered_path = get_nii_from_inputs($current_path,$runno,$ch);
    my $apply_cmd =  "ImageMath 3 ${out_path} m ${centered_path} ${runno_mask};\n";
    my $remove_cmd = "rm ${centered_path};\n";
    my $go_message = "$PM: Applying mask created by ${template_contrast} image of runno $runno" ;
    my $stop_message = "$PM: could not apply ${template_contrast} mask to ${centered_path}:\n${apply_cmd}\n" ;
    
    
    my $jid = 0;
    if (cluster_check) {

    
	my $cmd = $apply_cmd.$remove_cmd;
	
	my $home_path = $current_path;
	my $Id= "${runno}_{ch}_apply_${template_contrast}_mask";
	my $verbose = 2; # Will print log only for work done.
	$jid = cluster_exec($go,$go_message, $cmd ,$home_path,$Id,$verbose);     
	if (! $jid) {
	    error_out($stop_message);
	}
    } else {

	my @cmds = ($apply_cmd,$remove_cmd);
	if (! execute($go, $go_message, @cmds) ) {
	    error_out($stop_message);
	}
    }

    if ((!-e $out_path) && ($jid == 0)) {
	error_out("$PM: missing masked image: ${out_path}");
    }
    print "** $PM created ${out_path}\n";
  
    return($jid);
}

# ------------------
sub mask_images_vbm_Init_check {
# ------------------

    return('');
}

# ------------------
sub mask_images_vbm_Runtime_check {
# ------------------

# # Set up work
    $in_folder = $Hf->get_value('pristine_input_dir');
    $work_dir = $Hf->get_value('work_dir');
    $current_path = $Hf->get_value('inputs_dir');  # Dammit, "input" or "inputs"???
    $do_mask = $Hf->get_value('do_mask');
    $mask_dir = $Hf->get_value('mask_dir');
    $template_contrast = $Hf->get_value('skull_strip_contrast');
    $mask_threshold=$Hf->get_value('threshold_code');
                        # -1 use imagej (like evan and his dti pipe)
                        # 0-100 use threshold_zero 0-100, 
                        # 100-inf is set threshold.


    $num_morphs = 5;
    $morph_radius = 2;
    $dim_divisor = 2;
    $status_display_level=0;

    if ($mask_dir eq 'NO_KEY') {
	$mask_dir = "${current_path}/masks";
 	$Hf->set_value('mask_dir',$mask_dir); # Dammit, "input" or "inputs"??? 	
    }

    if ((! -e $mask_dir) && ($do_mask)) {
	mkdir ($mask_dir,0777);
    }

    $runlist = $Hf->get_value('complete_comma_list');
    @array_of_runnos = split(',',$runlist);
 
    $ch_runlist = $Hf->get_value('channel_comma_list');
    @channel_array = split(',',$ch_runlist);

    my $case = 1;
    my ($dummy,$skip_message)=mask_images_Output_check($case);

    if ($skip_message ne '') {
	print "${skip_message}";
    }


}


1;

