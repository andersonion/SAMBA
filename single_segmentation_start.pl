#!/usr/local/pipeline-link/perl
# single_segmentation_start.pl
# originally created as vbm_pipeline, 2014/11/17 BJ Anderson CIVM
# single_segmentation_start spun off on 2017/03/14 BJ Anderson CIVM
#
# Roughly modeled after seg_pipe_mc structure. (For better or for worse.)
# ...and so its richly ironic that we are back to doing just that, but in a more complicated manner.


# All my includes and requires are belong to us.
# use ...

my $PM = 'single_segmentation_start.pl'; 

use strict;
use warnings;
no warnings qw(uninitialized bareword);

use Cwd qw(abs_path);
use File::Basename;
use List::MoreUtils qw(uniq);
use vars qw($Hf $runno $BADEXIT $GOODEXIT $test_mode $combined_rigid_and_affine $syn_params $permissions $intermediate_affine $valid_formats_string $nodes $reservation $broken  $mdt_to_reg_start_time);
use Env qw(ANTSPATH PATH BIGGUS_DISKUS WORKSTATION_DATA WORKSTATION_HOME);

$ENV{'PATH'}=$ANTSPATH.':'.$PATH;
#$ENV{'WORKSTATION_HOME'}="/cm/shared/workstation_code_dev";
$GOODEXIT = 0;
$BADEXIT  = 1;
my $ERROR_EXIT=$BADEXIT;
$permissions = 0755;
my $interval = 0.1; ##Normally 1
$valid_formats_string = 'hdr|img|nii';

# a do it again variable, will allow you to pull data from another vbm_run
my $import_data = 1;


$intermediate_affine = 0;
$test_mode = 0;

$runno = shift(@ARGV);

my @runnos = split(',',$runno);  # 04 April 2017, BJA -- I am currently cheating how we supply inputs: runno can be followed by andros if comma delimited.

$runno = $runnos[0];

my $recon_machine;

if ($#runnos > 0) {
    $recon_machine = $runnos[1];
}



$reservation=shift(@ARGV);

if (! defined $nodes) {
    $nodes = 1 ;
} else {
    if ($nodes =~ /[^0-9]/) { # Test to see if this is not a number; if so, assume it to be a reservation.
	$reservation = $nodes;
	my $reservation_info = `scontrol show reservation ${reservation}`;
	if ($reservation_info =~ /NodeCnt=([0-9]*)/m) { # Unsure if I need the 'm' option)
	    $nodes = $1;
	} else {
	    $nodes = 4;
	    print "\n\n\n\nINVALID RESERVATION REQUESTED: unable to find reservation \"$reservation\".\nProceeding with NO reservation, and assuming you want to run on ${nodes} nodes.\n\n\n"; 
	    $reservation = '';
	    sleep(5);
	}
    }
}


print "nodes = $nodes; reservation = \"$reservation\".\n\n\n";
if (! defined $broken) { $broken = 0 ;} 

umask(002);

use lib dirname(abs_path($0));
use Env qw(RADISH_PERL_LIB);
if (! defined($RADISH_PERL_LIB)) {
    print STDERR "Cannot find good perl directories, quitting\n";
    exit;
}
my $custom_pipeline_utilities_path ="${WORKSTATION_HOME}/shared/cluster_pipeline_utilities/";
$RADISH_PERL_LIB=$custom_pipeline_utilities_path.':'.$RADISH_PERL_LIB;
use lib split(':',$RADISH_PERL_LIB);

# require ...
require vbm_pipeline_workflow;
require apply_warps_to_bvecs;
require Headfile;
# require retrieve_archived_data;
# require study_variables_vbm;

# require convert_all_to_nifti_vbm;
# require set_reference_space_vbm;
# require create_rd_from_e2_and_e3_vbm;
# require mask_images_vbm;
# require create_affine_reg_to_atlas_vbm;
# require apply_affine_reg_to_atlas_vbm;
# require iterative_pairwise_reg_vbm;
# require pairwise_reg_vbm;
# require calculate_mdt_warps_vbm;
# require iterative_calculate_mdt_warps_vbm;
# require iterative_apply_mdt_warps_vbm;
# require apply_mdt_warps_vbm;
# require calculate_mdt_images_vbm;
# require compare_reg_to_mdt_vbm;
# require mdt_reg_to_atlas_vbm;
# require warp_atlas_labels_vbm;
# require mask_for_mdt_vbm;
# require calculate_jacobians_vbm;
# require smooth_images_vbm;
# require vbm_analysis_vbm;

# Temporary hardcoded variables

