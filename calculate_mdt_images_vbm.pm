#!/usr/local/pipeline-link/perl
# calculate_mdt_images_vbm.pm 





my $PM = "calculate_mdt_images_vbm.pm";
my $VERSION = "2014/12/02";
my $NAME = "Calculation of the average Minimal Deformation Template for a given contrast.";
my $DESC = "ants";

use strict;
use warnings;
no warnings qw(uninitialized bareword);

use vars qw($Hf $BADEXIT $GOODEXIT $test_mode $intermediate_affine $permissions);
require Headfile;
require pipeline_utilities;

use List::Util qw(max);


my $do_inverse_bool = 0;
my ($atlas,$rigid_contrast,$mdt_contrast, $runlist,$work_path,$rigid_path,$current_path,$write_path_for_Hf);
my ($xform_code,$xform_path,$xform_suffix,$domain_dir,$domain_path,$inputs_dir);
my ($mdt_path,$pairwise_path,$template_predictor,$template_path,$template_name,$mdt_images_path,$work_done);
my (@array_of_runnos,@sorted_runnos,@jobs,@files_to_create,@files_needed);
my (%go_hash);
my $go = 1;
my $job;


my (@contrast_list);


# ------------------
sub calculate_mdt_images_vbm {  # Main code
# ------------------

    (@contrast_list) = @_;
    my $start_time = time;

    calculate_mdt_images_vbm_Runtime_check();

    foreach my $contrast (@contrast_list) {
	$go = $go_hash{$contrast};
	if ($go) {
	    ($job) = calculate_average_mdt_image($contrast);

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
	    my $contrast_string;
	    if ($mdt_contrast eq ($contrast_list[0] || $contrast_list[2])){
		$contrast_string = "primary MDT contrast(s) ${mdt_contrast}";
	    } else {
		$contrast_string = "all non-MDT contrasts";
	    }
	    print STDOUT  "  Average MDT images have been calculated for ${contrast_string}; moving on to next step.\n";
	}
    }

    my $case = 2;
    my ($dummy,$error_message);
    foreach my $contrast (@contrast_list) {
	my $temp_message;
	($dummy,$temp_message)=calculate_mdt_images_Output_check($case,$contrast);
	if ($temp_message ne '') {
	    $error_message=$error_message.$temp_message;
	}
    }

    my $real_time = write_stats_for_pm($PM,$Hf,$start_time,@jobs);
    print "$PM took ${real_time} seconds to complete.\n";

    if ($error_message ne '') {
	error_out("${error_message}",0);
    } else {
	$Hf->write_headfile($write_path_for_Hf);
#x	symbolic_link_cleanup($pairwise_path);
    }
 
}



# ------------------
sub calculate_mdt_images_Output_check {
# ------------------
     my ($case,$contrast) = @_;
     my $message_prefix ='';
     my ($out_file);
     my @file_array=();
     if ($case == 1) {
	 $message_prefix = "  Average MDT images already exist for the following contrast and will not be recalculated:\n";
     } elsif ($case == 2) {
 	$message_prefix = "  Unable to create average MDT images for contrast:\n";
     }   # For Init_check, we could just add the appropriate cases.

     
     my $existing_files_message = '';
     my $missing_files_message = '';
     
     $out_file = "${current_path}/MDT_${contrast}.nii";

     if (data_double_check($out_file)) {
	 $go_hash{$contrast}=1;
	 push(@file_array,$out_file);
	 #push(@files_to_create,$full_file); # This code may be activated for use with Init_check and generating lists of work to be done.
	 $missing_files_message = $missing_files_message."\t$contrast\n";
     } else {
	 $go_hash{$contrast}=0;
	 $existing_files_message = $existing_files_message."\t$contrast\n";
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
sub calculate_mdt_images_Input_check {
# ------------------

}


# ------------------
sub calculate_average_mdt_image {
# ------------------
    my ($contrast) = @_;
    my ($cmd);
    my $out_file = "${current_path}/MDT_${contrast}.nii";

 
    $cmd =" AverageImages 3 ${out_file} 0";
    foreach my $runno (@array_of_runnos) {
	$cmd = $cmd." ${mdt_images_path}/${runno}_${contrast}_to_MDT.nii";
    }
    my $go_message =  "$PM: created average MDT image(s) for contrast:  ${contrast}";
    my $stop_message = "$PM: could not create an average MDT image for contrast: ${contrast}:\n${cmd}\n";

    my $jid = 0;
    if (cluster_check) {
	my $home_path = $current_path;
	my $Id= "${contrast}_calculate_average_MDT_image";
	my $verbose = 2; # Will print log only for work done.
	$jid = cluster_exec($go, $go_message, $cmd ,$home_path,$Id,$verbose);     
	if (! $jid) {
	    error_out($stop_message);
	}
    } else {
	my @cmds = ($cmd);
	if (! execute($go,$go_message, @cmds) ) {
	    error_out($stop_message);
	}
    }

    if ((!-e $out_file) && ($jid == 0)) {
	error_out("$PM: missing average MDT image for contrast: ${contrast}: ${out_file}");
    }
    print "** $PM created ${out_file}\n";
  
    return($jid,$out_file);
}


# ------------------
sub calculate_mdt_images_vbm_Init_check {
# ------------------

    return('');
}


# ------------------
sub calculate_mdt_images_vbm_Runtime_check {
# ------------------

# # Set up work
    
    $mdt_contrast = $Hf->get_value('mdt_contrast'); #  Will modify to pull in arbitrary contrast, since will reuse this code for all contrasts, not just mdt contrast.
    $mdt_path = $Hf->get_value('mdt_work_dir');
    $pairwise_path = $Hf->get_value('mdt_pairwise_dir');
    $inputs_dir = $Hf->get_value('inputs_dir');
#
#    $predictor_id = $Hf->get_value('predictor_id');
#    $predictor_path = $Hf->get_value('predictor_work_dir');
   
    $template_predictor = $Hf->get_value('template_predictor');
    $template_path = $Hf->get_value('template_work_dir');  
    $template_name = $Hf->get_value('template_name'); 
#
    $mdt_images_path = $Hf->get_value('mdt_images_path');
    $current_path = $Hf->get_value('median_images_path');

    if ($current_path eq 'NO_KEY') {
	$current_path = "${template_path}/median_images";
	mkdir ($current_path,$permissions);
 	$Hf->set_value('median_images_path',$current_path);
    }
    
    $write_path_for_Hf = "${current_path}/${template_name}_temp.headfile";

#    $runlist = $Hf->get_value('control_comma_list');
    $runlist = $Hf->get_value('template_comma_list');

    if ($runlist eq 'NO_KEY') {
	$runlist = $Hf->get_value('control_comma_list');
    }
    @array_of_runnos = split(',',$runlist);
#

    my $case = 1;
    my ($dummy,$skip_message);
    foreach my $contrast (@contrast_list) {
	my $temp_message;
	($dummy,$temp_message)=calculate_mdt_images_Output_check($case,$contrast);
	if ($temp_message ne '') {
	    $skip_message=$skip_message.$temp_message;
	}
    }
	
    if ($skip_message ne '') {
	print "${skip_message}";
    }

# check for needed input files to produce output files which need to be produced in this step?

}

1;
