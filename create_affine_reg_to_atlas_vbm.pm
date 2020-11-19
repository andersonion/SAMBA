#!/usr/bin/false
# create_affine_reg_to_atlas_vbm.pm 
#  2015/01/02  BJ - added capability to register to any image, not just atlas; for use with full-affine registration.

use strict;
use warnings FATAL => qw(uninitialized);

my $PM = "create_affine_reg_to_atlas_vbm.pm";
my $VERSION = "2015/01/02";
my $NAME = "Create bulk rigid/affine registration to a specified atlas";
my $DESC = "ants";
my $ggo = 1;  # Needed for compatability with seg_pipe code

my ($rigid_atlas,$contrast, $runlist,$work_path,$current_path,$label_atlas);
my ($affine_metric,$affine_shrink_factors,$affine_iterations,$affine_gradient_step,$affine_convergence_thres);
my ($affine_convergence_window,$affine_smoothing_sigmas,$affine_sampling_options,$affine_radius);
my ($xform_code,$xform_path,$xform_suffix,$label_atlas_dir,$atlas_path,$inputs_dir);
my (@array_of_runnos,@array_of_control_runnos,@mdt_contrasts);
my @jobs=();
my (%go_hash,%create_output);
my $go = 1;
my $job;
my ($do_rigid,$affine_target,$q_string,$r_string,$other_xform_suffix,$mdt_to_atlas,$mdt_contrast_string,$mdt_contrast,$mdt_contrast_2,$mdt_path);
my $ants_affine_suffix = "0GenericAffine.mat";
my $mem_request;
my $log_msg="";
my $swap_fixed_and_moving=0;

my (%xform_paths,%runno_to_clean_named_transforms,%alt_result_path_bases);

if (! defined $dims) {$dims = 3;}
if (! defined $ants_verbosity) {$ants_verbosity = 1;}

