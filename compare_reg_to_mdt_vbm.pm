#!/usr/local/pipeline-link/perl
# compare_reg_to_mdt_vbm.pm 

my $PM = "compare_reg_to_mdt_vbm.pm";
my $VERSION = "2014/12/02";
my $NAME = "Pairwise registration for Minimum Deformation Template calculation.";
my $DESC = "ants";

use strict;
use warnings;
no warnings qw(uninitialized);

use vars qw($Hf $BADEXIT $GOODEXIT  $test_mode $intermediate_affine $combined_rigid_and_affine $nodes $permissions);
require Headfile;
require pipeline_utilities;
#use PDL::Transform;

my ($atlas,$rigid_contrast,$mdt_contrast,$mdt_contrast_string,$mdt_contrast_2, $runlist,$work_path,$rigid_path,$mdt_path,$template_path,$median_images_path,$current_path);
my ($xform_code,$xform_path,$xform_suffix,$domain_dir,$domain_path,$inputs_dir);
my ($diffeo_metric,$diffeo_radius,$diffeo_shrink_factors,$diffeo_iterations,$diffeo_transform_parameters);
my ($diffeo_convergence_thresh,$diffeo_convergence_window,$diffeo_smoothing_sigmas,$diffeo_sampling_options);
my (@array_of_runnos,@sorted_runnos,@jobs,@files_to_create,@files_needed,@mdt_contrasts);
my (%go_hash);
my $go = 1;
my $job;
my $mem_request;
my $dims;
my $log_msg;
my $batch_folder;

my($warp_suffix,$inverse_suffix,$affine_suffix);
if (! $intermediate_affine) {
   $warp_suffix = "1Warp.nii.gz";
   $inverse_suffix = "1InverseWarp.nii.gz";
   $affine_suffix = "0GenericAffine.mat";
} else {
    $warp_suffix = "0Warp.nii.gz";
    $inverse_suffix = "0InverseWarp.nii.gz";
    $affine_suffix = "0GenericAffine.mat";
}

my $affine = 0;
my $expected_number_of_jobs=0;

#$test_mode=0;


# ------------------
sub compare_reg_to_mdt_vbm {  # Main code
# ------------------
    
    my ($type) = @_;
    if ($type eq "a") {
	$affine = 1;
    }
    my $start_time = time;

    compare_reg_to_mdt_vbm_Runtime_check();

   # my ($expected_number_of_jobs,$hash_errors) = hash_summation(\%go_hash);

    my $MDT_to_atlas_JobID = $Hf->get_value('MDT_to_atlas_JobID');
    if (($MDT_to_atlas_JobID ne 'NO_KEY') && ($MDT_to_atlas_JobID ne 'UNDEFINED_VALUE' )) {
	$expected_number_of_jobs++;
    }
 
    $mem_request = memory_estimator($expected_number_of_jobs,$nodes);    
 
    foreach my $runno (@array_of_runnos) {
	my ($f_xform_path,$i_xform_path);
	$go = $go_hash{$runno};
	if ($go) {
	    ($job,$f_xform_path,$i_xform_path) = reg_to_mdt($runno);
	    #	sleep(0.25);
	    if ($job > 1) {
		push(@jobs,$job);
	    }
	} else {
	    $f_xform_path = "${current_path}/${runno}_to_MDT_warp.nii.gz";
	    $i_xform_path = "${current_path}/MDT_to_${runno}_warp.nii.gz";
	}
	headfile_list_handler($Hf,"forward_xforms_${runno}",$f_xform_path,0);
	headfile_list_handler($Hf,"inverse_xforms_${runno}",$i_xform_path,1);
    }
    
    print "batch folder = ${batch_folder}\n\n";    
    if (cluster_check() && ($jobs[0] ne '')) {
	my $interval = 15;
	my $verbose = 1;
	my $done_waiting = cluster_wait_for_jobs($interval,$verbose,$batch_folder,@jobs);

	if ($done_waiting) {
	    print STDOUT  "  All pairwise diffeomorphic registration jobs have completed; moving on to next step.\n";
	}
    }
    my $case = 2;
    my ($dummy,$error_message)=compare_reg_to_mdt_Output_check($case);

    my $real_time = write_stats_for_pm($PM,$Hf,$start_time,@jobs);
    print "$PM took ${real_time} seconds to complete.\n";

    if ($error_message ne '') {
	error_out("${error_message}",0);
    }
}



