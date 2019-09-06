#!/usr/bin/false

#  tabulate_label_statistics_by_contrast_vbm.pm 

#  2017/06/19  Created by BJ Anderson, CIVM.

my $PM = " tabulate_label_statistics_by_contrast_vbm.pm";
my $VERSION = "2017/06/16";
my $NAME = "Calculate label-wide statistics for all contrast, for an individual runno.";

use strict;
use warnings;

use List::MoreUtils qw(uniq);

# 25 June 2019, BJA: Will try to look for ENV variable to set matlab_execs and runtime paths
use Env qw(MATLAB_EXEC_PATH MATLAB_2015b_PATH); 
if (! defined($MATLAB_EXEC_PATH)) {
   $MATLAB_EXEC_PATH =  "/cm/shared/workstation_code_dev/matlab_execs";
}
if (! defined($MATLAB_2015b_PATH)) {
    $MATLAB_2015b_PATH =  "/cm/shared/apps/MATLAB/R2015b/";
}
my $matlab_path = "${MATLAB_2015b_PATH}";

my ($current_path, $image_dir,$runlist,$ch_runlist,$in_folder,$out_folder);
my ($channel_comma_list,$channel_comma_list_2,$mdt_contrast,$space_string,$current_label_space,$label_atlas_name,$label_atlas_nickname,$labels_dir);
my ($individual_stat_dir);
my (@array_of_runnos,@channel_array,@initial_channel_array);
#my ($predictor_id); # SAVE FOR LAST ROUND OF LABEL STATS CODE
my @jobs=();
my (%go_hash,%go_mask);
my $log_msg='';
my $skip=0;
my $go = 1;
my $job;
my $PM_code = 66;

#my $compilation_date = "20170619_1151";

my $compilation_date = "stable";
#$compilation_date="20190905_1035";
my $tabulate_study_stats_executable_path = "$MATLAB_EXEC_PATH/study_stats_by_contrast_executable/${compilation_date}/run_study_stats_by_contrast_exec.sh"; 

# ------------------
sub  tabulate_label_statistics_by_contrast_vbm {
# ------------------
 
    ($current_label_space,@initial_channel_array) = @_;
    my $start_time = time;
    tabulate_label_statistics_by_contrast_Runtime_check();

    foreach my $contrast (@channel_array) {
	$go = $go_hash{$contrast};
	if ($go) {
	    ($job) = tabulate_label_statistics_by_contrast($contrast);
	    if ($job) {
		push(@jobs,$job);
	    }
	} 
    }

    if (cluster_check() && (scalar @jobs)) {
	my $interval = 2;
	my $verbose = 1;
	my $done_waiting = cluster_wait_for_jobs($interval,$verbose,@jobs);
	if ($done_waiting) {
	    print STDOUT  " study-wide ${current_label_space} label statistics has been calculated for all contrasts; moving on to next step.\n";
	}
    }
    my $case = 2;
    my ($dummy,$error_message)=tabulate_label_statistics_by_contrast_Output_check($case);

    my $real_time = vbm_write_stats_for_pm($PM_code,$Hf,$start_time,@jobs);
    print "$PM took ${real_time} seconds to complete.\n";

    @jobs=(); # Clear out the job list, since it will remember everything if this module is used iteratively.

    my $write_path_for_Hf = "${current_path}/stats_collate_${label_atlas_nickname}_${space_string}_temp.headfile";
    if ($error_message ne '') {
	error_out("${error_message}",0);
    } else {
	$Hf->write_headfile($write_path_for_Hf);
    }
    return;
}


