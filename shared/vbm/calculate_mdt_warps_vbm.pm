#!/usr/local/pipeline-link/perl
# pairwise_reg_vbm.pm 





my $PM = "calculate_mdt_warp_vbm.pm";
my $VERSION = "2014/12/02";
my $NAME = "Calculation of warps to/from the Minimum Deformation Template.";
my $DESC = "ants";

use strict;
use warnings;
no warnings qw(uninitialized);

use vars qw($Hf $BADEXIT $GOODEXIT $test_mode $intermediate_affine);
require Headfile;
require pipeline_utilities;

use List::Util qw(max);


my $do_inverse_bool = 0;
my ($atlas,$rigid_contrast,$mdt_contrast, $runlist,$work_path,$rigid_path,$current_path,$write_path_for_Hf);
my ($xform_code,$xform_path,$xform_suffix,$domain_dir,$domain_path,$inputs_dir);
my ($mdt_path,$pairwise_path,$predictor_id,$predictor_path,$work_done);
my (@array_of_runnos,@sorted_runnos,@jobs,@files_to_create,@files_needed);
my (%go_hash);
my $go = 1;
my $job;

# my @parents = qw(pairwise_reg_vbm);
# my @children = qw (apply_mdt_warps_vbm);


# ------------------
sub calculate_mdt_warps_vbm {  # Main code
# ------------------
    my ($direction) = @_;

    calculate_mdt_warps_vbm_Runtime_check($direction);

    foreach my $runno (@array_of_runnos) {
	$go = $go_hash{$runno};
	if ($go) {
	    ($job) = calculate_average_mdt_warp($runno,$direction);
	    
	    if ($job > 1) {
		push(@jobs,$job);
	    }
	}
    }
     

    if (cluster_check()) {
	my $interval = 2;
	my $verbose = 1;
	my $done_waiting = cluster_wait_for_jobs($interval,$verbose,@jobs);
	
	if ($done_waiting) {
	    print STDOUT  "  All pairwise diffeomorphic registration jobs have completed; moving on to next step.\n";
	}
    }
    my $case = 2;
    my ($dummy,$error_message)=calculate_mdt_warps_Output_check($case,$direction);

    if ($error_message ne '') {
	error_out("${error_message}",0);
    } else {
	$Hf->write_headfile($write_path_for_Hf);
	symbolic_link_cleanup($pairwise_path);
    }
}



