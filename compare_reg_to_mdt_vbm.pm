#!/usr/local/pipeline-link/perl
# compare_reg_to_mdt_vbm.pm 

my $PM = "compare_reg_to_mdt_vbm.pm";
my $VERSION = "2016/11/15"; # Cleaned up code; added iterative template creation support; added ants verbosity default (1), as new ANTs has default of (0) otherwise.
my $NAME = "Registration to MDT or other template.";
my $DESC = "ants";

use strict;
use warnings;

#use PDL::Transform;

my ($mdt_contrast,$mdt_contrast_string,$compare_contrast_string,$mdt_contrast_2, $runlist,$rigid_path,$mdt_path,$template_path,$median_images_path,$current_path,$inputs_dir);
my ($diffeo_metric,$diffeo_radius,$diffeo_shrink_factors,$diffeo_iterations,$diffeo_transform_parameters);
my ($diffeo_convergence_thresh,$diffeo_convergence_window,$diffeo_smoothing_sigmas,$diffeo_sampling_options,$diffeo_levels);
my (@array_of_runnos,@sorted_runnos,@files_to_create,@files_needed,@mdt_contrasts);
my @jobs=();
my (%go_hash);
my $go = 1;
my ($job,$job_count);
my ($mem_request,$mem_request_2,$jobs_in_first_batch);

if (! defined $dims) {$dims = 3;}
if (! defined $ants_verbosity) {$ants_verbosity = 1;}

my $log_msg="";
my $batch_folder='';
my ($match_registration_levels_to_iteration,$mdt_creation_strategy);

my($warp_suffix,$inverse_suffix,$affine_suffix);

