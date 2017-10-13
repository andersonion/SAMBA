#!/usr/local/pipeline-link/perl

#  calculate_individual_label_statistics_vbm.pm 

#  2017/06/16  Created by BJ Anderson, CIVM.

my $PM = " calculate_individual_label_statistics_vbm.pm";
my $VERSION = "2017/06/16";
my $NAME = "Calculate label-wide statistics for all contrast, for an individual runno.";

use strict;
use warnings;
no warnings qw(bareword);

use vars qw($Hf $BADEXIT $GOODEXIT  $permissions $reservation);
require Headfile;
require pipeline_utilities;
use List::MoreUtils qw(uniq);

my ($current_path, $image_dir,$work_dir,$runlist,$ch_runlist,$in_folder,$out_folder);
my ($channel_comma_list,$channel_comma_list_2,$mdt_contrast,$space_string,$current_label_space,$label_atlas,$label_path);
my (@array_of_runnos,@channel_array);
#my ($predictor_id); # SAVE FOR LAST ROUND OF LABEL STATS CODE
my @jobs=();
my (%go_hash,%go_mask,%results_dir_hash,%work_dir_hash);
my $log_msg='';
my $skip=0;
my $go = 1;
my $job;
my $PM_code = 65;

my $pipe_home = "/home/rja20/cluster_code/workstation_code/analysis/vbm_pipe/";
my $matlab_path = "/cm/shared/apps/MATLAB/R2015b/";  #Need to make this more general, i.e. look somewhere else for the proper and/or current version.
my $compilation_date = "20170616_2204";
my $write_individual_stats_executable_path = "${pipe_home}label_stats_executables/write_individual_stats_executable/${compilation_date}/run_write_individual_stats_exec.sh"; 
my $write_rat_report_executable_path = '/home/rja20/cluster_code/workstation_code/analysis/vbm_pipe/label_stats_executables/write_rat_report_executable/20171013_1038/run_write_rat_report_exec.sh';

#if (! defined $valid_formats_string) {$valid_formats_string = 'hdr|img|nii';}

#if (! defined $dims) {$dims = 3;}

# ------------------
sub  calculate_individual_label_statistics_vbm {
# ------------------
 
    ($current_label_space) = @_;
    my $start_time = time;
     calculate_individual_label_statistics_Runtime_check();

    
    foreach my $runno (@array_of_runnos) {
	$go = $go_hash{$runno};
	if ($go) {
	    ($job) = calculate_label_statistics($runno);

	    if ($job) {
		push(@jobs,$job);
	    }
	} 
    }

    my $species = $Hf->get_value('U_species_m00');
    if ($species =~ /rat/) {
	foreach my $runno (@array_of_runnos) {
	    $go = $go_hash{$runno};
	    if ($go) {
		($job) = write_rat_report($runno);
		
		if ($job) {
		    push(@jobs,$job);
		}
	    } 
	}
    }

    if (cluster_check() && (scalar(@jobs)>0)) {
	my $interval = 2;
	my $verbose = 1;
	my $done_waiting = cluster_wait_for_jobs($interval,$verbose,@jobs);
	
	if ($done_waiting) {
	    print STDOUT  "  ${label_space} label statistics has been calculated for all runnos; moving on to next step.\n";
	}
    }
    my $case = 2;
    my ($dummy,$error_message)=calculate_individual_label_statistics_Output_check($case);

    my $real_time = write_stats_for_pm($PM_code,$Hf,$start_time,@jobs);
    print "$PM took ${real_time} seconds to complete.\n";

    @jobs=(); # Clear out the job list, since it will remember everything if this module is used iteratively.

    my $write_path_for_Hf = "${current_path}/${label_atlas}_${space_string}_temp.headfile";

    if ($error_message ne '') {
	error_out("${error_message}",0);
    } else {
	$Hf->write_headfile($write_path_for_Hf);
    }
      

}