# ------------------
sub compare_reg_to_mdt_Output_check {
# ------------------
     my ($case) = @_;
     my $message_prefix ='';
     my ($file_1,$file_2);
     my @file_array=();
     if ($case == 1) {
	 $message_prefix = " Diffeomorphic warps to the MDT already exist for the following runno(s) and will not be recalculated:\n";
     } elsif ($case == 2) {
	 $message_prefix = "  Unable to create diffeomorphic warps to the MDT for the following runno(s):\n";
     }   # For Init_check, we could just add the appropriate cases.
     
     
     my $existing_files_message = '';
     my $missing_files_message = '';
     
     foreach my $runno (@array_of_runnos) {
	 $file_1 = "${current_path}/${runno}_to_MDT_warp.nii.gz";
	 $file_2 = "${current_path}/MDT_to_${runno}_warp.nii.gz";
	 if (data_double_check($file_1,$file_2)) {
	     $go_hash{$runno}=1;
	     $expected_number_of_jobs++;
	     push(@file_array,$file_1,$file_2);
	     $missing_files_message = $missing_files_message."${runno}\n";
	 } else {
	     $go_hash{$runno}=0;
	     $existing_files_message = $existing_files_message."${runno}\n";
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
sub compare_reg_to_mdt_Input_check {
# ------------------


}


# ------------------
sub reg_to_mdt {
# ------------------
    
    
#
    my 	%node_ref = (	   
	    'N51393'   => 'civmcluster1-01',
	    'N51392'   => 'civmcluster1-01',
	    'N51390'   => 'civmcluster1-05',	   
	    'N51136'   => 'civmcluster1-01',	    
	    'N51282'   => 'civmcluster1-03',
	    'N51234'   => 'civmcluster1-02',	   
	    'N51241'   => 'civmcluster1-04',
	    'N51252'   => 'civmcluster1-04',
	    'N51201'   => 'civmcluster1-02',
	);
    
#

    my ($runno) = @_;
    my $pre_affined = $intermediate_affine;
    # Set to "1" for using results of apply_affine_reg_to_atlas module, 
    # "0" if we decide to skip that step.  It appears the latter is easily the superior option.
    
    my ($fixed,$moving,$fixed_2,$moving_2,$pairwise_cmd);
    my $out_file =  "${current_path}/${runno}_to_MDT_"; # Same
    my $new_warp = "${current_path}/${runno}_to_MDT_warp.nii.gz"; # none 
    my $new_inverse = "${current_path}/MDT_to_${runno}_warp.nii.gz";
    my $new_affine = "${current_path}/${runno}_to_MDT_affine.nii.gz";
    my $out_warp = "${out_file}${warp_suffix}";
    my $out_inverse =  "${out_file}${inverse_suffix}";
    my $out_affine = "${out_file}${affine_suffix}";
    my $second_contrast_string='';
    
    $fixed = $median_images_path."/MDT_${mdt_contrast}.nii";
    
    my ($r_string);
    my ($moving_string,$moving_affine);
    
    $moving_string=$Hf->get_value("forward_xforms_${runno}");
    my $stop = 2;
    my $start;
    if ($combined_rigid_and_affine) {
	$start = 2;
    } else {
	$start = 1;
    }

    $r_string = format_transforms_for_command_line($moving_string,"r",$start,$stop);
    
    
    if ($mdt_contrast_2 ne '') {
	$fixed_2 =  $median_images_path."/MDT_${mdt_contrast_2}.nii";
    }
    
    if ($pre_affined) {

	$moving = $rigid_path."/${runno}_${mdt_contrast}.nii";
	if ($mdt_contrast_2 ne '') {
	    
	    $moving_2 =$rigid_path."/${runno}_${mdt_contrast_2}.nii" ;
	    $second_contrast_string = " -m ${diffeo_metric}[ ${fixed_2},${moving_2},1,${diffeo_radius},${diffeo_sampling_options}] ";
	}
	$pairwise_cmd = "antsRegistration -d 3 -m ${diffeo_metric}[ ${fixed},${moving},1,${diffeo_radius},${diffeo_sampling_options}] ${second_contrast_string} -o ${out_file} ". 
	    "  -c [ ${diffeo_iterations},${diffeo_convergence_thresh},${diffeo_convergence_window}] -f ${diffeo_shrink_factors} -t SyN[${diffeo_transform_parameters}] -s $diffeo_smoothing_sigmas ${r_string} -u;\n";
    } else {
	$moving = get_nii_from_inputs($inputs_dir,$runno,$mdt_contrast);
	if ($mdt_contrast_2 ne '') {
	 
	    $moving_2 = get_nii_from_inputs($inputs_dir,$runno,$mdt_contrast_2) ;
	    $second_contrast_string = " -m ${diffeo_metric}[ ${fixed_2},${moving_2},1,${diffeo_radius}${diffeo_sampling_options}] ";
	}
#	my $fixed_affine = $rigid_path."/${fixed_runno}_${xform_suffix}"; 
#	my $moving_affine =  $rigid_path."/${runno}_${xform_suffix}";
	$pairwise_cmd = "antsRegistration -d 3 -m ${diffeo_metric}[ ${fixed},${moving},1,${diffeo_radius},${diffeo_sampling_options}] ${second_contrast_string} -o ${out_file} ".
	    "  -c [ ${diffeo_iterations},${diffeo_convergence_thresh},${diffeo_convergence_window}] -f ${diffeo_shrink_factors} -t SyN[${diffeo_transform_parameters}] -s $diffeo_smoothing_sigmas ${r_string} -u;\n"
    }

 my $go_message = "$PM: create diffeomorphic warp to MDT for ${runno}" ;
 my $stop_message = "$PM: could not create diffeomorphic warp to MDT for ${runno}:\n${pairwise_cmd}\n" ;
 my $node_name = $node_ref{$runno};
 #print "Node name = ${node_name}\n";

    my $jid = 0;
    if (cluster_check) {
	my $rand_delay="#sleep\n sleep \$[ \( \$RANDOM \% 10 \)  + 5 ]s;\n"; # random sleep of 5-15 seconds
	my $rename_cmd ="".  #### Need to add a check to make sure the out files were created before linking!
	    "ln -s ${out_warp} ${new_warp};\n".
	    "ln -s ${out_inverse} ${new_inverse};\n".
	    "rm ${out_affine};\n";
    
	my $cmd = $pairwise_cmd.$rename_cmd;	
	my $home_path = $current_path;
	$batch_folder = $home_path.'/sbatch/';
	my $Id= "${runno}_to_MDT_create_warp";
	my $verbose = 2; # Will print log only for work done.
	$jid = cluster_exec($go,$go_message , $cmd ,$home_path,$Id,$verbose,$mem_request);#,$node_name);     
	if (! $jid) {
	    error_out($stop_message);
	}
    } else {
	my @cmds = ($pairwise_cmd,  "ln -s ${out_warp} ${new_warp}", "ln -s ${out_inverse} ${new_inverse}","rm ${out_affine} ");
	if (! execute($go, $go_message, @cmds) ) {
	    error_out($stop_message);
	}
    }

    if (((!-e $new_warp) | (!-e $new_inverse)) && ($jid == 0)) {
	error_out("$PM: missing one or both of the warp results ${new_warp} and ${new_inverse}");
    }
    print "** $PM created ${new_warp} and ${new_inverse}\n";
  
    return($jid,$new_warp,$new_inverse);
}


# ------------------
sub compare_reg_to_mdt_vbm_Init_check {
# ------------------
    my $init_error_msg='';
    my $message_prefix="$PM initialization check:\n";

    # $diffeo_metric = $Hf->get_value('diffeomorphic_metric');
    # my @valid_metrics = ('CC','MI','Mattes','MeanSquares','Demons','GC');
    # my $valid_metrics = join(', ',@valid_metrics);
    # my $metric_flag = 0;
    # if ($diffeo_metric eq ('' || 'NO_KEY')) {
    # 	$diffeo_metric = 'CC';
    # 	$metric_flag = 1;
    # 	$log_msg = $log_msg."\tNo ants metric specified for diffeomorphic registration of compare group to MDT. Will use default: \"${diffeo_metric}\".\n";
    # } else {
    # 	foreach my $metric (@valid_metrics) {
    # 	    if ($diffeo_metric =~ /^$metric\Z/i) { # This should be able to catch any capitalization variation and correct it.
    # 		$diffeo_metric = $metric;
    # 		$metric_flag = 1;
    # 		$log_msg=$log_msg."\tUsing ants metric \"${diffeo_metric}\" for diffeomorphic registration of compare group to MDT.\n";
    # 	    }
    # 	}
    # }

    # if (! $metric_flag) {
    # 	$init_error_msg=$init_error_msg."Invalid ants metric requested for diffeomorphic registration of compare group to MDT \"${diffeo_metric}\" is invalid.\n".
    # 	    "\tValid metrics are: ${valid_metrics}\n";
    # }

    if ($log_msg ne '') {
	log_info("${message_prefix}${log_msg}");
    }

    if ($init_error_msg ne '') {
	$init_error_msg = $message_prefix.$init_error_msg;
    }

    return($init_error_msg);
}
# ------------------
sub compare_reg_to_mdt_vbm_Runtime_check {
# ------------------


    $diffeo_iterations = $Hf->get_value('diffeo_iterations');
    $diffeo_metric = $Hf->get_value('diffeo_metric');
    $diffeo_radius = $Hf->get_value('diffeo_radius');
    $diffeo_shrink_factors = $Hf->get_value('diffeo_shrink_factors');
    $diffeo_transform_parameters = $Hf->get_value('diffeo_transform_parameters');
    $diffeo_convergence_thresh = $Hf->get_value('diffeo_convergence_thresh');
    $diffeo_convergence_window = $Hf->get_value('diffeo_convergence_window');
    $diffeo_smoothing_sigmas = $Hf->get_value('diffeo_smoothing_sigmas');
    $diffeo_sampling_options = $Hf->get_value('diffeo_sampling_options');

    $dims=$Hf->get_value('image_dimensions');
    $xform_suffix = $Hf->get_value('rigid_transform_suffix');
    $mdt_contrast_string = $Hf->get_value('mdt_contrast'); #  Will modify to pull in arbitrary contrast, since will reuse this code for all contrasts, not just mdt contrast.
    @mdt_contrasts = split('_',$mdt_contrast_string); 
    $mdt_contrast = $mdt_contrasts[0];
    if ($#mdt_contrasts > 0) {
	$mdt_contrast_2 = $mdt_contrasts[1];
    }  #The working assumption is that we will not expand beyond using two contrasts for registration...

    $inputs_dir = $Hf->get_value('inputs_dir');
    $rigid_path = $Hf->get_value('rigid_work_dir');
    $mdt_path = $Hf->get_value('mdt_work_dir');
   

#    $predictor_path = $Hf->get_value('predictor_work_dir');  
    $template_path = $Hf->get_value('template_work_dir');  
    $median_images_path = $Hf->get_value('median_images_path');    
    $current_path = $Hf->get_value('reg_diffeo_dir');


    if ($current_path eq 'NO_KEY') {
	# $current_path = "${predictor_path}/reg_diffeo";
	$current_path = "${template_path}/reg_diffeo";
 	$Hf->set_value('reg_diffeo_path',$current_path);
 	if (! -e $current_path) {
 	    mkdir ($current_path,$permissions);
 	}
    }

    $runlist = $Hf->get_value('compare_comma_list');
    @array_of_runnos = split(',',$runlist);
    
    my $case = 1;
    my ($dummy,$skip_message)=compare_reg_to_mdt_Output_check($case);

    if ($skip_message ne '') {
	print "${skip_message}";
    }

# check for needed input files to produce output files which need to be produced in this step?

}

1;
