#!/usr/local/pipeline-link/perl
# warp_atlas_labels_vbm.pm 
# Originally written by BJ Anderson, CIVM




my $PM = "warp_atlas_labels_vbm.pm";
my $VERSION = "2014/12/11";
my $NAME = "Application of warps derived from the calculation of the Minimum Deformation Template.";
my $DESC = "ants";

use strict;
use warnings;
#no warnings qw(uninitialized bareword);

use vars qw($Hf $BADEXIT $GOODEXIT  $test_mode $reference_path $ants_verbosity $reservation);
require Headfile;
require pipeline_utilities;
use List::Util qw(max);


my $do_inverse_bool = 0;
my ($atlas,$rigid_contrast,$mdt_contrast, $runlist,$work_path,$rigid_path,$current_path,$write_path_for_Hf);
my ($xform_code,$xform_path,$xform_suffix,$domain_dir,$domain_path,$inputs_dir,$results_dir,$final_results_dir,$median_images_path);
my ($mdt_path,$template_name, $diffeo_path,$work_done);
my ($label_path,$label_reference_path,$label_refname,$do_byte);
my (@array_of_runnos,@files_to_create,@files_needed);
my @jobs=();
my (%go_hash);
my $go = 1;
my $job;
my $group='all';

my ($label_atlas,$atlas_label_dir,$atlas_label_path);
my ($convert_labels_to_RAS,$final_ROI_path);
if (! defined $ants_verbosity) {$ants_verbosity = 1;}


my $final_MDT_results_dir;
my $almost_results_dir;
my $almost_MDT_results_dir;

my $matlab_path = "/cm/shared/apps/MATLAB/R2015b/";
#my $make_ROIs_executable_path = "/glusterspace/BJ/run_Labels_to_ROIs_exec.sh";
my $make_ROIs_executable_path = "/cm/shared/workstation_code_dev/matlab_execs/Labels_to_ROIs_executable/20161006_1100/run_Labels_to_ROIs_exec.sh";

my $current_label_space; # 21 April 2017 -- BJA: Previously this wasn't initialized, but was still imported from the calling .pl (or at least that's my theory).

# ------------------
sub warp_atlas_labels_vbm {  # Main code
# ------------------
    ($group,$current_label_space) = @_; # Now we can call a specific label space from the calling function (in case we want to loop over several spaces without rerunning entire script).
    if (! defined $group) {
	$group = 'all';
    }

    if (! defined $current_label_space) {
	$current_label_space = '';
    }

    my $start_time = time;
    warp_atlas_labels_vbm_Runtime_check();

    foreach my $runno (@array_of_runnos) {
	$go = $go_hash{$runno};
	if ($go) {
	    ($job) = apply_mdt_warp_to_labels($runno);

	    if ($job) {
		push(@jobs,$job);
	    }
	} 
    }
     

    if (cluster_check()) {
	my $interval = 2;
	my $verbose = 1;
	my $done_waiting = cluster_wait_for_jobs($interval,$verbose,@jobs);
	
	if ($done_waiting) {
	    print STDOUT  " Label sets have been created from the ${label_atlas_name} atlas labels for all runnos; moving on to next step.\n";
	}
    }
    my $case = 2;
    my ($dummy,$error_message)=warp_atlas_labels_Output_check($case);

    my $real_time = write_stats_for_pm($PM,$Hf,$start_time,@jobs);
    print "$PM took ${real_time} seconds to complete.\n";


    if ($error_message ne '') {
	error_out("${error_message}",0);
    } else {
	$Hf->write_headfile($write_path_for_Hf);

	symbolic_link_cleanup($current_path,$PM);
    }
 
    my @jobs_2;
    if ($convert_labels_to_RAS == 1) {
	foreach my $runno (@array_of_runnos) {
	    ($job) = convert_labels_to_RAS($runno);
	    
	    if ($job) {
		push(@jobs_2,$job);
	    }
	} 

	if (cluster_check()) {
	    my $interval = 2;
	    my $verbose = 1;
	    my $done_waiting = cluster_wait_for_jobs($interval,$verbose,@jobs_2);
	    
	    if ($done_waiting) {
		print STDOUT  " RAS label sets have been created from the ${label_atlas_name} atlas labels for all runnos; moving on to next step.\n";
	    }
	}
    }


}



