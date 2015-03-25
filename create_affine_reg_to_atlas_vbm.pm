#!/usr/local/pipeline-link/perl
# create_affine_reg_to_atlas_vbm.pm 


#  2015/01/02  BJ - added capability to register to any image, not just atlas; for use with full-affine registration.


my $PM = "create_affine_reg_to_atlas_vbm.pm";
my $VERSION = "2015/01/02";
my $NAME = "Create bulk rigid/affine registration to a specified atlas";
my $DESC = "ants";
my $ggo = 1;  # Needed for compatability with seg_pipe code

use strict;
use warnings;
no warnings qw(uninitialized bareword);

use vars qw($Hf $BADEXIT $GOODEXIT $test_mode $combined_rigid_and_affine $create_labels $nodes $permissions);
require Headfile;
require pipeline_utilities;

my ($rigid_atlas,$contrast, $runlist,$work_path,$current_path,$affine_iter,$label_atlas,$label_path);
my ($xform_code,$xform_path,$xform_suffix,$atlas_dir,$atlas_path,$inputs_dir);
my (@array_of_runnos,@jobs,@mdt_contrasts);
my (%go_hash,%create_output);
my $go = 1;
my $job;
my ($do_rigid,$affine_target,$q_string,$r_string,$other_xform_suffix,$mdt_to_atlas,$mdt_contrast_string,$mdt_contrast,$mdt_contrast_2,$mdt_path);
my $ants_affine_suffix = "0GenericAffine.mat";
my $mem_request;

