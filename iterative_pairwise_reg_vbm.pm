#!/usr/local/pipeline-link/perl
# iterative_template_construction_vbm.pm 

my $PM = "iterative_pairwise_reg_vbm.pm";
my $VERSION = "2016/11/03";
my $NAME = "Adaptation of Nick and Brian's optimatal template construction (for a true Minimum Deformation Template).";
my $DESC = "ants";

use strict;
use warnings;
no warnings qw(uninitialized);

use vars qw($Hf $BADEXIT $GOODEXIT  $test_mode $combined_rigid_and_affine $ants_verbosity $intermediate_affine $nodes $reservation $permissions $dims);
require Headfile;
require pipeline_utilities;
#use PDL::Transform;

my ($mdt_contrast,$mdt_contrast_string,$mdt_contrast_2, $runlist,$rigid_path,$mdt_path,$current_path,$inputs_dir);
my ($diffeo_metric,$diffeo_radius,$diffeo_shrink_factors,$diffeo_iterations,$diffeo_levels,$diffeo_transform_parameters);
my ($diffeo_convergence_thresh,$diffeo_convergence_window,$diffeo_smoothing_sigmas,$diffeo_sampling_options);
my (@array_of_runnos,@sorted_runnos,@jobs,@files_to_create,@files_needed,@mdt_contrasts);
my (%go_hash);
my $go = 1;
my ($job,$job_count);
my $id_warp;
my $log_msg;
my ($expected_number_of_jobs,$hash_errors);
my ($mem_request,$mem_request_2,$jobs_in_first_batch);
my $max_iterations;
my $batch_folder;
my $counter=0;
my $current_checkpoint = 1; # Bound to change! Change here!
my $write_path_for_Hf;

my $update_step_size;
my ($template_predictor,$template_path,$master_template_dir,$starting_iteration,$template_match);
my ($current_target,$old_iteration);
my $match_registration_levels_to_iteration;

if (! defined $dims) {$dims = 3;}
if (! defined $ants_verbosity) {$ants_verbosity = 1;}

my($warp_suffix,$inverse_suffix,$affine_suffix);

my $cheating = 0;
if ($cheating) {
$warp_suffix = "2Warp.nii.gz";
$inverse_suffix = "2InverseWarp.nii.gz";
$affine_suffix = "0GenericAffine.mat";
} else {
$warp_suffix = "1Warp.nii.gz";
$inverse_suffix = "1InverseWarp.nii.gz";
$affine_suffix = "0GenericAffine.mat";
}

my $affine = 0;

# my @parents = qw(apply_affine_reg_to_atlas_vbm);
# my @children = qw (reg_template_vbm);

#$test_mode=0;
my ($type,$current_iteration);

# ------------------
sub iterative_pairwise_reg_vbm {  # Main code
# ------------------
    
   ($type,$current_iteration) = @_;
    if ($type eq "a") {
	$affine = 1;
    }
    my $start_time = time;
    iterative_pairwise_reg_vbm_Runtime_check();
    

#    my ($expected_number_of_jobs,$hash_errors) = hash_summation(\%go_hash);
   ($mem_request,$mem_request_2,$jobs_in_first_batch) = memory_estimator_2($expected_number_of_jobs,$nodes);
#    my $template_group ='';
   my @remaining_runnos = @sorted_runnos;
   for ((my $moving_runno = $remaining_runnos[0]); ($remaining_runnos[0] ne ''); (shift(@remaining_runnos)))  {
       $moving_runno = $remaining_runnos[0];
       my $current_file = get_nii_from_inputs($inputs_dir,$moving_runno,$mdt_contrast);
       $go = $go_hash{$moving_runno};
       my $forward_out =  "${current_path}/${moving_runno}_to_MDT_warp.nii.gz";
       my $inverse_out = "${current_path}/MDT_to_${moving_runno}_warp.nii.gz";
       if ($go) {
	   if ($current_iteration) {
	       ($job) = create_iterative_pairwise_warps($moving_runno);
	       #	sleep(0.25);
	       if ($job > 1) {
		   push(@jobs,$job);
	       }
	   } else {
	       `cp ${id_warp} ${forward_out}`;
	       `cp ${id_warp} ${inverse_out}`; 
	   }
       }
       my $replace = 0;

       my $xform_string = $Hf->get_value("mdt_forward_xforms_${moving_runno}");
       my @xforms = split(',',$xform_string);
       if ($xforms[0] =~ /\.nii(\.gz){0,1}?/) {
	   $replace = 1;
       }

       headfile_list_handler($Hf,"mdt_forward_xforms_${moving_runno}",$forward_out,0,$replace); # added 'mdt_', 15 June 2016
       headfile_list_handler($Hf,"mdt_inverse_xforms_${moving_runno}",$inverse_out,1,$replace); # added 'mdt_', 15 June 2016
   }

   if (cluster_check() && ($jobs[0] ne '')) {
       my $interval = 15;
       my $verbose = 1;
       my $done_waiting = cluster_wait_for_jobs($interval,$verbose,$batch_folder,@jobs);
       
       if ($done_waiting) {
	   print STDOUT  "  All pairwise diffeomorphic registration jobs have completed; moving on to next step.\n";
       }
   }
   my $case = 2;
   my ($dummy,$error_message)=iterative_pairwise_reg_Output_check($case);
   
   $Hf->write_headfile($write_path_for_Hf);
   `chmod 777 ${write_path_for_Hf}`;

   my $real_time = write_stats_for_pm($PM,$Hf,$start_time,@jobs);
   print "$PM took ${real_time} seconds to complete.\n";
   
   @jobs=(); # Clear out the job list, since it will remember everything when this module is used iteratively.

   if ($error_message ne '') {
       error_out("${error_message}",0);
   } else {
       return($current_iteration);
   }

}