# variables, set up by the study vars script(study_variables_vbm.pm)
use vars qw(
$project_name 
@control_group
@compare_group

@group_1
@group_2

@channel_array
$custom_predictor_string
$template_predictor
$template_name

$flip_x
$flip_z 
$optional_suffix
$atlas_name
$label_atlas_name

$skull_strip_contrast
$threshold_code
$do_mask
$pre_masked
$port_atlas_mask
$port_atlas_mask_path
$thresh_ref

$rigid_contrast

$affine_contrast
$affine_metric
$affine_radius
$affine_shrink_factors
$affine_iterations
$affine_gradient_step
$affine_convergence_thresh
$affine_convergence_window
$affine_smoothing_sigmas
$affine_sampling_options
$affine_target

$mdt_contrast
$mdt_creation_strategy
$mdt_iterations
$mdt_convergence_threshold
$initial_template

$compare_contrast

$diffeo_metric
$diffeo_radius
$diffeo_shrink_factors
$diffeo_iterations
$diffeo_transform_parameters
$diffeo_convergence_thresh
$diffeo_convergence_window
$diffeo_smoothing_sigmas
$diffeo_sampling_options

$reference_path
$create_labels
$label_space
$label_reference

$transform_nii4d
$convert_labels_to_RAS
$eddy_current_correction
$do_connectivity
$recon_machine

$vbm_reference_space

$image_dimensions
 );


