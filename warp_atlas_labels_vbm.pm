#!/usr/local/pipeline-link/perl
# warp_atlas_labels_vbm.pm 
# Originally written by BJ Anderson, CIVM




my $PM = "warp_atlas_labels_vbm.pm";
my $VERSION = "2014/12/11";
my $NAME = "Application of warps derived from the calculation of the Minimum Deformation Template.";
my $DESC = "ants";

use strict;
use warnings;
no warnings qw(uninitialized bareword);

use vars qw($Hf $BADEXIT $GOODEXIT  $test_mode $combined_rigid_and_affine $reference_path  $intermediate_affine);
require Headfile;
require pipeline_utilities;

use List::Util qw(max);


my $do_inverse_bool = 0;
my ($atlas,$rigid_contrast,$mdt_contrast, $runlist,$work_path,$rigid_path,$current_path,$write_path_for_Hf);
my ($xform_code,$xform_path,$xform_suffix,$domain_dir,$domain_path,$inputs_dir,$median_images_path);
my ($mdt_path,$template_name, $diffeo_path,$work_done);
my ($label_path,$label_reference_path,$label_refname,$do_byte);
my (@array_of_runnos,@jobs,@files_to_create,@files_needed);
my (%go_hash);
my $go = 1;
my $job;
my $group='all';

my ($label_atlas,$atlas_label_dir,$atlas_label_path);


# ------------------
sub warp_atlas_labels_vbm {  # Main code
# ------------------
    ($group) = @_;
    if (! defined $group) {
	$group = 'all';
    }

    my $start_time = time;
    warp_atlas_labels_vbm_Runtime_check();

    foreach my $runno (@array_of_runnos) {
	$go = $go_hash{$runno};
	if ($go) {
	    ($job) = apply_mdt_warp_to_labels($runno);

	    if ($job > 1) {
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

	symbolic_link_cleanup($current_path);
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
	     $out_file = "${median_images_path}/MDT_labels_${label_atlas_name}.nii.gz";
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
	$out_file = "${median_images_path}/MDT_labels_${label_atlas_name}.nii.gz";
    }else {
	$out_file = "${current_path}/${mdt_contrast}_labels_warp_${runno}.nii.gz";
    }
    my ($start,$stop);
    my $image_to_warp = $atlas_label_path;# get label set from atlas #get_nii_from_inputs($inputs_dir,$runno,$current_contrast); 
    my $reference_image;

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
    my @mdt_warp_array = split(',',$Hf->get_value('inverse_label_xforms'));
    my $mdt_warp_string = $Hf->get_value('inverse_label_xforms');
    my $mdt_warp_train;
    my ($warp_train,$warp_string,@warp_array);
    my $create_cmd;
    my $option_letter = "t";
    my $additional_warp='';
    my $raw_warp;

    if ($runno ne 'MDT') {
	my $add_warp_string = $Hf->get_value("forward_xforms_${runno}");    
	my @add_warp_array = split(',',$add_warp_string);
	$raw_warp = pop(@add_warp_array);
    }
 
    $reference_image = $label_reference_path;

    if (data_double_check($reference_image)) {
	$reference_image=$reference_image.'.gz';
    }

    $mdt_warp_train=format_transforms_for_command_line($mdt_warp_string);
    if ($runno ne 'MDT') {
	$warp_string = $Hf->get_value("inverse_xforms_${runno}");
	$stop=3;
	if ($label_space eq 'pre_rigid') {
	    if ($combined_rigid_and_affine) {
		$start=2;
	    } else {
		$start=1;
	    }
	} elsif (($label_space eq 'pre_affine') || ($label_space eq 'post_rigid')) {
	    $start=2;
	    if ($combined_rigid_and_affine) {
		$additional_warp = " -t [${raw_warp},0] ";  
	    } 
	} elsif ($label_space eq 'post_affine') {
	    $start= 3;	
	}
	$warp_train = format_transforms_for_command_line($warp_string,$option_letter,$start,$stop);
    } else {
	$warp_train = "-${option_letter} ";
    }
    
    $warp_train=$additional_warp.' '.$warp_train.' '.$mdt_warp_train;
    
    $create_cmd = "antsApplyTransforms --float -d 3 -i ${image_to_warp} -o ${out_file} -r ${reference_image} -n NearestNeighbor ${warp_train};\n";
 
    my $byte_cmd = "fslmaths ${out_file} -add 0 ${out_file} -odt char;\n"; # Formerly..."ImageMath 3 ${out_file} Byte ${out_file};\n";...but this would renormalize our labelsets and confound the matter
    my $short_cmd = "fslmaths ${out_file} -add 0 ${out_file} -odt short;\n";
    if ($do_byte) {
	$cmd =$create_cmd.$byte_cmd;
    } else {
	$cmd = $create_cmd.$short_cmd;
    }

    my $go_message =  "$PM: create ${label_atlas_name} label set for ${runno}";
    my $stop_message = "$PM: could not create ${label_atlas_name} label set for ${runno}:\n${cmd}\n";

    my $jid = 0;
    if (cluster_check) {
	my $home_path = $current_path;
	my $Id= "create_${label_atlas_name}_labels_for_${runno}";
	my $verbose = 2; # Will print log only for work done.
	$jid = cluster_exec($go, $go_message, $cmd ,$home_path,$Id,$verbose);     
	if (! $jid) {
	    error_out($stop_message);
	}
    } else {
	my @cmds = ($cmd);
	if (! execute($go, $go_message, @cmds) ) {
	    error_out($stop_message);
	}
    }

    if ((!-e $out_file) && ($jid == 0)) {
	error_out("$PM: missing ${label_atlas_name} label set for ${runno}: ${out_file}");
    }
    print "** $PM created ${out_file}\n";
  
    return($jid,$out_file);
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
 
    if ($group eq 'MDT') {
	$median_images_path = $Hf->get_value('median_images_path');
    }
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

    print "Convert labels to Byte = ${do_byte}\n";
    
    $label_path = $Hf->get_value('labels_dir');
    if ($label_path eq 'NO_KEY') {
	$label_path = "${work_path}/labels";
	$Hf->set_value('labels_dir',$label_path);
	if (! -e $label_path) {
	    mkdir ($label_path,$permissions);
	}
    }

    $current_path = $Hf->get_value('label_results_dir');

    if ($current_path eq 'NO_KEY') {
	$current_path = "${label_path}/${label_space}_${label_refname}_space/${label_atlas}";
	$Hf->set_value('label_results_dir',$current_path);
    }
    my $intermediary_path = "${label_path}/${label_space}_${label_refname}_space";
    if (! -e $intermediary_path) {
	mkdir ($intermediary_path,$permissions);
    }

    if (! -e $current_path) {
	mkdir ($current_path,$permissions);
    }
    
    print " $PM: current path is ${current_path}\n";

    $write_path_for_Hf = "${current_path}/${template_name}_temp.headfile";
    if ($group ne 'MDT') {
	$runlist = $Hf->get_value('complete_comma_list');
    } else {
	$runlist = 'MDT';
    }
    @array_of_runnos = split(',',$runlist);

    my $case = 1;
    my ($dummy,$skip_message)=warp_atlas_labels_Output_check($case,$direction);

    if ($skip_message ne '') {
	print "${skip_message}";
    }

# check for needed input files to produce output files which need to be produced in this step?

}

1;
