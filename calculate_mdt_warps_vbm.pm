#!/usr/local/pipeline-link/perl
# calculate_mdt_warps_vbm.pm 





my $PM = "calculate_mdt_warps_vbm.pm";
my $VERSION = "2014/12/02";
my $NAME = "Calculation of warps to/from the Minimum Deformation Template.";
my $DESC = "ants";

use strict;
use warnings;
no warnings qw(uninitialized bareword);

use vars qw($Hf $BADEXIT $GOODEXIT $forward_xform_hash $inverse_xform_hash $test_mode $intermediate_affine $permissions $broken);
require Headfile;
require pipeline_utilities;

use List::Util qw(max);


my $do_inverse_bool = 0;
my ($atlas,$rigid_contrast,$mdt_contrast, $runlist,$work_path,$rigid_path,$current_path,$write_path_for_Hf);
my ($xform_code,$xform_path,$xform_suffix,$domain_dir,$domain_path,$inputs_dir);
my ($mdt_path,$pairwise_path,$template_match);

my ($template_predictor,$template_path,$template_name);

my (@array_of_runnos,@sorted_runnos,@jobs,@files_to_create,@files_needed);
my (%go_hash);
#my (%convert_hash);
my $go = 1;
my $job;
my $current_checkpoint = 1; # Bound to change! Change here!
my $number_of_template_runnos;
my $log_msg;

# my @parents = qw(pairwise_reg_vbm);
# my @children = qw (apply_mdt_warps_vbm);


# ------------------
sub calculate_mdt_warps_vbm {  # Main code
# ------------------
    my ($direction) = @_;
    my $start_time = time;

    calculate_mdt_warps_vbm_Runtime_check($direction);

    foreach my $runno (@array_of_runnos) {
	$go = $go_hash{$runno};
	if ($go) {
	    ($job,$xform_path) = calculate_average_mdt_warp($runno,$direction);
	   
	    if ($job > 1) {
		push(@jobs,$job);
	    }
	} else {
	    if ($direction eq 'f') {
		$xform_path = "${current_path}/${runno}_to_MDT_warp.nii.gz"; #added '.gz' 2 September 2015
	    } else {
		$xform_path = "${current_path}/MDT_to_${runno}_warp.nii.gz"; #added '.gz' 2 September 2015
	    }
	}
	if ($direction eq 'f') {
	    headfile_list_handler($Hf,"mdt_forward_xforms_${runno}",$xform_path,0); # added 'mdt_', 15 June 2016
	} else {
	    headfile_list_handler($Hf,"mdt_inverse_xforms_${runno}",$xform_path,1); # added 'mdt_', 15 June 2016
	}
    }
     

    if (cluster_check()) {
	my $interval = 2;
	my $verbose = 1;
	my $done_waiting = cluster_wait_for_jobs($interval,$verbose,@jobs);
	
	if ($done_waiting) {
	    print STDOUT  "  All warps-to-MDT-space calculation jobs have completed; moving on to next step.\n";
	}
    }
    my $case = 2;
    my ($dummy,$error_message)=calculate_mdt_warps_Output_check($case,$direction);
    $Hf->write_headfile($write_path_for_Hf);
    `chmod 777 ${write_path_for_Hf}`;
    

    my $real_time = write_stats_for_pm($PM,$Hf,$start_time,@jobs);
    print "$PM took ${real_time} seconds to complete.\n";

    if ($error_message ne '') {
	error_out("${error_message}",0);
    } else {
	symbolic_link_cleanup($pairwise_path,$PM);
    }
    
}