# ------------------
sub warp_atlas_labels_Output_check {
# ------------------
     my ($case) = @_;
     my $message_prefix ='';
     my ($out_file);
     my @file_array=();
     if ($case == 1) {
  	$message_prefix = "  ${label_atlas_name} label sets have already been created for the following runno(s) and will not be recalculated:\n";
     } elsif ($case == 2) {
 	$message_prefix = "  Unable to create ${label_atlas_name} label sets for the following runno(s):\n";
     }   # For Init_check, we could just add the appropriate cases.

     
     my $existing_files_message = '';
     my $missing_files_message = '';
     #my $out_file = "${current_path}/${mdt_contrast}_labels_warp_${runno}.nii.gz";
     foreach my $runno (@array_of_runnos) {
	 if ($group eq 'MDT') {
	     #$out_file = "${median_images_path}/MDT_labels_${label_atlas_name}.nii.gz";
	     $out_file = "${current_path}/MDT_labels_${label_atlas_name}.nii.gz";
	     $Hf->set_value("${label_atlas_name}_MDT_labels",$out_file);
	 }else {
	     $out_file = "${current_path}/${mdt_contrast}_labels_warp_${runno}.nii.gz";
	 }
	
	# my $out_file      = "$out_file_path_base\.nii";

	 if  (data_double_check($out_file)) {
	     $go_hash{$runno}=1;
	     push(@file_array,$out_file);
	     #push(@files_to_create,$full_file); # This code may be activated for use with Init_check and generating lists of work to be done.
	     $missing_files_message = $missing_files_message."\t$runno\n";
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
sub warp_atlas_labels_Input_check {
# ------------------

}


# ------------------
sub apply_mdt_warp_to_labels {
# ------------------
    my ($runno) = @_;
    my ($cmd);
    my $out_file;
    if ($group eq 'MDT') {
	#$out_file = "${median_images_path}/MDT_labels_${label_atlas_name}.nii.gz";
	$out_file = "${current_path}/MDT_labels_${label_atlas_name}.nii.gz";
    }else {
	$out_file = "${current_path}/${mdt_contrast}_labels_warp_${runno}.nii.gz";
    }
    my ($start,$stop);
    my $image_to_warp = $atlas_label_path;# get label set from atlas #get_nii_from_inputs($inputs_dir,$runno,$current_contrast); 
    my $reference_image; ## 28 April 2017: NEED TO FURTHER INVESTIGATE WHAT REF IMAGE WE WANT OR NEED FOR MASS CONNECTIVITY COMPARISONS...!

    # if (! $native_reference_space) {
    # 	$reference_image = $image_to_warp;
    # } else {
    # 	my @mdt_contrast  = split('_',$mdt_contrast);
    # 	my $some_valid_contrast = $mdt_contrast[0];
    # 	if ($runno ne 'MDT') {
    # 	    $reference_image =get_nii_from_inputs($inputs_dir,$runno,$some_valid_contrast);
    # 	} else {
    # 	    $reference_image =get_nii_from_inputs($median_images_path,$runno,$some_valid_contrast);
    # 	}
    # }
    #my @mdt_warp_array = split(',',$Hf->get_value('inverse_label_xforms')); # This appears to be extraneous; commenting out on 28 April 2017
    my $mdt_warp_string = $Hf->get_value('inverse_label_xforms');
    my $mdt_warp_train='';
    my $warp_train='';
    my $warp_prefix= '-t '; # Moved all creation of "-t" to here to avoid "-t -t ..." fiasco. 3 May 2017, BJA
    my $warp_string;
    my $create_cmd;
    #my $option_letter = "t";
    my $option_letter = '';
    #my $additional_warp='';
    my $raw_warp;

    if ($runno ne 'MDT') {
	my $add_warp_string = $Hf->get_value("forward_xforms_${runno}");

	if ($add_warp_string eq 'NO_KEY') {
	    $add_warp_string=$Hf->get_value("mdt_forward_xforms_${runno}")
	}
    
	#my @add_warp_array = split(',',$add_warp_string);
	#$raw_warp = pop(@add_warp_array);
    } 
 
    $reference_image = $label_reference_path;

    if (data_double_check($reference_image)) {
	$reference_image=$reference_image.'.gz';
    }

    if ($current_label_space ne 'atlas') {
	$mdt_warp_train=format_transforms_for_command_line($mdt_warp_string);
    }

    if (($current_label_space ne 'MDT') && ($current_label_space ne 'atlas')) {
	if ($runno ne 'MDT'){
	    $warp_string = $Hf->get_value("inverse_xforms_${runno}");
	    if ($warp_string eq 'NO_KEY') {
		$warp_string=$Hf->get_value("mdt_inverse_xforms_${runno}")
	    }
	    $stop=3;
	    if ($current_label_space eq 'pre_rigid') {
		$start=1;
	    } elsif (($current_label_space eq 'pre_affine') || ($current_label_space eq 'post_rigid')) {
		$start=2;
	    } elsif ($current_label_space eq 'post_affine') {
		$start= 3;	
	    } 
	    
	    $warp_train = format_transforms_for_command_line($warp_string,$option_letter,$start,$stop);
	}
    }
    
    if (($warp_train ne '') || ($mdt_warp_train ne '')) {
	$warp_train=$warp_prefix.$warp_train.' '.$mdt_warp_train;
    }

    $create_cmd = "antsApplyTransforms --float -v ${ants_verbosity} -d 3 -i ${image_to_warp} -o ${out_file} -r ${reference_image} -n NearestNeighbor ${warp_train};\n";

    my $smoothing_sigma = 1;
    my $smooth_cmd = "SmoothImage 3 ${out_file} ${smoothing_sigma} ${out_file} 0 1;\n";
 
    my $byte_cmd = "fslmaths ${out_file} -add 0 ${out_file} -odt char;\n"; # Formerly..."ImageMath 3 ${out_file} Byte ${out_file};\n";...but this would renormalize our labelsets and confound the matter
    my $short_cmd = "fslmaths ${out_file} -add 0 ${out_file} -odt short;\n";
    if ($do_byte) { # Smoothing added 15 March 2017
	$cmd =$create_cmd.$smooth_cmd.$byte_cmd;
    } else {
	$cmd = $create_cmd.$smooth_cmd.$short_cmd;
    }

    my $go_message =  "$PM: create ${label_atlas_name} label set for ${runno}";
    my $stop_message = "$PM: could not create ${label_atlas_name} label set for ${runno}:\n${cmd}\n";


    my @test=(0);
    if (defined $reservation) {
	@test =(0,$reservation);
    }
    
    my $mem_request = 30000;  # Added 23 November 2016,  Will need to make this smarter later.


    my $jid = 0;
    if (cluster_check) {
	my $home_path = $current_path;
	my $Id= "create_${label_atlas_name}_labels_for_${runno}";
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
	error_out("$PM: missing ${label_atlas_name} label set for ${runno}: ${out_file}");
    }
    print "** $PM created ${out_file}\n";
  
    return($jid,$out_file);
}


# ------------------
sub convert_labels_to_RAS {
# ------------------
    my ($runno) = @_;
    my ($cmd);
    my ($out_file,$input_labels,$work_file);
 
    my $final_ROIs_dir;

    if ($group eq 'MDT') {
	$out_file = "${final_MDT_results_dir}/MDT_labels_${label_atlas_name}_RAS.nii.gz";
	#$input_labels = "${median_images_path}/MDT_labels_${label_atlas_name}.nii.gz";
	$input_labels = "${current_path}/MDT_labels_${label_atlas_name}.nii.gz";
	#$work_file = "${median_images_path}/MDT_labels_${label_atlas_name}_RAS.nii.gz";
	$work_file = "${current_path}/MDT_labels_${label_atlas_name}_RAS.nii.gz";
	$final_ROIs_dir = "${final_MDT_results_dir}/MDT_${label_atlas_name}_RAS_ROIs/";
    }else {
	$out_file = "${final_results_dir}/${mdt_contrast}_labels_warp_${runno}_RAS.nii.gz";
	$input_labels = "${current_path}/${mdt_contrast}_labels_warp_${runno}.nii.gz";
	$work_file = "${current_path}/${mdt_contrast}_labels_warp_${runno}_RAS.nii.gz";
	$final_ROIs_dir = "${final_results_dir}/${runno}_ROIs/";
    }

   if (! -e $final_ROIs_dir) {
	mkdir ($final_ROIs_dir,$permissions);
    }

    my $jid_2 = 0;

    if (data_double_check($out_file)) {
	my $current_vorder = 'ALS';
	my $desired_vorder = 'RAS';
	if (data_double_check($work_file)) {
	    $cmd = $cmd."${make_ROIs_executable_path} ${matlab_path} ${input_labels}  ${final_ROIs_dir} ${current_vorder} ${desired_vorder};\n";	
	}

	$cmd =$cmd."cp ${work_file} ${out_file}";
 
	my $go_message =  "$PM: converting ${label_atlas_name} label set for ${runno} to RAS orientation";
	my $stop_message = "$PM: could not convert ${label_atlas_name} label set for ${runno} to RAS orientation:\n${cmd}\n";
	
	
	my @test=(0);
	if (defined $reservation) {
	    @test =(0,$reservation);
	}
	
	my $mem_request = 30000;  # Added 23 November 2016,  Will need to make this smarter later.
	my $go_2 = 1;
	if (cluster_check) {
	    my $home_path = $current_path;
	    my $Id= "converting_${label_atlas_name}_labels_for_${runno}_to_RAS_orientation";
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
	print "** $PM created ${out_file}\n";
    }
    
    return($jid_2,$out_file);
}


# ------------------
sub warp_atlas_labels_vbm_Init_check {
# ------------------

    return('');
}


# ------------------
sub warp_atlas_labels_vbm_Runtime_check {
# ------------------
    my ($direction)=@_;
 
#    if ($group eq 'MDT') {
# 	$median_images_path = $Hf->get_value('median_images_path');
#    }
# # Set up work
    $label_atlas = $Hf->get_value('label_atlas_name');
    $atlas_label_dir   = $Hf->get_value('label_atlas_dir');   
    $atlas_label_path  = get_nii_from_inputs($atlas_label_dir,$label_atlas,'labels');
    $label_reference_path = $Hf->get_value('label_reference_path');    
    $label_refname = $Hf->get_value('label_refname');
    $mdt_contrast = $Hf->get_value('mdt_contrast');
    $inputs_dir = $Hf->get_value('inputs_dir');
   
    # $predictor_id = $Hf->get_value('predictor_id');
    $template_name = $Hf->get_value('template_name');

    $affine_target = $Hf->get_value('affine_target_image');

    my $header_output = `PrintHeader ${atlas_label_path}`;
    my $max_label_number;
    if ($header_output =~ /Range[\s]*\:[\s]*\[[^,]+,[\s]*([0-9\-\.e\+]+)/) {
	$max_label_number = $1;
	print "Max_label_number = ${max_label_number}\n"; 
    }
    $do_byte = 0;
    if ($max_label_number <= 255) {
	$do_byte = 1;
    }

    #print "Convert labels to Byte = ${do_byte}\n";
    
    $label_path = $Hf->get_value('labels_dir');
    $work_path = $Hf->get_value('regional_stats_dir');

    if ($label_path eq 'NO_KEY') {
	$label_path = "${work_path}/labels";
	$Hf->set_value('labels_dir',$label_path);
	if (! -e $label_path) {
	    mkdir ($label_path,$permissions);
	}
    }
    
    if ($group eq 'MDT') {
	$current_path = $Hf->get_value('median_images_path');
    } else {
	my $msg;
	if (! defined $current_label_space) {
	    $msg = "\$current_label_space not explicitly defined. Checking Headfile...";
	    $current_label_space = $Hf->get_value('label_space');
	} else {
	   $msg = "current_label_space has been explicitly set to: ${current_label_space}";
	}	
	printd(35,$msg);

	#$ROI_path_substring="${current_label_space}_${label_refname}_space/${label_atlas}";
	
	#$current_path = $Hf->get_value('label_results_dir');
	
	#if ($current_path eq 'NO_KEY') {
	    $current_path = "${label_path}/${current_label_space}_${label_refname}_space/${label_atlas}";
	    $Hf->set_value('label_results_dir',$current_path);
	#}
	my $intermediary_path = "${label_path}/${current_label_space}_${label_refname}_space";
	if (! -e $intermediary_path) {
	    mkdir ($intermediary_path,$permissions);
	}
	
	if (! -e $current_path) {
	    mkdir ($current_path,$permissions);
	}
    }
	
    print " $PM: current path is ${current_path}\n";
    
    $results_dir = $Hf->get_value('results_dir');
    
    $convert_labels_to_RAS=$Hf->get_value('convert_labels_to_RAS');
    
    if (($convert_labels_to_RAS ne 'NO_KEY') && ($convert_labels_to_RAS == 1)) {
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

	if (defined $current_label_space) {
	    $final_results_dir = "${almost_results_dir}/${current_label_space}_${label_refname}_space/";
	    if (! -e $final_results_dir) {
		mkdir ($final_results_dir,$permissions);
	    }
	    #$Hf->set_value('final_label_results_dir',$final_results_dir);
	    $Hf->set_value('final_connectomics_results_dir',$final_results_dir);
	}

	#$final_ROIs_dir = "${final_results_dir}/ROIs";
	#if (! -e $final_ROIs_dir) {
	#    mkdir ($final_ROIs_dir,$permissions);
	#}
    }

    $write_path_for_Hf = "${current_path}/${template_name}_temp.headfile";
    if ($group ne 'MDT') {
	$runlist = $Hf->get_value('complete_comma_list');
    } else {
	$runlist = 'MDT';
    }
 
    if ($runlist eq 'EMPTY_VALUE') {
	@array_of_runnos = ();
    } else {
	@array_of_runnos = split(',',$runlist);
    }

    my $case = 1;
    my ($dummy,$skip_message)=warp_atlas_labels_Output_check($case,$direction);

    if ($skip_message ne '') {
	print "${skip_message}";
    }

# check for needed input files to produce output files which need to be produced in this step?

}

1;
