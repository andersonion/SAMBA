#!/usr/local/pipeline-link/perl
# mdt_reg_to_atlas_vbm.pm 





my $PM = "mdt_reg_to_atlas_vbm.pm";
my $VERSION = "2015/01/06";
my $NAME = ".";
my $DESC = "ants";

use strict;
use warnings;
no warnings qw(uninitialized);

use vars qw($Hf $BADEXIT $GOODEXIT  $test_mode $intermediate_affine $permissions $nodes $mdt_to_reg_start_time);
require Headfile;
require pipeline_utilities;
#use PDL::Transform;

my ($atlas,$rigid_contrast,$mdt_contrast,$mdt_contrast_string,$mdt_contrast_2, $runlist,$work_path,$mdt_path,$median_images_path,$current_path);
my ($xform_code,$xform_path,$xform_suffix,$domain_dir,$domain_path);
my ($diffeo_metric,$diffeo_radius,$diffeo_shrink_factors,$diffeo_iterations,$diffeo_transform_parameters);
my ($diffeo_convergence_thresh,$diffeo_convergence_window,$diffeo_smoothing_sigmas,$diffeo_sampling_options);
my ($label_path);
my (@array_of_runnos,@sorted_runnos,@jobs,@files_to_create,@files_needed,@mdt_contrasts);
my (%go_hash);
my $go = 1;
my $job;
my $dims;
my ($log_msg);
my ($mem_request);


my($warp_suffix,$inverse_suffix,$affine_suffix,$label_atlas);
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


#$test_mode=0;


# ------------------
sub mdt_reg_to_atlas_vbm {  # Main code
# ------------------
    
    my ($type) = @_;
    if ($type eq "a") {
	$affine = 1;
    }
    $mdt_to_reg_start_time = time;
    mdt_reg_to_atlas_vbm_Runtime_check();
    
    my $compare_runlist = $Hf->get_value('compare_comma_list');
    my @array_of_compare_runnos = split(',',$compare_runlist);
    my $expected_number_of_jobs = $#array_of_compare_runnos + 2;

    $mem_request = memory_estimator($expected_number_of_jobs,$nodes);
    if ($expected_number_of_jobs > 3) {
	$mem_request = int($mem_request*(1.5)); # Need a smarter way to handle the greater variability in mem size of reg to atlas jobs.
    }
    print "Expected number of jobs = ${expected_number_of_jobs}\n\nMem_request = ${mem_request}\n\n";

    foreach my $runno (@array_of_runnos) {
	my ($f_xform_path,$i_xform_path);
	$go = $go_hash{$runno};
	if ($go) {
	    ($job,$f_xform_path,$i_xform_path) = mdt_reg_to_atlas($runno);
	    #	sleep(0.25);
	    if ($job > 1) {
		push(@jobs,$job);
	    }
	} else {
	    $f_xform_path = "${current_path}/MDT_to_${label_atlas}_warp.nii.gz";
	    $i_xform_path = "${current_path}/${label_atlas}_to_MDT_warp.nii.gz";
	}
	    headfile_list_handler($Hf,"forward_label_xforms",$f_xform_path,0);
	    headfile_list_handler($Hf,"inverse_label_xforms",$i_xform_path,1);    
    }
    
    $Hf->set_value('MDT_to_atlas_JobID',$jobs[0]);    


## THIS IS COMMENTED OUT BECAUSE WE WANT TO RUN ALL THE COMPARE REGISTRATIONS TO MDT IN PARALLEL TO THIS JOB
    # if (cluster_check() && ($jobs[0] ne '')) {
    # 	my $interval = 15;
    # 	my $verbose = 1;
    # 	my $done_waiting = cluster_wait_for_jobs($interval,$verbose,@jobs);

    # 	if ($done_waiting) {
    # 	    print STDOUT  " Diffeomorphic registration from MDT to label atlas ${label_atlas} job has completed; moving on to next serial step.\n";
    # 	}
    # }
    # my $case = 2;
    # my ($dummy,$error_message)=mdt_reg_to_atlas_Output_check($case);

    # if ($error_message ne '') {
    # 	error_out("${error_message}",0);
    # }
}