#study_variables_vbm();
{
    $flip_x = 1; # Normally zero for nian's code.
    #$flip_z = 1; # Normally zero for nian's code.
    $atlas_name='chass_symmetric2';
    $label_atlas_name=$atlas_name;
    $threshold_code=4;

    $project_name='16.gaj.38'; 
    @control_group=($runno);
    @compare_group=();
    
    
    @channel_array=qw(dwi fa);
    #$custom_predictor_string
    #$template_predictor
    $template_name=$runno;

    $optional_suffix=$runno;

    $skull_strip_contrast='dwi';

    $do_mask=1;
    $pre_masked=0;
    $port_atlas_mask=0;
    #$port_atlas_mask_path
    
    $rigid_contrast='dwi';

    $affine_contrast='dwi';
#$affine_metric
#$affine_radius
#$affine_shrink_factors
#$affine_iterations
#$affine_gradient_step
#$affine_convergence_thresh
#$affine_convergence_window
#$affine_smoothing_sigmas
#$affine_sampling_options
    $affine_target = $runno;

    $mdt_contrast='fa';
    $mdt_creation_strategy='pairwise';
#$mdt_iterations
#$mdt_convergence_threshold
#$initial_template

#$compare_contrast

#$diffeo_metric
#$diffeo_radius
#$diffeo_shrink_factors
    $diffeo_iterations = "3000x3000x3000x80";
#$diffeo_transform_parameters;
#$diffeo_convergence_thresh
#$diffeo_convergence_window
#$diffeo_smoothing_sigmas
#$diffeo_sampling_options

#$reference_path -- DEFUNCT?
    $create_labels=1;
    $label_space='post_rigid';
    #$label_space='pre_rigid';
    #$label_reference
    $convert_labels_to_RAS = 1;
    $vbm_reference_space='native';
    $do_connectivity = 1;

    $eddy_current_correction = 1;


## Add tensor preprocessing here...pulling in all data including nii4D and bvecs and ECC affine matrices
    vbm_pipeline_workflow();

## Add any tensory postprocessing here for nii4D and bvecs
    apply_mdt_warps_vbm('nii4D',"f",'all'); #
    apply_warps_to_bvecs();

} #end main

    
#---------------------
sub pull_data_for_connectivity {
#---------------------
    my $complete_runno_list=$Hf->get_value('complete_comma_list');
    my @array_of_runnos = split(',',$complete_runno_list);

    my $complete_channel_list=$Hf->get_value('channel_comma_list');
    my @array_of_channels = split(',',$complete_channel_list);

    my $inputs_dir = $Hf->get_value('pristine_input_dir');
    my $message_prefix="single_segmentation_start::pull_data_for_connectivity:\n";
    my $message_body;

    foreach my $runno(@array_of_runnos) {
	my $local_message_prefix="Attempting to retrieve data for runno: ${runno}\n";
	my $log_msg;
	my $tmp_log_msg;
	my $look_in_local_folder = 0;
	my $local_folder = "${inputs_dir}/tmp_folder/";

	# Look for more then two xform_$runno...mat files (ecc affine transforms)
	if ((defined $eddy_current_correction) && ($eddy_current_correction == 1)) {
	   my $number_of_ecc_xforms =  `ls ${inputs_dir}/xform_${runno}*.mat | wc -l`;
	   
	   print "number_of_ecc_xforms = ${number_of_ecc_xforms}\n\n";
	   if ($number_of_ecc_xforms < 6) { # For DTI, the minimum number of non-b0's is 6!
	       $tmp_log_msg = `puller_simple  -or ${recon_machine} tensor${runno}*-DTI-results/ ${local_folder}/`;
	       $log_msg = $log_msg.$tmp_log_msg;
	       $tmp_log_msg = `mv ${local_folder}/xform*mat ${inputs_dir}`;
	       $log_msg = $log_msg.$tmp_log_msg;
	       $look_in_local_folder = 1;
	   }
	   
	}


	# get any specified "traditional" dti images
	foreach my $contrast (@array_of_channels) {
	    my $test_file =  get_nii_from_inputs($inputs_dir,$runno,$contrast);
	    my $pull_file_cmd = "puller_simple -f file -or ${recon_machine} tensor${runno}*-DTI-results/${runno}*${contrast}.nii* ${inputs_dir}/";
	    
	    if ($test_file =~ /[\n]+/) {
		if ($look_in_local_folder) {
		    $test_file =  get_nii_from_inputs($local_folder,$runno,$contrast);
		    if ($test_file =~ /[\n]+/) {
			$tmp_log_msg = `${pull_file_cmd}`;
			$log_msg = $log_msg.$tmp_log_msg;
		    } else {
			$tmp_log_msg = `mv ${test_file} ${inputs_dir}`;
			$log_msg = $log_msg.$tmp_log_msg;
		    }
		} else {
		    $tmp_log_msg = `${pull_file_cmd}`;
		    $log_msg = $log_msg.$tmp_log_msg;
		}
	    }
	}
	
	# get nii4D
	my $nii4D = get_nii_from_inputs($inputs_dir,$runno,'nii4D');
	my $orig_nii4D;
	if ($nii4D =~ /[\n]+/) {
	    $orig_nii4D =  get_nii_from_inputs($inputs_dir,'nii4D',$runno); # tensor_create outputs nii4D_$runno.nii.gz
	    if ($orig_nii4D =~ /[\n]+/) {
		my $pull_nii4D_cmd = `puller_simple -f file -or ${recon_machine} tensor${runno}*-DTI-results/nii4D_${runno}*.nii* ${inputs_dir}/`;
		if ($look_in_local_folder) {
		    my $test_file =  get_nii_from_inputs($local_folder,'nii4D',$runno);
		    if ($test_file =~ /[\n]+/) {
			$tmp_log_msg = `${pull_nii4D_cmd}`;
			$log_msg = $log_msg.$tmp_log_msg;
		    } else {
			$tmp_log_msg = `mv ${test_file} ${inputs_dir}`;
			$log_msg = $log_msg.$tmp_log_msg;
		    }
		} else {
		    $tmp_log_msg = `${pull_nii4D_cmd}`;
		    $log_msg = $log_msg.$tmp_log_msg;
		}
	    }
	    $orig_nii4D =  get_nii_from_inputs($inputs_dir,'nii4D',$runno); # tensor_create outputs nii4D_$runno.nii.gz

	    my $new_nii4D = "${inputs_dir}/${runno}_nii4D.nii";
	    if ($orig_nii4D =~ /'.gz'/) {
		$new_nii4D = $new_nii4D.'.gz';
	    }
	    $tmp_log_msg = `mv ${orig_nii4D} ${new_nii4D}`;
	    $log_msg = $log_msg.$tmp_log_msg;
	}
	
	# get headfile
	my $head_file = "${inputs_dir}/tensor${runno}*.headfile";
	my $number_of_headfiles =  `ls ${head_file} | wc -l`;
	if ($number_of_headfiles < 1) {
	    my $pull_headfile_cmd = "puller_simple -f file -or ${recon_machine} tensor${runno}*-DTI-results/tensor${runno}*headfile ${inputs_dir}/";
	    if ($look_in_local_folder) {
		$head_file = "${local_folder}/tensor${runno}*.headfile";
		$number_of_headfiles =  `ls ${head_file} | wc -l`;
		if ($number_of_headfiles < 1) {
		    $tmp_log_msg = `${pull_headfile_cmd}`;
		    $log_msg = $log_msg.$tmp_log_msg;
		} else {
		    $tmp_log_msg = `mv ${head_file} ${inputs_dir}`;
		    $log_msg = $log_msg.$tmp_log_msg;
		    }
	    } else {
		$tmp_log_msg = `${pull_headfile_cmd}`;
		$log_msg = $log_msg.$tmp_log_msg;
	   }
	    
	}


	# Clean up temporary results folder
	if ($look_in_local_folder) {
	    #my $temp_folder = "${inputs_dir}/tensor${runno}*-DTI-results/";
	    my $number_of_temp_results_folders =  `ls -d ${head_file} | wc -l`;
	    if ($number_of_headfiles > 0) {
		$tmp_log_msg = `rm -r ${local_folder}`;
		$log_msg = $log_msg.$tmp_log_msg;
	    }
	}

	# Figure out which bvecs/bvals file to get
	my @headfiles = `ls ${inputs_dir}/tensor${runno}*headfile`;

	my $current_headfile = $headfiles[0];
	#my $current_Hf = read_headfile($current_headfile);
	my $current_Hf = new Headfile ('rw', $current_headfile);
	$current_Hf->read_headfile;
	my $original_gradient_location = $current_Hf->get_value('dti-recon-gradmat-file'); ## Unsure if this will work for Bruker...
	my ($o_grad_path,$grad_filename,$grad_ext) = fileparts($original_gradient_location,2);
	my $gradient_file = "${inputs_dir}/${runno}_${grad_filename}${grad_ext}";
	if (data_double_check($gradient_file)) { # Try pulling from tensor work folder first
	    my $bvec_machine;
	    if ($o_grad_path =~ s/^(\/){1}([A-Za-z1-9]*)(space\/)//){
		$bvec_machine = $2;
	    } else {
		$bvec_machine = $recon_machine;
	    }
	    my $pull_bvecs_cmd = "puller_simple -f file -or ${bvec_machine} ${o_grad_path}/${grad_filename}${grad_ext} ${gradient_file}";
	    $tmp_log_msg = `${pull_bvecs_cmd}`;
	    $log_msg = $log_msg.$tmp_log_msg;
	}
	
	if (data_double_check($gradient_file)) { #If unable to pull in from tensor work folder, create bvecs from info in headfile 
	    # This code is based on the shenanigans of tensor_create, as found in main_tensor.pl
	    my $Hf_grad_info =  $current_Hf->get_value("gradient_matrix_auto");
	    #parse bvecs
	    my ($grad_dim_info,$Hf_grad_string) = split(',',$Hf_grad_info);
	    my @Hf_gradients = split(' ',$Hf_grad_string);
	    my ($num_bvecs,$v_dim) = split(':',$grad_dim_info);
	    
	    #parse bvals
	    my $Bruker_data = 0; ### Temporarily only supporting Agilent data!
	    
	    my $approx_Hf_bval_handle;
	    my $Hf_bval_handle;
	    if (! $Bruker_data) { # Right now (06 April 2017) we're assuming Agilent data
		$approx_Hf_bval_handle = "z_Agilent_bvalue";
	    }
	    my $Hf_bval_info = $current_Hf->get_value_like($approx_Hf_bval_handle);
	    my ($bval_dim_info,$Hf_bval_string) = split(',',$Hf_bval_info);
	    my @Hf_bvals = split(' ',$Hf_bval_string);
	    my ($num_bvals,$bval_dim) = split(':',$bval_dim_info);
	    my $single_bval =0;
	    if ($num_bvals != $num_bvecs) { # If stuff blows up, let's default to assuming a single max_bvalue
		$single_bval=1;
		$approx_Hf_bval_handle = "max_bval";
		$Hf_bval_info = $current_Hf->get_value_like($approx_Hf_bval_handle);
		$Hf->set_value("max_bvalue_${runno}",$Hf_bval_info);
	    }

	    # combine bvals and bvecs into one table

	    my @gradient_matrix;
	    for (my $bb=0;($bb < $num_bvecs); $bb++) {
		$tmp_log_msg = "Creating combined bval/bvec b-table from headfile: ${current_headfile}.";
		$log_msg = $tmp_log_msg;
		
		my @temp_array;
		my $nonzero_test = 0;
		for (my $ii=0; ($ii < $v_dim); $ii++) {
		    my $temp_val = shift(@Hf_gradients);
		    push(@temp_array,$temp_val);
		    if (! $nonzero_test) {
			if ($temp_val ne '0') { # We are assuming that zero will always be stored in headfile as '0' (nor '0.0', '0.000', etc.
			    $nonzero_test = 1;
			}
		    }
		}
		my $current_bval=0;
		if ($single_bval) {
		    if ($nonzero_test) {
			$current_bval = $Hf_bval_info;
		    }
		} else {
		    my $new_bval = shift(@Hf_bvals);
		    if ($nonzero_test) {
			$current_bval = $new_bval;
		    }
		}

		my $b_string = join(', ',($current_bval,@temp_array));
		push(@gradient_matrix,$b_string."\n");
		$tmp_log_msg = ".";
		$log_msg = $tmp_log_msg;
	    }
	    $tmp_log_msg = "\nDone creating b-table: ${gradient_file} for ${num_bvecs} bval/bvec entries.\n";
	    $log_msg = $tmp_log_msg;
   	    	    
	    write_array_to_file($gradient_file,\@gradient_matrix);
	}
	$Hf->set_value("original_bvecs_${runno}",$gradient_file);
	# log any messages
	
	if ($log_msg ne '') {
	    $message_body=$message_body."\n".$local_message_prefix.$log_msg;
	}
    }
    if ($message_body ne '') {
	log_info("${message_prefix}${message_body}");
    }
}
   