# ------------------
sub calculate_mdt_warps_Output_check {
# ------------------
     my ($case, $direction) = @_;
     my $message_prefix ='';
     my ($out_file,$dir_string);
     if ($direction eq 'f' ) {
	 $dir_string = 'FORWARD';
     } elsif ($direction eq 'i') {
	 $dir_string = 'INVERSE';
     } else {
	 error_out("$PM: direction of warp \"$direction \"not recognized. Use \"f\" for forward and \"i\" for inverse.\n");
     }
     my @file_array=();
     if ($case == 1) {
  	$message_prefix = "  ${dir_string} MDT warp(s) already exist(s) for the following runno(s) and will not be recalculated:\n";
     } elsif ($case == 2) {
 	$message_prefix = "  Unable to create ${dir_string} MDT warp(s) for the following runno pairs:\n";
     }   # For Init_check, we could just add the appropriate cases.

     
     my $existing_files_message = '';
     my $missing_files_message = '';
     
     foreach my $runno (@sorted_runnos) {
	 if ($direction eq 'f' ) {
	     $out_file = "${current_path}/${runno}_to_MDT_warp.nii";
	 } elsif ($direction eq 'i') {
	     $out_file = "${current_path}/MDT_to_${runno}_warp.nii";
	 }
	 if (! -e  $out_file) {
	     $go_hash{$runno}=1;
	     push(@file_array,$out_file);
	     #push(@files_to_create,$full_file); # This code may be activated for use with Init_check and generating lists of work to be done.
	     $missing_files_message = $missing_files_message."\t$runno\n";
	 } else {
	     $go_hash{$runno}=0;
	     $existing_files_message = $existing_files_message."\t$runno\n";
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
sub calculate_mdt_warps_Input_check {
# ------------------

# This code was not completed before it was commented out.  It will need to be worked on further if put back into action.
# Its function is to use the files specified by @needed_array and check to see that both the original image and the affine transform existed,
# returning an error stating which ones were missing.

#     my ($needed_array_ref)=@_;
#     my @needed_array = @$needed_array_ref;

# # check for needed input files to produce output files which need to be produced in this step

#     my $message_prefix = " Unable to locate the following input files:\n";
#     my $missing_files_message = '';
#     my $message_postfix = " Process stopped during $PM. Please check for missing inputs and try again.\n";
#     foreach my $needed_runno (@needed_array) {
# 	opendir(DIR, $inputs_dir);
# 	# if ($go_hash{$runno}) {
# 	if (){
# 	    my @input_files = grep(/^$runno.*${rigid_contrast}/ ,readdir(DIR));
# 	    if ($input_files[0] eq '') {
# 		$missing_files_message = $missing_files_message."   $runno \n";
# 	    }
# 	}
#     }
#     if ($missing_files_message ne '') {
# 	error_out("$PM:\n${missing_files_message_prefix}${missing_files_message}${missing_files_message_postfix}");
#     }


}


# ------------------
sub calculate_average_mdt_warp {
# ------------------
    my ($runno,$direction) = @_;
    my ($fixed,$moving,$cmd);
    my $out_file = '';
    my $dir_string = '';
    if ($direction eq 'f') {
	$out_file = "${current_path}/${runno}_to_MDT_warp.nii";
	$dir_string = 'FORWARD';
    } else {
	$out_file = "${current_path}/MDT_to_${runno}_warp.nii";
	$dir_string = 'INVERSE';
    }
 
    $cmd =" AverageImages 3 ${out_file} 0";
    foreach my $other_runno (@sorted_runnos) {
	if ($direction eq 'f') {
	    $moving = $runno;
	    $fixed = $other_runno;
	} else {
	    $moving = $other_runno;
	    $fixed = $runno;
	}
	if ($fixed ne $moving) {
	    $cmd = $cmd." ${pairwise_path}/${moving}_to_${fixed}_warp.nii.gz";
	}
    }

    my $jid = 0;
    if (cluster_check) {
	my $home_path = $current_path;
	my $Id= "${runno}_calculate_${dir_string}_MDT_warp";
	my $verbose = 2; # Will print log only for work done.
	$jid = cluster_exec($go, "$PM: create ${dir_string} MDT warp for ${runno}", $cmd ,$home_path,$Id,$verbose);     
	if (! $jid) {
	    error_out("$PM: could not create ${dir_string} MDT warp for  ${runno}:\n${cmd}\n");
	}
    } else {
	my @cmds = ($cmd);#, "mv  `ls ${out_file}* | grep -E '[0-9]+Warp'` ${new_warp}", "mv  `ls ${out_file}* | grep -E '[0-9]+InverseWarp'` ${new_inverse}");
	if (! execute($go, "$PM: create ${dir_string} MDT warp for ${runno}", @cmds) ) {
	    error_out("$PM: could not create ${dir_string} MDT warp for  ${runno}:\n${cmd}\n");
	}
    }

    if ((!-e $out_file) && ($jid == 0)) {
	error_out("$PM: missing ${dir_string} MDT warp results for ${runno}: ${out_file}");
    }
    print "** $PM created ${out_file}\n";
  
    return($jid);
}


# ------------------
sub calculate_mdt_warps_vbm_Init_check {
# ------------------

    return('');
}


# ------------------
sub find_temp_headfile_pointer {
# ------------------
    my ($location) = @_;
    if (! -e  $location) {
	return(0);
    } else {
	opendir(DIR,$location);
	my @headfile_list = grep(/.*\.headfile$/ ,readdir(DIR));
	print " Headfile list first element: $headfile_list[0]\nLocation = $location\n";
	if ($#headfile_list > 0) {
	    error_out(" $PM: more than one temporary headfile found in folder: ${current_path}.  Unsure of which one accurately reflects previous work done.\n"); 
	}
	if ($headfile_list[0] eq '') {
	    print " $PM: No temporary headfile found in folder ${current_path}.  Any existing data will be removed and regenerated.\n";
	    return(0);
	} else {
	    my $tempHf = new Headfile ('ro', "${location}/${headfile_list[0]}");
	    if (! $tempHf->check()) {
		print " Unable to open temporary headfile ${headfile_list[0]}. Any existing data in ${current_path} will be removed and regenerated.\n";
		return(0);
	    }
	    if (! $tempHf->read_headfile) {
		print " Unable to read temporary headfile ${headfile_list[0]}. Any existing data in ${current_path} will be removed and regenerated.\n";
		return(0);
	    }
    
	    return($tempHf); 
	}
    }


}


# ------------------
sub calculate_mdt_warps_vbm_Runtime_check {
# ------------------
    my ($direction)=@_;
    
# # Set up work
    
    $mdt_contrast = $Hf->get_value('mdt_contrast'); #  Will modify to pull in arbitrary contrast, since will reuse this code for all contrasts, not just mdt contrast.
    $mdt_path = $Hf->get_value('mdt_work_dir');
    $pairwise_path = $Hf->get_value('mdt_pairwise_dir');
    $inputs_dir = $Hf->get_value('inputs_dir');
    $predictor_id = $Hf->get_value('predictor_id');
    $predictor_path = $Hf->get_value('predictor_work_dir');   
    $current_path = $Hf->get_value('mdt_diffeo_path');
 
    if ($predictor_path eq 'NO_KEY') {
	$predictor_path = "${mdt_path}/P_${predictor_id}"; # after debug need to add "p_${predictor_id}".
 	$Hf->set_value('predictor_work_dir',$predictor_path);
    }

    if ($current_path eq 'NO_KEY') {
	$current_path = "${predictor_path}/MDT_diffeo";
 	$Hf->set_value('mdt_diffeo_path',$current_path);
    }
    
    $write_path_for_Hf = "${current_path}/${predictor_id}_temp.headfile";

    my $current_tempHf = find_temp_headfile_pointer($current_path);
    $work_done = 0;
    my $Hf_comp = '';
    my $include = 0; # We will exclude certain keys from headfile comparison.
    my @excluded_keys =qw(compare_comma_list); 
 
    if ($current_tempHf ne "0"){
	$Hf_comp = compare_headfiles($Hf,$current_tempHf,$include,@excluded_keys);
	print " Hf_comp = ${Hf_comp}";
	if ($Hf_comp eq '') {
	    $work_done = 1;
	}
    }
    
    if (($current_tempHf eq "0") | ($Hf_comp ne '')) { # Move most recent (different) work to backup folder.	
	my $new_backup;
	my $existence=1;

	for (my $i=1; $existence== 1; $i++) {
	    if (! -e "${predictor_path}_b$i") {
		$existence = 0;
	    }
	    $new_backup = "${predictor_path}_b$i";
	}
	
	print " $PM: ${Hf_comp}\n";
	print " Will move existing work to backup folder: ${new_backup}.\n";
	rename($predictor_path,$new_backup);
    }
    
    
    if ((! -e $predictor_path) | ($current_tempHf eq "0")) {
	mkdir ($predictor_path,0777);
    }

    if ((! -e $current_path) | ($current_tempHf eq "0")) {
	mkdir ($current_path,0777);
    }
    

#   Functionize?
    $runlist = $Hf->get_value('control_comma_list');
    @array_of_runnos = split(',',$runlist);
    @sorted_runnos=sort(@array_of_runnos);
#

    my $case = 1;
    my ($dummy,$skip_message)=calculate_mdt_warps_Output_check($case,$direction);

    if ($skip_message ne '') {
	print "${skip_message}";
    }

# check for needed input files to produce output files which need to be produced in this step?

}

1;