# ------------------
sub calculate_mdt_warps_Output_check {
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
  	$message_prefix = "  ${dir_string} MDT warp(s) already exist(s) for the following runno(s) and will not be recalculated:\n";
     } elsif ($case == 2) {
 	$message_prefix = "  Unable to create ${dir_string} MDT warp(s) for the following runno(s):\n";
     }   # For Init_check, we could just add the appropriate cases.

     
     my $existing_files_message = '';
     my $missing_files_message = '';
     
     foreach my $runno (@sorted_runnos) {
	 if ($direction eq 'f' ) {
	     $out_file = "${current_path}/${runno}_to_MDT_warp.nii.gz"; #Added asterisk in hopes of catching .gz 
	 } elsif ($direction eq 'i') {
	     $out_file = "${current_path}/MDT_to_${runno}_warp.nii.gz"; #Added asterisk in hopes of catching .gz 
	 }
	 if (data_double_check($out_file)) {
	     if ($out_file =~ s/\.gz$//) {
		 if (data_double_check($out_file)) {
		     $go_hash{$runno}=1;
		     #$convert_hash{$runno}=0;
		     push(@file_array,$out_file);
		     #push(@files_to_create,$full_file); # This code may be activated for use with Init_check and generating lists of work to be done.
		     $missing_files_message = $missing_files_message."\t$runno\n";
		 } else {
		     `gzip ${out_file}`;
		     $go_hash{$runno}=0;
		     #$convert_hash{$runno}=1;
		     $existing_files_message = $existing_files_message."\t$runno\n";
		 }
	     }
	 } else {
	     $go_hash{$runno}=0;
	     #$convert_hash{$runno}=0;
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

}


# ------------------
sub calculate_average_mdt_warp {
# ------------------
    my ($runno,$direction) = @_;
    my ($fixed,$moving,$cmd);
    my $out_file = '';
    my $dir_string = '';
    if ($direction eq 'f') {
	$out_file = "${current_path}/${runno}_to_MDT_warp.nii.gz"; #Added ".gz" 2 September 2015
	$dir_string = 'forward';
    } else {
	$out_file = "${current_path}/MDT_to_${runno}_warp.nii.gz";  #Added ".gz" 2 September 2015
	$dir_string = 'inverse';
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

#	if ($fixed ne $moving) {  # Fixing previous error of self/identity warp omission!
	if ($broken && ($fixed eq $moving)) {
	    $cmd=$cmd;
	} else {
	    $cmd = $cmd." ${pairwise_path}/${moving}_to_${fixed}_warp.nii.gz";
	}

#	}
    }
 

    my $jid = 0;
    if (cluster_check()) {
	my $home_path = $current_path;
	my $Id= "${runno}_calculate_${dir_string}_MDT_warp";
	my $verbose = 2; # Will print log only for work done.
	$jid = cluster_exec($go, "$PM: create ${dir_string} MDT warp for ${runno}", $cmd ,$home_path,$Id,$verbose);     
	if (! $jid) {
	    error_out("$PM: could not create ${dir_string} MDT warp for  ${runno}:\n${cmd}\n");
	}
    } else {
	my @cmds = ($cmd);
	if (! execute($go, "$PM: create ${dir_string} MDT warp for ${runno}", @cmds) ) {
	    error_out("$PM: could not create ${dir_string} MDT warp for  ${runno}:\n${cmd}\n");
	}
    }

    if ((data_double_check($out_file)) && ($jid == 0)) {
	error_out("$PM: missing ${dir_string} MDT warp results for ${runno}: ${out_file}");
    }
    print "** $PM created ${out_file}\n";
  
    return($jid,$out_file);
}


# ------------------
sub calculate_mdt_warps_vbm_Init_check {
# ------------------
    my $init_error_msg='';
    my $message_prefix="$PM initialization check:\n";

    $template_predictor = $Hf->get_value('template_predictor');
    
    my $default_switch=0;
    if (($template_predictor eq 'NO_KEY') ||($template_predictor eq 'UNDEFINED_VALUE'))  {
	my $predictor_id = $Hf->get_value('predictor_id');
	if (($predictor_id ne 'NO_KEY') && ($predictor_id ne 'UNDEFINED_VALUE')) {
	   # print "Predictor id = ${predictor_id}\n";
	    if ($predictor_id =~ s/([_]+.*)//) {
		$template_predictor = $predictor_id;
	    } else {
		$template_predictor = "NoNameYet";
		$default_switch = 1;
	    }
	} else {
	    $template_predictor = "NoNameYet";
	    $default_switch = 1;
	}
    }
    $Hf->set_value('template_predictor',$template_predictor);
    $log_msg = $log_msg."\tTemplate predictor will be referred to as: ${template_predictor}.\n";
    if ($default_switch) {
	$log_msg = $log_msg."\tThis is the default value, since it was not otherwise specified.\n";
    }



    if ($log_msg ne '') {
	log_info("${message_prefix}${log_msg}");
    }

    if ($init_error_msg ne '') {
	$init_error_msg = $message_prefix.$init_error_msg;
    }
    
    return($init_error_msg);
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
   # $predictor_id = $Hf->get_value('predictor_id');
   # $predictor_path = $Hf->get_value('predictor_work_dir');

    $template_predictor = $Hf->get_value('template_predictor');
    $template_path = $Hf->get_value('template_work_dir');
   
    $template_name = $Hf->get_value('template_name');

#    $runlist = $Hf->get_value('control_comma_list');
    $runlist = $Hf->get_value('template_comma_list');

    if ($runlist eq 'NO_KEY') {
	$runlist = $Hf->get_value('control_comma_list');
    }

    @array_of_runnos = split(',',$runlist);
    @sorted_runnos=sort(@array_of_runnos);
    $number_of_template_runnos = $#sorted_runnos + 1;
#

    # if (($template_predictor eq 'NO_KEY') ||($template_predictor eq 'UNDEFINED'))  {
    # 	my $predictor_id = $Hf->get_value('predictor_id');
    # 	if (($predictor_id ne 'NO_KEY') && ($predictor_id ne 'UNDEFINED')) {
    # 	    if ($predictor_id =~ s/([_]+.*)//) {
    # 		$template_predictor = $predictor_id;
    # 	    } else {
    # 		$template_predictor = "NoNameYet";
    # 	    }
    # 	} else {
    # 	    $template_predictor = "NoNameYet";
    # 	}
    # }
    # $Hf->set_value('template_predictor',$template_predictor);

    if ($template_name eq 'NO_KEY') {
	$template_name = "${mdt_contrast}MDT_${template_predictor}_n${number_of_template_runnos}";
	$Hf->set_value('template_name',$template_name);
    }

    $current_path = $Hf->get_value('mdt_diffeo_path');
 
#    if ($predictor_path eq 'NO_KEY') {
#	$predictor_path = "${mdt_path}/P_${predictor_id}"; 
# 	$Hf->set_value('predictor_work_dir',$predictor_path);
#    }

   if ($template_path eq 'NO_KEY') {
       my $broken_string = '';
       if ($broken) { $broken_string = "Broken_";}
	$template_path = "${mdt_path}/${broken_string}${template_name}"; 
	$Hf->set_value('template_work_dir',$template_path);
   }

    if ($current_path eq 'NO_KEY') {
#	$current_path = "${predictor_path}/MDT_diffeo";
	$current_path = "${template_path}/MDT_diffeo";
	$Hf->set_value('mdt_diffeo_path',$current_path);
    }
 
   print "Should run checkpoint here!\n\n";
    my $checkpoint = $Hf->get_value('last_headfile_checkpoint'); # For now, this is the first checkpoint, but that will probably evolve.
    my $previous_checkpoint = $current_checkpoint - 1;
   
    # if (($checkpoint eq "NO_KEY") || ($checkpoint <= $previous_checkpoint)) {
    if (($checkpoint eq "NO_KEY") || ($checkpoint < $previous_checkpoint)) {
	$template_match = 0;
	my $temp_template_path;
	my $temp_current_path;
	my @alphabet = qw(a b c d e f g h j k m n p q r s t u v w x y z); # Don't want to use i,l,o (I,L,O)
	@alphabet = ('',@alphabet);

	my $include = 0; # We will exclude certain keys from headfile comparison. Exclude key list getting bloated...may need to switch to include.
	my @excluded_keys =qw(affine_identity_matrix
                              affine_target_image
                              all_groups_comma_list
                              compare_comma_list  
                              complete_comma_list
                              channel_comma_list
                              create_labels
                              group_1_runnos
                              group_2_runnos
                              label_atlas_dir
                              label_atlas_name
                              label_atlas_path
                              label_reference_path
                              label_reference_space
                              label_refname
                              label_refspace
                              label_refspace_folder
                              label_space
                              forward_xforms 
                              inverse_xforms
                              last_headfile_checkpoint
                              mdt_diffeo_path
                              number_of_nodes_used
                              predictor_id
                              rd_channel_added
                              smoothing_comma_list
                              stats_file
                              template_name
                              template_work_dir
                              threshold_hash_ref
                              vba_analysis_software
                              vba_contrast_comma_list ); # affine_target_image will need to be removed from this list once we fully support it.


	for (my $i=0; $template_match== 0; $i++) {
	    my $letter = $alphabet[$i];
	    $temp_template_path = $template_path.$letter ;
	    $temp_current_path = $current_path;
	    if ($temp_current_path =~ s/(\/[A-Za-z_]+[\/]?)$/${letter}$1/) {
		
		
		my $current_tempHf = find_temp_headfile_pointer($temp_current_path);
		my $Hf_comp = '';
		
		if ($current_tempHf ne "0"){# numeric compare vs string?
		    $Hf_comp = compare_headfiles($Hf,$current_tempHf,$include,@excluded_keys);
		    
		    if ($Hf_comp eq '') {
			$template_match = 1;
		    } else {
			print " $PM: ${Hf_comp}\n"; # Is this the right place for this?
		    }
		} else {
		    $template_match = 1;
		}
	    }
	    if ($template_match) {
		$template_name = $template_name.$letter; 
		$template_path = $temp_template_path;
		$current_path = $temp_current_path;   
		print " At least one ambiguously different MDT detected, current MDT is: ${template_name}.\n";
	    }
	}
    }

    print "Current template_path = ${template_path}\n\n";
    if (! -e $template_path) {
	mkdir ($template_path,$permissions);
    }
    
    $Hf->set_value('mdt_diffeo_path',$current_path);
    $Hf->set_value('template_work_dir',$template_path);
    $Hf->set_value('template_name',$template_name);
    $Hf->set_value('last_headfile_checkpoint',$current_checkpoint);

    $write_path_for_Hf = "${current_path}/${template_name}_temp.headfile";
    # $write_path_for_Hf = "${current_path}/${predictor_id}_temp.headfile";


    # if (1) {  ####### if (0) is only a temporary measure!!!
    # if (($checkpoint eq "NO_KEY") || ($checkpoint <= $previous_checkpoint)) {
    # 	my $current_tempHf = find_temp_headfile_pointer($current_path);
    # 	$work_done = 0;
    # 	my $Hf_comp = '';
    # 	my $include = 0; # We will exclude certain keys from headfile comparison. Exclude key list getting bloated...may need to switch to include.
    # 	my @excluded_keys =qw(affine_identity_matrix
    #                           compare_comma_list  
    #                           complete_comma_list
    #                           channel_comma_list
    #                           create_labels
    #                           label_atlas_dir
    #                           label_atlas_name
    #                           label_atlas_path
    #                           label_space
    #                           forward_xforms 
    #                           inverse_xforms
    #                           last_headfile_checkpoint
    #                           threshold_hash_ref ); 
 
    # 	if ($current_tempHf ne "0"){# numeric compare vs string?
    # 	    $Hf_comp = compare_headfiles($Hf,$current_tempHf,$include,@excluded_keys);

    # 	    if ($Hf_comp eq '') {
    # 		$work_done = 1;
    # 	    }
    # 	}
    
    # 	if (($Hf_comp ne '') && ($current_tempHf == 0)) { # Move most recent (different) work to backup folder.	
    # 	    my $new_backup;
    # 	    my $existence=1;

    # 	    for (my $i=1; $existence== 1; $i++) {
    # 		if (! -e "${predictor_path}_b$i") {
    # 		    $existence = 0;
    # 		}
    # 		$new_backup = "${predictor_path}_b$i";
    # 	    }
	
    # 	    print " $PM: ${Hf_comp}\n";
    # 	    print " Will move existing work to backup folder: ${new_backup}.\n";
    # 	    rename($predictor_path,$new_backup);
    # 	}
	
    # 	if ((! -e $predictor_path) | ($current_tempHf eq "0")) {
    # 	    mkdir ($predictor_path,$permissions);
    # 	}
    # 	$Hf->set_value('last_headfile_checkpoint',$current_checkpoint);
    # }
    
    if (! -e $current_path) {
	mkdir ($current_path,$permissions);
    }


    my $case = 1;
    my ($dummy,$skip_message)=calculate_mdt_warps_Output_check($case,$direction);

    if ($skip_message ne '') {
	print "${skip_message}";
    }

# check for needed input files to produce output files which need to be produced in this step?

}

1;
