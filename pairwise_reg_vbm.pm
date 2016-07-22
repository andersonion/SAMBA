#!/usr/local/pipeline-link/perl
# pairwise_reg_vbm.pm 

my $PM = "pairwise_reg_vbm.pm";
my $VERSION = "2015/06/17";
my $NAME = "Pairwise registration for Minimum Deformation Template calculation.";
my $DESC = "ants";

use strict;
use warnings;
no warnings qw(uninitialized);

use vars qw($Hf $BADEXIT $GOODEXIT  $test_mode $combined_rigid_and_affine $intermediate_affine $nodes $permissions);
require Headfile;
require pipeline_utilities;
#use PDL::Transform;

my ($atlas,$rigid_contrast,$mdt_contrast,$mdt_contrast_string,$mdt_contrast_2, $runlist,$work_path,$rigid_path,$mdt_path,$current_path);
my ($xform_code,$xform_path,$xform_suffix,$domain_dir,$domain_path,$inputs_dir);
my ($diffeo_metric,$diffeo_radius,$diffeo_shrink_factors,$diffeo_iterations,$diffeo_transform_parameters);
my ($diffeo_convergence_thresh,$diffeo_convergence_window,$diffeo_smoothing_sigmas,$diffeo_sampling_options);
my (@array_of_runnos,@sorted_runnos,@jobs,@files_to_create,@files_needed,@mdt_contrasts);
my (%go_hash);
my $go = 1;
my ($job,$job_count);
my $dims;
my $id_warp;
my $log_msg;
my ($expected_number_of_jobs,$hash_errors);
my ($mem_request,$mem_request_2,$jobs_in_first_batch);
my $batch_folder;
my $counter=0;

my($warp_suffix,$inverse_suffix,$affine_suffix);
# if (! $intermediate_affine) {
   $warp_suffix = "1Warp.nii.gz";
   $inverse_suffix = "1InverseWarp.nii.gz";
   $affine_suffix = "0GenericAffine.mat";
# } else {
#     $warp_suffix = "0Warp.nii.gz";
#     $inverse_suffix = "0InverseWarp.nii.gz";
#     $affine_suffix = "0GenericAffine.mat";
# }

my $affine = 0;

# my @parents = qw(apply_affine_reg_to_atlas_vbm);
# my @children = qw (reg_template_vbm);

#$test_mode=0;


