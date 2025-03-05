#!/usr/bin/env perl
# iterative_calculate_mdt_warps_vbm.pm 

my $PM = "iterative_calculate_mdt_warps_vbm.pm";
my $VERSION = "2016/11/10";
my $NAME = "Calculation of the warp to the Minimum Deformation Template.";
my $DESC = "ants";

use strict;
use warnings;
#no warnings qw(uninitialized bareword);

#use vars used to be here
require Headfile;
require SAMBA_pipeline_utilities;

use List::Util qw(max);

my ($runlist,$work_path,$current_path,$write_path_for_Hf);
my ($mdt_path,$template_match);
my ($template_predictor,$template_path,$template_name);
my (@array_of_runnos,@sorted_runnos,@files_to_create);
my @jobs=();
my (%go_hash);
my $go = 1;
my $job;
my $log_msg="";
my ($update_step_size,$update_string);



if (! defined $dims) {$dims = 3;}

# ------------------
sub iterative_calculate_mdt_warps_vbm {  # Main code
# ------------------
    #my ($direction) = @_;
    my $start_time = time;

    iterative_calculate_mdt_warps_vbm_Runtime_check();

    my $last_update_warp;
    
    $go = $go_hash{'shape_update_warp'};
    my $do_average_warps = $go_hash{'average_warp'};
    if ($go) {
	($job,$last_update_warp) = iterative_calculate_average_mdt_warp($do_average_warps);
	    if ($job) {
		push(@jobs,$job);
	    }
    } else {
        $last_update_warp = "${current_path}/shape_update_warp_${update_string}.nii.gz";
    }

    if (cluster_check() && (scalar @jobs) ) {
		my $interval = 2;
		my $verbose = 1;
		my $done_waiting = cluster_wait_for_jobs($interval,$verbose,@jobs);
		
		if ($done_waiting) {
			print STDOUT  "  Update Warp has been created; moving on to next step.\n";
		}
    }


    $Hf->set_value('last_update_warp',$last_update_warp);

    my $case = 2;
    my ($error_message)=iterative_calculate_mdt_warps_Output_check($case);
    $Hf->write_headfile($write_path_for_Hf);
    `chmod 777 ${write_path_for_Hf}`;

    my $real_time = vbm_write_stats_for_pm($PM,$Hf,$start_time,@jobs);
    print "$PM took ${real_time} seconds to complete.\n";

    @jobs=(); # Clear out the job list, since it will remember everything when this module is used iteratively.

    if ($error_message ne '') {
		error_out("${error_message}",0);
    }
}



