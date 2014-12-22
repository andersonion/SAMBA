#!/usr/local/pipeline-link/perl
# apply_mdt_warps_vbm.pm 
# Originally written by BJ Anderson, CIVM




my $PM = "apply_mdt_warps_vbm.pm";
my $VERSION = "2014/12/11";
my $NAME = "Application of warps derived from the calculation of the Minimum Deformation Template.";
my $DESC = "ants";

use strict;
use warnings;
no warnings qw(uninitialized bareword);

use vars qw($Hf $BADEXIT $GOODEXIT  $test_mode $intermediate_affine);
require Headfile;
require pipeline_utilities;

use List::Util qw(max);


my $do_inverse_bool = 0;
my ($atlas,$rigid_contrast,$mdt_contrast, $runlist,$work_path,$rigid_path,$current_path,$write_path_for_Hf);
my ($xform_code,$xform_path,$xform_suffix,$domain_dir,$domain_path,$inputs_dir);
my ($mdt_path,$predictor_id,$predictor_path, $diffeo_path,$work_done);
my (@array_of_runnos,@jobs,@files_to_create,@files_needed);
my (%go_hash);
my $go = 1;
my $job;

my ($current_contrast,$group,$gid);


# ------------------
sub apply_mdt_warps_vbm {  # Main code
# ------------------
    my $direction;
    ($current_contrast,$direction,$group) = @_;
    if ($group eq "control") {
	$gid = 1;
    } elsif ($group eq "compare") {
	$gid = 0;
    } else {
	error_out("$PM: invalid group of runnos specified.  Please consult your local coder and have them fix their problem.");
    }
    apply_mdt_warps_vbm_Runtime_check($direction);

    foreach my $runno (@array_of_runnos) {
	$go = $go_hash{$runno};
	if ($go) {
	    ($job) = apply_mdt_warp($runno,$direction);

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
	    print STDOUT  "  MDT warps have been applied to the ${current_contrast} images for all ${group} runnos; moving on to next step.\n";
	}
    }
    my $case = 2;
    my ($dummy,$error_message)=apply_mdt_warps_Output_check($case,$direction);

    if ($error_message ne '') {
	error_out("${error_message}",0);
    } else {
	$Hf->write_headfile($write_path_for_Hf);
	if (! $gid) {
	    symbolic_link_cleanup($diffeo_path);
	}
	symbolic_link_cleanup($rigid_path);
    }
 
}



# ------------------
sub apply_mdt_warps_Output_check {
# ------------------
     my ($case, $direction) = @_;
     my $message_prefix ='';
     my ($out_file,$dir_string);
     if ($direction eq 'f' ) {
	 $dir_string = 'forward';
     } elsif ($direction eq 'i') {
	 $dir_string = 'inverse';
     } else {
	 error_out("$PM: direction of warp \"$direction \"not recognized. Use \"f\" for forward and \"i\" for inverse.\n");
     }
     my @file_array=();
     if ($case == 1) {
  	$message_prefix = "  ${dir_string} MDT warp(s) have already been applied to the ${current_contrast} images for the following runno(s) and will not be recalculated:\n";
     } elsif ($case == 2) {
 	$message_prefix = "  Unable to apply ${dir_string} MDT warp(s) to the ${current_contrast} image for the following runno(s):\n";
     }   # For Init_check, we could just add the appropriate cases.

     
     my $existing_files_message = '';
     my $missing_files_message = '';
     
     foreach my $runno (@array_of_runnos) {
	 if ($direction eq 'f' ) {
	     $out_file = "${current_path}/${runno}_${current_contrast}_to_MDT.nii";
	 } elsif ($direction eq 'i') {
	     $out_file =  "${current_path}/MDT_to_${runno}_${current_contrast}.nii";
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
sub apply_mdt_warps_Input_check {
# ------------------

}


# ------------------
sub apply_mdt_warp {
# ------------------
    my ($runno,$direction) = @_;
    my ($cmd);
    my $out_file = '';
    my $direction_string = '';
    if ($direction eq 'f') {
	$out_file = "${current_path}/${runno}_${current_contrast}_to_MDT.nii"; # Need to settle on exact file name format...
	$direction_string = 'forward';
    } else {
	$out_file = "${current_path}/MDT_to_${runno}_${current_contrast}.nii"; # I don't think this will be the proper implementation of the "inverse" option.
	$direction_string = 'inverse';
    }

    my $image_to_warp = get_nii_from_inputs($inputs_dir,$runno,$current_contrast); 
    my ($warp_train,$warp_string,@warp_array);
## TEST
#    $direction_string = 'inverse';
## TEST
    $warp_string = $Hf->get_value("${direction_string}_xforms_${runno}");

    @warp_array = split(',',$warp_string);
    $warp_train = join(' ',@warp_array);

    $cmd = "WarpImageMultiTransform 3 ${image_to_warp} ${out_file} -R ${image_to_warp} ${warp_train}";

    my $go_message =  "$PM: apply ${direction_string} MDT warp(s) to ${current_contrast} image for ${runno}";
    my $stop_message = "$PM: could not apply ${direction_string} MDT warp(s) to ${current_contrast} image for  ${runno}:\n${cmd}\n";

    my $jid = 0;
    if (cluster_check) {
	my $home_path = $current_path;
	my $Id= "${runno}_${current_contrast}_apply_${direction_string}_MDT_warp";
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
	error_out("$PM: missing ${current_contrast} image with ${direction_string} MDT warp(s) applied for ${runno}: ${out_file}");
    }
    print "** $PM created ${out_file}\n";
  
    return($jid,$out_file);
}


# ------------------
sub apply_mdt_warps_vbm_Init_check {
# ------------------

    return('');
}


# ------------------
sub apply_mdt_warps_vbm_Runtime_check {
# ------------------
    my ($direction)=@_;
 
# # Set up work
    
    $mdt_contrast = $Hf->get_value('mdt_contrast');
    $mdt_path = $Hf->get_value('mdt_work_dir');
    $inputs_dir = $Hf->get_value('inputs_dir');
    $rigid_path = $Hf->get_value('rigid_work_dir');
    $predictor_id = $Hf->get_value('predictor_id');
    $predictor_path = $Hf->get_value('predictor_work_dir');
    if ($gid) {
	$diffeo_path = $Hf->get_value('mdt_diffeo_path');   
	$current_path = $Hf->get_value('mdt_images_path');
	if ($current_path eq 'NO_KEY') {
	    $current_path = "${predictor_path}/MDT_images";
	    $Hf->set_value('mdt_images_path',$current_path);
	}
	$runlist = $Hf->get_value('control_comma_list');
	
    } else {
	$diffeo_path = $Hf->get_value('reg_diffeo_path');   
	$current_path = $Hf->get_value('reg_images_path');
	if ($current_path eq 'NO_KEY') {
	    $current_path = "${predictor_path}/reg_images";
	    $Hf->set_value('reg_images_path',$current_path);
	}
	$runlist = $Hf->get_value('compare_comma_list');
    }
    
    if (! -e $current_path) {
	mkdir ($current_path,0777);
    }
    
    $write_path_for_Hf = "${current_path}/${predictor_id}_temp.headfile";

#   Functionize?
    
    @array_of_runnos = split(',',$runlist);
#

    my $case = 1;
    my ($dummy,$skip_message)=apply_mdt_warps_Output_check($case,$direction);

    if ($skip_message ne '') {
	print "${skip_message}";
    }

# check for needed input files to produce output files which need to be produced in this step?

}

1;
