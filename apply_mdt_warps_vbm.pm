#!/usr/bin/env perl
# apply_mdt_warps_vbm.pm 
# Originally written by BJ Anderson, CIVM

my $PM = "apply_mdt_warps_vbm.pm";
my $VERSION = "2015/02/19";
my $NAME = "Application of warps derived from the calculation of the Minimum Deformation Template.";
my $DESC = "ants";

use strict;
use warnings;
#no warnings qw(uninitialized bareword);

#use vars used to be here
require Headfile;
require SAMBA_pipeline_utilities;

#use SAMBA_pipeline_utilities qw(printd $debug_val);
use List::Util qw(max);


my $do_inverse_bool = 0;
my ($runlist,$rigid_path,$current_path,$write_path_for_Hf);
my ($inputs_dir,$mdt_creation_strategy);
my ($interp,$template_path, $template_name, $diffeo_path,$work_done,$vbm_reference_path,$label_reference_path,$label_refname,$label_results_path,$label_path);
my (@array_of_runnos,@files_to_create,@files_needed);
my @jobs=();
my (%go_hash);
my $go = 1;
my $job;


# 4 February 2020, BJA: Will try to look for ENV variable to set matlab_execs and runtime paths

use Env qw(MATLAB_EXEC_PATH MATLAB_2015b_PATH SAMBA_APPS_DIR); 
if (! defined($MATLAB_EXEC_PATH)) {
   $MATLAB_EXEC_PATH =  "${SAMBA_APPS_DIR}/matlab_execs_for_SAMBA";
}

if (! defined($MATLAB_2015b_PATH)) {
    $MATLAB_2015b_PATH =  "${SAMBA_APPS_DIR}/MATLAB2015b_runtime/v90";
}


my $matlab_path = "${MATLAB_2015b_PATH}";
my $img_transform_executable_path ="${MATLAB_EXEC_PATH}/img_transform_executable/run_img_transform_exec.sh";
my $current_label_space;

my $convert_images_to_RAS=0;

my ($results_dir,$final_MDT_results_dir,$almost_results_dir,$almost_MDT_results_dir,$median_images_path, $final_results_dir);

my ($current_contrast,$group,$gid);
if (! defined $dims) {$dims = 3;}
if (! defined $ants_verbosity) {$ants_verbosity = 1;}

# ------------------
sub apply_mdt_warps_vbm {  # Main code
# ------------------
    my $direction;
   ($current_contrast,$direction,$group,$current_label_space) = @_; # added optional current_label_space
    my $start_time = time;

    $interp = "Linear"; # Hardcode this here for now...may need to make it a soft variable.

    if ($current_contrast eq '') { # Skip this step entirely in case pipeline accidentally supplies a null contrast.
	return();
    }

    my $PM_code;

    if ($group =~ /(control|mdt|template)/i) {
	$gid = 1;
	$PM_code = 43;
    } elsif ($group eq "compare") {
	$gid = 0;
	$PM_code = 52;
    } elsif ($group eq "all"){
	$gid = 2;
	$PM_code = 64;
    }else {
	error_out("$PM: invalid group of runnos specified.  Please consult your local coder and have them fix their problem.");
    }
    apply_mdt_warps_vbm_Runtime_check($direction);

    foreach my $runno (@array_of_runnos) {
	$go = $go_hash{$runno};
	if ($go) {
	    ($job) = apply_mdt_warp($runno,$direction);

	    if ($job) {
		push(@jobs,$job);
	    }
	} 
    }
     

    # It is really a shame to wait after scheduling only one contrast worth of data. We should fix that... 
    # Maybe we could schedule the working contrasts independently to get them done asap, 
    # then schedule all the others without waiting for them?
    if (cluster_check() && (@jobs)) {
	my $interval = 2;
	my $verbose = 1;
	my $done_waiting = cluster_wait_for_jobs($interval,$verbose,@jobs);
	
	if ($done_waiting) {
	    print STDOUT  "  MDT warps have been applied to the ${current_contrast} images for all ${group} runnos; moving on to next step.\n";
	}
    }
    my $case = 2;
    my ($dummy,$error_message)=apply_mdt_warps_Output_check($case,$direction);

    my $real_time = vbm_write_stats_for_pm($PM_code,$Hf,$start_time,@jobs);
    print "$PM took ${real_time} seconds to complete.\n";

    @jobs=(); # Clear out the job list, since it will remember everything if this module is used iteratively.

    if ($error_message ne '') {
	error_out("${error_message}",0);
    } else {
	$Hf->write_headfile($write_path_for_Hf);
	if ($mdt_creation_strategy eq 'iterative') {
	    if ($gid < 2) {
		symbolic_link_cleanup($diffeo_path,$PM);
	    }
	} else {
	    if (! $gid) {
		symbolic_link_cleanup($diffeo_path,$PM);
		symbolic_link_cleanup($rigid_path,$PM);
	    }
	}
    }
    
    my @jobs_2;
    if (($convert_images_to_RAS == 1) && ($gid == 2)){
        foreach my $runno (@array_of_runnos,'MDT') {
            if (($runno eq 'MDT') && ($current_contrast eq 'nii4D')){
            $job=0;
            } else {
            ($job) = convert_images_to_RAS($runno,$current_contrast);
            } 
            if ($job) {
            push(@jobs_2,$job);
            }
        
        } 
	
        if (cluster_check()) {
            my $interval = 2;
            my $verbose = 1;
            my $done_waiting = cluster_wait_for_jobs($interval,$verbose,@jobs_2);
	    
            if ($done_waiting) {
            print STDOUT  " RAS images have been created for all runnos; moving on to next step.\n";
            }
        }
        #if ($current_contrast eq 'nii4D') {
        #    `gzip ${current_path}/*nii4D*nii`;  
        #}
    }

 
}



