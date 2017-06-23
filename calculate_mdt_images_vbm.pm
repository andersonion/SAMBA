#!/usr/local/pipeline-link/perl
# calculate_mdt_images_vbm.pm 

my $PM = "calculate_mdt_images_vbm.pm";
my $VERSION = "2016/11/14"; # Cleaned up code, added support for iterative template creation process.
my $NAME = "Calculation of the average Minimal Deformation Template for a given contrast.";
my $DESC = "ants";

use strict;
use warnings;
no warnings qw(uninitialized bareword);

use vars qw($Hf $BADEXIT $GOODEXIT $reservation $dims $ants_verbosity $reservation $permissions);
require Headfile;
require pipeline_utilities;

use List::Util qw(max);


my $do_inverse_bool = 0;
my ($inputs_dir,$mdt_contrast,$runlist,$current_path,$write_path_for_Hf);
my ($template_path,$template_name,$mdt_images_path,$work_done,$reference_image,$master_template_dir);
my (@array_of_runnos,@sorted_runnos,@files_to_create,@files_needed);
my @jobs=();
my (%go_hash,%int_go_hash);
my $go = 1;
my $job;
my ($last_update_warp,$mdt_creation_strategy,$current_iteration);

my (@contrast_list);

if (! defined $ants_verbosity) {$ants_verbosity = 1;}
if (! defined $dims) {$dims = 3;}

my $interp = "Linear"; # Hardcode this here for now...may need to make it a soft variable.