# ------------------
sub iterative_pairwise_reg_Output_check {
# ------------------
     my ($case) = @_;
     my $message_prefix ='';
     my ($file_1,$file_2,@files);
     my @file_array=();
     if ($case == 1) {
  	$message_prefix = "  Diffeomorphic warps to the iterativly constructed template already exist for the following runno(s) and will not be recalculated:\n";
     } elsif ($case == 2) {
 	$message_prefix = "  Unable to create diffeomorphic warp(s) to the iteratively constructed template for the following runno(s):\n";
     }   # For Init_check, we could just add the appropriate cases.


     my $existing_files_message = '';
     my $missing_files_message = '';
     my @remaining_runnos = @sorted_runnos;

     $expected_number_of_jobs = 0;

     for ((my $moving_runno = $remaining_runnos[0]); ($remaining_runnos[0] ne ''); (shift(@remaining_runnos)))  {
	 $moving_runno = $remaining_runnos[0];
	 $file_1 = "${current_path}/${moving_runno}_to_MDT_warp.nii.gz";
	 $file_2 = "${current_path}/MDT_to_${moving_runno}_warp.nii.gz";
	 
	 if (data_double_check($file_1, $file_2)) {
	     $go_hash{$moving_runno}=1;
	     if ($file_1 ne $file_2) {
		 $expected_number_of_jobs++;
	     }
	     push(@file_array,$file_1,$file_2);
	     $missing_files_message = $missing_files_message."\t${moving_runno}";
	 } else {
	     $go_hash{$moving_runno}=0;
	     $existing_files_message = $existing_files_message."\t${moving_runno}";
	 }
	 if (($existing_files_message ne '') && ($case == 1)) {
	     $existing_files_message = $existing_files_message."\n";
	 } elsif (($missing_files_message ne '') && ($case == 2)) {
	     $missing_files_message = $missing_files_message."\n";
	 }
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
sub iterative_pairwise_reg_Input_check {
# ------------------


}


# ------------------
sub create_iterative_pairwise_warps {
# ------------------
    my ($moving_runno) = @_;
    my $pre_affined = $intermediate_affine;
    
    # Set to "1" for using results of apply_affine_reg_to_atlas module, 
    # "0" if we decide to skip that step.  It appears the latter is easily the superior option.
    
    my ($fixed,$moving,$fixed_2,$moving_2,$pairwise_cmd);
    my $out_file =  "${current_path}/${moving_runno}_to_MDT_"; # Same
    my $new_warp = "${current_path}/${moving_runno}_to_MDT_warp.nii.gz"; # none 
    my $new_inverse = "${current_path}/MDT_to_${moving_runno}_warp.nii.gz";
    my $new_affine = "${current_path}/${moving_runno}_to_MDT_affine.nii.gz";
    my $out_warp = "${out_file}${warp_suffix}";
    my $out_inverse =  "${out_file}${inverse_suffix}";
    my $out_affine = "${out_file}${affine_suffix}";
    
    my $second_contrast_string='';
    
    my ($q_string,$r_string);
    my ($moving_string,$moving_affine);
    
    $moving_string=$Hf->get_value("forward_xforms_${moving_runno}");
    if ($moving_string eq 'NO_KEY') {
	$moving_string=$Hf->get_value("mdt_forward_xforms_${moving_runno}")
    }	
    
    my $stop = 2;
    my $start;
    if ($combined_rigid_and_affine) {
	$start = 2;
    } else {
	$start = 1;
    }


    my @moving_array=split(',',$moving_string);  # In this case, we only want to consider the last 2 listed transforms, affine and rigid.
    while ($#moving_array > 1) {
	my $trash = shift(@moving_array)
    }
    $moving_string = join(',',@moving_array);

    #$q_string = format_transforms_for_command_line($fixed_string,"q",$start,$stop);
    $q_string = '';
    $r_string = format_transforms_for_command_line($moving_string,"r",$start,$stop);
    
    
    $fixed = $current_target;
    $moving = get_nii_from_inputs($inputs_dir,$moving_runno,$mdt_contrast);
    if ($mdt_contrast_2 ne '') {
	##$fixed_2 = get_nii_from_inputs($inputs_dir,$fixed_runno,$mdt_contrast_2) ; # Need to "fix" this, chuckle chuckle.
	#$moving_2 = get_nii_from_inputs($inputs_dir,$moving_runno,$mdt_contrast_2) ;
	#$second_contrast_string = " -m ${diffeo_metric}[ ${fixed_2},${moving_2},1,${diffeo_radius},${diffeo_sampling_options}] ";
    }
    
    $pairwise_cmd = "antsRegistration -v ${ants_verbosity} -d $dims -m ${diffeo_metric}[ ${fixed},${moving},1,${diffeo_radius},${diffeo_sampling_options}] ${second_contrast_string} -o ${out_file} ".
	"  -c [ ${diffeo_iterations},${diffeo_convergence_thresh},${diffeo_convergence_window}] -f ${diffeo_shrink_factors} -t SyN[${diffeo_transform_parameters}] -s ${diffeo_smoothing_sigmas} ${q_string} ${r_string} -u;\n" ;
    
    
    if (-e $new_warp) { unlink($new_warp);}
    if (-e $new_inverse) { unlink($new_inverse);}
    my $go_message = "$PM: create iterative pairwise warp for the pair ${moving_runno} and MDT" ;
    my $stop_message = "$PM: could not create iterative warp between ${moving_runno} and MDT:\n${pairwise_cmd}\n";
    

    
    my $rename_cmd;
    $rename_cmd = "".  #### Need to add a check to make sure the out files were created before linking!
	"ln -s ${out_warp} ${new_warp};\n".
	"ln -s ${out_inverse} ${new_inverse};\n".#.
	"rm ${out_affine};\n";
    my @test = (0);
    my $node = '';
    
    if (! data_double_check($out_warp,$out_inverse)) {
	$pairwise_cmd = '';
    }
	
## It is possible that VBM processing was done after previous iteration.  If so, then the "reg_diffeo" warps will be the same work we want here, with the one caveat that the same diffeo parameters are used during template creation and registration to template (no doubt we will soon stray from this path).
    my $previous_template_path = $template_path;
    if ($previous_template_path =~ s/_i([0-9]+[\/]*)?/_i($old_iteration)/) { }
    my $prev_reg_diffeo_path = "${previous_template_path}/reg_diffeo/";
    my $reusable_warp = "${prev_reg_diffeo_path}/${moving_runno}_to_MDT_warp.nii.gz"; # none 
    my $reusable_inverse_warp = "${prev_reg_diffeo_path}/MDT_to_${moving_runno}_warp.nii.gz"; 

    if (! data_double_check($reusable_warp,$reusable_inverse_warp)){
	$pairwise_cmd = '';
	$rename_cmd = "ln ${reusable_warp} ${new_warp}; ln ${reusable_inverse_warp} ${new_inverse};";
    }
##


    if ($pairwise_cmd ne '') {
	$job_count++;
	if ($job_count > $jobs_in_first_batch){
	    $mem_request = $mem_request_2;
	}
    }



    my $jid = 0;
    if (cluster_check) {
	my $cmd = $pairwise_cmd.$rename_cmd;
	
	my $home_path = $current_path;
	$batch_folder = $home_path.'/sbatch/';
	my $Id= "${moving_runno}_to_MDT_create_iterative_pairwise_warp";
	my $verbose = 2; # Will print log only for work done.
	$jid = cluster_exec($go, $go_message, $cmd ,$home_path,$Id,$verbose,$mem_request,@test);     
	if (! $jid) {
	    error_out();
	}
    } else {
	my @cmds = ($pairwise_cmd,  "ln -s ${out_warp} ${new_warp}", "ln -s ${out_inverse} ${new_inverse}","rm ${out_affine} ");
	if (! execute($go, $go_message, @cmds) ) {
	    error_out($stop_message);
	}
    }

    if (((!-e $new_warp) | (!-e $new_inverse)) && ($jid == 0)) {
	error_out($stop_message);
    }
    print "** $PM created ${new_warp} and ${new_inverse}\n";
  
    return($jid);
}


# ------------------
sub iterative_pairwise_reg_vbm_Init_check {
# ------------------
    my $init_error_msg='';
    
    my $mdt_creation_strategy = $Hf->get_value('mdt_creation_strategy');
    if ($mdt_creation_strategy eq 'iterative') {
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

	my $initial_template = $Hf->get_value('initial_template');
	if (! data_double_check($initial_template))  {
	   my($name,$path,$suffix)= fileparts($initial_template);
	   if ($name =~ s/(_i)([0-9]+)$//) {
	       my $starting_iteration = (1+$2);
	       $Hf->set_value('starting_iteration_for_template_creation',$starting_iteration);
	       $Hf->set_value('template_name',$name);
	       $log_msg = $log_msg."\tAn initialization template has been specified with the name: $name\n";
	       $log_msg = $log_msg."\tIt appears to be from iteration ${2}; template creation will resume at ${starting_iteration}\n";

	   }
	   else {
	       $Hf->set_value('template_name',$name);
	       $log_msg = $log_msg."\tAn initialization template has been specified with the name: $name\n";
	       $log_msg = $log_msg."\tTemplate creation will attempt to pick up where any previous work may have left off\n";
	   }
	}

	$match_registration_levels_to_iteration = $Hf->get_value('match_registration_levels_to_iteration');
	if (($match_registration_levels_to_iteration eq 'NO_KEY') ||($match_registration_levels_to_iteration eq 'UNDEFINED_VALUE'))  {
	    $match_registration_levels_to_iteration=1;
	    $Hf->set_value('match_registration_levels_to_iteration',$match_registration_levels_to_iteration);
	}

	$diffeo_metric = $Hf->get_value('diffeo_metric');
	
	my @valid_metrics = ('CC','MI','Mattes','MeanSquares','Demons','GC');
	my $valid_metrics = join(', ',@valid_metrics);
	my $metric_flag = 0;
	if ($diffeo_metric eq ('' || 'NO_KEY')) {
	    $diffeo_metric = 'CC';
	    $metric_flag = 1;
	    $log_msg = $log_msg."\tNo ants metric specified for diffeomorphic pairwise registration of control group. Will use default: \"${diffeo_metric}\".\n";
	} else { 
	    foreach my $metric (@valid_metrics) {
		if ($diffeo_metric =~ /^$metric\Z/i) { # This should be able to catch any capitalization variation and correct it.
		    $diffeo_metric = $metric;
		    $metric_flag = 1;
		    $log_msg=$log_msg."\tUsing ants metric \"${diffeo_metric}\" for diffeomorphic pairwise registration of control group.\n";
		}
	    }
	}
	
	if (! $metric_flag) {
	    $init_error_msg=$init_error_msg."Invalid ants metric requested for diffeomorphic pairwise registration of control group \"${diffeo_metric}\" is invalid.\n".
		"\tValid metrics are: ${valid_metrics}\n";
	} else {
	    $Hf->set_value('diffeo_metric',$diffeo_metric);
	}
	
	
	$diffeo_radius=$Hf->get_value('diffeo_radius');
	if ($diffeo_radius eq ('' || 'NO_KEY')) {
	    #$diffeo_radius = $defaults_Hf->get_value('diffeo_radius');
	    $diffeo_radius = 4;
	    $log_msg = $log_msg."\tNo diffeomorphic radius specified; using default value of \"${diffeo_radius}\".\n";
	} elsif ($diffeo_radius =~ /^[0-9\.]+$/) {
	    # It is assumed that any positive number is righteous.
	} else {
	    $init_error_msg=$init_error_msg."Non-numeric diffeomorphic radius specified: \"${diffeo_radius}\".\n";
	}
	$Hf->set_value('diffeo_radius',$diffeo_radius);
	
	$diffeo_iterations=$Hf->get_value('diffeo_iterations');
	my @diffeo_iteration_array;
	my $diffeo_levels=0;
	if (! ($diffeo_iterations eq ('' || 'NO_KEY'))) {
	    if ($diffeo_iterations =~ /(,([0-9]+)+)/) {
		@diffeo_iteration_array = split(',',$diffeo_iterations);
		my $input_diffeo_iterations=$diffeo_iterations;
		$diffeo_iterations = join('x',@diffeo_iteration_array);
		$log_msg=$log_msg."\tConverting diffeomorphic iterations from \"${input_diffeo_iterations}\" to \"${diffeo_iterations}\".\n";
	    }
	    if ($diffeo_iterations =~ /(x([0-9]+)+)/) {
		@diffeo_iteration_array = split('x',$diffeo_iterations);
		$diffeo_levels=1+$#diffeo_iteration_array;
	    } elsif ($diffeo_iterations =~ /^[0-9]+$/) {
		$diffeo_levels=1;
	    } else {
		$init_error_msg=$init_error_msg."Non-numeric or non-integer  diffeomorphic iterations specified: \"${diffeo_iterations}\". ".
		    "Multiple iteration levels may be \'x\'- or comma-separated.\n";
	    }
	} else {
	    $diffeo_levels = 4;
	}
	
	if ((defined $test_mode) && ($test_mode==1)) {
	    $diffeo_iterations = '1';	    
	    for (my $jj = 2; $jj <= $diffeo_levels; $jj++) {
		$diffeo_iterations = $diffeo_iterations.'x0';
	    }
	    $log_msg = $log_msg."\tRunning in TEST MODE: using minimal diffeomorphic iterations:  \"${diffeo_iterations}\".\n";
	} else {
	    if ($diffeo_iterations eq ('' || 'NO_KEY')) {
	    #$diffeo_iterations = $defaults_Hf->get_value('diffeo_iterations');
		$diffeo_iterations="4000x4000x4000x4000";
		$log_msg = $log_msg."\tNo diffeomorphic iterations specified; using default values:  \"${diffeo_iterations}\".\n";
	    }
	}
	$log_msg=$log_msg."\tNumber of levels for diffeomorphic registration=${diffeo_levels}.\n";	
	$Hf->set_value('diffeo_iterations',$diffeo_iterations);
	$Hf->set_value('diffeo_levels',$diffeo_levels);
	
	$diffeo_shrink_factors=$Hf->get_value('diffeo_shrink_factors');
	if ( $diffeo_shrink_factors eq ('' || 'NO_KEY')) {
	    #$diffeo_shrink_factors = $defaults_Hf->get_value('diffeo_shrink_factors_${diffeo_levels}');
	    $diffeo_shrink_factors = '1';
	    my $temp_shrink=2;	    
	    for (my $jj = 2; $jj <= $diffeo_levels; $jj++) {
		$diffeo_shrink_factors = $temp_shrink.'x'.$diffeo_shrink_factors;
		$temp_shrink = 2*$temp_shrink;
	    }
	    $log_msg = $log_msg."\tNo diffeomorphic shrink factors specified; using default values:  \"${diffeo_shrink_factors}\".\n";
	} else {
	    my @diffeo_shrink_array;
	    my $diffeo_shrink_levels;
	    if ($diffeo_shrink_factors =~ /(,[0-9\.]+)+/) {
		@diffeo_shrink_array = split(',',$diffeo_shrink_factors);
		my $input_diffeo_shrink_factors=$diffeo_shrink_factors;
		$diffeo_shrink_factors = join('x',@diffeo_shrink_array);
		$log_msg=$log_msg."\tConverting diffeomorphic shrink factors from \"${input_diffeo_shrink_factors}\" to \"${diffeo_shrink_factors}\".\n";
	    }
	    if ($diffeo_shrink_factors =~ /(x[0-9\.]+)+/) {
		@diffeo_shrink_array = split('x',$diffeo_shrink_factors);
		$diffeo_shrink_levels=1+$#diffeo_shrink_array;
	    } elsif ($diffeo_shrink_factors =~ /^[0-9\.]+$/) {
		$diffeo_shrink_levels=1;
	    } else {
		$init_error_msg=$init_error_msg."Non-numeric diffeomorphic shrink factor(s) specified: \"${diffeo_shrink_factors}\". ".
		    "Multiple shrink factors may be \'x\'- or comma-separated.\n";
	    }
	    
	    if ($diffeo_shrink_levels != $diffeo_levels) {
		$init_error_msg=$init_error_msg."Number of diffeomorphic levels (${diffeo_shrink_levels}) implied by the specified diffeomorphic shrink factors \"${diffeo_shrink_factors}\" ".
		    "does not match the number of levels implied by the diffeomorphic iterations (${diffeo_levels}).\n";
	    }
	}
	$Hf->set_value('diffeo_shrink_factors',$diffeo_shrink_factors);
	
	## Need to better check the inputs and account for less than 3 parameters being given...someday.
	$diffeo_transform_parameters=$Hf->get_value('diffeo_transform_parameters');
	my @xform_params = split(',',$diffeo_transform_parameters);
	if ($diffeo_transform_parameters eq ('' || 'NO_KEY')) {
	    #$diffeo_transform_parameters = $defaults_Hf->get_value('diffeo_transform_parameters');
	    $diffeo_transform_parameters = '0.5,3,1'; # Was '0.5,3,0' up until 2 June 2016
	    $log_msg = $log_msg."\tNo diffeomorphic gradient step specified; using default value of \"${diffeo_transform_parameters}\".\n";
	} elsif (($xform_params[0] =~ /^[0-9\.]+$/) && ($xform_params[1] =~ /^[0-9\.]+$/) && ($xform_params[2] =~ /^[0-9\.]+$/)) {
	    $diffeo_transform_parameters = join(',',($xform_params[0],$xform_params[1],$xform_params[2])); # We will ignore any extra input, but not tell anyone--shhh!
	} elsif ($#xform_params<2){
	    $init_error_msg=$init_error_msg."Not enough diffeomorphic SyN parameters specified: \"${diffeo_transform_parameters}\"; three are required\n";
	} else {
	    $init_error_msg=$init_error_msg."Non-numeric diffeomorphic SyN parameters specified: \"${diffeo_transform_parameters}\".\n";
	}
	$Hf->set_value('diffeo_transform_parameters',$diffeo_transform_parameters);
	
	
	$diffeo_convergence_thresh=$Hf->get_value('diffeo_convergence_thresh');
	if (  $diffeo_convergence_thresh eq ('' || 'NO_KEY')) {
	    #$diffeo_convergence_thresh = $defaults_Hf->get_value('diffeo_convergence_thresh');
	    $diffeo_convergence_thresh = '1e-8';
	    $log_msg = $log_msg."\tNo diffeomorphic convergence threshold specified; using default value of \"${diffeo_convergence_thresh}\".\n";
	} elsif ($diffeo_convergence_thresh =~ /^[0-9\.]+(e(-|\+)?[0-9]+)?/) {
	    # Values specified in scientific notation need to be accepted as well.
	} else {
	    $init_error_msg=$init_error_msg."Invalid diffeomorphic convergence threshold specified: \"${diffeo_convergence_thresh}\". ".
		"Real positive numbers are accepted; scientific notation (\"X.Ye-Z\") are also righteous.\n";
    }
	$Hf->set_value('diffeo_convergence_thresh',$diffeo_convergence_thresh);    
	
	my $dcw_error = 0;
	$diffeo_convergence_window=$Hf->get_value('diffeo_convergence_window');
	if (  $diffeo_convergence_window eq ('' || 'NO_KEY')) {
	    #$diffeo_convergence_window = $defaults_Hf->get_value('diffeo_convergence_window');
	    $diffeo_convergence_window = 20;
	    $log_msg = $log_msg."\tNo diffeomorphic convergence window specified; using default value of \"${diffeo_convergence_window}\".\n";
	} elsif ($diffeo_convergence_window =~ /^[0-9]+$/) {
	    if ($diffeo_convergence_window < 5) {
	    $dcw_error=1;
	    }
	} else {
	    $dcw_error=1;
	}
	
	if ($dcw_error) {
	    $init_error_msg=$init_error_msg."Invalid diffeomorphic convergence window specified: \"${diffeo_convergence_window}\". ".
		"Window size must be an integer greater than 5.\n";
	} else {
	    $Hf->set_value('diffeo_convergence_window',$diffeo_convergence_window);
	}
	
	$diffeo_smoothing_sigmas=$Hf->get_value('diffeo_smoothing_sigmas');
	my $input_diffeo_smoothing_sigmas=$diffeo_smoothing_sigmas;
	if (  $diffeo_smoothing_sigmas eq ('' || 'NO_KEY')) {
	    #$diffeo_smoothing_sigmas = $defaults_Hf->get_value('diffeo_smoothing_sigmas_${diffeo_levels}');
	    $diffeo_smoothing_sigmas = '0vox';
	    my $temp_sigma=0.5;	    
	    for (my $jj = 2; $jj <= $diffeo_levels; $jj++) {
		$temp_sigma = 2*$temp_sigma;
		$diffeo_smoothing_sigmas = $temp_sigma.'x'.$diffeo_smoothing_sigmas;
	    }
	    $log_msg = $log_msg."\tNo diffeomorphic smoothing sigmas specified; using default values:  \"${diffeo_smoothing_sigmas}\".\n";
	} else {
	    
	    my $diffeo_smoothing_units ='';
	    my @diffeo_smoothing_array;
	    my $diffeo_smoothing_levels;
	    $diffeo_smoothing_sigmas =~ s/[\s]+//g;  #Strip any extraneous whitespace
	    if ($diffeo_smoothing_sigmas =~ s/([^0-9\.]*)$//) {
		$diffeo_smoothing_units = $1;
	    } 
	    
	    if ($diffeo_smoothing_units =~ /^(mm|vox|)$/) {
		if ($diffeo_smoothing_sigmas =~ /(,[0-9\.]+)+/) {
		    @diffeo_smoothing_array = split(',',$diffeo_smoothing_sigmas);
		    $diffeo_smoothing_sigmas = join('x',@diffeo_smoothing_array);
		    $log_msg=$log_msg."\tConverting diffeomorphic smoothing sigmas from \"${input_diffeo_smoothing_sigmas}\" to \"${diffeo_smoothing_sigmas}${diffeo_smoothing_units}\".\n";
		}
		if ($diffeo_smoothing_sigmas =~ /(x[0-9\.]+)+/) {
		    @diffeo_smoothing_array = split('x',$diffeo_smoothing_sigmas);
		    $diffeo_smoothing_levels=1+$#diffeo_smoothing_array;
		} elsif ($diffeo_smoothing_sigmas =~ /^[0-9\.]+$/) {
		    $diffeo_smoothing_levels=1;
		} else {
		    $init_error_msg=$init_error_msg."Non-numeric diffeomorphic smoothing factor(s) specified: \"${input_diffeo_smoothing_sigmas}\". ".
			"Multiple smoothing factors may be \'x\'- or comma-separated.\n";
		}
		
		if ($diffeo_smoothing_levels != $diffeo_levels) {
		    $init_error_msg=$init_error_msg."Number of diffeomorphic levels (${diffeo_smoothing_levels}) implied by the specified diffeomorphic smoothing factors \"${diffeo_smoothing_sigmas}\" ".
			"does not match the number of levels implied by the diffeomorphic iterations (${diffeo_levels})\n";
		} 
	    } else {
		$init_error_msg=$init_error_msg."Units specified for diffeomorphic smoothing sigmas \"${input_diffeo_smoothing_sigmas}\" are not valid. ".
		"Acceptable units are either \'vox\' or \'mm\', or may be omitted (equivalent to \'mm\').\n";
	    }
	    
	    $diffeo_smoothing_sigmas = $diffeo_smoothing_sigmas.$diffeo_smoothing_units;
    }
	$Hf->set_value('diffeo_smoothing_sigmas',$diffeo_smoothing_sigmas);
	
	$diffeo_sampling_options=$Hf->get_value('diffeo_sampling_options');
	if ($diffeo_sampling_options eq ('' || 'NO_KEY')) {
	    #$diffeo_sampling_options = $defaults_Hf->get_value('diffeo_sampling_options');
	    $diffeo_sampling_options='None'; # DOUBLE CHECK TO SEE IF THIS REALLY SHOULD BE OUR DEFAULT!!!
	    $log_msg = $log_msg."\tNo diffeomorphic sampling option specified; using default values of \"${diffeo_sampling_options}\".\n";
	} else {
	    my ($sampling_strategy,$sampling_percentage) = split(',',$diffeo_sampling_options);
	    if ($sampling_strategy =~ /^Random$/i) {
		$sampling_strategy = 'Random';
	    } elsif ($sampling_strategy =~ /^None$/i) {
		$sampling_strategy = 'None';
		$sampling_percentage = '';
	    } elsif ($sampling_strategy =~ /^Regular$/i) {
		$sampling_strategy = 'Regular';
	    } else {
		$init_error_msg=$init_error_msg."The specified diffeomorphic sampling strategy \"${sampling_strategy}\" is".
		    " invalid. Valid options are \'None\', \'Regular\', or \'Random\'.\n";
	    }
	    
	    if ($sampling_strategy eq ('Random'||'Regular')) {
		if (($sampling_percentage >1) && ($sampling_percentage < 100)) {
		    my $input_sampling_percentage = $sampling_percentage;
		    $sampling_percentage = $sampling_percentage/100;  # We'll be nice and accept actual percentages for this input.
		    $log_msg = $log_msg."\tSpecified diffeomorphic sampling percentage \"${input_sampling_percentage}\" is greater than 1 and less than 100:".
			" assuming value is a percentage instead of fractional; converting to fractional value: \"${sampling_percentage}\". \n";
		}
		if (($sampling_percentage <= 0) || ($sampling_percentage > 1)) {
		    $init_error_msg=$init_error_msg."For diffeomorphic sampling strategy = \"${sampling_strategy}\", specified sampling percentage ".
			" of \"${sampling_percentage}\" is outside of the acceptable range [0,1], exclusive.\n";
		} else {
		    if ($sampling_percentage ne ''){ 
			$diffeo_sampling_options = $sampling_strategy.','.$sampling_percentage;
		    } else {
			$diffeo_sampling_options = $sampling_strategy;
		    }
		}
	    }
	}
	$Hf->set_value('diffeo_sampling_options',$diffeo_sampling_options);
	
	
	$update_step_size = $Hf->get_value('update_step_size');
	if ($update_step_size eq ('' || 'NO_KEY')) {
	    $update_step_size =0.25;
	    $Hf->set_value('update_step_size',$update_step_size);
	    $log_msg = $log_msg."\tNo step size specified for shape update during iterative template construction; using default values of ${update_step_size}.\n";
	}
    
	if ($log_msg ne '') {
	    log_info("${message_prefix}${log_msg}");
	}

	if ($init_error_msg ne '') {
	    $init_error_msg = $message_prefix.$init_error_msg;
	}
    }    
    return($init_error_msg);
}
# ------------------
sub iterative_pairwise_reg_vbm_Runtime_check {
# ------------------

    $update_step_size = $Hf->get_value('update_step_size');
    $match_registration_levels_to_iteration=$Hf->get_value('match_registration_levels_to_iteration');
    
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
 
    $mdt_contrast_string = $Hf->get_value('mdt_contrast'); 
    @mdt_contrasts = split('_',$mdt_contrast_string); 
    $mdt_contrast = $mdt_contrasts[0];

    if ($#mdt_contrasts > 0) {
	$mdt_contrast_2 = $mdt_contrasts[1];
    }  #The working assumption is that we will not expand beyond using two contrasts for registration...

    $inputs_dir = $Hf->get_value('inputs_dir');
    $rigid_path = $Hf->get_value('rigid_work_dir');
    $mdt_path = $Hf->get_value('mdt_work_dir');

    $template_path = $Hf->get_value('template_work_dir'); #

    $current_path = $Hf->get_value('mdt_diffeo_path'); #

    my $template_checkpoint_completed = $Hf->get_value('template_checkpoint_completed');
    if  ($template_checkpoint_completed eq 'NO_KEY') {
	$template_checkpoint_completed = 0;
    }
    
    my $SyN_string = `echo "${diffeo_transform_parameters}" | tr "." "p" | tr "," "_" `;
    chomp($SyN_string);
    $mdt_contrast_string = "SyN_${SyN_string}_${mdt_contrast_string}"; 


    if ($mdt_path eq 'NO_KEY') {
	$mdt_path = "${rigid_path}/${mdt_contrast_string}";
 	$Hf->set_value('mdt_work_dir',$mdt_path);
 	if (! -e $mdt_path) {
 	    mkdir ($mdt_path,$permissions);
 	}
    }

 
    $master_template_dir = $Hf->get_value('master_template_folder');
    if ($master_template_dir eq 'NO_KEY') {
	$master_template_dir = "${mdt_path}/templates";
 	$Hf->set_value('master_template_folder',$master_template_dir);
 	if (! -e $master_template_dir) {
 	    mkdir ($master_template_dir,$permissions);
 	}
    }


    $initial_template = $Hf->get_value('initial_template');
    $template_name = $Hf->get_value('template_name');
    $starting_iteration = $Hf->get_value('starting_iteration_for_template_creation');

    if (! data_double_check($initial_template)){
	my $initial_source_iteration=0;
	my($name,$path,$suffix)= fileparts($initial_template);
	if ((defined $starting_iteration) && ($starting_iteration > 0)) { # This runs the danger of being defined as "NO_KEY", etc.
	    $initial_source_iteration = $starting_iteration - 1;
	    $name="${name}_i0";
	}
	`cp ${initial_template} ${master_template_dir}/${template_name}_i${initial_source_iteration}.${suffix}`;
    }


    $runlist = $Hf->get_value('control_comma_list');
    @array_of_runnos = split(',',$runlist);
    @sorted_runnos=sort(@array_of_runnos);

    my $number_of_template_runnos = $#sorted_runnos + 1;

    if ($template_name eq 'NO_KEY') {
	$template_name = "${mdt_contrast}MDT_${template_predictor}_n${number_of_template_runnos}";
	$Hf->set_value('template_name',$template_name);
    }
    if ($template_path eq 'NO_KEY') {
	$template_path = "${mdt_path}/${template_name}_i${current_iteration}"; # Unsure if I should add current iteration here.
    }
    
    if ($current_path eq 'NO_KEY') {
	$current_path = "${template_path}/MDT_diffeo";
    }
    my $original_template_name = $template_name;
#if ($template_path eq 'NO_KEY') {
######### Generate an appropriate template name, check for redundancy
    print "Should run checkpoint here!\n\n";
    my $checkpoint = $Hf->get_value('last_headfile_checkpoint'); # For now, this is the first checkpoint, but that will probably evolve.
    my $previous_checkpoint = $current_checkpoint - 1;
   
    # if (($checkpoint eq "NO_KEY") || ($checkpoint <= $previous_checkpoint)) {
    if ((($checkpoint eq "NO_KEY") || ($checkpoint < $previous_checkpoint)) && (! $template_checkpoint_completed)) {
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
                              template_checkpoint_completed
                              mdt_iterations
                              last_update_warp
                              mdt_images_path
                              template_comma_list
                              median_images_path
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

	#$temp_template_name = $template_name;
	$max_iterations = $Hf->get_value('mdt_iterations');
	for (my $i=0; $template_match== 0; $i++) {
	    my $letter = $alphabet[$i];
	   my $temp_template_name = $template_name.$letter;
	   # print "current_letter = ${letter}\n";
	    #$temp_current_path = $current_path;
	   # print "Original current path = ${temp_current_path}\n\n\n";
	    my $iteration_found = 0;
	    for (my $iter=$max_iterations; (($iteration_found== 0) && ($iter > -1)); $iter--) { # -1 or 0 before resetting # previously: ($max_iteration-1)
		$temp_current_path = $mdt_path.'/'.$temp_template_name."_i${iter}/MDT_diffeo" ;
		#if ($temp_current_path =~ s/(\/[A-Za-z_]+[\/]?)$/${letter}_i${iter}$1/) {
		    #print "Temp_current_path = ${temp_current_path}\n\n\n";		    
		    my $current_tempHf = find_temp_headfile_pointer($temp_current_path);
		    my $Hf_comp = '';
		    #print "current_iteration = ${iter}\n";
		    if ($current_tempHf ne "0"){# numeric compare vs string?
			$iteration_found = $iter;
			$Hf_comp = compare_headfiles($Hf,$current_tempHf,$include,@excluded_keys);		    
			if ($Hf_comp eq '') {
			    $template_match = 1;
			} else {
			    print " $PM: ${Hf_comp}\n"; # Is this the right place for this?
			}
		    }
		#}
	    }  

	    if ($template_match || (! $iteration_found)) {
		$template_match=1;
		$template_name = $template_name.$letter; 
		#$template_path = $temp_template_path.$letter;
		#$current_path = $temp_current_path;
		if ($template_name ne $original_template_name) {   
		    print " At least one ambiguously different MDT detected, current MDT is: ${template_name}.\n";
		}
	    }
	    
	    if ($iteration_found) {
		$current_iteration = $iteration_found;
		print " Evidence of previous iterations found; starting at highest iteration, Iteration ${current_iteration}.\n";
	    }
	    #$template_path = $template_path.$letter."_i".$current_iteration;
	}
	$Hf->set_value('template_checkpoint_completed',1);
    }
    $template_path = $mdt_path.'/'.$template_name."_i".$current_iteration;
    print "Current template_path = ${template_path}\n\n";
    if (! -e $template_path) {
	mkdir ($template_path,$permissions);
    }
    $Hf->set_value('template_work_dir',$template_path);
#####
    
    
    $current_path = "${template_path}/MDT_diffeo";
    $Hf->set_value('mdt_diffeo_path',$current_path);
    if (! -e $current_path) {
	mkdir ($current_path,$permissions);
    }
    $write_path_for_Hf = "${current_path}/${template_name}_temp.headfile";
 
    print "current_path = ${current_path}\n\n";
    $old_iteration=($current_iteration - 1);
    $current_target = "${master_template_dir}/${template_name}_i${old_iteration}.nii.gz";

# Adjust number of registration levels if need be.
    if ($match_registration_levels_to_iteration) {
	if ($current_iteration < $diffeo_levels) {
	    my @iteration_array = split('x',$diffeo_iterations);
	    my @new_iteration_array;
	    for (my $ii = 0; $ii < $diffeo_levels ; $ii++) {
		if ($ii < $current_iteration) {
		    push(@new_iteration_array,$iteration_array[$ii]);
		} else {
		    push(@new_iteration_array,'0');
		}
	    }
	    $diffeo_iterations = join('x',@new_iteration_array);
	}
    }


    ## Generate an identity warp for our general purposes ##

    $id_warp = "${master_template_dir}/identity_warp.nii.gz";
    my $first_runno = $array_of_runnos[0];
    my $first_image = get_nii_from_inputs($inputs_dir,$first_runno,$mdt_contrast);

    if (data_double_check($id_warp)) {
	make_identity_warp($first_image,$Hf,$master_template_dir);
    }
    
    ##

    my $case = 1;
    my ($dummy,$skip_message)=iterative_pairwise_reg_Output_check($case);
	
   if ($skip_message ne '') {
	print "${skip_message}";
    }
	
# check for needed input files to produce output files which need to be produced in this step?

}

1;
