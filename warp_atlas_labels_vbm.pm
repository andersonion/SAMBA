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

use vars qw($Hf $BADEXIT $GOODEXIT  $test_mode $intermediate_affine $native_reference_space);
require Headfile;
require pipeline_utilities;

use List::Util qw(max);


my $do_inverse_bool = 0;
my ($atlas,$rigid_contrast,$mdt_contrast, $runlist,$work_path,$rigid_path,$current_path,$write_path_for_Hf);
my ($xform_code,$xform_path,$xform_suffix,$domain_dir,$domain_path,$inputs_dir);
my ($mdt_path,$predictor_id,$predictor_path, $diffeo_path,$work_done);
my (@array_of_runnos,@jobs,@files_to_create,@files_needed);
my (%go_hash);
my $go = 1;
my $job;

my ($label_atlas,$atlas_label_dir,$atlas_label_path);


# ------------------
sub warp_atlas_labels_vbm {  # Main code
# ------------------

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
	    print STDOUT  " Label sets have been created from the ${atlas_name} atlas labels for all runnos; moving on to next step.\n";
	}
    }
    my $case = 2;
    my ($dummy,$error_message)=warp_atlas_labels_Output_check($case);

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
  	$message_prefix = "  ${atlas_name} label sets have already been created for the following runno(s) and will not be recalculated:\n";
     } elsif ($case == 2) {
 	$message_prefix = "  Unable to create ${atlas_name} label sets for the following runno(s):\n";
     }   # For Init_check, we could just add the appropriate cases.

     
     my $existing_files_message = '';
     my $missing_files_message = '';
     
     foreach my $runno (@array_of_runnos) {

	 my $out_file = "${current_path}/${mdt_contrast}_labels_warp_${runno}.nii.gz";
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
    my $out_file = "${current_path}/${mdt_contrast}_labels_warp_${runno}.nii.gz";

    my $image_to_warp = $atlas_label_path;# get label set from atlas #get_nii_from_inputs($inputs_dir,$runno,$current_contrast); 
    my $reference_image;
    if ($native_reference_space) {
	$reference_image = $image_to_warp;
    } else {
	my @mdt_contrast  = split('_',$mdt_contrast);
	my $some_valid_contrast = $mdt_contrast[0];
	$reference_image =get_nii_from_inputs($inputs_dir,$runno,$some_valid_contrast);
    }
    my @mdt_warp_array = split(',',$Hf->get_value('inverse_label_xforms'));
    my $mdt_warp_train = join(' ',@mdt_warp_array);
    my ($warp_train,$warp_string,@warp_array);

    $warp_string = $Hf->get_value("inverse_xforms_${runno}");

    @warp_array = split(',',$warp_string);

    if ($runno ne $affine_target) {
	shift(@warp_array);	
    }

    $warp_train = join(' ',@warp_array).' '.$mdt_warp_train;


    my $create_cmd = "WarpImageMultiTransform 3 ${image_to_warp} ${out_file} -R ${reference_image} ${warp_train} --use-NN;\n";
    my $byte_cmd = "ImageMath 3 ${out_file} Byte ${out_file};\n";
    $cmd =$create_cmd.$byte_cmd;
    my $go_message =  "$PM: create ${atlas_name} label set for ${runno}";
    my $stop_message = "$PM: could not create ${atlas_name} label set for ${runno}:\n${cmd}\n";

    my $jid = 0;
    if (cluster_check) {
	my $home_path = $current_path;
	my $Id= "create_${atlas_name}_labels_for_${runno}";
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
	error_out("$PM: missing ${atlas_name} label set for ${runno}: ${out_file}");
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
 
# # Set up work
    $label_atlas = $Hf->get_value('label_atlas_name');
    $atlas_label_dir   = $Hf->get_value ('label_atlas_dir');   
    $atlas_label_path  = "${atlas_label_dir}/${label_atlas}_labels.nii";    

    $mdt_contrast = $Hf->get_value('mdt_contrast');

    

   

#    $mdt_path = $Hf->get_value('mdt_work_dir');
    $inputs_dir = $Hf->get_value('inputs_dir');
#    $rigid_path = $Hf->get_value('rigid_work_dir');
    $predictor_id = $Hf->get_value('predictor_id');
#    $predictor_path = $Hf->get_value('predictor_work_dir');
    $affine_target = $Hf->get_value('affine_target_image');
 
#	$diffeo_path = $Hf->get_value('reg_diffeo_path');   
    $current_path = $Hf->get_value('labels_dir');

    $write_path_for_Hf = "${current_path}/${predictor_id}_temp.headfile";

#   Functionize?
    $runlist = $Hf->get_value('complete_comma_list');
    @array_of_runnos = split(',',$runlist);
#

    my $case = 1;
    my ($dummy,$skip_message)=warp_atlas_labels_Output_check($case,$direction);

    if ($skip_message ne '') {
	print "${skip_message}";
    }

# check for needed input files to produce output files which need to be produced in this step?

}

1;