# ------------------
sub mdt_reg_to_atlas_Output_check {
# ------------------
     my ($case) = @_;
     if (($current_path eq '') || ($array_of_runnos[0] eq '')) {
	 mdt_reg_to_atlas_vbm_Runtime_check();
     }


     my $message_prefix ='';
     my ($file_1,$file_2);
     my @file_array=();
     if ($case == 1) {
	 $message_prefix = " MDT diffeomorphic warps to ${label_atlas} atlas  already exists  and will not be recalculated:\n";
     } elsif ($case == 2) {
	 $message_prefix = "  Unable to create a diffeomorphic warp to the ${label_atlas} atlas for the MDT images:\n";
     }   # For Init_check, we could just add the appropriate cases.
     
     
     my $existing_files_message = '';
     my $missing_files_message = '';
     
     my $runno = $array_of_runnos[0];

     $file_1 = "${current_path}/MDT_to_${label_atlas}_warp.nii.gz";
     $file_2 = "${current_path}/${label_atlas}_to_MDT_warp.nii.gz";

     if (data_double_check($file_1,$file_2)) {

	 $go_hash{$runno}=1;
	 push(@file_array,$file_1,$file_2);
	 $missing_files_message = $missing_files_message."$file_1\n$file_2\n";
     } else {
	 $go_hash{$runno}=0;
	 $existing_files_message = $existing_files_message."$file_1\n$file_2\n";
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
sub mdt_reg_to_atlas_Input_check {
# ------------------


}


# ------------------
sub mdt_reg_to_atlas {
# ------------------
    my ($runno) = @_;
    my $pre_affined = $intermediate_affine;
    # Set to "1" for using results of apply_affine_reg_to_atlas module, 
    # "0" if we decide to skip that step.  It appears the latter is easily the superior option.

    my ($fixed,$moving,$fixed_2,$moving_2,$pairwise_cmd);
    my $out_file =  "${current_path}/MDT_to_${label_atlas}_"; # Same
    my $new_warp = "${current_path}/MDT_to_${label_atlas}_warp.nii.gz"; # none 
    my $new_inverse = "${current_path}/${label_atlas}_to_MDT_warp.nii.gz";
#    my $new_affine = "${current_path}/${runno}_to_MDT_affine.nii.gz";
    my $out_warp = "${out_file}${warp_suffix}";
    my $out_inverse =  "${out_file}${inverse_suffix}";
    my $out_affine = "${out_file}${affine_suffix}";
    my $second_contrast_string='';

    $fixed = $Hf->get_value ('label_atlas_path');  
    $moving = $median_images_path."/MDT_${mdt_contrast}.nii.gz"; #added .gz 22 October 2015

    if ($mdt_contrast_2 ne '') {
	$fixed_2 = $Hf->get_value('label_atlas_path_2'); 
	$moving_2 =  $median_images_path."/MDT_${mdt_contrast_2}.nii.gz";
	$second_contrast_string = " -m ${diffeo_metric}[ ${fixed_2},${moving_2},1,${diffeo_radius},${diffeo_sampling_options}] ";
    }
    my ($r_string);

    my (@moving_warps,$moving_affine);

    @moving_warps = split(',',$Hf->get_value("forward_label_xforms"));

    $moving_affine = shift(@moving_warps); # We are assuming that the most recent affine xform will incorporate any preceding xforms.

    if (defined $moving_affine) {
	$r_string = " -r ${moving_affine} ";
    } else {
	$r_string = '';
    }
    
    $pairwise_cmd = "antsRegistration -d $dims -m ${diffeo_metric}[ ${fixed},${moving},1,${diffeo_radius},${diffeo_sampling_options}] ${second_contrast_string} -o ${out_file} ".
	"  -c [ ${diffeo_iterations},${diffeo_convergence_thresh},${diffeo_convergence_window}] -f ${diffeo_shrink_factors} -t SyN[${diffeo_transform_parameters}] -s ${diffeo_smoothing_sigmas} ${r_string} -u;\n";

    
    my $go_message = "$PM: create diffeomorphic warp from MDT to label atlas ${label_atlas}" ;
    my $stop_message = "$PM: could not create diffeomorphic warp from MDT for label atlas ${label_atlas}:\n${pairwise_cmd}\n" ;

    my @test=(0);

    my $jid = 0;
    if (cluster_check) {
	my $rand_delay="#sleep\n sleep \$[ \( \$RANDOM \% 10 \)  + 5 ]s;\n"; # random sleep of 5-15 seconds
	my $rename_cmd ="".  #### Need to add a check to make sure the out files were created before linking!
	    "ln -s ${out_warp} ${new_warp};\n".
	    "ln -s ${out_inverse} ${new_inverse};\n".
	    "rm ${out_affine};\n";
    
	my $cmd = $pairwise_cmd.$rename_cmd;
	
	my $home_path = $current_path;
	my $Id= "MDT_to_${label_atlas}_create_warp";
	my $verbose = 2; # Will print log only for work done.
	$jid = cluster_exec($go,$go_message , $cmd ,$home_path,$Id,$verbose,$mem_request,@test);     
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
sub mdt_reg_to_atlas_vbm_Init_check {
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
	$log_msg = $log_msg."\tNo ants metric specified for diffeomorphic registration of MDT to labelled atlas. Will use default: \"${diffeo_metric}\".\n";
    } else {
	foreach my $metric (@valid_metrics) {
	    if ($diffeo_metric =~ /^$metric\Z/i) { # This should be able to catch any capitalization variation and correct it.
		$diffeo_metric = $metric;
		$metric_flag = 1;
	    }
	}
    }

    if ($metric_flag) {
	$log_msg=$log_msg."\tUsing ants metric \"${diffeo_metric}\" for diffeomorphic label registration.\n";
    } else {
	$init_error_msg=$init_error_msg."Invalid ants metric requested for diffeomorphic label registration \"${diffeo_metric}\" is invalid.\n".
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
sub mdt_reg_to_atlas_vbm_Runtime_check {
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
    $label_atlas = $Hf->get_value('label_atlas_name');
    $work_path = $Hf->get_value('regional_stats_dir');
    $label_path=$Hf->get_value('labels_dir');
    $current_path = $Hf->get_value('label_transform_dir');
    if ($work_path eq 'NO_KEY') {
	# my $predictor_path = $Hf->get_value('predictor_work_dir'); 
	my $template_path = $Hf->get_value('template_work_dir'); 
	$work_path = "${template_path}/stats_by_region";
	$Hf->set_value('regional_stats_dir',$work_path);
	if (! -e $work_path) {
	    mkdir ($work_path,$permissions);
	}
    }

	if ($label_path eq 'NO_KEY') {
	    $label_path = "${work_path}/labels";
	    $Hf->set_value('labels_dir',$label_path);
	    if (! -e $label_path) {
		mkdir ($label_path,$permissions);
	    }
	}

	if ($current_path eq 'NO_KEY') {
	    $current_path = "${label_path}/transforms";
	    $Hf->set_value('label_transform_dir',$current_path);
	    if (! -e $current_path) {
		mkdir ($current_path,$permissions);
	    }
	}

    $xform_suffix = $Hf->get_value('rigid_transform_suffix');
    $mdt_contrast_string = $Hf->get_value('mdt_contrast'); 
    @mdt_contrasts = split('_',$mdt_contrast_string); 
    $mdt_contrast = $mdt_contrasts[0];
    if ($#mdt_contrasts > 0) {
	$mdt_contrast_2 = $mdt_contrasts[1];
	
	$domain_dir   = $Hf->get_value ('label_atlas_dir');   
	$domain_path  = "$domain_dir/${label_atlas}_${mdt_contrast_2}.nii"; # potential error by not converting to .gz

    }  #The working assumption is that we will not expand beyond using two contrasts for registration...

    $mdt_path = $Hf->get_value('mdt_work_dir');
    
      
    $median_images_path = $Hf->get_value('median_images_path');    
    
    @array_of_runnos = ("MDT_${mdt_contrast}");
    
    my $case = 1;
    my ($dummy,$skip_message)=mdt_reg_to_atlas_Output_check($case);

    if ($skip_message ne '') {
	print "${skip_message}";
    }

# check for needed input files to produce output files which need to be produced in this step?

}

1;
