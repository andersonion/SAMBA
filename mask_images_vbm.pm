#!/usr/bin/env perl

# mask_images_vbm.pm 

# modified 2014/12/12 BJ Anderson for use in VBM pipeline.
# Based on convert_all_to_nifti.pm, as implemented by seg_pipe_mc
# modified 20130730 james cook, renamed flip_y to flip_x to be more accurate.
# modified 2012/04/27 james cook. Tried to make this generic will special handling for dti from archive cases.
# calls nifti code that can get dims from header
# created 2010/11/02 Sally Gewalt CIVM

my $PM = "mask_images_vbm.pm";
my $VERSION = "2014/12/23";
my $NAME = "Convert input data into the proper format, flipping x and/or z if need be.";

use strict;
use warnings;

#use Env qw(RADISH_PERL_LIB);
#if (! defined($RADISH_PERL_LIB)) {
#    print STDERR "Cannot find good perl directories, quitting\n";
#    exit;
#}
#use lib split(':',$RADISH_PERL_LIB);
use Env qw(ANTSPATH PATH BIGGUS_DISKUS ATLAS_FOLDER);

use Headfile;
use SAMBA_pipeline_utilities;

my ($current_path, $work_dir,$runlist,$ch_runlist,$in_folder,$out_folder,$do_mask,$mask_dir,$template_contrast);
my ($thresh_ref,$mask_threshold,$default_mask_threshold,$num_morphs,$morph_radius,$dim_divisor, $status_display_level);
my (@array_of_runnos,@channel_array);
my @jobs=();
my (%go_hash,%make_hash,%mask_hash);
my $go=1;
my ($port_atlas_mask_path,$port_atlas_mask);
my ($job);


# 01 July 2019, BJA: Will try to look for ENV variable to set matlab_execs and runtime paths

use Env qw(MATLAB_EXEC_PATH MATLAB_2015b_PATH); 
if (! defined($MATLAB_EXEC_PATH)) {
   $MATLAB_EXEC_PATH =  "${SAMBA_APPS_DIR}/matlab_execs";
}

if (! defined($MATLAB_2015b_PATH)) {
    $MATLAB_2015b_PATH =  "${SAMBA_APPS_DIR}/MATLAB/R2015b/";
}


my $matlab_path =  "${MATLAB_2015b_PATH}";
my $strip_mask_executable_path = "${MATLAB_EXEC_PATH}/strip_mask_executable/run_strip_mask_exec.sh"; 
if (! defined $dims) {$dims = 3;}
if (! defined $ants_verbosity) {$ants_verbosity = 1;}