my $out_ext=".nii.gz";
$out_ext=".nhdr";
# ------------------
sub create_affine_reg_to_atlas_vbm {  # Main code
# ------------------
    ($do_rigid,$mdt_to_atlas) = @_;
    my $start_time = time;
    create_affine_reg_to_atlas_vbm_Runtime_check();
    my ($expected_number_of_jobs,$hash_errors) = hash_summation(\%go_hash);
    $mem_request = memory_estimator($expected_number_of_jobs,$nodes);

    my $rigid_or_affine;
    if ($do_rigid) {
        $rigid_or_affine = 'rigid';
    } else {
        $rigid_or_affine = 'affine';
    }
    printd(1,"$PM: \tswap_fixed_and_moving is TURNED OFF (as it probably should be)\n\n");
    foreach my $runno (@array_of_runnos) {
        my $to_xform_path;
        my $result_path_base;
        my $alt_result_path_base;
        if ($mdt_to_atlas){
            $mdt_path = $Hf->get_value('median_images_path');
            $to_xform_path = $mdt_path.'/'.$runno.$out_ext; #added .gz 22 October 2015
            $result_path_base = "${current_path}/${runno}_to_${label_atlas}_";
            if ($swap_fixed_and_moving) {
                $alt_result_path_base = "${current_path}/${label_atlas}_to_${runno}_";
            } else {
                $alt_result_path_base = "${current_path}/${runno}_to_${label_atlas}_";
            }
        } else {
            $to_xform_path=get_nii_from_inputs($inputs_dir,$runno,$contrast);
            $result_path_base = "${current_path}/${runno}_";
            $alt_result_path_base = "${current_path}/${runno}_";
        }
        
        $go = $go_hash{$runno};
	# Not sure I like these var names, runno_transform_clean, and runno_to_clean_named_trasforms.
	# They are the singluar simple transform name and the collection of same.
	# (As opposed to the ants named NGenericAffine.mat uglyness.) 
        my  $runno_transform_clean = $result_path_base.$xform_suffix;
        $runno_to_clean_named_transforms{$runno}=$runno_transform_clean;
        $alt_result_path_bases{$runno}=$alt_result_path_base;
        if ($go) {
            if ( ! $do_rigid
		&& ( $runno eq $affine_target || scalar(@array_of_runnos)<3 )
		) {
                # For the affine target ONLY, and ONLY when we are doing an affine(not rigid) transform,
		# we want to use the identity matrix.
                my $affine_identity = $Hf->get_value('affine_identity_matrix');
		# Switching to a link from cp.
		run_and_watch("ln -s ${affine_identity} ${runno_transform_clean}");
            } else {
                ($xform_path,$job) = create_affine_transform_vbm($to_xform_path,  $alt_result_path_base, $runno);

                # We are setting atlas as fixed and current runno as moving...
		# this is opposite of what happens in seg_pipe_mc, 
                # when you are essential passing around the INVERSE of that registration to atlas step,
                # but accounting for it by setting "-i 1" with $do_inverse_bool.

                $xform_paths{$runno}=$xform_path;
                if ($swap_fixed_and_moving) {
                    print "swap_fixed_and_moving is activated\n\n\n";
                } else {
		    #MOVED LINK CODE TO LATER BECAUSE THE FILE WOULDN'T BE READY YET.
		    # THATS BAD FORM AND THWARTED DEBUGGING.
		}
                if ($job) {
                    push(@jobs,$job);
                }
            }
        }

        my $mdt_flag = 0;
        foreach my $current_runno (@array_of_control_runnos) {
            if ($runno eq $current_runno) {
                $mdt_flag = 1;
            }
        }


	# COMICALLY REDUNDANT BLEH, TODO: clean up.
        if ($mdt_to_atlas) {
            headfile_list_handler($Hf,"forward_label_xforms","${runno_transform_clean}",0);
            headfile_list_handler($Hf,"inverse_label_xforms","-i ${runno_transform_clean}",1);
        } elsif (! ((! $do_rigid) && ($runno eq $affine_target))) {
            if ($mdt_flag) {
                headfile_list_handler($Hf,"mdt_forward_xforms_${runno}","${runno_transform_clean}",0);
                headfile_list_handler($Hf,"mdt_inverse_xforms_${runno}","-i ${runno_transform_clean}",1);
            } else {
                headfile_list_handler($Hf,"forward_xforms_${runno}","${runno_transform_clean}",0);
                headfile_list_handler($Hf,"inverse_xforms_${runno}","-i ${runno_transform_clean}",1);
            }
        } elsif ((! $do_rigid) && ($runno eq $affine_target)) {
            if ($mdt_flag) {
                headfile_list_handler($Hf,"mdt_forward_xforms_${runno}","${runno_transform_clean}",0);
                headfile_list_handler($Hf,"mdt_inverse_xforms_${runno}","-i ${runno_transform_clean}",1);
            } else {
                headfile_list_handler($Hf,"forward_xforms_${runno}","${runno_transform_clean}",0);
                headfile_list_handler($Hf,"inverse_xforms_${runno}","-i ${runno_transform_clean}",1);
            }
        }
    }

    if (cluster_check() && ($#jobs != -1)) {
        my $interval = 2;
        my $verbose = 1;
        my $done_waiting = cluster_wait_for_jobs($interval,$verbose,@jobs);
        if ($done_waiting) {
            print STDOUT  "  All ${rigid_or_affine} registration jobs have completed; moving on to next step.\n";
        }
    }


    foreach my $runno (@array_of_runnos) {
        if (! $go) {
	    next;
	}
	# All these negatives makes it hard to understand when this would be run.
	#do_rigid is 0 or 1, and would be better named, transform_is_rigid
	# so this could be written as
	# if  not     affine && we're the affine_Target
	#if (! (  (!$do_rigid) && ($runno eq $affine_target)  )    ) {
	# if   we're not the affine target, or transform_is_rigid
	# Code should operate for all rigid, and most affine(exclude affine target)
	if (  $do_rigid 
	      || ($runno ne $affine_target && scalar(@array_of_runnos)>2)
	    ) {
	    $xform_path = $xform_paths{$runno};
	    my $runno_transform_clean = $runno_to_clean_named_transforms{$runno};
	    if ($swap_fixed_and_moving) {
		my $alt_pipeline_name = $alt_result_path_bases{$runno}.$xform_suffix;
		# WHAT MADDNESS IS THIS :p
		#`if [ -f "${xform_path}" ]; then mv ${xform_path}  ${alt_pipeline_name}; fi`;
		#run_and_watch("if [ -f \"${xform_path}\" ]; then mv ${xform_path}  ${alt_pipeline_name}; fi");
		if( -f ${xform_path} ) {
		    rename($xform_path,$alt_pipeline_name)
			|| error_out("trouble renaming $xform_path $alt_pipeline_name");
		}
		create_explicit_inverse_of_ants_affine_transform($alt_pipeline_name,$runno_transform_clean); 
		#`if [ -f "${runno_transform_clean}" ]; then rm ${alt_pipeline_name}; fi`;
		#run_and_watch("if [ -f \"${runno_transform_clean}\" ]; then rm ${alt_pipeline_name}; fi");
		if( -f ${runno_transform_clean} ) {
		    unlink($alt_pipeline_name)
			|| error_out("trouble creating $runno_transform_clean from $alt_pipeline_name");
		}
	    } else {
		# THIS WAS INITIALLY CREATING A LINK BEFORE THE FILE EXISTS!!!!
		# After decoding the crazy conditionals, it looks like the code belongs in here.
		# THATS FUNNY because here we overwrite the link with the file!
		# 
		# Now we're gonna skip the linking, and see what breaks.
		#
		#print "swap_fixed_and_moving is TURNED OFF (as it probably should be)\n\n\n";
		#`ln -s ${xform_path}  ${runno_transform_clean}`;
		# It looks like this link is created everytime 
		# Except we're doing an affine transform, and are the affine target.
		#run_and_watch("ln -s ${xform_path}  ${runno_transform_clean}");
		# former move code before switching first to run_and watch, then to perl inline.
		#`if [ -f "${xform_path}" ]; then mv ${xform_path}  ${runno_transform_clean}; fi`;
		#run_and_watch("if [ -f \"${xform_path}\" ]; then mv ${xform_path}  ${runno_transform_clean}; fi");
		if( -f ${xform_path} ) {
		    rename($xform_path,$runno_transform_clean) 
			|| error_out("trouble renaming $xform_path $runno_transform_clean");
		}
	    }
	}
    }
    
    my $case = 2;
    my ($dummy,$error_message)=create_affine_reg_to_atlas_Output_check($case);

    my $write_path_for_Hf = "${current_path}/${PM}_current.headfile";
    $Hf->write_headfile($write_path_for_Hf);

    # Clean up derived transforms.
    # Now in Pure Perl :D!
    my @excess_mats=find_file_by_pattern(${current_path},'.*Derived.*mat$',1);
    chomp(@excess_mats);
    # tests each thing found in excess mats, but we really only ever run one time;
    foreach (@excess_mats) {
	unlink $_;
    }

    my $PM_code;
    if ($do_rigid) {
        $PM_code = 21;
    } elsif (! $mdt_to_atlas) {
        $PM_code = 39;
    } else {
        $PM_code = 61;
    }
    
    my $real_time = vbm_write_stats_for_pm($PM_code,$Hf,$start_time,@jobs);
    print "$PM took ${real_time} seconds to complete.\n";
    @jobs=();
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
        if (data_double_check($full_file_1,$case-1)) {
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
    #($to_xform_path,  $alt_result_path_base, $runno);
    my ($B_path, $result_transform_path_base,$moving_runno) = @_;
    my $collapse = 0;
    my $transform_path="${result_transform_path_base}0GenericAffine.mat";

    if (($xform_code ne 'rigid1') && (! $mdt_to_atlas)){
        $transform_path="${result_transform_path_base}1Affine.mat"; #2Affine.mat      
    }
    
    my ($q,$r)=('','');
    if ((! $do_rigid) && (! $mdt_to_atlas)) {
        $r_string = "${current_path}/${moving_runno}_${other_xform_suffix}";
    }

    if ($swap_fixed_and_moving){
        my $tmp_string = $q_string;
        $q_string=$r_string;
        $r_string=$tmp_string;
    } 
    if ((defined $q_string) && ($q_string ne '')) {
        $q = "-q $q_string"; 
    }
    if ((defined $r_string) && ($r_string ne '')) {
        $r = "-r $r_string";
    }

    my ($fixed,$moving);
    if ($swap_fixed_and_moving){
        $moving = $atlas_path;
        $fixed = $B_path;
    } else {
        $fixed = $atlas_path;
        $moving = $B_path;
    }
    confess "Err missing m:$moving" if ! -e $moving;
    confess "Err missing f:$fixed" if ! -e $fixed;
    
    my ($metric_1,$metric_2);
    $metric_1 = " -m ${affine_metric}[${fixed},${moving},1,${affine_radius},${affine_sampling_options}]";
    $metric_2 = '';
    if (($mdt_to_atlas) && ($mdt_contrast_2 ne '')) {
        my $fixed_2 = $Hf->get_value ('label_atlas_path_2');
        my $moving_2 =  $mdt_path."/MDT_${mdt_contrast_2}".$out_ext; # added .gz 22 October 2015
        if ($swap_fixed_and_moving) {
            $metric_2 = " -m ${affine_metric}[ ${moving_2},${fixed_2},1,{$affine_radius},${affine_sampling_options}]"
        } else {
            #random,0.3
            $metric_2 = " -m ${affine_metric}[ ${fixed_2},${moving_2},1,{$affine_radius},${affine_sampling_options}]"; 
        }
    }
        
    my $cmd;
    if ($xform_code eq 'rigid1') {
        # if ($mdt_to_atlas) {  # We don't do rigid separately from affine for MDT to Atlas.
        #         $cmd = "antsRegistration -d $dims ".
        #             " ${metric_1} ${metric_2} -t rigid[${affine_gradient_step}] -c [${affine_iterations},${affine_convergence_thresh},${affine_convergence_window}] ". 
        # " -s ${affine_smoothing_sigmas}  -f  ${affine_shrink_factors}  ". #-s 4x2x1x1vox -f 6x4x2x1
        #             " -u 1 -z $collapse -l 1 -o $result_transform_path_base --affine-gradient-descent-option 0.05x0.5x1.e-4x1.e-4"; 
        # } else {
        $cmd = "antsRegistration -v ${ants_verbosity} -d ${dims} -r [${fixed},${moving},1] ". 
            " ${metric_1} ${metric_2} -t rigid[${affine_gradient_step}] -c [ ${affine_iterations},${affine_convergence_thresh},${affine_convergence_window} ] ".
            " -s ${affine_smoothing_sigmas} -f ${affine_shrink_factors}  ". #-f 6x4x2x1
            " $q $r -u 1 -z 1 -o $result_transform_path_base";# --affine-gradient-descent-option 0.05x0.5x1.e-4x1.e-4";
        # }       
    } elsif ($xform_code eq 'full_affine') {
        if ($mdt_to_atlas) {
            $cmd = "antsRegistration -v ${ants_verbosity} -d ${dims} ". # 3 Feb 2016: do I want rigid and affine separate?
                #" ${metric_1} ${metric_2} -t rigid[${affine_gradient_step}] -c [${affine_iterations},${affine_convergence_thresh},${affine_convergence_window}] ". 
                #" -s ${affine_smoothing_sigmas} -f ${affine_shrink_factors}  ". # -s 4x2x1x1vox -f  6x4x2x1 
                " ${metric_1} ${metric_2} -t affine[${affine_gradient_step}] -c [ ${affine_iterations},${affine_convergence_thresh},${affine_convergence_window} ] ". 
                " -s  ${affine_smoothing_sigmas} -f ${affine_shrink_factors} ". # -s 4x2x1x0vox  -f  6x4x2x1 
                " -u 1 -z 1 -l 1 -o $result_transform_path_base";# --affine-gradient-descent-option 0.05x0.5x1.e-4x1.e-4";  # "-z 1" instead of "-z $collapse", as we want rigid + affine together in this case.
        } else {          
            $cmd = "antsRegistration -v ${ants_verbosity} -d ${dims} ". #-r [$atlas_path,$B_path,1] ".
                " ${metric_1} ${metric_2} -t affine[${affine_gradient_step}] -c [ ${affine_iterations},${affine_convergence_thresh},${affine_convergence_window} ] ".
                "-s ${affine_smoothing_sigmas} -f  ${affine_shrink_factors} -l 1 ". # -s 4x2x1x0.5vox-f 6x4x2x1
                " $q $r -u 1 -z $collapse -o $result_transform_path_base";# --affine-gradient-descent-option 0.05x0.5x1.e-4x1.e-4";
        }
    } else {
        error_out("$PM: create_transform: don't understand xform_code: $xform_code\n");
    }
    
    my @list = split '/', $atlas_path;
    my $A_file = pop @list;
    my ($dum,$B_name,$b_e) = fileparts($B_path,3);
    my $go_message =  "create ${xform_code} transform for ${B_name}".$b_e;
    my $stop_message = "$PM: create_transform: could not make transform: $cmd\n";
    my @test=(0);
    if (defined $reservation) {
        @test =(0,$reservation);
    }
    my $jid = 0;
    if (cluster_check) {
        my ($home_path,$dummy1,$dummy2) = fileparts($result_transform_path_base,2);
        my $Id= "${moving_runno}_create_affine_registration";
        my $verbose = 1; # Will print log only for work done.
        $jid = cluster_exec($go, $go_message, $cmd,$home_path,$Id,$verbose,$mem_request,@test);
        if (not $jid) {
            error_out($stop_message);
        }
    } else {
        if (! execute($go, $go_message, $cmd) ) {
            error_out($stop_message);
        }
    }
    # my $transform_path = "${result_transform_path_base}Affine.txt"; # From previous version of Ants, perhaps?
    #if (data_double_check($transform_path,1) && $go && (not $jid)) {
    if ($go && (not $jid)) {
	# I think that data_double_checking transform path here causes this to wait for completion,
	# while erroneously giving errors.
        error_out("$PM: could not start for xform: $transform_path");
    }
    print "** $PM: create_transform $xform_code creating $transform_path\n";
    return($transform_path,$jid);
}

# ------------------
sub create_affine_reg_to_atlas_vbm_Init_check {
# ------------------
    my $init_error_msg='';
    my $message_prefix="$PM:\n";
    my $rigid_contrast;



    # PROPOSED CHANGE TO TRANSFORMING
    # A
    #File::Spec->catfile($ThisPackageInRoot,"transforms","MDT_to_${TargetDataPackage}")  ,
    # B
    #File::Spec->catfile($ThisPackageInRoot,"transforms")  ,
    # (CURRENT)
    #File::Spec->catfile($ThisPackageInRoot,"stats_by_region","labels","transforms")


# check for valid atlas
    (my $rc_ok,$rigid_contrast) = $Hf->get_value_check('rigid_contrast');
    (my $ac_ok, my $affine_contrast) = $Hf->get_value_check('affine_contrast');
    if (! $rc_ok) {
        if ($ac_ok) {
            $rigid_contrast = $affine_contrast;
            $log_msg=$log_msg."\tNo rigid contrast specified; inheriting contrast used for affine registration: \"${rigid_contrast}\" for rigid  registrations.\n";
        } else {
            my $channel_comma_list = $Hf->get_value('channel_comma_list');
	    if ($channel_comma_list =~ /(dwi)/i) {
                $rigid_contrast = $1;
                $log_msg=$log_msg."\tNo rigid contrast specified; using default contrast: \"${rigid_contrast}\" for rigid  registrations.\n";
            } else {
                my @channels = split(',',${channel_comma_list});
                $rigid_contrast = shift(@channels);
                #$Hf->set_value('affine_contrast',$affine_contrast);
                $log_msg=$log_msg."\tNo rigid contrast specified; using first specified contrast: \"${rigid_contrast}\" for rigid  registrations.\n";
            }
        }
        $Hf->set_value('rigid_contrast',$rigid_contrast);
    }

    my ($v_ok, $rigid_work_dir) = $Hf->get_value_check('rigid_work_dir');
    #if ($rigid_work_dir eq 'NO_KEY') {
    if (! $v_ok) {
        my $w_path = $Hf->get_value('dir_work');
        $rigid_work_dir = "${w_path}/${rigid_contrast}";
        $Hf->set_value('rigid_work_dir',$rigid_work_dir);
    }
    if (-d $rigid_work_dir) {
        my $affine_tag="${rigid_work_dir}/affine_target.txt";
        if ( -f $affine_tag) {
            #my $found_affine_target = `cat ${affine_tag}`;
	    my ($found_affine_target) = run_and_watch("cat ${affine_tag}");
            $Hf->set_value('affine_target', $found_affine_target);
        } else {
            # BJ desperately wants to use a diff against the identity matrix to find a previously used affine target...will have to do it behind James' back.
        }
    }

    if ($affine_contrast eq ('' || 'NO_KEY' || 'UNDEFINED_VALUE')) {
        #$affine_contrast = $defaults_Hf->get_value('affine_contrast');
        $affine_contrast = $Hf->get_value('rigid_contrast');
        $Hf->set_value('affine_contrast',$affine_contrast);
        $log_msg=$log_msg."\tNo affine contrast specified; using rigid contrast \"${rigid_contrast}\" for affine registrations.\n";
    }

    if ($register_MDT_to_atlas || $create_labels) {
        $mdt_contrast_string = $Hf->get_value('mdt_contrast'); 
        @mdt_contrasts = split('_',$mdt_contrast_string); 
        $mdt_contrast = $mdt_contrasts[0];
	# Atlas path in this context is atlas image, and annoyingly is just a short term temp var 
        my $label_atlas_name = $Hf->get_value('label_atlas_name');
        my $label_atlas_dir=''; 
        # Test to see if this is an arbitrary file/folder
        if ( -e $label_atlas_name) {
            if ( -d $label_atlas_name) {
		# Its a directory, so we're in kinda normal mode.
                $label_atlas_dir=$label_atlas_name;
		# silly slash fixer here.
                $label_atlas_dir =~ s/[\/]*$//;
                (my $dummy_path , $label_atlas_name) = fileparts($label_atlas_dir,2);
                $atlas_path  = get_nii_from_inputs($label_atlas_dir,$label_atlas_name,$mdt_contrast);
            } else { 
                #  Assume its a specific LABEL file
		$atlas_path = $label_atlas_name;
                (my $dummy_path , $label_atlas_name) = fileparts($label_atlas_name,2);
                $label_atlas_name =~ s/_$samba_label_types$//x;
            }
        } else {
            #print("label_atlas_name not a direct object\n\t($label_atlas_name)\n");die;
            $label_atlas_dir = "${WORKSTATION_DATA}/atlas/${label_atlas_name}";
            if (! -d $label_atlas_dir) {
                if ($label_atlas_dir =~ s/\/data/\/CIVMdata/) {}
            }
            $atlas_path  = get_nii_from_inputs($label_atlas_dir,$label_atlas_name,$mdt_contrast);
        }
        
        if (data_double_check($atlas_path))  {
            $init_error_msg = $init_error_msg."For mdt contrast ${mdt_contrast}: missing atlas nifti file ${atlas_path}\n";
        } else {
            $Hf->set_value('label_atlas_path',$atlas_path);
            $Hf->set_value('label_atlas_dir',$label_atlas_dir);
        }
        $Hf->set_value('label_atlas_name',$label_atlas_name);
        if ($#mdt_contrasts > 0) {
            $mdt_contrast_2 = $mdt_contrasts[1];            
            $atlas_path  = "${label_atlas_dir}/${label_atlas}_${mdt_contrast_2}".$out_ext;
            if (data_double_check($atlas_path))  {
                $init_error_msg = $init_error_msg."For secondary affine contrast ${mdt_contrast_2}: missing atlas nifti file ${atlas_path}\n";
            } else {
                $Hf->set_value('label_atlas_path_2',$atlas_path);
            }
        } 
    }
    # set the globals :p
    $inputs_dir = $Hf->get_value('inputs_dir');
    $affine_metric = $Hf->get_value('affine_metric');
    my @valid_metrics = ('CC','MI','Mattes','MeanSquares','Demons','GC');
    my $valid_metrics = join(', ',@valid_metrics);
    my $metric_flag = 0;
    if ($affine_metric eq ('' || 'NO_KEY')) {
        #$affine_metric = $defaults_Hf->get_value('affine_metric');
        $affine_metric = 'Mattes';
        $metric_flag = 1;
        $log_msg = $log_msg."\tNo ants metric specified for all rigid and/or affine registrations. Will use default: \"${affine_metric}\".\n";
    } else {
        foreach my $metric (@valid_metrics) {
            if ($affine_metric =~ /^$metric\Z/i) { # This should be able to catch any capitalization variation and correct it.
                $affine_metric = $metric;
                $metric_flag = 1;
                $log_msg=$log_msg."\tUsing ants metric \"${affine_metric}\" for all rigid and/or affine registrations.\n";
            }
        }
    }
    if (! $metric_flag) {
        $init_error_msg=$init_error_msg."Invalid ants metric requested for all rigid and/or affine registrations \"${affine_metric}\".\n".
            "\tValid metrics are: ${valid_metrics}\n";
    } else {
        $Hf->set_value('affine_metric',$affine_metric);
    }

    $affine_radius=$Hf->get_value('affine_radius');
    if ($affine_radius eq ('' || 'NO_KEY')) {
        #$affine_radius = $defaults_Hf->get_value('affine_radius');
        $affine_radius = 32;
        $log_msg = $log_msg."\tNo affine radius specified; using default value of \"${affine_radius}\".\n";
    } elsif ($affine_radius =~ /^[0-9\.]+$/) {
        # It is assumed that any positive number is righteous.
    } else {
        $init_error_msg=$init_error_msg."Non-numeric affine radius specified: \"${affine_radius}\".\n";
    }
    $Hf->set_value('affine_radius',$affine_radius);
    
    $affine_iterations=$Hf->get_value('affine_iterations');
    my @affine_iteration_array;
    my $affine_levels=0;
    if (! ($affine_iterations eq ('' || 'NO_KEY'))) {
        if ($affine_iterations =~ /(,([0-9]+)+)/) {
            @affine_iteration_array = split(',',$affine_iterations);
            my $input_affine_iterations=$affine_iterations;
            $affine_iterations = join('x',@affine_iteration_array);
            $log_msg=$log_msg."\tConverting affine iterations from \"${input_affine_iterations}\" to \"${affine_iterations}\".\n";
        }
        if ($affine_iterations =~ /(x([0-9]+)+)/) {
            @affine_iteration_array = split('x',$affine_iterations);
            $affine_levels=1+$#affine_iteration_array;
        } elsif ($affine_iterations =~ /^[0-9]+$/) {
            $affine_levels=1;
        } else {
            $init_error_msg=$init_error_msg."Non-numeric or non-integer  affine iterations specified: \"${affine_iterations}\". ".
                "Multiple iteration levels may be \'x\'- or comma-separated.\n";
        }
    } else {
        $affine_levels = 4;
    }
    if ((defined $test_mode) && ($test_mode==1)) {
        $affine_iterations = '1';           
        for (my $jj = 2; $jj <= $affine_levels; $jj++) {
            $affine_iterations = $affine_iterations.'x0';
        }
        $log_msg = $log_msg."\tRunning in TEST MODE: using minimal affine iterations:  \"${affine_iterations}\".\n";
    } else {
        if ($affine_iterations eq ('' || 'NO_KEY')) {
            #$affine_iterations = $defaults_Hf->get_value('affine_iterations');
            $affine_iterations="3000x3000x0x0";
            $log_msg = $log_msg."\tNo affine iterations specified; using default values:  \"${affine_iterations}\".\n";
        }
    }
    $log_msg=$log_msg."\tNumber of levels for affine registration=${affine_levels}.\n"; 
    $Hf->set_value('affine_iterations',$affine_iterations);

    $affine_shrink_factors=$Hf->get_value('affine_shrink_factors');
    if ( $affine_shrink_factors eq ('' || 'NO_KEY')) {
        #$affine_shrink_factors = $defaults_Hf->get_value('affine_shrink_factors_${affine_levels}');
        $affine_shrink_factors = '1';
        my $temp_shrink=2;          
        for (my $jj = 2; $jj <= $affine_levels; $jj++) {
            $affine_shrink_factors = $temp_shrink.'x'.$affine_shrink_factors;
            $temp_shrink = 2+$temp_shrink;
        }
        $log_msg = $log_msg."\tNo affine shrink factors specified; using default values:  \"${affine_shrink_factors}\".\n";
    } else {
        my @affine_shrink_array;
        my $affine_shrink_levels;
        if ($affine_shrink_factors =~ /(,[0-9\.]+)+/) {
            @affine_shrink_array = split(',',$affine_shrink_factors);
            my $input_affine_shrink_factors=$affine_shrink_factors;
            $affine_shrink_factors = join('x',@affine_shrink_array);
            $log_msg=$log_msg."\tConverting affine shrink factors from \"${input_affine_shrink_factors}\" to \"${affine_shrink_factors}\".\n";
        }
        if ($affine_shrink_factors =~ /(x[0-9\.]+)+/) {
            @affine_shrink_array = split('x',$affine_shrink_factors);
            $affine_shrink_levels=1+$#affine_shrink_array;
        } elsif ($affine_shrink_factors =~ /^[0-9\.]+$/) {
            $affine_shrink_levels=1;
        } else {
            $init_error_msg=$init_error_msg."Non-numeric affine shrink factor(s) specified: \"${affine_shrink_factors}\". ".
                "Multiple shrink factors may be \'x\'- or comma-separated.\n";
        }
        
        if ($affine_shrink_levels != $affine_levels) {
            $init_error_msg=$init_error_msg."Number of affine levels (${affine_shrink_levels}) implied by the specified affine shrink factors \"${affine_shrink_factors}\" ".
                "does not match the number of levels implied by the affine iterations (${affine_levels}).\n";
        }
    }
    $Hf->set_value('affine_shrink_factors',$affine_shrink_factors);

    $affine_gradient_step=$Hf->get_value('affine_gradient_step');
    if ($affine_gradient_step eq ('' || 'NO_KEY')) {
        #$affine_gradient_step = $defaults_Hf->get_value('affine_gradient_step');
        $affine_gradient_step = 0.1;
        $log_msg = $log_msg."\tNo affine gradient step specified; using default value of \"${affine_gradient_step}\".\n";
    } elsif ($affine_gradient_step =~ /^[0-9\.]+$/) {
        # It is assumed that any positive number is righteous.
    } else {
        $init_error_msg=$init_error_msg."Non-numeric affine gradient step specified: \"${affine_gradient_step}\".\n";
    }
    $Hf->set_value('affine_gradient_step',$affine_gradient_step);

    $affine_convergence_thresh=$Hf->get_value('affine_convergence_thresh');
    if (  $affine_convergence_thresh eq ('' || 'NO_KEY')) {
        #$affine_convergence_thresh = $defaults_Hf->get_value('affine_convergence_thresh');
        $affine_convergence_thresh = '1e-8';
        $log_msg = $log_msg."\tNo affine convergence threshold specified; using default value of \"${affine_convergence_thresh}\".\n";
    } elsif ($affine_convergence_thresh =~ /^[0-9\.]+(e(-|\+)?[0-9]+)?/) {
        # Values specified in scientific notation need to be accepted as well.
    } else {
        $init_error_msg=$init_error_msg."Invalid affine convergence threshold specified: \"${affine_convergence_thresh}\". ".
            "Real positive numbers are accepted; scientific notation (\"X.Ye-Z\") are also righteous.\n";
    }
    $Hf->set_value('affine_convergence_thresh',$affine_convergence_thresh);    

    my $acw_error = 0;
    $affine_convergence_window=$Hf->get_value('affine_convergence_window');
    if (  $affine_convergence_window eq ('' || 'NO_KEY')) {
        #$affine_convergence_window = $defaults_Hf->get_value('affine_convergence_window');
        $affine_convergence_window = 20;
        $log_msg = $log_msg."\tNo affine convergence window specified; using default value of \"${affine_convergence_window}\".\n";
    } elsif ($affine_convergence_window =~ /^[0-9]+$/) {
        if ($affine_convergence_window < 5) {
            $acw_error=1;
        }
    } else {
        $acw_error=1;
    }
    if ($acw_error) {
        $init_error_msg=$init_error_msg."Invalid affine convergence window specified: \"${affine_convergence_window}\". ".
            "Window size must be an integer greater than 5.\n";
    } else {
        $Hf->set_value('affine_convergence_window',$affine_convergence_window);
    }

    $affine_smoothing_sigmas=$Hf->get_value('affine_smoothing_sigmas');
    my $input_affine_smoothing_sigmas=$affine_smoothing_sigmas;
    if (  $affine_smoothing_sigmas eq ('' || 'NO_KEY')) {
        #$affine_smoothing_sigmas = $defaults_Hf->get_value('affine_smoothing_sigmas_${affine_levels}');
        $affine_smoothing_sigmas = '0.5vox';
        my $temp_sigma=0.5;         
        for (my $jj = 2; $jj <= $affine_levels; $jj++) {
            $temp_sigma = 2*$temp_sigma;
            $affine_smoothing_sigmas = $temp_sigma.'x'.$affine_smoothing_sigmas;
        }
        $log_msg = $log_msg."\tNo affine smoothing sigmas specified; using default values:  \"${affine_smoothing_sigmas}\".\n";
    } else {
        my $affine_smoothing_units ='';
        my @affine_smoothing_array;
        my $affine_smoothing_levels;
        $affine_smoothing_sigmas =~ s/[\s]+//g;  #Strip any extraneous whitespace
        if ($affine_smoothing_sigmas =~ s/([^0-9\.]*)$//) {
            $affine_smoothing_units = $1;
        } 
        if ($affine_smoothing_units =~ /^(mm|vox|)$/) {
            if ($affine_smoothing_sigmas =~ /(,[0-9\.]+)+/) {
                @affine_smoothing_array = split(',',$affine_smoothing_sigmas);
                $affine_smoothing_sigmas = join('x',@affine_smoothing_array);
                $log_msg=$log_msg."\tConverting affine smoothing sigmas from \"${input_affine_smoothing_sigmas}\" to \"${affine_smoothing_sigmas}${affine_smoothing_units}\".\n";
            }
            if ($affine_smoothing_sigmas =~ /(x[0-9\.]+)+/) {
                @affine_smoothing_array = split('x',$affine_smoothing_sigmas);
                $affine_smoothing_levels=1+$#affine_smoothing_array;
            } elsif ($affine_smoothing_sigmas =~ /^[0-9\.]+$/) {
                $affine_smoothing_levels=1;
            } else {
                $init_error_msg=$init_error_msg."Non-numeric affine smoothing factor(s) specified: \"${input_affine_smoothing_sigmas}\". ".
                    "Multiple smoothing factors may be \'x\'- or comma-separated.\n";
            }
            
            if ($affine_smoothing_levels != $affine_levels) {
                $init_error_msg=$init_error_msg."Number of affine levels (${affine_smoothing_levels}) implied by the specified affine smoothing factors \"${affine_smoothing_sigmas}\" ".
                    "does not match the number of levels implied by the affine iterations (${affine_levels})\n";
            } 
        } else {
            $init_error_msg=$init_error_msg."Units specified for affine smoothing sigmas \"${input_affine_smoothing_sigmas}\" are not valid. ".
                "Acceptable units are either \'vox\' or \'mm\', or may be omitted (equivalent to \'mm\').\n";
        }
        
        $affine_smoothing_sigmas = $affine_smoothing_sigmas.$affine_smoothing_units;
    }
    $Hf->set_value('affine_smoothing_sigmas',$affine_smoothing_sigmas);

    #   my $affine_smoothing_units ='';
    #   if ($affine_smoothing_sigmas =~ s/[0-9\.]+(vox|mm)$//) {
    #       $affine_smoothing_units = $1;
    #   } 
    
    
    #   my @affine_smoothing_array;
    #   my $affine_smoothing_levels;
    #   if ($affine_smoothing_sigmas =~ /[0-9\.]+\s$/) {
    #       if ($affine_smoothing_sigmas =~ /(,[0-9\.]+)+/) {
    #           @affine_smoothing_array = split(',',$affine_smoothing_sigmas);
    #           my $input_affine_smoothing_sigmas=$affine_smoothing_sigmas;
    #           $affine_smoothing_sigmas = join('x',@affine_smoothing_array);
    #           $log_msg=$log_msg."\tConverting affine smoothing sigmas from \"${input_affine_smoothing_sigmas}\" to \"${affine_smoothing_sigmas}\".\n";
    #       }
    #       if ($affine_smoothing_sigmas =~ /(x[0-9\.]+)+/) {
    #           @affine_smoothing_array = split('x',$affine_smoothing_sigmas);
    #           $affine_smoothing_levels=1+$#affine_smoothing_array;
    #       } elsif ($affine_smoothing_sigmas =~ /^[0-9\.]+$/) {
    #           $affine_smoothing_levels=1;
    #       } else {
    #           $init_error_msg=$init_error_msg."Non-numeric affine smoothing factor(s) specified: \"${affine_smoothing_sigmas}\". ".
    #               "Multiple smoothing factors may be \'x\'- or comma-separated.\n";
    #       }
    
    #       if ($affine_smoothing_levels != $affine_levels) {
    #           $init_error_msg=$init_error_msg."Number of affine levels (${affine_smoothing_levels}) implied by the specified affine smoothing factors (\'${affine_smoothing_sigmas}\'\" ".
    #               "does not match the number of levels implied by the affine iterations (${affine_levels})\n";
    #       } 
    #   } else {
    #       $init_error_msg=$init_error_msg."Units specified for affine smoothing sigmas \"${affine_smoothing_sigmas}\" are not valid. ".
    #           "Acceptable units are either \'vox\' or \'mm\', or may be omitted (equivalent to \'mm\')./n";
    #   }
    
    #   $affine_smoothing_sigmas = $affine_smoothing_sigmas.$affine_smoothing_units;
    # }
    # $Hf->set_value('affine_smoothing_sigmas',$affine_smoothing_sigmas);
    
    $affine_sampling_options=$Hf->get_value('affine_sampling_options');
    if ($affine_sampling_options eq ('' || 'NO_KEY')) {
        #$affine_sampling_options = $defaults_Hf->get_value('affine_sampling_options');
        $affine_sampling_options='None';
        $log_msg = $log_msg."\tNo affine sampling option specified; using default values of \"${affine_sampling_options}\".\n";
    } else {
        my ($sampling_strategy,$sampling_percentage) = split(',',$affine_sampling_options);
        if ($sampling_strategy =~ /^Random$/i) {
            $sampling_strategy = 'Random';
        } elsif ($sampling_strategy =~ /^None$/i) {
            $sampling_strategy = 'None';
            $sampling_percentage = '';
        } elsif ($sampling_strategy =~ /^Regular$/i) {
            $sampling_strategy = 'Regular';
        } else {
            $init_error_msg=$init_error_msg."The specified affine sampling strategy \"${sampling_strategy}\" is".
                " invalid. Valid options are \'None\', \'Regular\', or \'Random\'.\n";
        }
        if ($sampling_strategy eq ('Random'||'Regular')) {
            if (($sampling_percentage >1) && ($sampling_percentage < 100)) {
                my $input_sampling_percentage = $sampling_percentage;
                $sampling_percentage = $sampling_percentage/100;  # We'll be nice and accept actual percentages for this input.
                $log_msg = $log_msg."\tSpecified affine sampling percentage \"${input_sampling_percentage}\" is greater than 1 and less than 100:".
                    " assuming value is a percentage instead of fractional; converting to fractional value: \"${sampling_percentage}\". \n";
            }
            if (($sampling_percentage <= 0) || ($sampling_percentage > 1)) {
                $init_error_msg=$init_error_msg."For affine sampling strategy = \"${sampling_strategy}\", specified sampling percentage ".
                    " of \"${sampling_percentage}\" is outside of the acceptable range [0,1], exclusive.\n";
            } else {
                if ($sampling_percentage ne ''){ 
                    $affine_sampling_options = $sampling_strategy.','.$sampling_percentage;
                } else {
                    $affine_sampling_options = $sampling_strategy;
                }
            }
        }
    }
    $Hf->set_value('affine_sampling_options',$affine_sampling_options);
    
    ## 
    ## ADD FUNCTIONALITY: Create an affine MDT (once per study) and allow that to be the affine target.
    # $affine_target=$Hf->set_value('affine_target');
    # if (  $affine_target eq ('' || 'NO_KEY')) {
    #   $affine_target =  = $defaults_Hf->get_value('affine_target');
    # }
    # $Hf->set_value('affine_target',$affine_target);
    ## ADD FUNCTIONALITY: Allow the rigid registration step to be skipped, creating rigid transforms from the identity transform.
    # $rigid_target=$Hf->set_value('rigid_target');
    # if (  $rigid_target eq ('' || 'NO_KEY')) {
    #   $rigid_target =  = $defaults_Hf->get_value('rigid_target');
    # }
    # $Hf->set_value('rigid_target',$rigid_target);
    
    if ($log_msg ne '') {
        log_info("${message_prefix}${log_msg}");
    }
    if ($init_error_msg ne '') {
        $init_error_msg = $message_prefix.$init_error_msg;
    }
    return($init_error_msg);
}

# ------------------
sub create_affine_reg_to_atlas_vbm_Runtime_check {
# ------------------
    $affine_iterations = $Hf->get_value('affine_iterations');
    $affine_metric = $Hf->get_value('affine_metric');
    $affine_radius = $Hf->get_value('affine_radius');
    $affine_shrink_factors = $Hf->get_value('affine_shrink_factors');
    $affine_gradient_step = $Hf->get_value('affine_gradient_step');
    $affine_convergence_thresh = $Hf->get_value('affine_convergence_thresh');
    $affine_convergence_window = $Hf->get_value('affine_convergence_window');
    $affine_smoothing_sigmas = $Hf->get_value('affine_smoothing_sigmas');
    $affine_sampling_options = $Hf->get_value('affine_sampling_options');

## ADD FUNCTIONALITY: It would be nice to be able to optionally specify any or all the affine registration parameters for 
#                     the affine_MDT creation and MDT to atlas registration (label creation).  All values would naturally
#                     default to the general affine options.
##

    #$dims=$Hf->get_value('image_dimensions');  
    $inputs_dir = $Hf->get_value('inputs_dir');
    if ($mdt_to_atlas) {
	# looks like fifmtar could be replaced with get_value_check.
        my $fifmtar = $Hf->get_value('fixed_image_for_mdt_to_atlas_registratation');
	if ((defined $fifmtar) && ($fifmtar ne 'NO_KEY')) {
            if ($fifmtar eq 'mdt') {
                $swap_fixed_and_moving=1;
            }
        }
        $label_atlas = $Hf->get_value('label_atlas_name');
	#2019-08-28 The grand task of unentangle labled bits
        #$work_path = $Hf->get_value('regional_stats_dir');
	$work_path = $Hf->get_value('label_transform_dir');
        #$labels_dir = $Hf->get_value('labels_dir');
        $current_path = $Hf->get_value('label_transform_dir');
	my $template_path = $Hf->get_value('template_work_dir');
        if ($work_path eq 'NO_KEY') {
            # my $predictor_path = $Hf->get_value('predictor_work_dir'); 
            #my $template_path = $Hf->get_value('template_work_dir');
	    #2019-08-28 The grand task of unentangle labled bits
            #$work_path = "${template_path}/stats_by_region";
	    my $old_fashioned_work_path="${template_path}/stats_by_region/labels/transforms";
	    # MAYBE we want to have this be per atlas?
            $work_path = "${template_path}/transforms";
	    my $rsd="${template_path}/vox_measure";
	    #$Hf->set_value('regional_stats_dir',$work_path);
	    $Hf->set_value('regional_stats_dir',$rsd);
            if (! -e $work_path ) {
		if ( ! -e $old_fashioned_work_path ) {
		    mkdir ($work_path,$permissions);
		} else {
		    printd(5,"Old data directory detected, Will attempt to link to new structure to omit completed work.\n");
		    sleep_with_countdown(5);
		    run_and_watch("ln -s $old_fashioned_work_path $work_path");
		}
            }
        }
	# Label path has no business being set here.
        #if ($labels_dir eq 'NO_KEY') {
	#    #2019-08-28 The grand task of unentangle labled bits
        #    #$labels_dir = "${work_path}/labels";
	#    $labels_dir = $Hf->get_value('regional_stats_dir')
	#	."/${current_label_space}_${label_refname}_space";
        #    $Hf->set_value('labels_dir',$labels_dir);
        #    if (! -e $labels_dir) {
        #        mkdir ($labels_dir,$permissions);
        #    }
        #}
        if ($current_path eq 'NO_KEY') {
	    #2019-08-28 The grand task of unentangle labled bits
            #$current_path = "${labels_dir}/transforms"; #$current_path = "${work_path}/labels_${label_atlas}";
            $current_path = "${work_path}";
            $Hf->set_value('label_transform_dir',$current_path);
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
        } else {
            $mdt_contrast_2 = '';
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
            symbolic_link_cleanup($current_path,$PM);
        }
        @array_of_runnos = ("MDT_${mdt_contrast}");

    } else {
        $work_path = $Hf->get_value('dir_work');
        (my $c_ok,$current_path) = $Hf->get_value_check('rigid_work_dir');
        if ($do_rigid) {
            my $rigid_target=$Hf->get_value('rigid_target');
	    $contrast = $Hf->get_value('rigid_contrast');
	    my $updated_rigid_target;
            if ($rigid_target ne 'NO_KEY') {
		# wtf... we update it if it's set? ... 
                $updated_rigid_target=get_nii_from_inputs($inputs_dir,$rigid_target,$contrast);
                if ($updated_rigid_target =~ /[\n]+/) {
		    # get_nii_from_inputs was unsuccessful in finding a file.
                    log_info("$PM: Rigid target was specified but did not conform to runno format; assuming it is an arbitrary image specified by the user.");
                } else {
                    $Hf->set_value('rigid_atlas_path',$updated_rigid_target);
                    print "Rigid atlas path = ${updated_rigid_target}\n";
                }
            }
	    # Extra debugging in status... 
	    my @status=();
	    #push(@status,"missing updated $updated_rigid_target") if ! -e $updated_rigid_target;
	    #push(@status,"missing rigid_target $rigid_target") if ! -e $rigid_target;
            #if ($current_path eq 'NO_KEY') {
	    if ( ! $c_ok) {
                $current_path = "${work_path}/${contrast}";
                $Hf->set_value('rigid_work_dir',$current_path);
		carp("rigid_work_dir was not set when we got here, so we're setting it now");
		sleep_with_countdown(1);
            }
	    push(@status,"missing rigid_work_dir $current_path") if ! -e $current_path;
            if (! -e $current_path) {
                mkdir ($current_path,$permissions);
            }
            
            $atlas_path   = $Hf->get_value ('rigid_atlas_path');
            $xform_code = 'rigid1';
            $xform_suffix = $Hf->get_value('rigid_transform_suffix');
            $q_string = '';
            $r_string = '';
	    push(@status,"missing rigid_atlas_path $atlas_path") if ! -e $atlas_path;
	    die join("\n",@status) if scalar(@status)
        } else {
            #  25 January 2019: Default behavior is changing in a data-dependent way:
            #  If we change the control group (mdt group) population, then a different affine target might be selected.
            #  Apart from introducing a headfile checkpoint, we need to guard against a different affine target
            #  being used on a later run.  This is handled by dropping a short text file in the directory indicating
            #  which runno was used; this will take precedence over all other methods of target selection.
            #  For backwards compatability, a quick 'diff' check on all *_affine.mat files in directory,
            #  compared to the static identity matrix, will quickly tell us which one was previously used as the target.
            #  This will be done during the Init check?
            $contrast = $Hf->get_value('affine_contrast');
            
            $affine_target = $Hf->get_value('affine_target');
            if ($affine_target eq 'NO_KEY') {
                my @controls = split(',',($Hf->get_value('control_comma_list')));
                #if ($affine_target eq 'first_control') {
                #    $affine_target = shift(@controls);
                #} elsif ( $affine_target eq 'median') {

                # This code is a lazy way of setting the affine target to approximately the average-ish value.
                # In practice we use the median of the masked volume of the control images.
                # If there are an even number of control images, it will select the larger/smaller of the middle two.
                
                if (scalar @controls > 2) {
                    # James's CRAZY finder funtion, uses open dir, and a regex to match.
                    # this regex is (runnoA|runnoB).*$contrast.*[.]n.*
                    # note this finds any .n* images
                    # could/should set the "acceptable" images someplace and use that as part of the regex
                    # some annoying contrasts may collide... like fa./fa_color.... 
                    # BJ says: this makes it harder to control when all we want to return is runno to use, not the whole file name
                    #my @control_images=civm_simple_util::find_file_by_pattern($inputs_dir, '('.join("|",@controls).').*_'.$contrast.'_masked[.]n.{2,5}$');
                    my %volume_hash;
                    for my $c_runno (uniq(@controls)) {
                        my $c_file = get_nii_from_inputs($inputs_dir, $c_runno, "${contrast}_masked");
                        if ($c_file !~ /[\n]+/) {
			    confess("cannot fslstats on nhdr")if $c_file =~ /(nhdr|nrrd)$/x;
                            #my $volume = `fslstats ${c_file} -V | cut -d ' ' -f2`;
                            my ( $volume ) = run_and_watch("fslstats ${c_file} -V | cut -d ' ' -f2");
                            chomp($volume);
                            $volume_hash{$volume}=$c_runno;
                        }
		    }
                    use List::Util qw(sum);
                    use civm_simple_util qw(round);
                    
                    my @sorted_v = sort(keys %volume_hash);
                    my $v_index = round($#sorted_v/2);
                    my $mean_v= round(sum(@sorted_v)/scalar(@sorted_v));
                    for(my $i=0;$i<scalar(@sorted_v);$i++) {
                        if( abs($sorted_v[$v_index]-$mean_v) > abs($sorted_v[$i]-$mean_v) ) {
                            $v_index=$i;
                        }
                    }
                    $affine_target=$volume_hash{$sorted_v[$v_index]};
                } else {
                    $affine_target = shift(@controls);
                }
                my $affine_tag = "${current_path}/affine_target.txt";
		#`echo -n ${affine_target} > ${affine_tag}`;
		write_array_to_file($affine_tag,[$affine_target]);
                #}
            }# else
            #die $affine_target;
            
            $Hf->set_value('affine_target',$affine_target);

            $xform_code = 'full_affine';
            $xform_suffix = $Hf->get_value('affine_transform_suffix');
            $other_xform_suffix = $Hf->get_value('rigid_transform_suffix');

            $atlas_path  = get_nii_from_inputs($Hf->get_value('inputs_dir'),$affine_target,$contrast);
            $q_string = "${current_path}/${affine_target}_${other_xform_suffix}";
            symbolic_link_cleanup($current_path,$PM);

        }

        $runlist = $Hf->get_value('complete_comma_list');
	if ($runlist eq 'EMPTY_VALUE') {
            @array_of_runnos = ();
        } else {
            @array_of_runnos = split(',',$runlist);
        }

        my $control_runlist = $Hf->get_value('control_comma_list');
        if ($control_runlist eq 'EMPTY_VALUE') {
            @array_of_control_runnos = ();
        } else {
            @array_of_control_runnos = split(',',$control_runlist);
        }
    }

    my $case = 1;
    my ($dummy,$skip_message)=create_affine_reg_to_atlas_Output_check($case);

    if ($skip_message ne '') {
        print "${skip_message}";
    }
}
1;