# ------------------
sub calculate_individual_label_statistics_Output_check {
# ------------------

    my ($case) = @_;
    my $message_prefix ='';
    #my ($file_1);
    my @file_array=();

    my $existing_files_message = '';
    my $missing_files_message = '';

    
    if ($case == 1) {
	$message_prefix = "  Complete label statistics have been found for the following runnos and will not be re-calculated:\n";
    } elsif ($case == 2) {
	 $message_prefix = "  Unable to properly scalculate label statistics for the following runnos:\n";
    }   # For Init_check, we could just add the appropriate cases.

    foreach my $runno (@array_of_runnos) {
	#print "$runno\n\n";
	my $sub_existing_files_message='';
	my $sub_missing_files_message='';
	
	my $file_1 = "${current_path}/${runno}_${label_atlas}_labels_in_${space_string}_space_stats.txt" ;
#	print "${file_1}\n\n\n";
	if (data_double_check($file_1)) {
	    $go_hash{$runno}=1;
	    push(@file_array,$file_1);
	    $sub_missing_files_message = $sub_missing_files_message."\t$runno";
	} else {
	    my $header_string = `head -1 ${file_1}`;
	    my @c_array_1 = split('=',$header_string);
	    my @completed_contrasts = split(',',$c_array_1[1]);
	    my $completed_contrasts_string = join(' ',@completed_contrasts);
	    my $missing_contrasts = 0;
	    foreach my $ch (@channel_array) {
		if (! $missing_contrasts) {
		    if ($completed_contrasts_string !~ /($ch)/) {
			$missing_contrasts = 1;
		    }
		}
	    }
	    if ($missing_contrasts) {
		$go_hash{$runno}=1;
		push(@file_array,$file_1);
		$sub_missing_files_message = $sub_missing_files_message."\t$runno";
	    } else {
		$go_hash{$runno}=0;
		$sub_existing_files_message = $sub_existing_files_message."\t$runno";
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
sub calculate_label_statistics {
# ------------------
    my ($runno) = @_;
    my $input_labels = "${work_dir}/${mdt_contrast}_labels_warp_${runno}.nii.gz";

    #my $exec_args_ ="${runno} {contrast} ${average_mask} ${input_path} ${contrast_path} ${group_1_name} ${group_2_name} ${group_1_files} ${group_2_files}";# Save for part 3..
    my $exec_args ="${runno} ${input_labels} ${channel_comma_list_2} ${image_dir} ${current_path} ${space_string} ${label_atlas}";

    my $go_message = "$PM: Calculating individual label statistics for runno: ${runno}\n" ;
    my $stop_message = "$PM: Failed to properly calculate individual label statistics for runno: ${runno} \n" ;
    
    my @test=(0);
    if (defined $reservation) {
	@test =(0,$reservation);
    }
    my $mem_request = '10000';
    my $jid = 0;
    if (cluster_check) {
	my $go =1;	    
#	my $cmd = $pairwise_cmd.$rename_cmd;
	my $cmd = "${write_individual_stats_executable_path} ${matlab_path} ${exec_args}";
	
	my $home_path = $current_path;
	my $Id= "${runno}_calculate_individual_label_statistics";
	my $verbose = 2; # Will print log only for work done.
	$jid = cluster_exec($go,$go_message , $cmd ,$home_path,$Id,$verbose,$mem_request,@test);     
	if (! $jid) {
	    error_out($stop_message);
	} else {
	    return($jid);
	}
    }
} 


# ------------------
sub write_rat_report {
# ------------------
    my ($runno) = @_;
    my $input_labels = "${work_dir}/${mdt_contrast}_labels_warp_${runno}.nii.gz";
    my $spec_id = $Hf->get_value('U_specid');
    my $project_id = $Hf->get_value('project_id');

    #my $exec_args_ ="${runno} {contrast} ${average_mask} ${input_path} ${contrast_path} ${group_1_name} ${group_2_name} ${group_1_files} ${group_2_files}";# Save for part 3..
    my $exec_args ="${runno} ${input_labels} 'e1,rd,fa' ${image_dir} ${current_path} ${project_id} 'Rat' ${spec_id}";

    my $go_message = "$PM: Writing rat report for runno: ${runno}\n" ;
    my $stop_message = "$PM: Failed to properly write rat report for runno: ${runno} \n" ;
    
    my @test=(0);
    if (defined $reservation) {
	@test =(0,$reservation);
    }
    my $mem_request = '10000';
    my $jid = 0;
    if (cluster_check) {
	my $go =1;	    
#	my $cmd = $pairwise_cmd.$rename_cmd;
	my $cmd = "${write_rat_report_executable_path} ${matlab_path} ${exec_args}";
	
	my $home_path = $current_path;
	my $Id= "${runno}_write_rat_report";
	my $verbose = 2; # Will print log only for work done.
	$jid = cluster_exec($go,$go_message , $cmd ,$home_path,$Id,$verbose,$mem_request,@test);     
	if (! $jid) {
	    error_out($stop_message);
	} else {
	    return($jid);
	}
    }
} 



# ------------------
sub  calculate_individual_label_statistics_Init_check {
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
sub  calculate_individual_label_statistics_Runtime_check {
# ------------------
    
    $mdt_contrast = $Hf->get_value('mdt_contrast');
    $label_atlas = $Hf->get_value('label_atlas_name');

    my $msg;
    if (! defined $current_label_space) {
	$msg =  "\$current_label_space not explicitly defined. Checking Headfile...";
	$current_label_space = $Hf->get_value('label_space');
    } else {
	$msg = "current_label_space has been explicitly set to: ${current_label_space}";
    }
    printd(35,$msg);    


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

    $label_path = $Hf->get_value('labels_dir');
    my $label_refname = $Hf->get_value('label_refname');
    my $intermediary_path = "${label_path}/${current_label_space}_${label_refname}_space";
    $image_dir = "${intermediary_path}/images/";
    $work_dir="${intermediary_path}/${label_atlas}/";

    my $stat_path = "${work_dir}/stats/";
    if (! -e $stat_path) {
	mkdir ($stat_path,$permissions);
    }
    $current_path = "${stat_path}/individual_label_statistics/";
    if (! -e $current_path) {
	mkdir ($current_path,$permissions);
    }


    my $runlist = $Hf->get_value('all_groups_comma_list');
    if ($runlist eq 'NO_KEY') {
	$runlist = $Hf->get_value('complete_comma_list');
    }

    @array_of_runnos = split(',',$runlist);
 

    # $predictor_id = $Hf->get_value('predictor_id'); # SAVE THIS FOR PART TRES OF LABEL STATS! REMOVE OTHERWISE!
    # if ($predictor_id eq 'NO_KEY') {
    # 	$group_1_name = 'control';
    # 	$group_2_name = 'treated';
	
    # } else {	
    # 	if ($predictor_id =~ /([^_]+)_(''|vs_|VS_|Vs_){1}([^_]+)/) {
    # 	    $group_1_name = $1;
    # 	    if (($3 ne '') || (defined $3)) {
    # 		$group_2_name = $3;
    # 	    } else {
    # 		$group_2_name = 'others';
    # 	    }
    # 	}
    # }

    # my $group_1_runnos = $Hf->get_value('group_1_runnos');
    # if ($group_1_runnos eq 'NO_KEY') {
    # 	$group_1_runnos = $Hf->get_value('control_comma_list');
    # }
    # @group_1_runnos = split(',',$group_1_runnos);

    # my $group_2_runnos = $Hf->get_value('group_2_runnos');
    # if ($group_2_runnos eq 'NO_KEY'){ 
    # 	$group_2_runnos = $Hf->get_value('compare_comma_list');
    # }
    # @group_2_runnos = split(',',$group_2_runnos);

 
    $ch_runlist = $Hf->get_value('channel_comma_list');
    my @initial_channel_array = split(',',$ch_runlist);

    foreach my $contrast (@initial_channel_array) {
	if ($contrast !~ /^(ajax|jac|nii4D)/) {
	    push(@channel_array,$contrast);
	}
    }
    @channel_array=uniq(@channel_array);

    $channel_comma_list_2 = join(',',@channel_array);

    my $case = 1;
    my ($dummy,$skip_message)=calculate_individual_label_statistics_Output_check($case);
 
    if ($skip_message ne '') {
	print "${skip_message}";
    }


}


1;