# ------------------
sub mask_images_vbm {
# ------------------
    my $start_time = time;
    mask_images_vbm_Runtime_check();

    my @nii_cmds;
    my @nii_files;


## Make masks for each runno using the template contrast (usually dwi).
    foreach my $runno (@array_of_runnos) {
        my $go = $make_hash{$runno};
        if ($go) {
            my $current_file=get_nii_from_inputs($current_path,$runno,$template_contrast);
            if (($thresh_ref ne "NO_KEY") && ($$thresh_ref{$runno})){
                $mask_threshold = $$thresh_ref{$runno};
            } else {
		# Custom tc, a la original_orientation, added 26 July 2023 (Wed), by RJA
		my $Hf_key = "threshold_code_${runno}";
	        ${mask_threshold} = $Hf->get_value($Hf_key);
                if (${mask_threshold} eq 'NO_KEY') {
		    $mask_threshold=$default_mask_threshold;
		}
            }

            my $mask_path =  "${mask_dir}/${runno}_${template_contrast}_mask\.nii";
            if (data_double_check($mask_path,0))  {
		$mask_path = get_nii_from_inputs($current_path,$runno,'mask');
	    }

	    if (data_double_check($mask_path,0))  {
                $mask_path = "${mask_dir}/${runno}_${template_contrast}_mask\.nii";
            }

            my $ported_mask = $mask_dir.'/'.$runno.'_port_mask.nii';

            $mask_hash{$runno} = $mask_path;

            if ((! -e $mask_path) && (! -e $mask_path.".gz") ){
                if ( ( (! $port_atlas_mask)) || (($port_atlas_mask) && (! -e $ported_mask) && (! -e $ported_mask.'.gz')) ) {
                    ($job) =  strip_mask_vbm($current_file,$mask_path);
                    if ($job) {
                        push(@jobs,$job);
                    }
                }
            }
        }
    }

    if (cluster_check() && (@jobs)) {
        my $interval = 2;
        my $verbose = 1;
        my $done_waiting = cluster_wait_for_jobs($interval,$verbose,@jobs);
        
        if ($done_waiting) {
            print STDOUT  " Automated skull-stripping/mask generation based on ; moving on to next step.\n";
        }
    }

    @jobs=();

    if ($port_atlas_mask) {
        my $atlas_mask =$Hf->get_value('port_atlas_mask_path') ;
        foreach my $runno (@array_of_runnos) {
            my $go = $make_hash{$runno};
            if ($do_mask && $go){               
                my $ported_mask = $mask_dir.'/'.$runno.'_port_mask.nii.gz';
                if (data_double_check($ported_mask)) {
                    ($job) = port_atlas_mask_vbm($runno,$atlas_mask,$ported_mask);
                    if ($job) {
                        push(@jobs,$job);
                    }
                }
                $mask_hash{$runno} = $ported_mask;
            }
        }
        
        if (cluster_check() && ($#jobs != -1)) {
            my $interval = 2;
            my $verbose = 1;
            my $done_waiting = cluster_wait_for_jobs($interval,$verbose,@jobs);
            
            if ($done_waiting) {
                print STDOUT  "  All port_atlas_mask jobs have completed; moving on to next step.\n";
            }
        }
    }
    @jobs=(); # Reset job array;
## Apply masks to all images in each runno set.
    foreach my $runno (@array_of_runnos) {
        foreach my $ch (@channel_array) {
            my $go = $go_hash{$runno}{$ch};
            if ($go) {
		# 24 June 2020, BJA: Will not apply a mask to itself. It will still look silly: "mask_masked.nii.gz"...
		# And I'm sure we'll find a way to break this soon enough.
                if (($do_mask) && ( $ch ne 'mask' ) ) {
                    ($job) = mask_one_image($runno,$ch);
                } else {
                    ($job) = rename_one_image($runno,$ch);
                }   
                if ($job) {
                    push(@jobs,$job);
                }
            }
        }
    }

    if (cluster_check() && (@jobs)) {
        my $interval = 1;
        my $verbose = 1;
        my $done_waiting = cluster_wait_for_jobs($interval,$verbose,@jobs);

        if ($done_waiting) {
            print STDOUT  "  All input images have been masked; moving on to next step.\n";
        }
    }
    my $case = 2;
    my ($dummy,$error_message)=mask_images_Output_check($case);


    my $real_time = vbm_write_stats_for_pm($PM,$Hf,$start_time,@jobs);
    print "$PM took ${real_time} seconds to complete.\n";


    if (($error_message ne '') && ($do_mask)) {
        error_out("${error_message}",0);
    } else {
        # Clean up matlab junk
        if (`ls ${work_dir} | grep -E /.m$/`) {
            `rm ${work_dir}/*.m`;
        }
        if (`ls ${work_dir} | grep -E /matlab/`) {
            `rm ${work_dir}/*matlab*`;
        }
    }
}


# ------------------
sub mask_images_Output_check {
# ------------------

    my ($case) = @_;
    my $message_prefix ='';
    my ($file_1);
    my @file_array=();

    my $existing_files_message = '';
    my $missing_files_message = '';

    if ($case == 1) {
        if ($do_mask) {
            $message_prefix = "  Masked images have been found for the following runno(s) and will not be re-processed:\n";
        } elsif ($pre_masked){
	    $message_prefix = "  Pre-masked and properly named images have been found for the following runno(s) and will not be re-processed:\n";
	} else {
            $message_prefix = "  Unmasked and properly named images have been found for the following runno(s) and will not be re-processed:\n";
        }
    } elsif ($case == 2) {
        if ($do_mask) {
            $message_prefix = "  Unable to properly mask images for the following runno(s) and channel(s):\n";
        } elsif ($pre_masked) {
	    $message_prefix = "  Unable to properly rename the pre-masked images for the following runno(s) and channel(s):\n";
	} else {
            $message_prefix = "  Unable to properly rename the unmasked images for the following runno(s) and channel(s):\n";
        }
    }   # For Init_check, we could just add the appropriate cases.
    
    foreach my $runno (@array_of_runnos) {

	
	my $sub_existing_files_message='';
	my $sub_missing_files_message='';
	

	foreach my $ch (@channel_array) {
	    
	    if (($do_mask) || ($pre_masked) ) {
		$file_1 = "${current_path}/${runno}_${ch}_masked.nii";
	    } else {
		$file_1 = "${current_path}/${runno}_${ch}.nii";
	    }

	    if (data_double_check($file_1)) {
		$file_1 = $file_1.'.gz'; # 8 Feb 2016: added .gz    
	    }
	    
	    if (data_double_check($file_1,$case-1) ) { 
		$go_hash{$runno}{$ch}=1;#*$do_mask; Moving the $do_mask logic elsewhere because we want action either way.
		push(@file_array,$file_1);
		$sub_missing_files_message = $sub_missing_files_message."\t$ch";
	    } else {
		$go_hash{$runno}{$ch}=0;
		$sub_existing_files_message = $sub_existing_files_message."\t$ch";
	    }
	}


	if (($sub_existing_files_message ne '') && ($case == 1)) {
	    $existing_files_message = $existing_files_message.$runno."\t".$sub_existing_files_message."\n";
	} elsif (($sub_missing_files_message ne '') && ($case == 2)) {
	    $missing_files_message =$missing_files_message. $runno."\t".$sub_missing_files_message."\n";
	}

	if (($sub_missing_files_message ne '') && ($case == 1)) {
	    $make_hash{$runno} = $do_mask;
	} else {
	    $make_hash{$runno} = 0;
	}

    }
     
    my $error_msg='';
    
    if (($existing_files_message ne '') && ($case == 1)) {
	$error_msg =  "$PM:\n${message_prefix}${existing_files_message}\n";
    } elsif (($missing_files_message ne '') && ($case == 2)) {
	$error_msg =  "$PM:\n${message_prefix}${missing_files_message}\n";
    }
     
    my $file_array_ref = \@file_array;
    return($file_array_ref,$error_msg);
}

# ------------------
sub strip_mask_vbm {
# ------------------
    my ($input_file,$mask_path) = @_;

    my $jid = 0;
    my ($go_message, $stop_message);


    my $matlab_exec_args="${input_file} ${dim_divisor} ${mask_threshold} ${mask_path} ${num_morphs} ${morph_radius} ${status_display_level}";
    $go_message = "$PM: Creating mask from file: ${input_file}\n" ;
    $stop_message = "$PM: Failed to properly create mask from file: ${input_file}\n" ;

    my @test=(0);
    if (defined $reservation) {
	@test =(0,$reservation);
    }
    my $mem_request = '40000'; # Should test to get an idea of actual mem usage.

    if (cluster_check) {
	my $go =1;	    
#	my $cmd = $pairwise_cmd.$rename_cmd;
	my $cmd = "${strip_mask_executable_path} ${matlab_path} ${matlab_exec_args}";
	
	my $home_path = $current_path;
	my $Id= "creating_mask_from_contrast_${template_contrast}";
	my $verbose = 2; # Will print log only for work done.
	$jid = cluster_exec($go,$go_message , $cmd ,$home_path,$Id,$verbose,$mem_request,@test);     
	if (not $jid) {
	    error_out($stop_message);
	}
    }

    return($jid);
}




# ------------------
sub port_atlas_mask_vbm {
# ------------------
    my ($runno,$atlas_mask,$port_mask) = @_;

    my $input_mask = $mask_hash{$runno};
    my $new_mask = $mask_dir.'/'.$runno.'_atlas_mask.nii.gz'; # 2 Feb 2016: added '.gz'
    
     my $current_norm_mask = "${mask_dir}/${runno}_norm_mask.nii.gz";# 2 Feb 2016: added '.gz'
    my $out_prefix = $mask_dir.'/'.$runno."_mask_";
   # my $port_mask = $mask_dir.'/'.$runno.'_port_mask.nii';
    my $temp_out_file = $out_prefix."0GenericAffine.mat";
    my ($cmd,$norm_command,$atlas_mask_reg_command,$apply_xform_command,$new_norm_command,$cleanup_command);
    $norm_command='';
    $new_norm_command = "ImageMath 3 $port_mask Normalize $new_mask;\n";
    $cleanup_command=$cleanup_command."if [ -e \"${port_mask}\" ]\nthen\n\tif [ -e \"${new_mask}\" ]\n\tthen\n\t\trm ${new_mask};\n";
    
    if (! -e $new_mask) {
	$apply_xform_command = "antsApplyTransforms -v ${ants_verbosity} --float -d ${dims} -i $atlas_mask -o $new_mask -t [${temp_out_file}, 1] -r $current_norm_mask -n NearestNeighbor".
	    "\niMath 3 ${new_mask} MD ${new_mask} 2 1 ball 1;\nSmoothImage 3 ${new_mask} 1 ${new_mask} 0 1;\n"; #BJA, 19 Oct 2017: Added radius=2 dilation, and then smoothing of new mask.Added
	$cleanup_command=$cleanup_command."\t\tif [ -e \"${temp_out_file}\" ]\n\t\tthen\n\t\t\trm ${temp_out_file};\n";
	
	if (! -e $temp_out_file) {
	    $atlas_mask_reg_command = "antsRegistration -v ${ants_verbosity} -d ${dims} -r [$atlas_mask,$current_norm_mask,1] ".
#		" -m MeanSquares[$atlas_mask,$current_norm_mask,1,32,random,0.3] -t translation[0.1] -c [3000x3000x0x0,1.e-8,20] ".
#		" -m MeanSquares[$atlas_mask,$current_norm_mask,1,32,random,0.3] -t rigid[0.1] -c [3000x3000x0x0,1.e-8,20] ".
		" -m MeanSquares[$atlas_mask,$current_norm_mask,1,32,random,0.3] -t affine[0.1] -c [3000x3000x0x0,1.e-8,20] ". 
		" -s 4x2x1x0.5vox -f 6x4x2x1 -u 1 -z 1 -o $out_prefix;\n";# --affine-gradient-descent-option 0.05x0.5x1.e-4x1.e-4";
	
	    $cleanup_command=$cleanup_command."\t\t\tif [ -e \"${current_norm_mask}\" ]\n\t\t\tthen\n\t\t\t\trm ${current_norm_mask};\n\t\t\tfi\n";
	    if (! -e $current_norm_mask) {
		$norm_command = "ImageMath 3 $current_norm_mask Normalize $input_mask;\n";
	    }	    
	    }
	$cleanup_command=$cleanup_command."\t\tfi\n";
    }
    $cleanup_command=$cleanup_command."\tfi\nfi\n";
    
    $cmd = $norm_command.$atlas_mask_reg_command.$apply_xform_command.$new_norm_command;#.$cleanup_command;
    my @cmds =  ($norm_command,$atlas_mask_reg_command,$apply_xform_command,$new_norm_command,$cleanup_command);
    my $go_message =  "$PM: Creating port atlas mask for ${runno}\n";
    my $stop_message = "$PM: Unable to create port atas mask for ${runno}:  $cmd\n";
    
    my @test = (0);
    my $node = '';
    if (defined $reservation) {
	@test =(0,$reservation);
    }

    my $mem_request = 60000;

    my $jid = 0;
    if (cluster_check) {
	my ($home_path,$dummy1,$dummy2) = fileparts($port_mask,2);
	my $Id= "${runno}_create_port_atlas_mask";
	my $verbose = 2; # Will print log only for work done.
	$jid = cluster_exec($go, $go_message, $cmd,$home_path,$Id,$verbose,$mem_request,@test);     
	if (not $jid) {
	    error_out($stop_message);
	}
    } else {
	if (! execute($go, $go_message, @cmds) ) {
	    error_out($stop_message);
	}
    }

    if (data_double_check($port_mask)  && (not $jid)) {
	error_out("$PM: could not properly create port atlas mask: ${port_mask}");
	print "** $PM: port atlas mask created ${port_mask}\n";
    }
    return($jid);
}



# ------------------
sub mask_one_image {
# ------------------
    my ($runno,$ch) = @_;
    my $runno_mask;
#    if ($port_atlas_mask) {
#	$runno_mask=$mask_dir.'/'.$runno.'_port_mask.nii';
#    } else {
	$runno_mask = $mask_hash{$runno};
#    }
    my $out_path = "${current_path}/${runno}_${ch}_masked.nii.gz"; # 12 Feb 2016: Added .gz
    my $centered_path = get_nii_from_inputs($current_path,$runno,$ch);
    my $apply_cmd = "fslmaths ${centered_path} -mas ${runno_mask} ${out_path} -odt \"input\";"; # 7 March 2016, Switched from ants ImageMath command to fslmaths, as fslmaths should be able to automatically handle color_fa images. (dim =4 instead of 3).
    my $im_a_real_tensor = '';
    if ($centered_path =~ /tensor/){
	$im_a_real_tensor = '1';
    }
   # my $apply_cmd =  "ImageMath ${dims} ${out_path} m ${centered_path} ${runno_mask};\n";
    my $copy_hd_cmd = '';#"CopyImageHeaderInformation ${centered_path} ${out_path} ${out_path} 1 1 1 ${im_a_real_tensor};\n"; # 24 Feb 2018, disabling, function seems to be broken and wreaking havoc
    my $remove_cmd = "if [[ -f ${out_path} ]];then\n rm ${centered_path};\nfi\n";
    my $go_message = "$PM: Applying mask created by ${template_contrast} image of runno $runno" ;
    my $stop_message = "$PM: could not apply ${template_contrast} mask to ${centered_path}:\n${apply_cmd}\n" ;
    
    my @test = (0);
    my $node = '';
    
    if (defined $reservation) {
	@test =(0,$reservation);
    }

    my $mem_request = 100000; # 12 April 2017, BJA: added higher memory request (60000) because of nii4Ds...may need to even go higher, but really should do this smartly.
    # 10 July 2017, BJA: Increased from 60000, to 100000, because we were trying to process 8.1GB files
    my $jid = 0;
    if (cluster_check) {

    
	my $cmd = $apply_cmd.$copy_hd_cmd.$remove_cmd;
	
	my $home_path = $current_path;
	my $Id= "${runno}_${ch}_apply_${template_contrast}_mask";
	my $verbose = 2; # Will print log only for work done.
	$jid = cluster_exec($go,$go_message, $cmd ,$home_path,$Id,$verbose,$mem_request,@test);     
	if (! $jid) {
	    error_out($stop_message);
	}
    } else {

	my @cmds = ($apply_cmd,$remove_cmd);
	if (! execute($go, $go_message, @cmds) ) {
	    error_out($stop_message);
	}
    }

    if ((data_double_check($out_path)) && (not $jid)) {
	error_out("$PM: missing masked image: ${out_path}");
    }
    print "** $PM expected output: ${out_path}\n";
  
    return($jid);
}

# ------------------
sub rename_one_image {
# ------------------
    my ($runno,$ch) = @_;
    my $centered_path = get_nii_from_inputs($current_path,$runno,$ch); ## THIS IS WHERE THINGS PROBABLY BROKE  24 October 2018 (Wed)
    my $masked_prefix = 'un';    
    my $masked_suffix='';
    if ($pre_masked) {
	$masked_suffix = '_masked';
	$masked_prefix = 'pre';
    }
    my $out_path = "${current_path}/${runno}_${ch}${masked_suffix}.nii.gz"; # 12 Feb 2016: Added .gz # 29 August 2019: Added $masked_suffix.
    
    my $rename_cmd = "mv ${centered_path} ${out_path}";
   

    my $go_message = "$PM: Renaming ${masked_prefix}masked image from \"${centered_path}\" to \"${out_path}\"." ;
    my $stop_message = "$PM: Unable to rename ${masked_prefix}masked image from \"${centered_path}\" to \"${out_path}\":\n${rename_cmd}\n";
    
    my @test = (0);
    my $node = '';
    
    if (defined $reservation) {
        @test =(0,$reservation);
    }

    my $mem_request = 100000; # 12 April 2017, BJA: added higher memory request (60000) because of nii4Ds...may need to even go higher, but really should do this smartly.
    # 10 July 2017, BJA: Increased from 60000, to 100000, because we were trying to process 8.1GB files
    my $jid = 0;
    if (cluster_check) {

    
	my $cmd = $rename_cmd;
	
	my $home_path = $current_path;
	my $Id= "${runno}_${ch}_rename_${masked_prefix}masked_image";
	my $verbose = 2; # Will print log only for work done.
	$jid = cluster_exec($go,$go_message, $cmd ,$home_path,$Id,$verbose,$mem_request,@test);     
	if (! $jid) {
	    error_out($stop_message);
	}
    } else {

	my @cmds = ($rename_cmd);
	if (! execute($go, $go_message, @cmds) ) {
	    error_out($stop_message);
	}
    }

    if ((data_double_check($out_path)) && (not $jid)) {
        error_out("$PM: missing ${masked_prefix}masked image: ${out_path}");
    }
    print "** $PM expected output: ${out_path}\n";
  
    return($jid);
}



# ------------------
sub mask_images_vbm_Init_check {
# ------------------
    my $init_error_msg='';
    my $message_prefix="$PM initialization check:\n";
    my $log_msg='';

    $pre_masked = $Hf->get_value('pre_masked');
    $do_mask = $Hf->get_value('do_mask');

    if ($do_mask !~ /^(1|0)$/) {
        $init_error_msg=$init_error_msg."Variable 'do_mask' (${do_mask}) is not valid; please change to 1 or 0.";
    }

    $port_atlas_mask = $Hf->get_value('port_atlas_mask');

    if ($pre_masked  == 1) {
        $do_mask = 0;
        $Hf->set_value('do_mask',$do_mask);
        $port_atlas_mask = 0;
        $Hf->set_value('port_atlas_mask',$port_atlas_mask);
        $log_msg=$log_msg."\tImages have been pre-masked. No skulls will be stripped today.\n";
    }
    my $rigid_atlas_name = $Hf->get_value('rigid_atlas_name');
    $port_atlas_mask_path = $Hf->get_value('port_atlas_mask_path');
    $rigid_contrast = $Hf->get_value('rigid_contrast');
    my $rigid_atlas_path=$Hf->get_value('rigid_atlas_path');
    my $original_rigid_atlas_path=$Hf->get_value('original_rigid_atlas_path'); # Added 1 September 2016
    my $rigid_atlas=$Hf->get_value('rigid_atlas_name');


########
    my $source_rigid_atlas_path;
    my $runno_list= $Hf->get_value('complete_comma_list');
    my $preprocess_dir = $Hf->get_value('preprocess_dir');
    my $inputs_dir = $Hf->get_value('inputs_dir');
#    $rigid_atlas_name = $Hf->get_value('rigid_atlas_name');
#    $rigid_contrast = $Hf->get_value('rigid_contrast');
    my $rigid_target = $Hf->get_value('rigid_target');
    
    my $this_path;
    if ($rigid_atlas_name eq 'NO_KEY') {
        if ($rigid_target eq 'NO_KEY') {
            $Hf->set_value('rigid_atlas_path','null');
            $Hf->set_value('rigid_contrast','null');
            $log_msg=$log_msg."\tNo rigid target or atlas has been specified. No rigid registration will be performed. Rigid contrast is \"null\".\n";
        } else {
            if ($runno_list =~ /[,]*${rigid_target}[,]*}/) {
                $this_path=get_nii_from_inputs($preprocess_dir,$rigid_target,$rigid_contrast);
                if ($this_path !~ /[\n]+/) {
                   my ($dumdum,$this_name,$this_ext)= fileparts($this_path,2);
                   my $that_path = "${inputs_dir}/${this_name}${this_ext}";
                   #$Hf->set_value('rigid_atlas_path',$that_path);
                   $Hf->set_value('original_rigid_atlas_path',$that_path); #Updated 1 September 2016
                   $log_msg=$log_msg."\tA runno has been specified as the rigid target; setting ${that_path} as the expected rigid atlas path.\n";
                } else {
                    $init_error_msg=$init_error_msg."The desired target for rigid registration appears to be runno: ${rigid_target}, ".
                    "but could not locate appropriate image.\nError message is: ${this_path}";	    
                }
            } else {
                if (data_double_check($rigid_target)) {
                    $log_msg=$log_msg."\tNo valid rigid targets have been implied or specified (${rigid_target} could not be validated). Rigid registration will be skipped.\n";
                    $Hf->set_value('rigid_atlas_path','');
                    $Hf->set_value('original_rigid_atlas_path',''); # Added 1 September 2016
                } else {
                    $log_msg=$log_msg."\tThe specified file to be used as the original rigid target exists: ${rigid_target}. (Note: it has not been verified to be a valid image.)\n";
                   # $Hf->set_value('rigid_atlas_path',$rigid_target);
                    $Hf->set_value('original_rigid_atlas_path',$rigid_target);#Updated 1 September 2016
                }
            }
        }
    } else {
        if (($rigid_contrast eq 'NO_KEY') || ($rigid_contrast eq 'UNDEFINED_VALUE')){
            create_affine_reg_to_atlas_vbm::create_affine_reg_to_atlas_vbm_Init_check();
        }

        if (($rigid_contrast eq 'NO_KEY') || ($rigid_contrast eq 'UNDEFINED_VALUE')){
            $init_error_msg=$init_error_msg."No rigid contrast has been specified. Please set this to proceed.\n";
        } else {
            my $rigid_atlas_dir   = "${ATLAS_FOLDER}/${rigid_atlas_name}/";
            if (! -d $rigid_atlas_dir) {
                if ($rigid_atlas_dir =~ s/\/data/\/CIVMdata/) {}
            }
            my $expected_rigid_atlas_path = "${rigid_atlas_dir}${rigid_atlas_name}_${rigid_contrast}.nii";
            #$rigid_atlas_path  = get_nii_from_inputs($rigid_atlas_dir,$rigid_atlas_name,$rigid_contrast);
            if (data_double_check($expected_rigid_atlas_path)) {
                $expected_rigid_atlas_path = "${expected_rigid_atlas_path}.gz";
            }
            $source_rigid_atlas_path = $expected_rigid_atlas_path;
            my $test_path = get_nii_from_inputs($rigid_atlas_dir,$rigid_atlas_name,$rigid_contrast); #Added 14 March 2017
            if ($test_path =~ s/\.gz//) {} # Strip '.gz', 15 March 2017
            my ($dumdum,$rigid_atlas_filename,$rigid_atlas_ext)= fileparts($test_path,2);
            #$rigid_atlas_path =  "${inputs_dir}/${rigid_atlas_name}_${rigid_contrast}.nii";#Added 1 September 2016
            $rigid_atlas_path =  "${inputs_dir}/${rigid_atlas_filename}${rigid_atlas_ext}"; #Updated 14 March 2017

            if (data_double_check($rigid_atlas_path))  {
                $rigid_atlas_path=$rigid_atlas_path.'.gz';
                if (data_double_check($rigid_atlas_path))  {
                    $original_rigid_atlas_path  = get_nii_from_inputs($preprocess_dir,$rigid_atlas_name,$rigid_contrast);
                    if ($original_rigid_atlas_path =~ /[\n]+/) {
                        $original_rigid_atlas_path  = get_nii_from_inputs($rigid_atlas_dir,$rigid_atlas_name,$rigid_contrast);#Updated 1 September 2016
                        if (data_double_check($original_rigid_atlas_path))  { # Updated 1 September 2016
                            $init_error_msg = $init_error_msg."For rigid contrast ${rigid_contrast}: missing atlas nifti file ${expected_rigid_atlas_path}  (note optional \'.gz\')\n";
                        } else {
                            `cp ${original_rigid_atlas_path} ${preprocess_dir}`;
                            if ($original_rigid_atlas_path !~ /\.gz$/) {
                                `gzip ${preprocess_dir}/${rigid_atlas_name}_${rigid_contrast}.nii`;
                            } 
                        }
                    }
                } else {
                    `gzip ${rigid_atlas_path}`;
                    #$rigid_atlas_path=$rigid_atlas_path.'.gz'; #If things break, look here! 27 Sept 2016
                    $original_rigid_atlas_path = $expected_rigid_atlas_path;
                }
            } else {
                $original_rigid_atlas_path = $expected_rigid_atlas_path;
            }

            $Hf->set_value('rigid_atlas_path',$rigid_atlas_path);
            $Hf->set_value('original_rigid_atlas_path',$original_rigid_atlas_path); # Updated 1 September 2016
        }
    }

########

    if ($do_mask eq 'NO_KEY') { $do_mask=0;}
        if ($port_atlas_mask eq 'NO_KEY') { $port_atlas_mask=0;}
        my $default_mask = "${ATLAS_FOLDER}/chass_symmetric2/chass_symmetric2_mask.nii.gz"; ## Set default mask for porting here!
        if (! -f $default_mask) {
            if ($default_mask =~ s/\/data/\/CIVMdata/) {
                if (! -f $default_mask) {
                    $default_mask = "${default_mask}.gz";
                if (! -f $default_mask) {
                    if ($default_mask =~ s/\/CIVMdata/\/data/) {}
                }
            }
        }
    }


    if (($do_mask == 1) && ($port_atlas_mask == 1)) {
        #print "Port atlas mask path = ${port_atlas_mask_path}\n\n";
        if ($port_atlas_mask_path eq 'NO_KEY') {
            #print "source_rigid_atlas_path = ${source_rigid_atlas_path}\n\n\n\n";
            my ($dummy1,$rigid_dir,$dummy2);
            if (! data_double_check($source_rigid_atlas_path)){
            ($rigid_dir,$dummy1,$dummy2) = fileparts($source_rigid_atlas_path,2);
            $port_atlas_mask_path = get_nii_from_inputs($rigid_dir,$rigid_atlas_name,'mask');
            #print "Port atlas mask path = ${port_atlas_mask_path}\n\n"; #####
            #pause(15);
            if ($port_atlas_mask_path =~ /[\n]+/) {
                my ($dummy1,$original_rigid_dir,$dummy2);
                ($original_rigid_dir,$dummy1,$dummy2) = fileparts($source_rigid_atlas_path,2);
                $port_atlas_mask_path = get_nii_from_inputs($original_rigid_dir,$rigid_atlas_name,'mask');      
                if ($port_atlas_mask_path =~ /[\n]+/) {
                    $port_atlas_mask_path=$default_mask;  # Use default mask
                    $log_msg=$log_msg."\tNo atlas mask specified; porting default atlas mask: ${port_atlas_mask_path}\n";
                } else {
                    `cp ${port_atlas_mask} ${rigid_dir}`;
                }
            } else {
                $log_msg=$log_msg."\tNo atlas mask specified; porting rigid ${rigid_atlas} atlas mask: ${port_atlas_mask_path}\n";
            }
	    } else {
            $port_atlas_mask_path=$default_mask;  # Use default mask
            $log_msg=$log_msg."\nNo atlas mask specified and rigid atlas being used; porting default atlas mask: ${port_atlas_mask_path}\n";
	    }
	}  
	
	if (data_double_check($port_atlas_mask_path)) {
	    $init_error_msg=$init_error_msg."Unable to port atlas mask (i.e. file does not exist): ${port_atlas_mask_path}\n";
	} else {	    
	    $Hf->set_value('port_atlas_mask_path',$port_atlas_mask_path);
	}
    }

    my $threshold_code;
    if ($do_mask) {
        $threshold_code = $Hf->get_value('threshold_code');
        if (($threshold_code eq 'NO_KEY') || ($threshold_code eq 'UNDEFINED_VALUE')) {
            $threshold_code = 4;
            $Hf->set_value('threshold_code',$threshold_code);
            $log_msg=$log_msg."\tThreshold code for skull-stripping is not set. Will use default value of ${threshold_code}.\n";
        }    
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
sub mask_images_vbm_Runtime_check {
# ------------------

# # Set up work
    $port_atlas_mask=$Hf->get_value('port_atlas_mask');
    $in_folder = $Hf->get_value('pristine_input_dir');
    $work_dir = $Hf->get_value('dir_work');
    #$current_path = $Hf->get_value('inputs_dir');  # Dammit, "input" or "inputs"???
    $current_path = $Hf->get_value('preprocess_dir');
    $do_mask = $Hf->get_value('do_mask');
    $mask_dir = $Hf->get_value('mask_dir');
    (my $tc_isbad,$template_contrast) = $Hf->get_value_check('skull_strip_contrast');

    if ($tc_isbad ==0) {
        
    #if ($template_contrast eq ('' || 'NO_KEY' || 'UNDEFINED_VALUE')) {
        my $ch_runlist=$Hf->get_value('channel_comma_list');
        if ($ch_runlist =~ /(dwi)/i) {
                $template_contrast = $1;
            } else {
                my @channels = split(',',$ch_runlist);
                $template_contrast = shift(@channels);    
        }
        $Hf->set_value('skull_strip_contrast',${template_contrast});
    }
    $thresh_ref = $Hf->get_value('threshold_hash_reference');
    $default_mask_threshold=$Hf->get_value('threshold_code'); # Do this on an the basis of individual runnos
                        # -1 use imagej (like evan and his dti pipe)
                        # 0-100 use threshold_zero 0-100, 
                        # 100-inf is set threshold.


    $num_morphs = 5; # Need to make these user-specifiable for mask tuning
    $morph_radius = 2; # Need to make these user-specifiable for mask tuning
    #$dim_divisor = 2; #Changed to 1, BJA 14 March 2017
    $dim_divisor = 1;

    $status_display_level=0;

    if ($mask_dir eq 'NO_KEY') {
        $mask_dir = "${current_path}/masks";
        $Hf->set_value('mask_dir',$mask_dir); # Dammit, "input" or "inputs"??? 	
    }

    if ((! -e $mask_dir) && ($do_mask)) {
        mkdir ($mask_dir,$permissions);
    }

    $runlist = $Hf->get_value('complete_comma_list');
 
    if ($runlist eq 'EMPTY_VALUE') {
	@array_of_runnos = ();
    } else {
	@array_of_runnos = split(',',$runlist);
    }


 
    $ch_runlist = $Hf->get_value('channel_comma_list');
    @channel_array = split(',',$ch_runlist);

    # 21 September 2020, BJA: going to avoid the tricky bits of processing a pre-given mask through masking code...
    @channel_array = grep {$_ ne 'mask'} @channel_array;

    my $case = 1;
    my ($dummy,$skip_message)=mask_images_Output_check($case);

    if ($skip_message ne '') {
	print "${skip_message}";
    }


}


1;