# ------------------
sub create_affine_reg_to_atlas_vbm {  # Main code
# ------------------
    ($do_rigid,$mdt_to_atlas) = @_;
    create_affine_reg_to_atlas_vbm_Runtime_check();
    my ($expected_number_of_jobs,$hash_errors) = hash_summation(\%go_hash);
    $mem_request = memory_estimator($expected_number_of_jobs,$nodes);

    foreach my $runno (@array_of_runnos) {
	my $to_xform_path;
	my $result_path_base;
	if ($mdt_to_atlas){
	    $mdt_path = $Hf->get_value('median_images_path');
	    $to_xform_path = $mdt_path.'/'.$runno.'.nii';
	    $result_path_base = "${current_path}/${runno}_to_${label_atlas}_";
	} else {
	    $to_xform_path=get_nii_from_inputs($inputs_dir,$runno,$contrast);
	    $result_path_base = "${current_path}/${runno}_";
	}
	
	$go = $go_hash{$runno};
	my  $pipeline_name = $result_path_base.$xform_suffix;

	if ($go) {
	    if ((! $do_rigid) && ($runno eq $affine_target ) && ($combined_rigid_and_affine)) { # For the affine target, we want to use the identity matrix.
		my $affine_identity = $Hf->get_value('affine_identity_matrix');
		`cp ${affine_identity} ${pipeline_name}`;
	    } else {
		($xform_path,$job) = create_affine_transform_vbm($to_xform_path,  $result_path_base, $runno);
		# We are setting atlas as fixed and current runno as moving...this is opposite of what happens in seg_pipe_mc, 
		# when you are essential passing around the INVERSE of that registration to atlas step,
		# but accounting for it by setting "-i 1" with $do_inverse_bool.
	    
		if ($job > 1) {
		    push(@jobs,$job);
		}
		`ln -s ${xform_path}  ${pipeline_name}`;
	    }
	}
	if ($mdt_to_atlas) {
	    headfile_list_handler($Hf,"forward_label_xforms","${pipeline_name}",0);
	    headfile_list_handler($Hf,"inverse_label_xforms","-i ${pipeline_name}",1);
	} elsif (! ((! $do_rigid) && ($runno eq $affine_target))) {
	    headfile_list_handler($Hf,"forward_xforms_${runno}","${pipeline_name}",0);
	    headfile_list_handler($Hf,"inverse_xforms_${runno}","-i ${pipeline_name}",1);
	} elsif ((! $do_rigid) && ($runno eq $affine_target)) {
	    if ($combined_rigid_and_affine) {
		my $rigid_xform_name = $Hf->get_value("forward_xforms_${runno}");
		`cp $rigid_xform_name $pipeline_name`;
	    }
	    headfile_list_handler($Hf,"forward_xforms_${runno}","${pipeline_name}",0);
	    headfile_list_handler($Hf,"inverse_xforms_${runno}","-i ${pipeline_name}",1);
	}


    }


    if (cluster_check() && ($#jobs != -1)) {
	my $interval = 2;
	my $verbose = 1;
	my $done_waiting = cluster_wait_for_jobs($interval,$verbose,@jobs);

	if ($done_waiting) {
	    print STDOUT  "  All rigid registration jobs have completed; moving on to next step.\n";
	}
    }


    my $case = 2;
    my ($dummy,$error_message)=create_affine_reg_to_atlas_Output_check($case);

    if ($error_message ne '') {
	error_out("${error_message}",0);
    }


}


# ------------------
sub create_affine_reg_to_atlas_Output_check {
# ------------------
     my ($case) = @_;
     my $message_prefix ='';
     my ($full_file_1);
     my @file_array=();
     my $affine_type;
     my $fixed_affine_string;
     if ($do_rigid) {
	 $affine_type = "Rigid";
	 $fixed_affine_string = "atlas";
     } else {
	 $affine_type = "Full affine";
	 $fixed_affine_string = $affine_target;
     }

     if ($case == 1) {
  	$message_prefix = "  ${affine_type} registration to ${fixed_affine_string} transforms already exist for the following runno(s) and will not be recalculated:\n";
     } elsif ($case == 2) {
 	$message_prefix = "  Unable to perform ${affine_type} registration to ${fixed_affine_string} for the following runno(s):\n";
     }   # For Init_check, we could just add the appropriate cases.


     my $existing_files_message = '';
     my $missing_files_message = '';
 
     
     foreach my $runno (@array_of_runnos) {
	 if ($runno eq "MDT_${mdt_contrast}") {
	     $full_file_1 = "${current_path}/${runno}_to_${label_atlas}_${xform_suffix}";
	 } else {
	     $full_file_1 = "${current_path}/${runno}_${xform_suffix}";
	 }
	 if (data_double_check($full_file_1)) {
	     $go_hash{$runno}=1;
	     push(@file_array,$full_file_1);
	     #push(@files_to_create,$full_file); # This code may be activated for use with Init_check and generating lists of work to be done.
	     $missing_files_message = $missing_files_message."   $runno \n";
	 } else {
	     $go_hash{$runno}=0;
	     $existing_files_message = $existing_files_message."   $runno \n";
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
sub create_affine_transform_vbm {
# ------------------
  my ($B_path, $result_transform_path_base,$moving_runno) = @_;
  my $collapse = 0;
  my $transform_path="${result_transform_path_base}0GenericAffine.mat";
  if ($combined_rigid_and_affine) {
      $collapse = 1;
  } else {
      if (($xform_code ne 'rigid1') && (! $mdt_to_atlas)){
	  $transform_path="${result_transform_path_base}2Affine.mat";
      }
  }
  my ($q,$r);
  if ((! $do_rigid) && (! $mdt_to_atlas)) {
      $r_string = "${current_path}/${moving_runno}_${other_xform_suffix}";
  }

  if ((defined $q_string) && ($q_string ne '')) {
      $q = "-q $q_string";
  }
  if ((defined $r_string) && ($r_string ne '')) {
      $r = "-r $r_string";
  }
  my $metric_1 = " -m Mattes[${atlas_path},${B_path},1,32,random,0.3]";
  my $metric_2 = '';

  if (($mdt_to_atlas) && ($mdt_contrast_2 ne '')) {
      my $fixed_2 = $Hf->get_value ('label_atlas_path_2');; 
      my $moving_2 =  $mdt_path."/MDT_${mdt_contrast_2}.nii";
      $metric_2 = " -m Mattes[ ${fixed_2},${moving_2},1,32,random,0.3] ";
  }


  my $cmd;
  if ($xform_code eq 'rigid1') {
      # if ($mdt_to_atlas) {  # We don't do rigid separately from affine for MDT to Atlas.
      # 	  $cmd = "antsRegistration -d 3 ".
      # 	      " ${metric_1} ${metric_2} -t rigid[0.1] -c [${affine_iter},1.e-8,20] -s 4x2x1x1vox -f 6x4x2x1 ".
      # 	      " -u 1 -z $collapse -l 1 -o $result_transform_path_base --affine-gradient-descent-option 0.05x0.5x1.e-4x1.e-4"; 

      # } else {
	  $cmd = "antsRegistration -d 3 -r [$atlas_path,$B_path,1] ". 
	      " ${metric_1} ${metric_2} -t rigid[0.1] -c [${affine_iter},1.e-8,20] -s 4x2x1x0.5vox -f 6x4x2x1 ".
	      " $q $r ".
	      " -u 1 -z 1 -o $result_transform_path_base --affine-gradient-descent-option 0.05x0.5x1.e-4x1.e-4";
      # }	  
  } elsif ($xform_code eq 'full_affine') {
      if ($mdt_to_atlas) {
	  $cmd = "antsRegistration -d 3 ".
	      " ${metric_1} ${metric_2} -t rigid[0.1] -c [${affine_iter},1.e-8,20] -s 4x2x1x1vox -f 6x4x2x1 ".
	      " ${metric_1} ${metric_2} -t affine[0.1] -c [${affine_iter},1.e-8,20] -s 4x2x1x0vox -f 6x4x1x1 ".
	      " -u 1 -z 1 -l 1 -o $result_transform_path_base --affine-gradient-descent-option 0.05x0.5x1.e-4x1.e-4";  # "-z 1" instead of "-z $collapse", as we want rigid + affine together in this case.

      } else {	  
	  $cmd = "antsRegistration -d 3 -r [$atlas_path,$B_path,1] ".
	      " ${metric_1} ${metric_2} -t affine[0.1] -c [${affine_iter},1.e-8,20] -s 4x2x1x0.5vox -f 6x4x2x1 -l 1 ".
	      " $q $r ".
	      "  -u 1 -z $collapse -o $result_transform_path_base --affine-gradient-descent-option 0.05x0.5x1.e-4x1.e-4";
      }
  }
  
  else {
      error_out("$PM: create_transform: don't understand xform_code: $xform_code\n");
  }

  my @list = split '/', $atlas_path;
  my $A_file = pop @list;

  my $go_message =  "create ${xform_code} transform for ${A_file}";
  my $stop_message = "$PM: create_transform: could not make transform: $cmd\n";

  my $jid = 0;
  if (cluster_check) {
      my ($dummy1,$home_path,$dummy2) = fileparts($result_transform_path_base);
#      my ($home_base,$dummy3,$dummy4) = fileparts($B_path);
#      my @home_base = split(/[_-]+/,$home_base);
#      my $Id_base = $home_base[0];
      my $Id= "${moving_runno}_create_affine_registration";
      my $verbose = 2; # Will print log only for work done.
      $jid = cluster_exec($go, $go_message, $cmd,$home_path,$Id,$verbose,$mem_request);
    
      if (! $jid) {
	  error_out($stop_message);
      }
  } else {
      if (! execute($go, $go_message, $cmd) ) {
	  error_out($stop_message);
      }
  }
 # my $transform_path = "${result_transform_path_base}Affine.txt"; # From previous version of Ants, perhaps?

  

  if (data_double_check($transform_path) && $go && ($jid == 0)) {
    error_out("$PM: create_transform: did not find result xform: $transform_path");
    print "** $PM: create_transform $xform_code created $transform_path\n";
  }
  return($transform_path,$jid);
}

# ------------------
sub create_affine_reg_to_atlas_vbm_Init_check {
# ------------------
    my $init_error_msg='';
    my $message_prefix="$PM:\n";
    my $rigid_contrast;
# check for valid atlas


    my $affine_contrast = $Hf->get_value('full_affine_contrast');
    if ($affine_contrast eq 'NO_KEY') {
	$affine_contrast = $Hf->get_value('rigid_contrast');
	$Hf->set_value('full_affine_contrast',$affine_contrast);
    }

    if ($create_labels) {

	$mdt_contrast_string = $Hf->get_value('mdt_contrast'); 
	@mdt_contrasts = split('_',$mdt_contrast_string); 
	$mdt_contrast = $mdt_contrasts[0];

	my $label_atlas = $Hf->get_value('label_atlas_name');
	$atlas_dir   = $Hf->get_value ('label_atlas_dir'); 
	$atlas_path  = "$atlas_dir/${label_atlas}_${mdt_contrast}.nii";

	if (data_double_check($atlas_path))  {
	    $init_error_msg = $init_error_msg."For affine contrast ${mdt_contrast}: missing atlas nifti file ${atlas_path}\n";
	} else {
	    $Hf->set_value('label_atlas_path',$atlas_path);
	}

	if ($#mdt_contrasts > 0) {
	    $mdt_contrast_2 = $mdt_contrasts[1];	    
	    $atlas_path  = "$atlas_dir/${label_atlas}_${mdt_contrast_2}.nii";   
	    if (data_double_check($atlas_path))  {
		$init_error_msg = $init_error_msg."For secondary affine contrast ${mdt_contrast_2}: missing atlas nifti file ${atlas_path}\n";
	    } else {
		$Hf->set_value('label_atlas_path_2',$atlas_path);
	    }
	} 
    }

    $inputs_dir = $Hf->get_value('inputs_dir');
 
   if ($init_error_msg ne '') {
	$init_error_msg = $message_prefix.$init_error_msg;
    }
    return($init_error_msg);
}

# ------------------
sub create_affine_reg_to_atlas_vbm_Runtime_check {
# ------------------
 
    $affine_iter="3000x3000x0x0";
    
    if (defined $test_mode) {
	if ($test_mode==1) {
	    $affine_iter="1x0x0x0";
	}
    }
    $Hf->set_value('affine_iter',$affine_iter);
    
    $inputs_dir = $Hf->get_value('inputs_dir');
    if ($mdt_to_atlas) {
	$label_atlas = $Hf->get_value('label_atlas_name');
	$work_path = $Hf->get_value('regional_stats_dir');
	$label_path = $Hf->get_value('labels_dir');
	$current_path = $Hf->get_value('label_transform_dir');
	if ($work_path eq 'NO_KEY') {
	    my $predictor_path = $Hf->get_value('predictor_work_dir'); 
	    $work_path = "${predictor_path}/stats_by_region";
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
	    $current_path = "${label_path}/transforms"; #$current_path = "${work_path}/labels_${label_atlas}";
	    $Hf->set_value('label_tranform_dir',$current_path);
	    if (! -e $current_path) {
		mkdir ($current_path,$permissions);
	    }
	}
	$atlas_path   = $Hf->get_value ('label_atlas_path');   

	$mdt_contrast_string = $Hf->get_value('mdt_contrast'); 
	@mdt_contrasts = split('_',$mdt_contrast_string); 
	$mdt_contrast = $mdt_contrasts[0];

	if ($#mdt_contrasts > 0) {
	    $mdt_contrast_2 = $mdt_contrasts[1];
	}

	if ($do_rigid) {
	    $xform_code = 'rigid1';
	    $xform_suffix = $Hf->get_value('rigid_transform_suffix');
	    $q_string = '';
	    $r_string = '';
	} else {
	    $affine_target = $Hf->get_value('label_atlas_name');
	    $xform_code = 'full_affine';
	    $q_string = '';
	    symbolic_link_cleanup($current_path);
	}
	    @array_of_runnos = ("MDT_${mdt_contrast}");

    } else {
	$work_path = $Hf->get_value('dir_work');
	$current_path = $Hf->get_value('rigid_work_dir');

	if ($do_rigid) {
	    my $rigid_target=$Hf->get_value('rigid_target');
	    $contrast = $Hf->get_value('rigid_contrast');
	    my $updated_rigid_target;
	    if ($rigid_target ne 'NO_KEY') {
		$updated_rigid_target=get_nii_from_inputs($inputs_dir,$rigid_target,$contrast);
		if ($updated_rigid_target =~ /[\n]+/) {
		    log_info("$PM: Rigid target was specified but did not conform to runno format; assuming it is an arbitrary image specified by the user.");
		} else {
		    $Hf->set_value('rigid_atlas_path',$updated_rigid_target);
		}
	    }

	    if ($current_path eq 'NO_KEY') {
		$current_path = "${work_path}/${contrast}";
		$Hf->set_value('rigid_work_dir',$current_path);
	    }
	    
	    if (! -e $current_path) {
		mkdir ($current_path,$permissions);
	    }
	    
	    $atlas_path   = $Hf->get_value ('rigid_atlas_path');
	    $xform_code = 'rigid1';
	    $xform_suffix = $Hf->get_value('rigid_transform_suffix');
	    $q_string = '';
	    $r_string = '';
	} else {
	    $affine_target = $Hf->get_value('affine_target_image');
	    if ($affine_target eq 'NO_KEY') {
		my @controls = split(',',($Hf->get_value('control_comma_list')));
		$affine_target = shift(@controls);
		$Hf->set_value('affine_target_image',$affine_target);
	    }
	    
	    $contrast = $Hf->get_value('full_affine_contrast');
	    $xform_code = 'full_affine';
	    $xform_suffix = $Hf->get_value('affine_transform_suffix');
	    $other_xform_suffix = $Hf->get_value('rigid_transform_suffix');

	    $atlas_dir = $Hf->get_value('inputs_dir');
	    $atlas_path  = get_nii_from_inputs($atlas_dir,$affine_target,$contrast);
	    $q_string = "${current_path}/${affine_target}_${other_xform_suffix}";
	    symbolic_link_cleanup($current_path);

	}
	$runlist = $Hf->get_value('complete_comma_list');
	@array_of_runnos = split(',',$runlist);

	
    }
   
    my $case = 1;
    my ($dummy,$skip_message)=create_affine_reg_to_atlas_Output_check($case);

    if ($skip_message ne '') {
	print "${skip_message}";
    }
}
1;
