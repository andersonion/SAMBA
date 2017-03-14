#!/usr/local/pipeline-%link/perl
# calculate_jacobians_vbm.pm 
# Originally written by BJ Anderson, CIVM




my $PM = "calculate_jacobians_vbm.pm";
my $VERSION = "2015/02/06";
my $NAME = "Calculate jacobians based on the warps to and/or from the MDT.";
my $DESC = "ants";

use strict;
use warnings;
no warnings qw(uninitialized bareword);

use vars qw($Hf $BADEXIT $GOODEXIT  $test_mode $intermediate_affine $permissions $reservation);
require Headfile;
require pipeline_utilities;

use List::Util qw(max);


my $do_inverse_bool = 0;
my ($atlas,$rigid_contrast,$mdt_contrast, $runlist,$work_path,$rigid_path,$current_path,$write_path_for_Hf);
my ($xform_code,$xform_path,$xform_suffix,$domain_dir,$domain_path);
my ($mask_path,$template_name,$template_path, $diffeo_path,$space_string);
my (@array_of_runnos,@jobs,@files_to_create,@files_needed);
my (%go_hash);
my $go = 1;
my $job;

my ($new_contrast,$group,$gid,$affine_target);


# ------------------
sub calculate_jacobians_vbm {  # Main code
# ------------------
    my ($direction);
    ($direction,$group) = @_;
    my $start_time = time;

    if ($direction eq 'f' ) {
	$space_string = 'individual image';
	$new_contrast = "jac_to_MDT";
    } elsif ($direction eq 'i') {
	$space_string = 'MDT';
	$new_contrast = "jac_from_MDT";
    }

    my $PM_code;
    if ($group eq "control") {
	$gid = 1;
	$PM_code = 47;
    } elsif ($group eq "compare") {
	$gid = 0;
	$PM_code = 53;
    } else {
	error_out("$PM: invalid group of runnos specified.  Please consult your local coder and have them fix their problem.");
    }
    calculate_jacobians_vbm_Runtime_check($direction);

    foreach my $runno (@array_of_runnos) {
	$go = $go_hash{$runno};
	if ($go) {
	    ($job) = calculate_jacobian($runno,$direction);

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
	    print STDOUT  "  Jacobians in ${space_string} space have been calculated for all ${group} runnos; moving on to next step.\n";
	}
    }
    my $case = 2;
    my ($dummy,$error_message)=calculate_jacobians_Output_check($case,$direction);

    my $real_time = write_stats_for_pm($PM_code,$Hf,$start_time,@jobs);
    print "$PM took ${real_time} seconds to complete.\n";

    if ($error_message ne '') {
	error_out("${error_message}",0);
    } else {
 	$Hf->write_headfile($write_path_for_Hf);
	my $temp_list = $Hf->get_value('channel_comma_list');
	print "$PM: temp_list before: ${temp_list}\n";
	if ($temp_list !~ /[,]*${new_contrast}[,]*/) {
	    $temp_list=$temp_list.",${new_contrast}";
	    $Hf->set_value('channel_comma_list',$temp_list);
	}
	print "$PM: temp_list after: ${temp_list}\n";
	
	return($new_contrast);
    }
 
 }