# ------------------
sub pairwise_reg_vbm {  # Main code
# ------------------
    
    my ($type) = @_;
    if ($type eq "a") {
	$affine = 1;
    }
    my $start_time = time;
    pairwise_reg_vbm_Runtime_check();
    

#    my ($expected_number_of_jobs,$hash_errors) = hash_summation(\%go_hash);
    ($mem_request,$mem_request_2,$jobs_in_first_batch) = memory_estimator_2($expected_number_of_jobs,$nodes);

    my @remaining_runnos = @sorted_runnos;
    for ((my $moving_runno = $remaining_runnos[0]); ($remaining_runnos[0] ne ''); (shift(@remaining_runnos)))  {
	$moving_runno = $remaining_runnos[0];
	foreach my $fixed_runno (@remaining_runnos) {
	    $go = $go_hash{$moving_runno}{$fixed_runno};
	    if ($go) {
		($job) = create_pairwise_warps($moving_runno,$fixed_runno);
	#	sleep(0.25);
		if ($job > 1) {
		    push(@jobs,$job);
		}
	    }
	}
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
    my ($dummy,$error_message)=pairwise_reg_Output_check($case);

    my $real_time = write_stats_for_pm($PM,$Hf,$start_time,@jobs);
    print "$PM took ${real_time} seconds to complete.\n";

    if ($error_message ne '') {
	error_out("${error_message}",0);
    }
}



# ------------------
sub pairwise_reg_Output_check {
# ------------------
     my ($case) = @_;
     my $message_prefix ='';
     my ($file_1,$file_2,@files);
     my @file_array=();
     if ($case == 1) {
  	$message_prefix = "  Pairwise diffeomorphic warps already exist for the following runno pairs and will not be recalculated:\n";
     } elsif ($case == 2) {
 	$message_prefix = "  Unable to create pairwise diffeomorphic warps for the following runno pairs:\n";
     }   # For Init_check, we could just add the appropriate cases.


     my $existing_files_message = '';
     my $missing_files_message = '';
     my @remaining_runnos = @sorted_runnos;

     $expected_number_of_jobs = 0;

     for ((my $moving_runno = $remaining_runnos[0]); ($remaining_runnos[0] ne ''); (shift(@remaining_runnos)))  {
	 $moving_runno = $remaining_runnos[0];
	 foreach my $fixed_runno (@remaining_runnos) {
	     $file_1 = "${current_path}/${moving_runno}_to_${fixed_runno}_warp.nii.gz";
	     $file_2 = "${current_path}/${fixed_runno}_to_${moving_runno}_warp.nii.gz";

	     if (data_double_check($file_1, $file_2)) {
		 $go_hash{$moving_runno}{$fixed_runno}=1;
		 if ($file_1 ne $file_2) {
		     $expected_number_of_jobs++;
		 }
		 push(@file_array,$file_1,$file_2);
		 $missing_files_message = $missing_files_message."\t${moving_runno}<-->${fixed_runno}";
	     } else {
		 $go_hash{$moving_runno}{$fixed_runno}=0;
		 $existing_files_message = $existing_files_message."\t${moving_runno}<-->${fixed_runno}";
	     }
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
sub pairwise_reg_Input_check {
# ------------------


}


# ------------------
sub create_pairwise_warps {
# ------------------
    my ($moving_runno,$fixed_runno) = @_;
    my $pre_affined = $intermediate_affine;

    # Set to "1" for using results of apply_affine_reg_to_atlas module, 
    # "0" if we decide to skip that step.  It appears the latter is easily the superior option.

    my ($fixed,$moving,$fixed_2,$moving_2,$pairwise_cmd);
    my $out_file =  "${current_path}/${moving_runno}_to_${fixed_runno}_"; # Same
    my $new_warp = "${current_path}/${moving_runno}_to_${fixed_runno}_warp.nii.gz"; # none 
    my $new_inverse = "${current_path}/${fixed_runno}_to_${moving_runno}_warp.nii.gz";
    my $new_affine = "${current_path}/${moving_runno}_to_${fixed_runno}_affine.nii.gz";
    my $out_warp = "${out_file}${warp_suffix}";
    my $out_inverse =  "${out_file}${inverse_suffix}";
    my $out_affine = "${out_file}${affine_suffix}";

    my $second_contrast_string='';

    my ($q_string,$r_string);
    my ($fixed_string,$moving_string,$fixed_affine,$moving_affine);
    $fixed_string=$Hf->get_value("forward_xforms_${fixed_runno}");
    if ($fixed_string eq 'NO_KEY') {
	$fixed_string=$Hf->get_value("mdt_forward_xforms_${fixed_runno}")
    }

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
    $q_string = format_transforms_for_command_line($fixed_string,"q",$start,$stop);
    $r_string = format_transforms_for_command_line($moving_string,"r",$start,$stop);
    
    if ($pre_affined) {
	$fixed = $rigid_path."/${fixed_runno}_${mdt_contrast}.nii";
	$moving = $rigid_path."/${moving_runno}_${mdt_contrast}.nii";
	if ($mdt_contrast_2 ne '') {
	    $fixed_2 = $rigid_path."/${fixed_runno}_${mdt_contrast_2}.nii" ;
	    $moving_2 =$rigid_path."/${moving_runno}_${mdt_contrast_2}.nii" ;
	    $second_contrast_string = " -m ${diffeo_metric}[ ${fixed_2},${moving_2},1,${diffeo_radius},${diffeo_sampling_options}] ";
	}
	$pairwise_cmd = "antsRegistration -d $dims -m ${diffeo_metric}[ ${fixed},${moving},1,${diffeo_radius},${diffeo_sampling_options}] ${second_contrast_string} -o ${out_file} ". 
	    "  -c [ ${diffeo_iterations},${diffeo_convergence_thresh},${diffeo_convergence_window}] -f ${diffeo_shrink_factors} -t SyN[${diffeo_transform_parameters}] -s ${diffeo_smoothing_sigmas} ${q_string} ${r_string} -u;\n";
    } else {
	$fixed = get_nii_from_inputs($inputs_dir,$fixed_runno,$mdt_contrast);
	$moving = get_nii_from_inputs($inputs_dir,$moving_runno,$mdt_contrast);
	if ($mdt_contrast_2 ne '') {
	  $fixed_2 = get_nii_from_inputs($inputs_dir,$fixed_runno,$mdt_contrast_2) ;
	  $moving_2 = get_nii_from_inputs($inputs_dir,$moving_runno,$mdt_contrast_2) ;
	  $second_contrast_string = " -m ${diffeo_metric}[ ${fixed_2},${moving_2},1,${diffeo_radius},${diffeo_sampling_options}] ";
	}

	$pairwise_cmd = "antsRegistration -d $dims -m ${diffeo_metric}[ ${fixed},${moving},1,${diffeo_radius},${diffeo_sampling_options}] ${second_contrast_string} -o ${out_file} ".
	    "  -c [ ${diffeo_iterations},${diffeo_convergence_thresh},${diffeo_convergence_window}] -f ${diffeo_shrink_factors} -t SyN[${diffeo_transform_parameters}] -s ${diffeo_smoothing_sigmas} ${q_string} ${r_string} -u;\n" 
    }

    if (-e $new_warp) { unlink($new_warp);}
    if (-e $new_inverse) { unlink($new_inverse);}
    my $go_message = "$PM: create pairwise warp for the pair ${moving_runno} and ${fixed_runno}" ;
    my $stop_message = "$PM: could not create warp between ${moving_runno} and ${fixed_runno}:\n${pairwise_cmd}\n";


   
    my $rename_cmd;
    $rename_cmd = "".  #### Need to add a check to make sure the out files were created before linking!
	"ln -s ${out_warp} ${new_warp};\n".
	"ln -s ${out_inverse} ${new_inverse};\n".#.
	"rm ${out_affine};\n";
    my @test = (0);
    my $node = '';
   # print "t1 = $test[0]\n\nt2=$test[1]\n\n";

    if ($fixed_runno eq $moving_runno) {
	$pairwise_cmd = "cp ${id_warp} ${new_warp}";
	$rename_cmd = '';
	$node = "civmcluster1";
	@test=(1,$node);
    } else {
	$job_count++;
	if ($job_count > $jobs_in_first_batch){
	    $mem_request = $mem_request_2;
	}
    }

# ##  This code was supposed to optimize the node distribution of jobs for McNamara 10/10 run--didn't work as well as hoped!
# 	$counter=$counter+1;
# 	if ($counter=~ /^(19|32|35|9|29|21|31|22|10|37|18|45|24)$/) {
# 	    $node = "civmcluster1-02"; #-01
# 	    $mem_request = memory_estimator(13,1);
# 	} elsif ($counter =~ /^(4|33|28|43|1|2|5|38|27|12|25|6)$/) { # Moved "13" to last node 
# 	    $node = "civmcluster1-05"; #-02
# 	    $mem_request = memory_estimator(13,1);
# 	} elsif ($counter =~ /^(26|20|40|8|23|14|3|16|7|41|36|34)$/) {
# 	    $node = "civmcluster1-04"; #-03
# 	    $mem_request = memory_estimator(12,1);
# 	} elsif ($counter =~ /^(30|17|39|15|11|42|44|13)$/){ #Imported "13" from 2nd node
# 	    $node = "civmcluster1"; #-04
# 	    $mem_request = memory_estimator(10,1); #(7,1)
# 	}
# 	@test=(0,$node);
#     }

    my $jid = 0;
    if (cluster_check) {

    
	my $cmd = $pairwise_cmd.$rename_cmd;
	
	my $home_path = $current_path;
	$batch_folder = $home_path.'/sbatch/';
	my $Id= "${moving_runno}_to_${fixed_runno}_create_pairwise_warp";
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
sub pairwise_reg_vbm_Init_check {
# ------------------
    my $init_error_msg='';
    my $message_prefix="$PM initialization check:\n";
    
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




    if ($log_msg ne '') {
	log_info("${message_prefix}${log_msg}");
    }

    if ($init_error_msg ne '') {
	$init_error_msg = $message_prefix.$init_error_msg;
    }

    return($init_error_msg);
}
# ------------------
sub pairwise_reg_vbm_Runtime_check {
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
    $mdt_contrast_string = $Hf->get_value('mdt_contrast'); 
    @mdt_contrasts = split('_',$mdt_contrast_string); 
    $mdt_contrast = $mdt_contrasts[0];
    if ($#mdt_contrasts > 0) {
	$mdt_contrast_2 = $mdt_contrasts[1];
    }  #The working assumption is that we will not expand beyond using two contrasts for registration...


# ONE OFF BAD CODE!!!!
#  $mdt_contrast_string = "SyN_1_3_1_fa";
#


    $inputs_dir = $Hf->get_value('inputs_dir');
    $rigid_path = $Hf->get_value('rigid_work_dir');
    $mdt_path = $Hf->get_value('mdt_work_dir');
    $current_path = $Hf->get_value('mdt_pairwise_dir');
 
    if ($mdt_path eq 'NO_KEY') {
	$mdt_path = "${rigid_path}/${mdt_contrast_string}";
 	$Hf->set_value('mdt_work_dir',$mdt_path);
 	if (! -e $mdt_path) {
 	    mkdir ($mdt_path,$permissions);
 	}
    }

    if ($current_path eq 'NO_KEY') {
	$current_path = "${mdt_path}/MDT_pairs";
 	$Hf->set_value('mdt_pairwise_dir',$current_path);
 	if (! -e $current_path) {
 	    mkdir ($current_path,$permissions);
 	}
    }

    $runlist = $Hf->get_value('control_comma_list');
    @array_of_runnos = split(',',$runlist);
    @sorted_runnos=sort(@array_of_runnos);


    ## Generate an identity warp for our general purposes ##

    $id_warp = "${current_path}/identity_warp.nii.gz";
    my $first_runno = $array_of_runnos[0];
    my $first_image = get_nii_from_inputs($inputs_dir,$first_runno,$mdt_contrast);
    print "current path = ${current_path}\n\n";
    if (data_double_check($id_warp)) {
	make_identity_warp($first_image,$Hf,$current_path);
    }
    
    ##

    my $case = 1;
    my ($dummy,$skip_message)=pairwise_reg_Output_check($case);

    if ($skip_message ne '') {
	print "${skip_message}";
    }

# check for needed input files to produce output files which need to be produced in this step?

}

1;
