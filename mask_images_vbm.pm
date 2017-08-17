#!/usr/local/pipeline-link/perl

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
#no warnings qw(uninitialized bareword);

use vars qw($Hf $BADEXIT $GOODEXIT $test_mode $permissions $reservation $dim $ants_verbosity);
require Headfile;
require pipeline_utilities;
#require convert_to_nifti_util;


my ($current_path, $work_dir,$runlist,$ch_runlist,$in_folder,$out_folder,$do_mask,$mask_dir,$template_contrast);
my ($thresh_ref,$mask_threshold,$default_mask_threshold,$num_morphs,$morph_radius,$dim_divisor, $status_display_level);
my (@array_of_runnos,@channel_array);
my @jobs=();
my (%go_hash,%make_hash,%mask_hash);
my $go=1;
my ($port_atlas_mask_path,$port_atlas_mask);
my ($job);

my $matlab_path = "/cm/shared/apps/MATLAB/R2015b/";
my $strip_mask_executable_path = "/home/rja20/cluster_code/workstation_code/analysis/vbm_pipe/strip_mask_executables/strip_mask_executable/20170727_1304/run_strip_mask_exec.sh";

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
		$mask_threshold=$default_mask_threshold;
	    }
	    my $mask_path     = "${mask_dir}/${runno}_${template_contrast}_mask\.nii";
	    my $ported_mask = $mask_dir.'/'.$runno.'_port_mask.nii';

	    $mask_hash{$runno} = $mask_path;

	    if (! -e $mask_path) {
		if ( ( (! $port_atlas_mask)) || (($port_atlas_mask) && (! -e $ported_mask) && (! -e $ported_mask.'.gz')) ) {
		    #my $nifti_args ="\'$current_file\', $dim_divisor, $mask_threshold, \'$mask_path\',$num_morphs , $morph_radius,$status_display_level";
		    #my $nifti_command = make_matlab_command('strip_mask',$nifti_args,"${runno}_${template_contrast}_",$Hf,0); # 'center_nii'
		    #execute(1, "Creating mask for $runno using ${template_contrast} channel", $nifti_command);
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
	    if ($go){		
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
	if ($make_hash{$runno}) {
	    foreach my $ch (@channel_array) {
		my $go = $go_hash{$runno}{$ch};
		if ($go) {
		    my ($job) = mask_one_image($runno,$ch);
		    if ($job) {
			push(@jobs,$job);
		    }
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


    my $real_time = write_stats_for_pm($PM,$Hf,$start_time,@jobs);
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
	$message_prefix = "  Masked images have been found for the following runno(s) and will not be re-processed:\n";
    } elsif ($case == 2) {
	 $message_prefix = "  Unable to properly mask images for the following runno(s) and channel(s):\n";
    }   # For Init_check, we could just add the appropriate cases.
    
    foreach my $runno (@array_of_runnos) {
	my $sub_existing_files_message='';
	my $sub_missing_files_message='';
	

	foreach my $ch (@channel_array) {
	    $file_1 = "${current_path}/${runno}_${ch}_masked.nii";
	    
	    if (data_double_check($file_1)) {
		$file_1 = $file_1.'.gz'; # 8 Feb 2016: added .gz    
	    }
	    
	    if (data_double_check($file_1) ) {
		$go_hash{$runno}{$ch}=1*$do_mask;
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

    $new_norm_command = "ImageMath 3 $port_mask Normalize $new_mask;\n";
    $cleanup_command=$cleanup_command."if [ -e \"${port_mask}\" ]\nthen\n\tif [ -e \"${new_mask}\" ]\n\tthen\n\t\trm ${new_mask};\n";
    
    if (! -e $new_mask) {
	$apply_xform_command = "antsApplyTransforms -v ${ants_verbosity} --float -d ${dims} -i $atlas_mask -o $new_mask -t [${temp_out_file}, 1] -r $current_norm_mask -n NearestNeighbor;\n";
	$cleanup_command=$cleanup_command."\t\tif [ -e \"${temp_out_file}\" ]\n\t\tthen\n\t\t\trm ${temp_out_file};\n";
	
	if (! -e $temp_out_file) {
	    $atlas_mask_reg_command = "antsRegistration -v ${ants_verbosity} -d ${dims} -r [$atlas_mask,$current_norm_mask,1] ".
#		" -m MeanSquares[$atlas_mask,$current_norm_mask,1,32,random,0.3] -t translation[0.1] -c [3000x3000x0x0,1.e-8,20] ".
#		" -m MeanSquares[$atlas_mask,$current_norm_mask,1,32,random,0.3] -t rigid[0.1] -c [3000x3000x0x0,1.e-8,20] ".
		" -m MeanSquares[$atlas_mask,$current_norm_mask,1,32,random,0.3] -t affine[0.1] -c [3000x3000x0x0,1.e-8,20] ". 
		" -s 4x2x1x0.5vox -f 6x4x2x1 -l 1 -u 1 -z 1 -o $out_prefix;\n";# --affine-gradient-descent-option 0.05x0.5x1.e-4x1.e-4";
	
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
    my $copy_hd_cmd = "CopyImageHeaderInformation ${centered_path} ${out_path} ${out_path} 1 1 1 ${im_a_real_tensor};\n";
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
    print "** $PM created ${out_path}\n";
  
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
    if ($do_mask eq 'NO_KEY') { $do_mask=0;}
    if ($port_atlas_mask eq 'NO_KEY') { $port_atlas_mask=0;}
    my $default_mask = "${WORKSTATION_DATA}/atlas/chass_symmetric2/chass_symmetric2_mask.nii"; ## Set default mask for porting here!
    if (! -f $default_mask) {
	if ($default_mask =~ s/data/CIVMdata/) {}
    }

    if (($do_mask == 1) && ($port_atlas_mask == 1)) {
	if ($port_atlas_mask_path eq 'NO_KEY') {
	    print "rigid_atlas_path = ${rigid_atlas_path}\n\n\n\n";
	    my ($dummy1,$rigid_dir,$dummy2);
	    if (! data_double_check($rigid_atlas_path)){
		($rigid_dir,$dummy1,$dummy2) = fileparts($rigid_atlas_path,2);
		$port_atlas_mask_path = get_nii_from_inputs($rigid_dir,$rigid_atlas_name,'mask');
		if ($port_atlas_mask_path =~ /[\n]+/) {
		    my ($dummy1,$original_rigid_dir,$dummy2);
		    ($original_rigid_dir,$dummy1,$dummy2) = fileparts($original_rigid_atlas_path,2);
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
		$log_msg=$log_msg."\tNo atlas mask specified and rigid atlas being used; porting default atlas mask: ${port_atlas_mask_path}\n";
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
	if ($threshold_code eq 'NO_KEY') {
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
    $template_contrast = $Hf->get_value('skull_strip_contrast');
    $thresh_ref = $Hf->get_value('threshold_hash_reference');
    $default_mask_threshold=$Hf->get_value('threshold_code'); # Do this on an the basis of individual runnos
                        # -1 use imagej (like evan and his dti pipe)
                        # 0-100 use threshold_zero 0-100, 
                        # 100-inf is set threshold.


    $num_morphs = 5;
    $morph_radius = 2;
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

    my $case = 1;
    my ($dummy,$skip_message)=mask_images_Output_check($case);

    if ($skip_message ne '') {
	print "${skip_message}";
    }


}


1;