# ------------------
sub iterative_calculate_mdt_warps_Output_check {
# ------------------
     my ($case) = @_;
     my $message_prefix ='';
     my ($out_file_1,$out_file_2,$dir_string);
        $dir_string = 'forward';

     my @file_array=();
     if ($case == 1) {
		$message_prefix = "Fractional average ${dir_string} warp to current template already exists and will not be recalculated:\n";
     } elsif ($case == 2) {
		$message_prefix = "  Unable to create fractional average ${dir_string} warp to current template:\n";
     }   # For Init_check, we could just add the appropriate cases.

     
     my $existing_files_message = '';
     my $missing_files_message = '';
     $out_file_1 = "${current_path}/shape_update_warp_${update_string}.nii.gz"; 
     $out_file_2 = "${current_path}/average_of_to_template_warps.nii.gz";  


	  # We seem to be checking too quickly for these files...always says not there immediately after creation.
     if (data_double_check($out_file_1)) {
		if ($case == 2) {
			sleep(10);
			`ls -arlth ${current_path} | tail -3 `;
		}
		 if (data_double_check($out_file_1)) {
			 $go_hash{'shape_update_warp'}=1;
			 push(@file_array,$out_file_1);
			 #push(@files_to_create,$full_file); # This code may be activated for use with Init_check and generating lists of work to be done.
			 $missing_files_message = $missing_files_message."\t${out_file_1}\n";
			 if (data_double_check($out_file_2)) {
				 $go_hash{'average_warp'}=1;
				 push(@file_array,$out_file_2);
				 #push(@files_to_create,$full_file); # This code may be activated for use with Init_check and generating lists of work to be done.
				 $missing_files_message = $missing_files_message."\t${out_file_2}\n";
			 } else {
				 $go_hash{'average_warp'}=0;
				 $existing_files_message = $existing_files_message."\t${out_file_2}\n";
			 }
			 
		 } else {
			 $go_hash{'shape_update_warp'}=0;
			 $go_hash{'average_warp'}=0;
			 $existing_files_message = $existing_files_message."\t${out_file_1}\n";
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
     
     return($error_msg);
 }

# ------------------
sub iterative_calculate_mdt_warps_Input_check {
# ------------------

}


# ------------------
sub iterative_calculate_average_mdt_warp {
# ------------------
    my ($average_warps) = @_;
    my $fraction_cmd;
    my ($out_file_1,$out_file_2);
    my $dir_string = '';
    $dir_string = 'forward';

    $out_file_1 = "${current_path}/shape_update_warp_${update_string}.nii.gz"; 
    $out_file_2 = "${current_path}/average_of_to_template_warps.nii.gz";  


    my $avg_cmd = '';
    my $clean_cmd = '';
    if ($average_warps) {
		$avg_cmd =" AverageImages ${dims} ${out_file_2} 0";
		foreach my $runno (@sorted_runnos) {
			$avg_cmd = $avg_cmd." ${current_path}/${runno}_to_MDT_warp.nii.gz";
		}
		$avg_cmd=$avg_cmd.";\n";
		# $clean_cmd = "rm $out_file_2;\n"; May want to keep around if trying adjustable gradient step size
    }

    $fraction_cmd = "MultiplyImages ${dims} ${out_file_2} -${update_step_size} ${out_file_1};\n";

    my $cmd = $avg_cmd.$fraction_cmd.$clean_cmd;
    
    my $jid = 0;

    my @test=0;
    if (defined $reservation) {
	@test =(0,$reservation);
    }

    my $mem_request = 60000;  # Added 23 November 2016,  Will need to make this smarter later.

    if (cluster_check()) {
		my $home_path = $current_path;
		my $Id= "create_update_warp";
		my $verbose = 2; # Will print log only for work done.
		$jid = cluster_exec($go, "$PM: create update warp}", $cmd ,$home_path,$Id,$verbose,$mem_request,@test);     
		if (not $jid) {
			error_out("$PM: could not create update warp:\n${cmd}\n");
		}
    } else {
		my @cmds = ($cmd);
		if (! execute($go, "$PM: create update warp", @cmds) ) {
			error_out("$PM: could not create update warp:\n${cmd}\n");
		}
    }

    if ((data_double_check($out_file_1)) && (not $jid)) {
		error_out("$PM: missing update warp: ${out_file_1}");
    }
    print "** $PM expected output: ${out_file_1}\n";
  
    return($jid,$out_file_1);
}


# ------------------
sub iterative_calculate_mdt_warps_vbm_Init_check {
# ------------------
    my $init_error_msg='';
    my $message_prefix="$PM initialization check:\n";

    $update_step_size = $Hf->get_value('update_step_size');
    if (($update_step_size eq ('' || 'NO_KEY')) || ($update_step_size > 0.25)) {
	$update_step_size =0.25;
	$Hf->set_value('update_step_size',$update_step_size);
	$log_msg = $log_msg."\tNo step size specified for shape update during iterative template construction; using default values of ${update_step_size}.\n";
    }


    if (defined $log_msg) {
        log_info("${message_prefix}${log_msg}");
    }

    if ($init_error_msg ne '') {
	$init_error_msg = $message_prefix.$init_error_msg;
    }
    
    return($init_error_msg);
}


# ------------------
sub iterative_calculate_mdt_warps_vbm_Runtime_check {
# ------------------
 
# # Set up work
    
    $update_step_size = $Hf->get_value('update_step_size');
    $update_string = `echo ${update_step_size} | tr '.' 'p' `;
    chomp($update_string);

    $mdt_path = $Hf->get_value('mdt_work_dir');

    $template_path = $Hf->get_value('template_work_dir');
   
    $template_name = $Hf->get_value('template_name');

    $runlist = $Hf->get_value('template_comma_list');

    if ($runlist eq 'NO_KEY') { # Backwards compatibility -- can remove in future
	$runlist = $Hf->get_value('control_comma_list');
    }

    if ($runlist eq 'EMPTY_VALUE') {
	@array_of_runnos = ();
    } else {
	@array_of_runnos = split(',',$runlist);
    }


    @sorted_runnos=sort(@array_of_runnos);
    #$number_of_template_runnos = $#sorted_runnos + 1;

    #$current_path = $Hf->get_value('mdt_diffeo_path');

    #if ($current_path eq 'NO_KEY') {
    $current_path = "${template_path}/MDT_diffeo";
    if (! -e $current_path) {
	mkdir ($current_path,$permissions);
    }
    $Hf->set_value('mdt_diffeo_path',$current_path);
    
    #}

    $write_path_for_Hf = "${current_path}/${template_name}_temp.headfile";

    my $case = 1;
    my ($skip_message)=iterative_calculate_mdt_warps_Output_check($case);

    if ($skip_message ne '') {
	print "${skip_message}";
    }

# check for needed input files to produce output files which need to be produced in this step?

}

1;