# ------------------
sub apply_mdt_warps_Output_check {
# ------------------
     my ($case, $direction) = @_;
     my $message_prefix ='';
     my ($out_file,$dir_string);
     if ($direction eq 'f' ) {
        $dir_string = 'forward';
     } elsif ($direction eq 'i') {
        $dir_string = 'inverse';
     } else {
        error_out("$PM: direction of warp \"$direction \"not recognized. Use \"f\" for forward and \"i\" for inverse.\n");
     }
     my @file_array=();
     if ($case == 1) {
        $message_prefix = "  ${dir_string} MDT warp(s) have already been applied to the ${current_contrast} images for the following runno(s) and will not be recalculated:\n";
     } elsif ($case == 2) {
        $message_prefix = "  Unable to apply ${dir_string} MDT warp(s) to the ${current_contrast} image for the following runno(s):\n";
     }   # For Init_check, we could just add the appropriate cases.

     
     my $existing_files_message = '';
     my $missing_files_message = '';
     
     foreach my $runno (@array_of_runnos) {
	 if ($direction eq 'f' ) {
	     if ($gid == 2) {
		 $out_file = "${current_path}/${runno}_${current_contrast}.nii.gz";  #Added '.gz', 2 September 2015
	     } else {
		 $out_file = "${current_path}/${runno}_${current_contrast}_to_MDT.nii.gz";  #Added '.gz', 2 September 2015
	     }
	 } elsif ($direction eq 'i') {
	     $out_file =  "${current_path}/MDT_to_${runno}_${current_contrast}.nii.gz";  #Added '.gz', 2 September 2015
	 }

	 if (data_double_check($out_file,$case-1)) {
	     #if ($out_file =~ s/\.gz$//) {
		 #if (data_double_check($out_file)) {
		     $go_hash{$runno}=1;
		     push(@file_array,$out_file);
		     #push(@files_to_create,$full_file); # This code may be activated for use with Init_check and generating lists of work to be done.
		     $missing_files_message = $missing_files_message."\t$runno\n";
		 #} else {
		  #   `gzip -f ${out_file}`; #Is -f safe to use?
		  #   $go_hash{$runno}=0;
		  #   $existing_files_message = $existing_files_message."\t$runno\n";
		 #}
	     #}
	 } else {
	     $go_hash{$runno}=0;
	     $existing_files_message = $existing_files_message."\t$runno\n";
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
sub apply_mdt_warps_Input_check {
# ------------------

}


# ------------------
sub apply_mdt_warp {
# ------------------
    my ($runno,$direction) = @_;
    my ($cmd);
    my $out_file = '';
    my $direction_string = '';
    my ($start,$stop);
    my $reference_image;  ## 28 April 2017: NEED TO FURTHER INVESTIGATE WHAT REF IMAGE WE WANT OR NEED FOR MASS CONNECTIVITY COMPARISONS...!
   # my $option_letter = "t";
    my $option_letter = '';
    my $warp_prefix= '-t '; # Moved all creation of "-t" to here to avoid "-t -t ..." fiasco. 3 May 2017, BJA

    my $mdt_warp_string = $Hf->get_value('forward_label_xforms');
    my $mdt_warp_train;
    my $gz='.gz';
    if ($current_contrast eq 'nii4D') {
        $gz='';
    }
    if ($gid == 2 ) {
	$out_file = "${current_path}/${runno}_${current_contrast}.nii${gz}"; # Added '.gz', 2 September 2015
	$reference_image = $label_reference_path;
    
    if (! defined $current_label_space) {die "\$current_label_space error! It is not being defined when $PM is called with \$group_name = \"all\". See your local programmer.";}
    
    if ($direction eq 'f') {
	    $direction_string = 'forward';
	    if ($current_label_space eq 'pre_rigid') {
		$start=0;
		$stop=0;
		$option_letter = '';
	    } elsif (($current_label_space eq 'pre_affine') ||($current_label_space eq 'post_rigid')) {
		$start=3;
		$stop=3;
	    } elsif ($current_label_space eq 'post_affine') {
		$start=2;
		$stop=3;
	    } elsif (($current_label_space eq 'MDT') || ($current_label_space eq 'atlas')) {
		$start=1;
		$stop=3;
	    }
	} else { # No known use for inverting for label purposes yet...would make sense if this code had been generalized enough to handle label warping.
	    $direction_string = 'inverse';
	    ###
	}
    } else {
	$reference_image=$vbm_reference_path;
	if ($direction eq 'f') {
	    $out_file = "${current_path}/${runno}_${current_contrast}_to_MDT.nii${gz}"; # Need to settle on exact file name format...  Added '.gz', 2 September 2015
	    $direction_string = 'forward';
	    $start=1;
	    $stop=3;
	} else {
	    $out_file = "${current_path}/MDT_to_${runno}_${current_contrast}.nii${gz}"; # I don't think this will be the proper implementation of the "inverse" option.  Added '.gz', 2 September 2015
	    $direction_string = 'inverse';
	    $start=1;
	    $stop=3;
	}
    }

    my $image_to_warp = get_nii_from_inputs($inputs_dir,$runno,$current_contrast); 
    
    my $warp_string = $Hf->get_value("${direction_string}_xforms_${runno}");
    if ($warp_string eq 'NO_KEY') {
	$warp_string=$Hf->get_value("mdt_${direction_string}_xforms_${runno}")
    }

    my $warp_train = format_transforms_for_command_line($warp_string,$option_letter,$start,$stop);
##
    if ((defined $current_label_space) && ($current_label_space eq 'atlas') ) {
	$mdt_warp_train=format_transforms_for_command_line($mdt_warp_string,$option_letter);
	$warp_train= $mdt_warp_train.' '.$warp_train;
    }
###
   # my $warp_train = format_transforms_for_command_line($warp_string,$option_letter,$start,$stop);

    if ($warp_train ne '') {
		$warp_train = $warp_prefix.$warp_train;
    }

    if (data_double_check($reference_image)) {
		$reference_image=$reference_image.'.gz';
    }

    my $test_dim =  nifti_dim4(${image_to_warp});#`PrintHeader ${image_to_warp} 2`;
    #my @dim_array = split('x',$test_dim);
    #my $real_dim = $#dim_array +1;
    my $opt_e_string='';
    # if ($real_dim == 4) {
    if ($image_to_warp =~ /tensor/) {
        $opt_e_string = ' -e 2 -f 0.0007'; # Testing value for -f option, as per https://github.com/ANTsX/ANTs/wiki/Warp-and-reorient-a-diffusion-tensor-image
    } elsif ($test_dim > 1) {
        $opt_e_string = ' -e 3 ';
    } 
    
    if (($current_contrast eq 'nii4D') && (! data_double_check($out_file,1))) {
    #skip apply warp
    } else {
      $cmd = "antsApplyTransforms -v ${ants_verbosity} --float -d ${dims} ${opt_e_string} -i ${image_to_warp} -o ${out_file} -r ${reference_image} -n $interp ${warp_train};\n";  
    }
    
    if ($current_contrast eq 'nii4D') {
        if (($convert_images_to_RAS == 1) && ($gid == 2)) {
            my $tmp_file;   
            if ($runno eq 'MDT') {
                $tmp_file= "${median_images_path}/MDT_${current_contrast}_tmp.nii";
            } else {
                 $tmp_file= "${current_path}/${runno}_${current_contrast}_tmp.nii";
            }
            $cmd=$cmd."cp ${out_file} ${tmp_file};\n";
        }
        $cmd=$cmd."gzip ${out_file};\n";
    }


    my $go_message =  "$PM: apply ${direction_string} MDT warp(s) to ${current_contrast} image for ${runno}";
    my $stop_message = "$PM: could not apply ${direction_string} MDT warp(s) to ${current_contrast} image for  ${runno}:\n${cmd}\n";

    my @test=(0);
    if (defined $reservation) {
	@test =(0,$reservation);
    }

    my $mem_request = 75000;  # Added 23 November 2016,  Will need to make this smarter later.
    #my $input_size = 1024*(stat $image_to_warp)[7];
    my $input_size=1;
    for (my $ii=1; $ii<6; $ii++){
		#my $c_string = `fslhd ${image_to_warp} | grep dim${ii} | grep -v pix`;
		#chomp($c_string);
		my $c_string = nifti_dim4(${image_to_warp},${ii});
		my $c_dim_size = 1;
		if ($c_string =~ /\s([0-9]+)$/) {
			$c_dim_size = $1;
		} 
		$input_size = $input_size*$c_dim_size;
    }
    my $bytes_per_point = 8; # Going to go with 64-bit depth by default, though float is the usual case;   
    $input_size = $input_size*($bytes_per_point/1024/1024); # Originally just divided by 1024 instead of 1024*1024...was calculating request in kB instead of MB!


    my $expected_max_mem = int(6.2*$input_size);
    print "Expected amount of memory required to apply warps: ${expected_max_mem} MB.\n";
    if ($expected_max_mem > $mem_request) {
	$mem_request = $expected_max_mem;
    }


    my $jid = 0;
    if (cluster_check) {
	my $home_path = $current_path;
	my $Id= "${runno}_${current_contrast}_apply_${direction_string}_MDT_warp";
	my $verbose = 2; # Will print log only for work done.
	$jid = cluster_exec($go, $go_message, $cmd ,$home_path,$Id,$verbose,$mem_request,@test);     
	if (not $jid) {
	    error_out($stop_message);
	}
    } else {
	my @cmds = ($cmd);
	if (! execute($go, $go_message, @cmds) ) {
	    error_out($stop_message);
	}
    }

    if ((!-e $out_file) && (not $jid)) {
	error_out("$PM: missing ${current_contrast} image with ${direction_string} MDT warp(s) applied for ${runno}: ${out_file}");
    }
    print "** $PM expected output: ${out_file}\n";
  
    return($jid,$out_file);
}



# ------------------
sub convert_images_to_RAS {
# ------------------
    my ($runno,$contrast) = @_;
    my ($cmd);
    my ($out_file,$input_image,$work_file);
    my $final_images_dir;
    my $gz='.gz';
    if ($contrast eq 'nii4D') {
        $gz='';
    }
    my $fat_out_file;
    my $tmp_file;
    if ($runno eq 'MDT') {
        #$out_file = "${final_MDT_results_dir}/MDT_labels_${label_atlas_name}_RAS.nii.gz";
        $input_image = "${median_images_path}/MDT_${contrast}.nii.gz";
        $tmp_file= "${median_images_path}/MDT_${contrast}_tmp.nii";
        #$work_file = "${median_images_path}/MDT_labels_${label_atlas_name}_RAS.nii.gz";
        #$final_images_dir = "${final_MDT_results_dir}/${runno}_images/";
        $final_images_dir = "${final_MDT_results_dir}/";

        $out_file = "${final_images_dir}/MDT_${contrast}_RAS.nii.gz";
        $fat_out_file = "${final_images_dir}/MDT_${contrast}_tmp_RAS.nii";
    }else {
        #$out_file = "${final_results_dir}/${mdt_contrast}_labels_warp_${runno}_RAS.nii.gz";
        $input_image = "${current_path}/${runno}_${contrast}.nii.gz";
        $tmp_file= "${current_path}/${runno}_${contrast}_tmp.nii";   
        #$work_file = "${current_path}/${mdt_contrast}_labels_warp_${runno}_RAS.nii.gz";
        #$final_images_dir = "${final_results_dir}/${runno}_images/";
        $final_images_dir = "${final_results_dir}/${runno}/";
        $out_file = "${final_images_dir}/${runno}_${contrast}_RAS.nii.gz";
        $fat_out_file = "${final_images_dir}/${runno}_${contrast}_tmp_RAS.nii";
    }


   if (! -e $final_images_dir) {
	mkdir ($final_images_dir,$permissions);
    }

    my $jid_2 = 0;

    #print "out_file = ${out_file}\n\n";

    if (data_double_check($out_file)) {
		my $current_vorder= $Hf->get_value('working_image_orientation');
        if (($current_vorder eq 'NO_KEY') || ($current_vorder eq 'UNDEFINED_VALUE') || ($current_vorder eq '')) {
            $current_vorder= 'ALS';
        }
        my $desired_vorder = 'RAS';

    if (($contrast eq 'nii4D') && (data_double_check($fat_out_file,1))) {
        $cmd =$cmd."if [[ ! -f ${tmp_file} ]]; then\ngunzip -c ${input_image} > ${tmp_file};\nfi\n";
        $input_image=$tmp_file;
     };
	#$cmd = $cmd."${img_transform_executable_path} ${matlab_path} ${input_image} ${current_vorder} ${desired_vorder} ${final_images_dir};\n";        
    if ($contrast eq 'nii4D' && (! data_double_check($fat_out_file,1))) {
    # Do nothing
    } else {
        $cmd = $cmd."${img_transform_executable_path} ${matlab_path} ${input_image} ${current_vorder} ${desired_vorder} ${final_images_dir};\n";    
    }
    if ($contrast eq 'nii4D') {
        $cmd =$cmd."gzip -c ${fat_out_file} > ${out_file};\n";
        $cmd =$cmd."rm ${tmp_file};\n";
        $cmd =$cmd."rm ${fat_out_file};\n";
     };
	my $go_message =  "$PM: converting ${runno}_${contrast} image to RAS orientation";
	my $stop_message = "$PM: could not convert ${runno}_${contrast} image to RAS orientation:\n${cmd}\n";
	
	
	my @test=(0);
	if (defined $reservation) {
	    @test =(0,$reservation);
	}
	
	my $mem_request = 30000;  # Added 23 November 2016,  Will need to make this smarter later.
	my $go_2 = 1;
	if (cluster_check) {
	    my $home_path = $current_path;
	    my $Id= "converting_${runno}_${contrast}_image_to_RAS_orientation";
	    my $verbose = 2; # Will print log only for work done.
	    $jid_2 = cluster_exec($go_2, $go_message, $cmd ,$home_path,$Id,$verbose,$mem_request,@test);     
	    if (not $jid_2) {
		error_out($stop_message);
	    }
	} else {
	    my @cmds = ($cmd);
	    if (! execute($go_2, $go_message, @cmds) ) {
		error_out($stop_message);
	    }
	}
	
	if ((!-e $out_file) && (not $jid_2)) {
	    error_out("$PM: missing RAS version of ${label_atlas_name} label set for ${runno}: ${out_file}");
	}
	print "** $PM expected output: ${out_file}\n";
    }
    
    return($jid_2,$out_file);
}



# ------------------
sub apply_mdt_warps_vbm_Init_check {
# ------------------

    my $init_error_msg='';
    my $message_prefix="$PM:\n";

    if ($init_error_msg ne '') {
	$init_error_msg = $message_prefix.$init_error_msg;
    }
    return($init_error_msg);
}


# ------------------
sub apply_mdt_warps_vbm_Runtime_check {
# ------------------
    my ($direction)=@_;
 
# # Set up work

    $inputs_dir = $Hf->get_value('inputs_dir');
    $rigid_path = $Hf->get_value('rigid_work_dir');

    $template_path = $Hf->get_value('template_work_dir');
    $template_name = $Hf->get_value('template_name');

    $vbm_reference_path = $Hf->get_value('vbm_reference_path');

    if ($gid == 1) {
	$diffeo_path = $Hf->get_value('mdt_diffeo_path');   
	#$current_path = $Hf->get_value('mdt_images_path');
	#if ($current_path eq 'NO_KEY') {
	   # $current_path = "${predictor_path}/MDT_images";
	    $current_path = "${template_path}/MDT_images";
	    $Hf->set_value('mdt_images_path',$current_path);
	#}
#	$runlist = $Hf->get_value('control_comma_list');
	$runlist = $Hf->get_value('template_comma_list');

	if ($runlist eq 'NO_KEY') {
	    $runlist = $Hf->get_value('control_comma_list');
	    $Hf->set_value('template_comma_list',$runlist); # 1 Feb 2016, just added these. If bug, then check here.
	}
	
    } elsif ($gid == 0) {
	$diffeo_path = $Hf->get_value('reg_diffeo_path');   
	#$current_path = $Hf->get_value('reg_images_path');
	#if ($current_path eq 'NO_KEY') {
	 #  $current_path = "${predictor_path}/reg_images";
	    $current_path = "${template_path}/reg_images";
	    $Hf->set_value('reg_images_path',$current_path);
	#}
	# $runlist = $Hf->get_value('compare_comma_list');
	$runlist = $Hf->get_value('nontemplate_comma_list');

	if ($runlist eq 'NO_KEY') {
	    $runlist = $Hf->get_value('compare_comma_list');
	    $Hf->set_value('nontemplate_comma_list',$runlist);  # 1 Feb 2016, just added these. If bug, then check here.
	}


    } elsif ($gid == 2) {
	$inputs_dir = $Hf->get_value('label_refspace_folder');
	$label_reference = $Hf->get_value('label_reference');
	$label_reference_path = $Hf->get_value('label_reference_path');
	$label_refname = $Hf->get_value('label_refname');

	my $msg;
	if (! defined $current_label_space) {
	    $msg = "current_label_space not explicitly defined. Checking Headfile...\n";
	    $current_label_space = $Hf->get_value('label_space');
	} else {
	    $msg="current_label_space has been explicitly set to: ${current_label_space}\n";
	}
	#printd(0,$msg);die;
    printd(35,$msg);

	$label_path=$Hf->get_value('labels_dir');
	$label_results_path=$Hf->get_value('label_results_path');
   

	$current_path=$Hf->get_value('label_images_dir');

	$median_images_path = $Hf->get_value('median_images_path');

	my $intermediary_path = "${label_path}/${current_label_space}_${label_refname}_space";
	#print "\$intermediary_path = ${intermediary_path}\n\n";

	if (! -e  $intermediary_path) {
	    mkdir ( $intermediary_path,$permissions);
	    print "Whether you like it or not, making directory: ${intermediary_path}\n\n";  
	}

	#if ($current_path eq 'NO_KEY') {
	    $current_path = "${intermediary_path}/images";
	    $Hf->set_value('label_images_dir',$current_path);
	#}
	if (! -e $current_path) {
	    mkdir ($current_path,$permissions);
	}

	$results_dir = $Hf->get_value('results_dir');

	$convert_images_to_RAS=$Hf->get_value('convert_labels_to_RAS');
	if ( $convert_images_to_RAS eq 'NO_KEY') {$convert_images_to_RAS = 0;}

	if (($convert_images_to_RAS ne 'NO_KEY') && ($convert_images_to_RAS == 1)) {

	    #$almost_MDT_results_dir = "${results_dir}/labels/";
	    $almost_MDT_results_dir = "${results_dir}/connectomics/";
	    if (! -e $almost_MDT_results_dir) {
		mkdir ($almost_MDT_results_dir,$permissions);
	    }
	    
	    #$final_MDT_results_dir = "${almost_MDT_results_dir}/${label_atlas}/";
	    $final_MDT_results_dir = "${almost_MDT_results_dir}/MDT/";
	    if (! -e $final_MDT_results_dir) {
		mkdir ($final_MDT_results_dir,$permissions);
	    }
	    
	    #$almost_results_dir = "${results_dir}/labels/${current_label_space}_${label_refname}_space/";
	    $almost_results_dir = "${results_dir}/connectomics/";
	    if (! -e $almost_results_dir) {
		mkdir ($almost_results_dir,$permissions);
	    }
	    
	    #$final_results_dir = "${almost_results_dir}/${label_atlas}/";
	    
	    $final_results_dir = "${almost_results_dir}/${current_label_space}_${label_refname}_space/";
	    if (! -e $final_results_dir) {
            mkdir ($final_results_dir,$permissions);
	    }
	    #$Hf->set_value('final_label_results_dir',$final_results_dir);
	    #$Hf->set_value('final_connectomics_results_dir',$final_results_dir);
	}

	$runlist = $Hf->get_value('complete_comma_list');
    } else {
	print " ERROR: Invalid group ID in $PM.  Dying now...\n";
	die;
    }
    
    if (! -e $current_path) {
	mkdir ($current_path,$permissions);
    }
    
    $write_path_for_Hf = "${current_path}/${template_name}_temp.headfile";

#   Functionize?
    if ($runlist eq 'EMPTY_VALUE') {
	@array_of_runnos = ();
    } else {
	@array_of_runnos = split(',',$runlist);
    }    

#

    $mdt_creation_strategy = $Hf->get_value('mdt_creation_strategy');

    my $case = 1;
    my ($dummy,$skip_message)=apply_mdt_warps_Output_check($case,$direction);

    if ($skip_message ne '') {
	print "${skip_message}";
    }

# check for needed input files to produce output files which need to be produced in this step?

}

1;
