#!/usr/local/pipeline-link/perl
# compare_reg_to_mdt_vbm.pm 





my $PM = "compare_reg_to_mdt_vbm.pm";
my $VERSION = "2014/12/02";
my $NAME = "Pairwise registration for Minimum Deformation Template calculation.";
my $DESC = "ants";

use strict;
use warnings;
no warnings qw(uninitialized);

use vars qw($Hf $BADEXIT $GOODEXIT  $test_mode $intermediate_affine);
require Headfile;
require pipeline_utilities;
#use PDL::Transform;

my ($atlas,$rigid_contrast,$mdt_contrast,$mdt_contrast_string,$mdt_contrast_2, $runlist,$work_path,$rigid_path,$mdt_path,$predictor_path,$median_images_path,$current_path);
my ($xform_code,$xform_path,$xform_suffix,$domain_dir,$domain_path,$inputs_dir);
my ($diffsyn_iter,$syn_param);
my (@array_of_runnos,@sorted_runnos,@jobs,@files_to_create,@files_needed,@mdt_contrasts);
my (%go_hash);
my $go = 1;
my $job;

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


#$test_mode=0;


# ------------------
sub compare_reg_to_mdt_vbm {  # Main code
# ------------------
    
    my ($type) = @_;
    if ($type eq "a") {
	$affine = 1;
    }

    compare_reg_to_mdt_vbm_Runtime_check();
    
 
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
	    $f_xform_path = "${current_path}/${runno}_to_MDT_warp.nii";
	    $i_xform_path = "${current_path}/MDT_to_${runno}_warp.nii";
	}
	    headfile_list_handler($Hf,"forward_xforms_${runno}",$f_xform_path,0);
	    headfile_list_handler($Hf,"inverse_xforms_${runno}",$i_xform_path,1);    }
    
    
    if (cluster_check() && ($jobs[0] ne '')) {
	my $interval = 15;
	my $verbose = 1;
	my $done_waiting = cluster_wait_for_jobs($interval,$verbose,@jobs);

	if ($done_waiting) {
	    print STDOUT  "  All pairwise diffeomorphic registration jobs have completed; moving on to next step.\n";
	}
    }
    my $case = 2;
    my ($dummy,$error_message)=compare_reg_to_mdt_Output_check($case);

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
	     if (((! -e ($file_1 || $file_2)) || (((-l $file_1) && (! -e readlink($file_1))) || ((-l $file_2) && (! -e readlink($file_2)))))) {
		 $go_hash{$runno}=1;
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
    
    if ($mdt_contrast_2 ne '') {
	$fixed_2 = $rigid_path."/${runno}_${mdt_contrast_2}.nii" ;
	$fixed_2 = get_nii_from_inputs($inputs_dir,$runno,$mdt_contrast_2) ;
    }
    
    if ($pre_affined) {

	$moving = $rigid_path."/${runno}_${mdt_contrast}.nii";
	if ($mdt_contrast_2 ne '') {
	    
	    $moving_2 =$rigid_path."/${runno}_${mdt_contrast_2}.nii" ;
	    $second_contrast_string = " -m CC[ ${fixed_2},${moving_2},1,4] ";
	}
	$pairwise_cmd = "antsRegistration -d 3 -m CC[ ${fixed},${moving},1,4] ${second_contrast_string} -o ${out_file} ". 
	    "  -c [ ${diffsyn_iter},1.e-8,20] -f 8x4x2x1 -t SyN[0.5,3,0] -s 0x0x0x0 -u;\n";
    } else {
	$moving = get_nii_from_inputs($inputs_dir,$runno,$mdt_contrast);
	if ($mdt_contrast_2 ne '') {
	 
	    $moving_2 = get_nii_from_inputs($inputs_dir,$runno,$mdt_contrast_2) ;
	    $second_contrast_string = " -m CC[ ${fixed_2},${moving_2},1,4] ";
	}
#	my $fixed_affine = $rigid_path."/${fixed_runno}_${xform_suffix}"; 
	my $moving_affine =  $rigid_path."/${runno}_${xform_suffix}";
	$pairwise_cmd = "antsRegistration -d 3 -m CC[ ${fixed},${moving},1,4] ${second_contrast_string} -o ${out_file} ".
	    "  -c [ ${diffsyn_iter},1.e-8,20] -f 8x4x2x1 -t SyN[0.5,3,0] -s 0x0x0x0 -r ${moving_affine} -u;\n"
    }

    my $go_message = "$PM: create diffeomorphic warp to MDT for ${runno}" ;
    my $stop_message = "$PM: could not create diffeomorphic warp to MDT for ${runno}:\n${pairwise_cmd}\n" ;


    my $jid = 0;
    if (cluster_check) {
	my $rand_delay="#sleep\n sleep \$[ \( \$RANDOM \% 10 \)  + 5 ]s;\n"; # random sleep of 5-15 seconds
	my $rename_cmd ="".  #### Need to add a check to make sure the out files were created before linking!
	    "ln -s ${out_warp} ${new_warp};\n".
	    "ln -s ${out_inverse} ${new_inverse};\n".
	    "rm ${out_affine};\n";
    
	my $cmd = $pairwise_cmd.$rename_cmd;
	
	my $home_path = $current_path;
	my $Id= "${runno}_to_MDT_create_warp";
	my $verbose = 2; # Will print log only for work done.
	$jid = cluster_exec($go,$go_message , $cmd ,$home_path,$Id,$verbose);     
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

    return('');
}
# ------------------
sub compare_reg_to_mdt_vbm_Runtime_check {
# ------------------

    $diffsyn_iter="4000x4000x4000x4000";
    $syn_param = 0.5;

    if ( defined($test_mode)) {
	if( $test_mode == 1 ) {
#	    $diffsyn_iter="2x2x2x2";
	    $diffsyn_iter="1x0x0x0";
	}
    }

# # Set up work
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
    
    $predictor_path = $Hf->get_value('predictor_work_dir');  
    $median_images_path = $Hf->get_value('median_images_path');    
    $current_path = $Hf->get_value('reg_diffeo_dir');


    if ($current_path eq 'NO_KEY') {
	$current_path = "${predictor_path}/reg_diffeo";
 	$Hf->set_value('reg_diffeo_path',$current_path);
 	if (! -e $current_path) {
 	    mkdir ($current_path,0777);
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