# ------------------
sub calculate_mdt_images_vbm {  # Main code
# ------------------

    ($current_iteration,@contrast_list) = @_;
    if ($current_iteration !~ /^[0-9]+?/) { # Backwards compatibility, maybe first contrast instead of current iteration.
	unshift(@contrast_list,$current_iteration);
	$current_iteration = 69; # This is just a juvenile number to make sure we can see if it fails.
    }

    my $start_time = time;

    calculate_mdt_images_vbm_Runtime_check();

    foreach my $contrast (@contrast_list) {
	$go = $go_hash{$contrast};
	if ($go) {
	    ($job) = calculate_average_mdt_image($contrast);

	    if ($job) {
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

    @jobs=(); # Clear out the job list, since it will remember everything when this module is used iteratively.

    if ($error_message ne '') {
	error_out("${error_message}",0);
    } else {
	$Hf->write_headfile($write_path_for_Hf);
#	symbolic_link_cleanup($pairwise_path);
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
     
     $out_file = "${current_path}/MDT_${contrast}.nii.gz";
     $int_go_hash{$contrast}=0;
     if (data_double_check($out_file)) {
	 if ($out_file =~ s/\.gz$//) {
	     if (data_double_check($out_file)) {
		 $go_hash{$contrast}=1;
		 push(@file_array,$out_file);
		 #push(@files_to_create,$full_file); # This code may be activated for use with Init_check and generating lists of work to be done.
		 $missing_files_message = $missing_files_message."\t$contrast\n";
		 if ($mdt_creation_strategy eq 'iterative'){
		     my $int_file = "${current_path}/intermediate_MDT_${contrast}.nii.gz";
		     if (data_double_check($int_file)) {
			 if ($int_file =~ s/\.gz$//) {
			     if (data_double_check($int_file)) {
				 $int_go_hash{$contrast}=1;
				 push(@file_array,$int_file);
				 #push(@files_to_create,$full_file); # This code may be activated for use with Init_check and generating lists of work to be done.
			     }
			 }
		     }
		 } else {
		     $int_go_hash{$contrast}=1;
		 }
	     } else {
		 `gzip -f ${out_file}`; #Is -f safe to use?
		 $go_hash{$contrast}=0;
		 $existing_files_message = $existing_files_message."\t$contrast\n";
	     }
	 }  
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
    my ($cmd,$avg_cmd,$update_cmd,$cleanup_cmd,$copy_cmd);
    my ($out_file, $intermediate_file);
	$out_file = "${current_path}/MDT_${contrast}.nii.gz";
    if ($mdt_creation_strategy eq 'iterative') {

	my $warp_train_car = " -t ${last_update_warp} ";
	my $warp_train = $warp_train_car.$warp_train_car.$warp_train_car.$warp_train_car;

	#$out_file = "${current_path}/MDT_${contrast}.nii.gz"; #moved outside of if statement
	$intermediate_file = "${current_path}/intermediate_MDT_${contrast}.nii.gz";
 	$update_cmd = "antsApplyTransforms --float -v ${ants_verbosity} -d ${dims} -i ${intermediate_file} -o ${out_file} -r ${reference_image} -n $interp ${warp_train};\n";
	$cleanup_cmd = "if [[ -f ${out_file} ]]; then rm ${intermediate_file}; fi\n";
	if ($contrast eq $mdt_contrast) { # This needs to be adapted to support multiple mdt contrasts!
	    my $backup_file = "${master_template_dir}/${template_name}_i${current_iteration}.nii.gz";
	    $copy_cmd = "cp ${out_file} ${backup_file}\n";
	}
    } else {
	$intermediate_file = $out_file;
    }
    if ($int_go_hash{$contrast}) { 
	$avg_cmd =" AverageImages 3 ${intermediate_file} 0";
	foreach my $runno (@array_of_runnos) {
	    $avg_cmd = $avg_cmd." ${mdt_images_path}/${runno}_${contrast}_to_MDT.nii.gz";
	}
	$avg_cmd = $avg_cmd.";\n";
    }

    $cmd = $avg_cmd.$update_cmd.$cleanup_cmd.$copy_cmd;

    my $go_message =  "$PM: created average MDT image(s) for contrast:  ${contrast}";
    my $stop_message = "$PM: could not create an average MDT image for contrast: ${contrast}:\n${cmd}\n";

    my @test=(0);
    if (defined $reservation) {
	@test =(0,$reservation);
    }

    my $mem_request = 30000;  # Added 23 November 2016,  Will need to make this smarter later.


    my $jid = 0;
    if (cluster_check) {
	my $home_path = $current_path;
	my $Id= "${contrast}_calculate_average_MDT_image";
	my $verbose = 2; # Will print log only for work done.
	$jid = cluster_exec($go, $go_message, $cmd ,$home_path,$Id,$verbose,$mem_request,@test);     
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
    $master_template_dir = $Hf->get_value('master_template_folder');
    $mdt_contrast = $Hf->get_value('mdt_contrast'); #  Will modify to pull in arbitrary contrast, since will reuse this code for all contrasts, not just mdt contrast.
    $inputs_dir = $Hf->get_value('inputs_dir');

    $last_update_warp = $Hf->get_value('last_update_warp');
    $mdt_creation_strategy = $Hf->get_value('mdt_creation_strategy');

    $template_path = $Hf->get_value('template_work_dir');  
    $template_name = $Hf->get_value('template_name'); 
#
    $mdt_images_path = $Hf->get_value('mdt_images_path');
    #$current_path = $Hf->get_value('median_images_path');

    #if ($current_path eq 'NO_KEY') {
    $current_path = "${template_path}/median_images";
    if (! -e $current_path) {
	mkdir ($current_path,$permissions);
    }
    $Hf->set_value('median_images_path',$current_path); 
    #}

    my $vbm_reference_path = $Hf->get_value('vbm_reference_path');
    $reference_image=$vbm_reference_path;

    
    $write_path_for_Hf = "${current_path}/${template_name}_temp.headfile";

#    $runlist = $Hf->get_value('control_comma_list');
    $runlist = $Hf->get_value('template_comma_list');

    if ($runlist eq 'NO_KEY') {
	$runlist = $Hf->get_value('control_comma_list');
    }

    if ($runlist eq 'EMPTY_VALUE') {
	@array_of_runnos = ();
    } else {
	@array_of_runnos = split(',',$runlist);
    }
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
