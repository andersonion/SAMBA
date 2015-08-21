#!/usr/local/pipeline-link/perl
# create_rd_from_e2_and_e3_vbm.pm 





my $PM = "create_rd_from_e2_and_e3_vbm.pm";
my $VERSION = "2015/02/25";
my $NAME = "Creation of rd channel/contrast via averaging e2 and e3.";
my $DESC = "ants";

use strict;
use warnings;
no warnings qw(uninitialized bareword);

use vars qw($Hf $BADEXIT $GOODEXIT);
require Headfile;
require pipeline_utilities;


my ($channel_comma_list,$runlist,$work_path,$current_path,$inputs_dir);
my (@array_of_runnos,@jobs,@files_to_create,@files_needed);
my (%go_hash);
my $create_rd;
my $go = 1;
my $job;

# ------------------
sub create_rd_from_e2_and_e3_vbm {  # Main code
# ------------------
    my $start_time = time;
    create_rd_from_e2_and_e3_vbm_Runtime_check();
    if ($create_rd) {
	foreach my $runno (@array_of_runnos) {
	    $go = $go_hash{$runno};
	    if ($go) {
		($job) =  average_e2_and_e3_images($runno);
		
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
		print STDOUT  "  Rd images have been created for all runnos; moving on to next step.\n";
	    }
	}
	my $case = 2;
	my ($dummy,$error_message)=create_rd_from_e2_and_e3_Output_check($case);


	my $real_time = write_stats_for_pm($PM,$Hf,$start_time,@jobs);
	print "$PM took ${real_time} seconds to complete.\n";
	
	if ($error_message ne '') {
	    error_out("${error_message}",0);
	} elsif ($create_rd) {
	    $channel_comma_list=$channel_comma_list.',rd';
	    $Hf->set_value('channel_comma_list',$channel_comma_list);
	    $Hf->set_value('rd_channel_added',1);    
	}
    }
    return($create_rd);
}



# ------------------
sub create_rd_from_e2_and_e3_Output_check {
# ------------------
     my ($case) = @_;
     my $message_prefix ='';
     my ($out_file);

     my @file_array=();
     if ($case == 1) {
  	$message_prefix = "  Rd images exist(s) for the following runno(s) and will not be recalculated:\n";
     } elsif ($case == 2) {
 	$message_prefix = "  Unable to create rd images for the following runno(s):\n";
     } 

     
     my $existing_files_message = '';
     my $missing_files_message = '';
 
     foreach my $runno (@array_of_runnos) {  
	my  $out_file =  get_nii_from_inputs($current_path,$runno,'e2'); 
	print "First out_file = ${out_file}\n";
	$out_file =~ s/_e2/_rd/;
	print "Second out file = ${out_file}\n";
	 if (data_double_check($out_file)) {
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
sub create_rd_from_e2_and_e3_Input_check {
# ------------------

}


# ------------------
sub average_e2_and_e3_images {
# ------------------
    my ($runno) = @_;
    my ($e2_file,$e3_file,$cmd);
    my  $out_file =  get_nii_from_inputs($current_path,$runno,'e2'); 
    $out_file =~ s/_e2/_rd/;
 
    $e2_file = get_nii_from_inputs($current_path,$runno,'e2'); 
    $e3_file = get_nii_from_inputs($current_path,$runno,'e3');

    $cmd =" AverageImages 3 ${out_file} 0 $e2_file $e3_file";

    my $go_message =  "$PM: create rd image for ${runno}";
    my $stop_message = "$PM: could not create rd image for ${runno}:\n${cmd}\n";

    my $jid = 0;
    if (cluster_check()) {
	my $home_path = $current_path;
	my $Id= "${runno}_create_rd_image";
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

    if ((data_double_check($out_file)) && ($jid == 0)) {
	error_out("$PM: missing rd image for ${runno}: ${out_file}");
    }
    print "** $PM created ${out_file}\n";
  
    return($jid);
}


# ------------------
sub create_rd_from_e2_and_e3_vbm_Init_check {
# ------------------

    return('');
}


# ------------------
sub create_rd_from_e2_and_e3_vbm_Runtime_check {
# ------------------
    
    $channel_comma_list = $Hf->get_value('channel_comma_list'); 
     
    if (($channel_comma_list =~ /[,]*e2[,]*/) && ($channel_comma_list =~ /[,]*e3[,]*/) && ($channel_comma_list !~ /[,]*rd[,]*/)) {
	$create_rd=1;
	$current_path = $Hf->get_value('preprocess_dir'); 
	# $current_path = $Hf->get_value('inputs_dir'); 

	$runlist = $Hf->get_value('complete_comma_list');
	@array_of_runnos = split(',',$runlist);

	my $case = 1;
	my ($dummy,$skip_message)=create_rd_from_e2_and_e3_Output_check($case);
	
	if ($skip_message ne '') {
	    print "${skip_message}";
	}
    }
}

1;
