#!/usr/local/pipeline-link/perl
# pairwise_reg_vbm.pm 





my $PM = "pairwise_reg_vbm.pm";
my $VERSION = "2014/12/02";
my $NAME = "Pairwise registration for Minimum Deformation Template calculation.";
my $DESC = "ants";

use strict;
use warnings;
no warnings qw(uninitialized);

use vars qw($Hf $BADEXIT $GOODEXIT  $test_mode $combined_rigid_and_affine $intermediate_affine $syn_params $permissions);
require Headfile;
require pipeline_utilities;
#use PDL::Transform;

my ($atlas,$rigid_contrast,$mdt_contrast,$mdt_contrast_string,$mdt_contrast_2, $runlist,$work_path,$rigid_path,$mdt_path,$current_path);
my ($xform_code,$xform_path,$xform_suffix,$domain_dir,$domain_path,$inputs_dir);
my ($diffsyn_iter,$syn_param,$diffeo_shrink_factors,$sigmas,$diffeo_metric);
my (@array_of_runnos,@sorted_runnos,@jobs,@files_to_create,@files_needed,@mdt_contrasts);
my (%go_hash);
my $go = 1;
my $job;
my $log_msg;
my ($expected_number_of_jobs,$hash_errors);
my $mem_request;

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

    pairwise_reg_vbm_Runtime_check();
    

#    my ($expected_number_of_jobs,$hash_errors) = hash_summation(\%go_hash);
    $mem_request = memory_estimator($expected_number_of_jobs,$nodes);

    my @remaining_runnos = @sorted_runnos;
    for ((my $moving_runno = shift(@remaining_runnos)); ($remaining_runnos[0] ne ''); ($moving_runno = shift(@remaining_runnos)))  {
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
	my $done_waiting = cluster_wait_for_jobs($interval,$verbose,@jobs);

	if ($done_waiting) {
	    print STDOUT  "  All pairwise diffeomorphic registration jobs have completed; moving on to next step.\n";
	}
    }
    my $case = 2;
    my ($dummy,$error_message)=pairwise_reg_Output_check($case);

    if ($error_message ne '') {
	error_out("${error_message}",0);
    }
}



# ------------------
sub pairwise_reg_Output_check {
# ------------------
     my ($case) = @_;
     my $message_prefix ='';
     my ($file_1,$file_2);
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

     for ((my $moving_runno = shift(@remaining_runnos)); ($remaining_runnos[0] ne ''); ($moving_runno = shift(@remaining_runnos)))  {
	 foreach my $fixed_runno (@remaining_runnos) {
	     $file_1 = "${current_path}/${moving_runno}_to_${fixed_runno}_warp.nii.gz";
	     $file_2 = "${current_path}/${fixed_runno}_to_${moving_runno}_warp.nii.gz";
	     if (data_double_check($file_1, $file_2)) {
		 $go_hash{$moving_runno}{$fixed_runno}=1;
		 $expected_number_of_jobs++;
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
    $moving_string=$Hf->get_value("forward_xforms_${moving_runno}");
	
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
	    $second_contrast_string = " -m CC[ ${fixed_2},${moving_2},1,4] ";
	}
	$pairwise_cmd = "antsRegistration -d 3 -m CC[ ${fixed},${moving},1,4] ${second_contrast_string} -o ${out_file} ". 
	    "  -c [ ${diffsyn_iter},1.e-8,20] -f ${diffeo_shrink_factors } -t SyN[${syn_params}] -s $sigmas ${q_string} ${r_string} -u;\n";
    } else {
	$fixed = get_nii_from_inputs($inputs_dir,$fixed_runno,$mdt_contrast);
	$moving = get_nii_from_inputs($inputs_dir,$moving_runno,$mdt_contrast);
	if ($mdt_contrast_2 ne '') {
	  $fixed_2 = get_nii_from_inputs($inputs_dir,$fixed_runno,$mdt_contrast_2) ;
	  $moving_2 = get_nii_from_inputs($inputs_dir,$moving_runno,$mdt_contrast_2) ;
	  $second_contrast_string = " -m CC[ ${fixed_2},${moving_2},1,4] ";
	}

	$pairwise_cmd = "antsRegistration -d 3 -m CC[ ${fixed},${moving},1,4] ${second_contrast_string} -o ${out_file} ".
	    "  -c [ ${diffsyn_iter},1.e-8,20] -f ${diffeo_shrink_factors} -t SyN[${syn_params}] -s $sigmas ${q_string} ${r_string} -u;\n" 
    }

    if (-e $new_warp) { unlink($new_warp);}
    if (-e $new_inverse) { unlink($new_inverse);}
    my $go_message = "$PM: create pairwise warp for the pair ${moving_runno} and ${fixed_runno}" ;
    my $stop_message = "$PM: could not create warp between ${moving_runno} and ${fixed_runno}:\n${pairwise_cmd}\n";


    my $jid = 0;
    if (cluster_check) {
	my $rename_cmd ="".  #### Need to add a check to make sure the out files were created before linking!
	    "ln -s ${out_warp} ${new_warp};\n".
	    "ln -s ${out_inverse} ${new_inverse};\n".#.
	    "rm ${out_affine};\n";
    
	my $cmd = $pairwise_cmd.$rename_cmd;
	
	my $home_path = $current_path;
	my $Id= "${moving_runno}_to_${fixed_runno}_create_pairwise_warp";
	my $verbose = 2; # Will print log only for work done.
	$jid = cluster_exec($go, $go_message, $cmd ,$home_path,$Id,$verbose,$mem_request);     
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
    
    $diffeo_metric = $Hf->get_value('diffeomorphic_metric');
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
sub pairwise_reg_vbm_Runtime_check {
# ------------------

    $diffsyn_iter=$Hf->get_value('syn_iteration_string');
    $diffeo_shrink_factors = $Hf->get_value('diffeo_shrink_factors');
    $sigmas = $Hf->get_value('smoothing_sigmas');
    $syn_param = 0.5;


    $xform_suffix = $Hf->get_value('rigid_transform_suffix');
    $mdt_contrast_string = $Hf->get_value('mdt_contrast'); #  Will modify to pull in arbitrary contrast, since will reuse this code for all contrasts, not just mdt contrast.
    @mdt_contrasts = split('_',$mdt_contrast_string); 
    $mdt_contrast = $mdt_contrasts[0];
    if ($#mdt_contrasts > 0) {
	$mdt_contrast_2 = $mdt_contrasts[1];
    }  #The working assumption is that we will not expand beyond using two contrasts for registration...

    $diffeo_metric = $Hf->get_value('diffeomorphic_metric');

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
    my $case = 1;
    my ($dummy,$skip_message)=pairwise_reg_Output_check($case);

    if ($skip_message ne '') {
	print "${skip_message}";
    }

# check for needed input files to produce output files which need to be produced in this step?

}

1;
