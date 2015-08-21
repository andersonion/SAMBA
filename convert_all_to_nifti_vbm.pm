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

use vars qw($Hf $BADEXIT $GOODEXIT $test_mode $permissions);
require Headfile;
require pipeline_utilities;
#require convert_to_nifti_util;


my ($current_path, $work_dir,$runlist,$ch_runlist,$in_folder,$out_folder,$flip_x,$flip_z,$do_mask);
my (@array_of_runnos,@channel_array);
my (%go_hash,%go_mask,%mask_hash);
my $skip=0;

# ------------------
sub convert_all_to_nifti_vbm {
# ------------------
# convert the source image volumes used in this SOP to nifti format (.nii)
# could use image name (suffix) to figure out datatype
    ($skip) = @_;
    if ($skip eq '') {$skip = 0;}
    my $start_time = time;
    
    convert_all_to_nifti_vbm_Runtime_check();

    my @nii_cmds;
    my @nii_files;


    foreach my $runno (@array_of_runnos) {
	foreach my $ch (@channel_array) {
	    my $go = $go_hash{$runno}{$ch};
	    if ($go) {
		my $current_file=get_nii_from_inputs($in_folder,$runno,$ch);

		if ($current_file) {
		    push(@nii_files,$current_file);
		} else {
		    print "Unable to find input image for $runno and $ch in folder: ${in_folder}.\n";
		}
	    }
	}
    }
    if ($nii_files[0] ne '') {
	my $message="\n$PM:\nThe following files will be prepared by Matlab for the VBM pipeline:\n".
	    join("\n",@nii_files)."\n\n";
	print "$message";
    }


    foreach my $file (@nii_files) {
	recenter_nii_function($file,$current_path,$skip,$Hf);
    }
   # execute_indep_forks(1,"Recentering nifti images from tensor inputs", @nii_cmds);

    my $case = 2;
    my ($dummy,$error_message)=convert_all_to_nifti_Output_check($case);

 
    my $real_time = write_stats_for_pm($PM,$Hf,$start_time);
    print "$PM took ${real_time} seconds to complete.\n";


    if ($error_message ne '') {
	error_out("${error_message}",0);
    } else {
    # Clean up matlab junk
	my $test_string = `ls ${work_dir} `;
	if ($test_string =~ /.m$/) {
	    `rm ${work_dir}/*.m`;
	}
	if ($test_string =~ /matlab/) {
	    `rm ${work_dir}/*matlab*`;
	}
    }
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
	    if ($file_1 =~ /[\n]+/) {
		$file_1 = "${current_path}/${runno}_${ch}.nii";
	    }
	    if ((data_double_check($file_1) ) || ((! $do_mask) &&  ($file_1 =~ /.*masked\.nii / ))) {
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
sub convert_all_to_nifti_vbm_Init_check {
# ------------------

    return('');
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

    $flip_x = $Hf->get_value('flip_x'); 
    $flip_z = $Hf->get_value('flip_z'); 
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
    @array_of_runnos = split(',',$runlist);
 
    $ch_runlist = $Hf->get_value('channel_comma_list');
    @channel_array = split(',',$ch_runlist);

    my $case = 1;
    my ($dummy,$skip_message)=convert_all_to_nifti_Output_check($case);

    if ($skip_message ne '') {
	print "${skip_message}";
    }


}


1;