$warp_suffix = "1Warp.nii.gz";
$inverse_suffix = "1InverseWarp.nii.gz";
$affine_suffix = "0GenericAffine.mat";

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
    $job_count = 0;
    my $MDT_to_atlas_JobID = $Hf->get_value('MDT_to_atlas_JobID');
    if (($MDT_to_atlas_JobID ne 'NO_KEY') && ($MDT_to_atlas_JobID ne 'UNDEFINED_VALUE' )) {
	$expected_number_of_jobs++;
	$job_count++;
    }
 
    ($mem_request,$mem_request_2,$jobs_in_first_batch) = memory_estimator_2($expected_number_of_jobs,$nodes);    
 
    foreach my $runno (@array_of_runnos) {
	my ($f_xform_path,$i_xform_path);

	$go = $go_hash{$runno};

	
	if ($go) {
	    ($job,$f_xform_path,$i_xform_path) = reg_to_mdt($runno);
	    #	sleep(0.25);
	    if ($job) {
		push(@jobs,$job);
	    }
	} else {
	    $f_xform_path = "${current_path}/${runno}_to_MDT_warp.nii.gz";
	    $i_xform_path = "${current_path}/MDT_to_${runno}_warp.nii.gz";
	}
   
	my $xform_string=$Hf->get_value("forward_xforms_${runno}");
	if ($xform_string eq 'NO_KEY') {
	    $xform_string=$Hf->get_value("mdt_forward_xforms_${runno}");
	    my @xform_array = split(',',$xform_string);
	    shift(@xform_array);
	    $xform_string = join(',',@xform_array);
	    $Hf->set_value("forward_xforms_${runno}",$xform_string);

	    my $inverse_xform_string=$Hf->get_value("mdt_inverse_xforms_${runno}");
	    my @inverse_xform_array = split(',',$inverse_xform_string);
	    pop(@inverse_xform_array);
	    $inverse_xform_string = join(',',@inverse_xform_array);
	    $Hf->set_value("inverse_xforms_${runno}",$inverse_xform_string);
	}
	headfile_list_handler($Hf,"forward_xforms_${runno}",$f_xform_path,0);
	headfile_list_handler($Hf,"inverse_xforms_${runno}",$i_xform_path,1);
    }
    
      
    if (cluster_check() && (scalar @jobs)) {
    #print "batch folder = ${batch_folder}\n\n";  
	my $interval = 15;
	my $verbose = 1;
	my $done_waiting = cluster_wait_for_jobs($interval,$verbose,$batch_folder,@jobs);

	if ($done_waiting) {
	    print STDOUT  "  All diffeomorphic \"to-MDT\" registration jobs have completed; moving on to next step.\n";
	}
    }
    my $case = 2;
    my ($dummy,$error_message)=compare_reg_to_mdt_Output_check($case);

    my $real_time = vbm_write_stats_for_pm($PM,$Hf,$start_time,@jobs);
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
	 if ($runno eq 'EMPTY_VALUE') {
	     $go_hash{$runno}=0;
	 } else {
	     $file_1 = "${current_path}/${runno}_to_MDT_warp.nii.gz";
	     $file_2 = "${current_path}/MDT_to_${runno}_warp.nii.gz";
	     if (data_double_check($file_1,$file_2)) {
		 $go_hash{$runno}=1;
		 $expected_number_of_jobs++;
		 push(@file_array,$file_1,$file_2);
		 $missing_files_message = $missing_files_message."\t${runno}\n";
	     } else {
		 $go_hash{$runno}=0;
		 $existing_files_message = $existing_files_message."\t${runno}\n";
	     }
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
    my ($runno) = @_;
    my $jid = 0;
    my ($fixed,$moving,$fixed_2,$moving_2,$pairwise_cmd);
    my $out_file =  "${current_path}/${runno}_to_MDT_"; # Same
    my $new_warp = "${current_path}/${runno}_to_MDT_warp.nii.gz"; # none 
    my $new_inverse = "${current_path}/MDT_to_${runno}_warp.nii.gz";
    #my $new_affine = "${current_path}/${runno}_to_MDT_affine.nii.gz";
    my $out_warp = "${out_file}${warp_suffix}";
    my $out_inverse =  "${out_file}${inverse_suffix}";
    my $out_affine = "${out_file}${affine_suffix}";
    my $second_contrast_string='';
    

    # For single-specimen work, the "MDT" will most likely be that specimen, so the out put should be the identity_warp.nii.gz
    # Test for this condition...

    my $CCL = $Hf->get_value('template_comma_list');
    if (($CCL eq 'NO_KEY') || ($CCL eq 'EMPTY_VALUE')) {
	$CCL=$Hf->get_value('control_comma_list');
    }
    
    if ($runno =~ /^${CCL}$/) {
	my $id_warp = "${current_path}/identity_warp.nii.gz";
	my $first_image = get_nii_from_inputs($inputs_dir,$runno,$mdt_contrast);
	
	if (data_double_check($id_warp)) {
	    make_identity_warp($first_image,$Hf,$current_path);
	}
	`mv ${id_warp} ${new_warp}; cp ${new_warp} ${new_inverse}`;
	
    } else { # Business as usual

	$fixed = $median_images_path."/MDT_${mdt_contrast}.nii.gz"; # added .gz 23 October 2015
	
	my ($r_string);
	my ($moving_string,$moving_affine);
	
	$moving_string=$Hf->get_value("forward_xforms_${runno}");
	if ($moving_string eq 'NO_KEY') {
	    $moving_string=$Hf->get_value("mdt_forward_xforms_${runno}");
	    my @moving_array = split(',',$moving_string);
	    shift(@moving_array);
	    $moving_string = join(',',@moving_array);
	}
	my $stop = 2;
	my $start = 1;

	$r_string = format_transforms_for_command_line($moving_string,"r",$start,$stop);
	
	
	if ((defined $mdt_contrast_2 ) && ($mdt_contrast_2 ne '') ) {
	    $fixed_2 =  $median_images_path."/MDT_${mdt_contrast_2}.nii.gz";
	}
	
	$moving = get_nii_from_inputs($inputs_dir,$runno,$mdt_contrast);
	if ((defined $mdt_contrast_2 ) && ($mdt_contrast_2 ne '') ) {
	    $moving_2 = get_nii_from_inputs($inputs_dir,$runno,$mdt_contrast_2) ;
	    $second_contrast_string = " -m ${diffeo_metric}[ ${fixed_2},${moving_2},1,${diffeo_radius}${diffeo_sampling_options}] ";
	}
	
	$pairwise_cmd = "antsRegistration -v ${ants_verbosity} -d ${dims} -m ${diffeo_metric}[ ${fixed},${moving},1,${diffeo_radius},${diffeo_sampling_options}] ${second_contrast_string} -o ${out_file} ".
	    "  -c [ ${diffeo_iterations},${diffeo_convergence_thresh},${diffeo_convergence_window}] -f ${diffeo_shrink_factors} -t SyN[${diffeo_transform_parameters}] -s $diffeo_smoothing_sigmas ${r_string} -u;\n";
	
	my @test = (0);

	my $go_message = "$PM: create diffeomorphic warp to MDT for ${runno}" ;
	my $stop_message = "$PM: could not create diffeomorphic warp to MDT for ${runno}:\n${pairwise_cmd}\n" ;
	
	my $rename_cmd ="".  #### Need to add a check to make sure the out files were created before linking!
	    "ln -s ${out_warp} ${new_warp};\n".
	    "ln -s ${out_inverse} ${new_inverse};\n".
	    "rm ${out_affine};\n";
	

	if ($mdt_creation_strategy eq 'iterative') {
## It is possible that we have done more iterations of template creation.  If so, then the "MDT_diffeo" warps will be the same work we want here, with the one caveat that the same diffeo parameters are used during template creation and registration to template (no doubt we will stray from this path soon).
	    my $future_template_path = $template_path;
	    my $mdt_iterations = $Hf->get_value('mdt_iterations');
	    my $future_iteration = ($mdt_iterations + 1);
	    if ($future_template_path =~ s/_i([0-9]+[\/]*)?/_i${future_iteration}/) { }
	    my $future_MDT_diffeo_path = "${future_template_path}/MDT_diffeo/";
	    my $reusable_warp = "${future_MDT_diffeo_path}/${runno}_to_MDT_warp.nii.gz"; # none 
	    my $reusable_inverse_warp = "${future_MDT_diffeo_path}/MDT_to_${runno}_warp.nii.gz"; 
	    
	    if ((! data_double_check($reusable_warp,$reusable_inverse_warp)) && ($mdt_iterations >= $diffeo_levels)){
		$pairwise_cmd = '';
		$rename_cmd = "ln ${reusable_warp} ${new_warp}; ln ${reusable_inverse_warp} ${new_inverse};";
	    } else {
		$job_count++;
	    }
	} else {
	    $job_count++;
	}

	if ($job_count > $jobs_in_first_batch){
	    $mem_request = $mem_request_2;
	}


	if (defined $reservation) {
	    @test =(0,$reservation);
	}

	if (cluster_check) {
	    #my $rand_delay="#sleep\n sleep \$[ \( \$RANDOM \% 10 \)  + 5 ]s;\n"; # random sleep of 5-15 seconds
	    # my $rename_cmd ="".  #### Need to add a check to make sure the out files were created before linking!
	    #     "ln -s ${out_warp} ${new_warp};\n".
	    #     "ln -s ${out_inverse} ${new_inverse};\n".
	    #     "rm ${out_affine};\n";
	    
	    my $cmd = $pairwise_cmd.$rename_cmd;	
	    my $home_path = $current_path;
	    $batch_folder = $home_path.'/sbatch/';
	    my $Id= "${runno}_to_MDT_create_warp";
	    my $verbose = 2; # Will print log only for work done.
	    $jid = cluster_exec($go,$go_message , $cmd ,$home_path,$Id,$verbose,$mem_request,@test);     
	    if (not $jid) {
		error_out($stop_message);
	    }
	} else {
	    my @cmds = ($pairwise_cmd,  "ln -s ${out_warp} ${new_warp}", "ln -s ${out_inverse} ${new_inverse}","rm ${out_affine} ");
	    if (! execute($go, $go_message, @cmds) ) {
		error_out($stop_message);
	    }
	}

	if (((!-e $new_warp) | (!-e $new_inverse)) && (not $jid)) {
	    error_out("$PM: missing one or both of the warp results ${new_warp} and ${new_inverse}");
	}
	print "** $PM expected output: ${new_warp} and ${new_inverse}\n";
    }
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
    $mdt_creation_strategy = $Hf->get_value('mdt_creation_strategy');

    $diffeo_iterations = $Hf->get_value('diffeo_iterations');
    $diffeo_levels = $Hf->get_value('diffeo_levels');
    $diffeo_metric = $Hf->get_value('diffeo_metric');
    $diffeo_radius = $Hf->get_value('diffeo_radius');
    $diffeo_shrink_factors = $Hf->get_value('diffeo_shrink_factors');
    $diffeo_transform_parameters = $Hf->get_value('diffeo_transform_parameters');
    $diffeo_convergence_thresh = $Hf->get_value('diffeo_convergence_thresh');
    $diffeo_convergence_window = $Hf->get_value('diffeo_convergence_window');
    $diffeo_smoothing_sigmas = $Hf->get_value('diffeo_smoothing_sigmas');
    $diffeo_sampling_options = $Hf->get_value('diffeo_sampling_options');

    $compare_contrast_string = $Hf->get_value('compare_contrast');
    if ((defined $compare_contrast_string) && ($compare_contrast_string ne 'NO_KEY')) {
	$mdt_contrast_string = $compare_contrast_string;
    } else {
	$mdt_contrast_string = $Hf->get_value('mdt_contrast'); #  Will modify to pull in arbitrary contrast, since will reuse this code for all contrasts, not just mdt contrast.
    }
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

    if ($mdt_creation_strategy eq 'iterative') {
	$match_registration_levels_to_iteration = $Hf->get_value('match_registration_levels_to_iteration');
	if (($match_registration_levels_to_iteration eq 'NO_KEY') ||($match_registration_levels_to_iteration eq 'UNDEFINED_VALUE'))  {
	    $match_registration_levels_to_iteration=0;
	}
	# Adjust number of registration levels if need be.
	if ($match_registration_levels_to_iteration) {
	    if ($mdt_iterations < $diffeo_levels) {
		my @iteration_array = split('x',$diffeo_iterations);
		my @new_iteration_array;
		for (my $ii = 0; $ii < $diffeo_levels ; $ii++) {
		    if ($ii < $mdt_iterations) {
			push(@new_iteration_array,$iteration_array[$ii]);
		    } else {
			push(@new_iteration_array,'0');
		    }
		}
		$diffeo_iterations = join('x',@new_iteration_array);
	    }
	}
    }


    $runlist = $Hf->get_value('compare_comma_list');
    if ($runlist eq 'EMPTY_VALUE') {
	@array_of_runnos = ();
    } else {
	@array_of_runnos = split(',',$runlist);
    }
    
    my $case = 1;
    my ($dummy,$skip_message)=compare_reg_to_mdt_Output_check($case);

    if ($skip_message ne '') {
	print "${skip_message}";
    }

# check for needed input files to produce output files which need to be produced in this step?

}

1;