# ------------------
sub tabulate_label_statistics_by_contrast_Output_check {
# ------------------

    my ($case) = @_;
    my $message_prefix ='';
    #my ($file_1);
    my @file_array=();

    my $existing_files_message = '';
    my $missing_files_message = '';

    
    if ($case == 1) {
	$message_prefix = "  Study-wide label statistics have been found for the following contrasts and will not be re-tabulated:\n";
    } elsif ($case == 2) {
	 $message_prefix = "  Unable to properly tabulate study-wide label statistics for the following contrasts:\n";
    }   # For Init_check, we could just add the appropriate cases.

    foreach my $contrast (@channel_array) {
	#print "$runno\n\n";
	my $sub_existing_files_message='';
	my $sub_missing_files_message='';
	
	my $file_1 = "${current_path}/studywide_stats_for_${contrast}.txt" ;
	$file_1 = "${current_path}/collated_${contrast}_${label_atlas_nickname}_${space_string}_stats.txt" ;
#	print "${file_1}\n\n\n";
	if (data_double_check($file_1,$case-1)) {
	    $go_hash{$contrast}=1;
	    push(@file_array,$file_1);
	    $sub_missing_files_message = $sub_missing_files_message."\t$contrast";
	} else {
	    my $header_string = `head -1 ${file_1}`;
	    #my @c_array_1 = split('=',$header_string);
	    #my @completed_contrasts = split(',',$c_array_1[1]);
	    #my $completed_contrasts_string = join(' ',@completed_contrasts);
	    my $missing_runnos = 0;
	    my @runno_array = split(',',$runlist);
	    foreach my $runno (@runno_array) {
		if (! $missing_runnos) {
		    #if ($completed_contrasts_string !~ /($ch)/) {
		    if ($header_string !~ /($runno)/) {
			$missing_runnos = 1;
		    }
		}
	    }
	    if ($missing_runnos) {
		$go_hash{$contrast}=1;
		push(@file_array,$file_1);
		$sub_missing_files_message = $sub_missing_files_message."\t$contrast";
	    } else {
		$go_hash{$contrast}=0;
		$sub_existing_files_message = $sub_existing_files_message."\t$contrast";
	    }
	}

	if (($sub_existing_files_message ne '') && ($case == 1)) {
	    $existing_files_message = $existing_files_message.$contrast."\t".$sub_existing_files_message."\n";
	} elsif (($sub_missing_files_message ne '') && ($case == 2)) {
	    $missing_files_message =$missing_files_message.$contrast."\t".$sub_missing_files_message."\n";
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
sub tabulate_label_statistics_by_contrast {
# ------------------
    my ($current_contrast) = @_;

    #my $exec_args_ ="${runno} {contrast} ${average_mask} ${input_path} ${contrast_path} ${group_1_name} ${group_2_name} ${group_1_files} ${group_2_files}";# Save for part 3..
    my $exec_args ="${individual_stat_dir} ${current_contrast} ${runlist} ${current_path}/collated_${current_contrast}_${label_atlas_nickname}_${space_string}_stats.txt";

    my $go_message = "$PM: Tabulating study-wide label statistics for contrast: ${current_contrast}\n" ;
    my $stop_message = "$PM: Failed to properly tabulate study_wide label statistics for contrast: ${current_contrast} \n" ;
    
    my @test=(0);
    if (defined $reservation) {
        @test =(0,$reservation);
    }
    my $mem_request = '10000';
    my $jid = 0;
    if (cluster_check) {
        my $go =1;	    
        my $cmd = "${tabulate_study_stats_executable_path} ${matlab_path} ${exec_args}";

        my $home_path = ${current_path};
        my $Id= "${current_contrast}_tabulate_label_statistics_by_contrast";
        my $verbose = 1; # Will print log only for work done.
        $jid = cluster_exec($go,$go_message , $cmd ,$home_path,$Id,$verbose,$mem_request,@test);     
        if (! $jid) {
            error_out($stop_message);
        } else {
            return($jid);
        }
    }
    return;
} 

# ------------------
sub  tabulate_label_statistics_by_contrast_vbm_Init_check {
# ------------------
   my $init_error_msg='';
   my $message_prefix="$PM initialization check:\n";


   # if ($log_msg ne '') {
   #     log_info("${message_prefix}${log_msg}");
   # }
   
   if ($init_error_msg ne '') {
       $init_error_msg = $message_prefix.$init_error_msg;
   }
       
   return($init_error_msg);
}

# ------------------
sub  tabulate_label_statistics_by_contrast_Runtime_check {
# ------------------
    
    $label_atlas_nickname = $Hf->get_value('label_atlas_nickname');
    $label_atlas_name = $Hf->get_value('label_atlas_name');
    if ($label_atlas_nickname eq 'NO_KEY') {
        $label_atlas_nickname=$label_atlas_name;
    }

    if (! defined $current_label_space) {
        $current_label_space = $Hf->get_value('label_space');
    }
    
    $space_string='rigid'; # Default

    if ($current_label_space eq 'pre_rigid') {
        $space_string = 'native';
    } elsif (($current_label_space eq 'pre_affine') || ($current_label_space eq 'post_rigid')) {
        $space_string = 'rigid';
    } elsif ($current_label_space eq 'post_affine') {
        $space_string = 'affine';
    } elsif ($current_label_space eq 'MDT') {
        $space_string = 'mdt';
    } elsif ($current_label_space eq 'atlas') {
        $space_string = 'atlas';
    }

    $labels_dir = $Hf->get_value('labels_dir');
    my $label_refname = $Hf->get_value('label_refname');
    my $intermediary_path = "${labels_dir}/${current_label_space}_${label_refname}_space";

    my $stat_path = $Hf->get_value('stat_path');
    #$individual_stat_dir = "${stat_path}/individual_label_statistics/";
    $individual_stat_dir = "${stat_path}";

    $current_path = "${stat_path}/studywide_label_statistics/";
    if (! -e $current_path) {
        mkdir ($current_path,$permissions);
    }

    $runlist = $Hf->get_value('all_groups_comma_list');
    if ($runlist eq 'NO_KEY') {
        $runlist = $Hf->get_value('complete_comma_list');
    }

    #@array_of_runnos = split(',',$runlist);
 


    foreach my $contrast (@initial_channel_array) {
	if ($contrast !~ /^(ajax|jac|nii4D)/) {
	    push(@channel_array,$contrast);
	}
    }
    push(@channel_array,'volume');
    @channel_array=uniq(@channel_array);

    #$channel_comma_lis_2 = join(',',@channel_array);

    my $case = 1;
    my ($dummy,$skip_message)=tabulate_label_statistics_by_contrast_Output_check($case);
 
    if ($skip_message ne '') {
	print "${skip_message}";
    }


}


1;