# ------------------
sub calculate_jacobians_Output_check {
# ------------------
    my ($case, $direction) = @_;
    my $message_prefix ='';
    my ($out_file,$dir_string);
    if ($direction eq 'f' ) {
	$space_string = 'individual image';
    } elsif ($direction eq 'i') {
	$space_string = 'MDT';
    }
    
    my @file_array=();
    if ($case == 1) {
  	$message_prefix = "  Jacobian images in ${space_string} space have already been calculated for the following runno(s) and will not be recalculated:\n";
    } elsif ($case == 2) {
 	$message_prefix = "  Unable to calculate jacobian images in ${space_string} for the following runno(s):\n";
    }   # For Init_check, we could just add the appropriate cases.
    
    
    my $existing_files_message = '';
    my $missing_files_message = '';
    
    foreach my $runno (@array_of_runnos) {
	if ($direction eq 'f' ) {
	    $out_file = "${current_path}/${runno}_jac_to_MDT.nii.gz"; #added '.gz' 2 September 2015
	} elsif ($direction eq 'i') {
	    $out_file =  "${current_path}/${runno}_jac_from_MDT.nii.gz"; #added '.gz' 2 September 2015
	}
	
	if (data_double_check($out_file)) {
	    if ($out_file =~ s/\.gz$//) {
		if (data_double_check($out_file)) {
		    $go_hash{$runno}=1;
		    push(@file_array,$out_file);
		    #push(@files_to_create,$full_file); # This code may be activated for use with Init_check and generating lists of work to be done.
		    $missing_files_message = $missing_files_message."\t$runno\n";
		} else {
		    `gzip -f ${out_file}`; #Is -f safe to use?
		    $go_hash{$runno}=0;
		    $existing_files_message = $existing_files_message."\t$runno\n";
		}
	    }
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

# # ------------------
# sub calculate_jacobians_Input_check {
# # ------------------

# }


# ------------------
sub calculate_jacobian {
# ------------------
    my ($runno,$direction) = @_;
    my ($cmd,$input_warp);
    my ($jac_command,$unzip_command);
    my $out_file = '';
    my $space_string = '';
    
    if ($direction eq 'f') {
	$out_file = "${current_path}/${runno}_jac_to_MDT.nii.gz"; # Need to settle on exact file name format... #Added '.gz' 2 September 2015
	$space_string = 'individual_image';
	$input_warp = "${diffeo_path}/${runno}_to_MDT_warp.nii.gz"; #Added '.gz' 2 September 2015
    } else {
	$out_file = "${current_path}/${runno}_jac_from_MDT.nii.gz"; # I don't think this will be the proper implementation of the "inverse" option. #Added '.gz' 2 September 2015
	$space_string = 'MDT';
	
	$input_warp = "${diffeo_path}/MDT_to_${runno}_warp.nii.gz"; #Added '.gz' 2 September 2015
	#$input_warp = "${diffeo_path}/${runno}_to_MDT_warp.nii.gz"; # HORRIBLE CODE! Only testing to prove that "from MDT" is correct. NOTE: this is irrelevant if I use 'f' instead of 'i' for the Direction when I call the command.
	
    }
    $jac_command = "CreateJacobianDeterminantImage 3 ${input_warp} ${out_file} 1 1 ;\n"; # Just testing...should still be bad. # Correct when used with Sub2MDT warp, counter-intuitive as it is.
#    $jac_command = "CreateJacobianDeterminantImage 3 ${input_warp} ${out_file} 1 0 ;\n"; # Changed last binary flag from 1 to 0 (use GeometricJacobian)
    
## NOTE!!! All jacobian images created before 04 December 2015 are BAD!  They used a version of CreateJacobianDeterminantImage that did not account for any
#          rotation matrices in the header when using the GeometricJacobian option.  This caused the effects of the warp to be inverted in the x and y direction
#         (because of the "standard" [-1 -1 1] diagonals of our cosine matrix), but not the z.  The net result for logJacobian images was roughly -2/3 modulation,
#         though that is only approximate and any images and VBM calculated this way is unreliable.
##         While the ANTs guys found the bug and fixed it, James was unable to rebuild the latest version of ANTs on the cluster, so our best option to moved forward
#         is to just turn off the GeometricJacobian option.  The alternative, the Finite Differences method, is pretty comparable.
    
    
    
    $unzip_command = "ImageMath 3 ${out_file} m ${out_file} ${mask_path};\n";
    
#    $jac_command = "ANTSJacobian 3 ${input_warp} ${out_file} 1 ${mask_path} 1;\n"; # Older ANTS command
#    $unzip_command = "gunzip -c ${out_file}logjacobian.nii.gz > ${out_file}.nii;\n";  
    
    $cmd=$jac_command.$unzip_command;
    my $go_message =  "$PM: Calculate jacobian images in ${space_string} for ${runno}";
    my $stop_message = "$PM:  Unable to calculate jacobian images in ${space_string} for ${runno}:\n${cmd}\n";
    
    my @test=(0);
    if (defined $reservation) {
	@test =(0,$reservation);
    }
    my $mem_request = 30000;  # Added 23 November 2016,  Will need to make this smarter later.
    
    my $jid = 0;    
    if (cluster_check) {
	my $home_path = $current_path;
	my $Id= "${runno}_calculate_jacobian_in_${space_string}_space";
	my $verbose = 2; # Will print log only for work done.
	$jid = cluster_exec($go, $go_message, $cmd ,$home_path,$Id,$verbose,$mem_request,@test);     
	if (! $jid) {
	    error_out($stop_message);
	}
    } else {
	my @cmds = ($jac_command,$unzip_command);
	if (! execute($go, $go_message, @cmds) ) {
	    error_out($stop_message);
	}
    }
    
    if ((!-e $out_file) && ($jid == 0)) {
	error_out("$PM: missing jacobian image in ${space_string} space for ${runno}: ${out_file}");
    }

    print "** $PM created ${out_file}\n"; #Added '.gz' 2 September 2015 -- Don't have a clue why I thought that would be useful...
  
    return($jid,$out_file);
 }


# ------------------
sub calculate_jacobians_vbm_Init_check {
# ------------------

    return('');
}


# ------------------
sub calculate_jacobians_vbm_Runtime_check {
# ------------------
    my ($direction)=@_;
 
# # Set up work
    
   # $predictor_id = $Hf->get_value('predictor_id');
   # $predictor_path = $Hf->get_value('predictor_work_dir');
    $template_name = $Hf->get_value('template_name');
    $template_path = $Hf->get_value('template_work_dir');

    $mask_path = $Hf->get_value('MDT_eroded_mask');

    if ($gid) {
	$diffeo_path = $Hf->get_value('mdt_diffeo_path');   
	$current_path = $Hf->get_value('mdt_images_path');
	if ($current_path eq 'NO_KEY') {
	    # $current_path = "${predictor_path}/MDT_images";
	    $current_path = "${template_path}/MDT_images";
	    $Hf->set_value('mdt_images_path',$current_path);
	}
	$runlist = $Hf->get_value('control_comma_list');
	
    } else {
	$diffeo_path = $Hf->get_value('reg_diffeo_path');   
	$current_path = $Hf->get_value('reg_images_path');
	if ($current_path eq 'NO_KEY') {
	    # $current_path = "${predictor_path}/reg_images";
	    $current_path = "${template_path}/reg_images";
	    $Hf->set_value('reg_images_path',$current_path);
	}
	$runlist = $Hf->get_value('compare_comma_list');
    }
    
    if (! -e $current_path) {
 	mkdir ($current_path,$permissions);
    }
    
    $write_path_for_Hf = "${current_path}/${template_name}_temp.headfile";
        
    @array_of_runnos = split(',',$runlist);


    my $case = 1;
    my ($dummy,$skip_message)=calculate_jacobians_Output_check($case,$direction);

    if ($skip_message ne '') {
	print "${skip_message}";
    }

}

1;
