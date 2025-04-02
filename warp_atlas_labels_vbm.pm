#!/usr/bin/env perl
# warp_atlas_labels_vbm.pm 
# Originally written by BJ Anderson, CIVM

my $PM = "warp_atlas_labels_vbm.pm";
my $VERSION = "2014/12/11";
my $NAME = "Application of warps derived from the calculation of the Minimum Deformation Template.";
my $DESC = "ants";

use strict;
use warnings;

require Headfile;
require SAMBA_pipeline_utilities;
#use SAMBA_pipeline_utilities qw(find_file_by_pattern);
use List::Util qw(max);


my $do_inverse_bool = 0;
my ($atlas,$rigid_contrast,$mdt_contrast, $runlist,$work_path,$rigid_path,$current_path,$write_path_for_Hf);
my ($xform_code,$xform_path,$xform_suffix,$domain_dir,$domain_path,$inputs_dir,$results_dir,$final_results_dir,$median_images_path);
my ($mdt_path,$template_name, $diffeo_path,$work_done);
my ($label_path,$label_reference_path,$label_refname,$do_byte,$do_short);
my (@array_of_runnos,@files_to_create,@files_needed);
my @jobs=();
my (%go_hash);
my $go = 1;
my $job;
my $group='all';
my $extra_transform_string='';
my ($label_atlas,$atlas_label_path,$label_atlas_nickname);
my ($convert_labels_to_RAS,$final_ROI_path);
my $label_type;
if (! defined $ants_verbosity) {$ants_verbosity = 1;}

my $make_individual_ROIs=0;
my $final_MDT_results_dir;
my $almost_results_dir;
my $almost_MDT_results_dir;

use Env qw(MATLAB_EXEC_PATH MATLAB_2015b_PATH SAMBA_APPS_DIR);
if (! defined($MATLAB_EXEC_PATH)) {
    $MATLAB_EXEC_PATH =  "${SAMBA_APPS_DIR}/matlab_execs_for_SAMBA";
}

if (! defined($MATLAB_2015b_PATH)) {
    $MATLAB_2015b_PATH =  "${SAMBA_APPS_DIR}/MATLAB2015b_runtime/v90";
}

my $matlab_path =  "${MATLAB_2015b_PATH}";

my $make_ROIs_executable_path = "${MATLAB_EXEC_PATH}/Labels_to_ROIs_executable/run_Labels_to_ROIs_exec.sh";

my $img_transform_executable_path ="${MATLAB_EXEC_PATH}/img_transform_executable/run_img_transform_exec.sh";

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
            print STDOUT  " Label sets have been created from the ${label_atlas_nickname} atlas labels for all runnos; moving on to next step.\n";
        }
    }
    my $case = 2;
    my ($dummy,$error_message)=warp_atlas_labels_Output_check($case);

    my $real_time = vbm_write_stats_for_pm($PM,$Hf,$start_time,@jobs);
    print "$PM took ${real_time} seconds to complete.\n";


    if ($error_message ne '') {
        error_out("${error_message}",0);
    } else {
        $Hf->write_headfile($write_path_for_Hf);

        symbolic_link_cleanup($current_path,$PM);
    }

    my @jobs_2;
    if (($convert_labels_to_RAS ne 'NO_KEY') && ($convert_labels_to_RAS == 1) ) {
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
                print STDOUT  " RAS label sets have been created from the ${label_atlas_nickname} atlas labels for all runnos; moving on to next step.\n";
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
        $message_prefix = "  ${label_atlas_nickname} label sets have already been created for the following runno(s) and will not be recalculated:\n";
     } elsif ($case == 2) {
        $message_prefix = "  Unable to create ${label_atlas_nickname} label sets for the following runno(s):\n";
     }   # For Init_check, we could just add the appropriate cases.

     
     my $existing_files_message = '';
     my $missing_files_message = '';
     #my $out_file = "${current_path}/${mdt_contrast}_labels_warp_${runno}.nii.gz";
     foreach my $runno (@array_of_runnos) {
         if ($group eq 'MDT') {
             $out_file = "${current_path}/MDT_${label_atlas_nickname}_${label_type}.nii.gz";
             $Hf->set_value("${label_atlas_nickname}_MDT_labels",$out_file);
         }else {
             $out_file = "${current_path}/${runno}_${label_atlas_nickname}_${label_type}.nii.gz";
         }
        
        # my $out_file      = "$out_file_path_base\.nii";

         if  (data_double_check($out_file,$case-1)) {
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
sub reveal_label_source_components {
# ------------------

# $direction=1: transform chain will be moving images from atlas to target
# $direction=0: transform chain will be moving images from target to atlas
my ($atlas_image_path,$direction) = @_;


if (! defined $direction) {
    $direction =1;
}

my $transform_chain='';
my $original_source_found=0;
my $c_path=$atlas_image_path;

#while (! $original_source_found
# Look in atlas folder for folder named warps_${any_old_atlas}
# Grab first one
# Look in forward or inverse folder and capture numbered names of warps/xforms
# Add to transform_chain

# We will develop this thought more later...want to search until we have backtracked to our 

# After finding the right warp directory nested in an atlaas dir, use ls to grab the pre-ordered file names
#$c_string = `ls -r ${c_warp_dir}/_*`;

#return($new_source_labels,$transform_chain);

}


# ------------------
sub resolve_transform_chain {
# ------------------

my ($chain_comma_string,$direction) = @_;
use Env('ATLAS_FOLDER');
my $atlases_path="${ATLAS_FOLDER}";
if (! defined $direction) {$direction =1;}

my $transform_chain='';

my @nodes = split(',',$chain_comma_string);
my @node_names=();
my @node_folders=();

# Resolve node_name and node_folder for each input node
for my $c_node (@nodes) {
    my $c_node_name='';
    my $c_node_folder='';
    # Test to to see if we have been given an explicit/arbitrary path to an atlas-like package
    if ( -e $c_node) {
        $c_node_folder=$c_node;
        (my $dummy_path , $c_node_name) = fileparts($c_node,2);
        push(@node_names,$c_node_name);
        push(@node_folders,$c_node_folder);
    } else {
        $c_node_name=$c_node;
        $c_node_folder = "${atlases_path}/${c_node}";
        push(@node_names,$c_node_name);
        push(@node_folders,$c_node_folder);
    }
}

for (my $ii=1;$ii<(scalar @node_names);$ii++) {
    my $edge_string = '';
    my $other_node_name = $node_names[$ii-1];
    my $c_node_name = $node_names[$ii];
    my ($test_dir_1 )= glob("${node_folders[$ii]}/transforms_${other_node_name}/${other_node_name}_to_*");
    if ((defined $test_dir_1) && (-e ${test_dir_1})) {
        $edge_string = `ls -r ${test_dir_1}/_*| xargs`;
    } else {
        my ($test_dir_2) = glob("${node_folders[$ii-1]}/transforms_${c_node_name}/${other_node_name}_to_${c_node_name}");
        $edge_string = `ls -r ${test_dir_2}/_* |xargs`;
    }
    chomp($edge_string);
    # check if edge is empty.
  

    $transform_chain = "${edge_string} ${transform_chain}";

}
return(${node_folders[0]},$transform_chain);

}



# ------------------
sub apply_mdt_warp_to_labels {
# ------------------
    my ($runno) = @_;
    my ($cmd);
    my $out_file;
    if ($group eq 'MDT') {
        $out_file = "${current_path}/MDT_${label_atlas_nickname}_${label_type}.nii.gz";
    }else {
        $out_file = "${current_path}/${runno}_${label_atlas_nickname}_${label_type}.nii.gz";
    }
    my ($start,$stop);
    my $image_to_warp = $atlas_label_path;# get label set from atlas #get_nii_from_inputs($inputs_dir,$runno,$current_contrast); 
    my $reference_image; ## 28 April 2017: NEED TO FURTHER INVESTIGATE WHAT REF IMAGE WE WANT OR NEED FOR MASS CONNECTIVITY COMPARISONS...!

    # 01 February 2019 (Fri): Adding support for substituting a source label file and extended 


    # if (! $native_reference_space) {
    #   $reference_image = $image_to_warp;
    # } else {
    #   my @mdt_contrast  = split('_',$mdt_contrast);
    #   my $some_valid_contrast = $mdt_contrast[0];
    #   if ($runno ne 'MDT') {
    #       $reference_image =get_nii_from_inputs($inputs_dir,$runno,$some_valid_contrast);
    #   } else {
    #       $reference_image =get_nii_from_inputs($median_images_path,$runno,$some_valid_contrast);
    #   }
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
    if (defined $extra_transform_string) {
        $warp_train=$warp_train.$extra_transform_string;
    }
    my $use_pre_Feb2019_code=0;
    # Before 6 Feb 2019, we would use NearestNeighbor, then run a second smoothing command
    # Using MultiLabel does nearly the same thing, but seems to do a slightly better job 
    # of avoiding orphaned islands.
    if ($use_pre_Feb2019_code) {
        $create_cmd = "antsApplyTransforms --float -v ${ants_verbosity} -d 3 -i ${image_to_warp} -o ${out_file} -r ${reference_image} -n NearestNeighbor ${warp_train};\n"; 
        my $smoothing_sigma = 1;
        my $smooth_cmd = "SmoothImage 3 ${out_file} ${smoothing_sigma} ${out_file} 0 1;\n";
        $create_cmd=$create_cmd.$smooth_cmd;
    } else {
       my @ref_array=split( ' ',$Hf->get_value('label_refspace'));
       my $voxel_size=pop(@ref_array);
       #$create_cmd = "antsApplyTransforms --float -v ${ants_verbosity} -d 3 -i ${image_to_warp} -o ${out_file} -r ${reference_image} -n MultiLabel[$voxel_size,2] ${warp_train};\n";
       # 11 March 2019: Removing "--float" option so that it will, OUT OF NECESSITY for the ABA/CCF3 case, use double for calculations and save out as such.
        $create_cmd = "antsApplyTransforms -v ${ants_verbosity} -d 3 -i ${image_to_warp} -o ${out_file} -r ${reference_image} -n MultiLabel[$voxel_size,2] ${warp_train};\n";
    }
 
    my $byte_cmd = "fslmaths ${out_file} -add 0 ${out_file} -odt char;\n"; # Formerly..."ImageMath 3 ${out_file} Byte ${out_file};\n";...but this would renormalize our labelsets and confound the matter
    my $short_cmd = "fslmaths ${out_file} -add 0 ${out_file} -odt short;\n";
    if ($do_byte) { # Smoothing added 15 March 2017
        $cmd =$create_cmd.$byte_cmd;
    } elsif ($do_short) { # Added support for 32-bit labels, i.e. CCF3_quagmire
        $cmd = $create_cmd.$short_cmd;
    } else {
        $cmd = ${create_cmd};
    }

    my $go_message =  "$PM: create ${label_atlas_nickname} label set for ${runno}";
    my $stop_message = "$PM: could not create ${label_atlas_nickname} label set for ${runno}:\n${cmd}\n";


    my @test=(0);
    if (defined $reservation) {
        @test =(0,$reservation);
    }
    
    my $mem_request = 30000;  # Added 23 November 2016,  Will need to make this smarter later.


    my $jid = 0;
    if (cluster_check) {
        my $home_path = $current_path;
        my $Id= "create_${label_atlas_nickname}_labels_for_${runno}";
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
        error_out("$PM: missing ${label_atlas_nickname} label set for ${runno}: ${out_file}");
    }
    print "** $PM expected output: ${out_file}\n";
  
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
        $out_file = "${final_MDT_results_dir}/MDT_${label_atlas_nickname}_${label_type}_RAS.nii.gz";
        $input_labels = "${current_path}/MDT_${label_atlas_nickname}_${label_type}.nii.gz";
        $work_file = "${current_path}/MDT_${label_atlas_nickname}_${label_type}_RAS.nii.gz";
        $final_ROIs_dir = "${final_MDT_results_dir}/MDT_${label_atlas_nickname}_RAS_ROIs/";
    }else {
        $out_file = "${final_results_dir}/${runno}/${runno}_${label_atlas_nickname}_${label_type}_RAS.nii.gz";
        $input_labels = "${current_path}/${runno}_${label_atlas_nickname}_${label_type}.nii.gz";
        $work_file = "${current_path}/${runno}_${label_atlas_nickname}_${label_type}_RAS.nii.gz";
        $final_ROIs_dir = "${final_results_dir}/${runno}_ROIs/";
        my $runno_results_dir="${final_results_dir}/${runno}";
        if (! -e $runno_results_dir) {
            mkdir ($runno_results_dir,$permissions);
        }
    }
    if ($make_individual_ROIs) {
        if (! -e $final_ROIs_dir) {
            mkdir ($final_ROIs_dir,$permissions);
        }
    }

    my $jid_2 = 0;

    if (data_double_check($out_file)) {

        my $current_vorder= $Hf->get_value('working_image_orientation');
    if (($current_vorder eq 'NO_KEY') || ($current_vorder eq 'UNDEFINED_VALUE') || ($current_vorder eq '')) {
        $current_vorder= 'ALS';
    }

        my $desired_vorder = 'RAS';

        if (data_double_check($work_file)) {
        my $matlab_exec_args="${input_labels} ${current_vorder} ${desired_vorder}"; #${output_folder}";
        $cmd = $cmd."${img_transform_executable_path} ${matlab_path} ${matlab_exec_args};\n";
        if ($make_individual_ROIs) {
            $cmd = $cmd."${make_ROIs_executable_path} ${matlab_path} ${input_labels}  ${final_ROIs_dir} ${current_vorder} ${desired_vorder};\n";
        }
        }

        $cmd =$cmd."cp ${work_file} ${out_file}";
 
        my $go_message =  "$PM: converting ${label_atlas_nickname} label set for ${runno} to RAS orientation";
        my $stop_message = "$PM: could not convert ${label_atlas_nickname} label set for ${runno} to RAS orientation:\n${cmd}\n";
        
        
        my @test=(0);
        if (defined $reservation) {
            @test =(0,$reservation);
        }
        
        my $mem_request = 30000;  # Added 23 November 2016,  Will need to make this smarter later.
        my $go_2 = 1;
        if (cluster_check) {
            my $home_path = $current_path;
            my $Id= "converting_${label_atlas_nickname}_labels_for_${runno}_to_RAS_orientation";
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
            error_out("$PM: missing RAS version of ${label_atlas_nickname} label set for ${runno}: ${out_file}");
        }
        print "** $PM expected output: ${out_file}\n";
    }
    
    return($jid_2,$out_file);
}


# ------------------
sub warp_atlas_labels_vbm_Init_check {
# ------------------

    my $init_error_msg='';
    my $message_prefix="$PM:\n";
    my $log_msg='';

    my $create_labels = $Hf->get_value('create_labels');
    my $label_atlas_name = $Hf->get_value('label_atlas_name');
    if (0) { # Code was moved from vbm_pipeline_workflow.pm, and we want to deactivate it for now.
    
            
        if (($create_labels eq 'NO_KEY') && (defined $label_atlas_name)){
           $create_labels = 1;
        } elsif (! defined $label_atlas_name) {
            $create_labels = 0;
        }
        Hf->set_value('create_labels',$create_labels);
    }

    my $label_space = $Hf->get_value('label_space');
    if ($label_space eq 'NO_KEY') {
        $label_space = "pre_affine"; # Pre-affine is the tentative default label space.
        $Hf->set_value('label_space',$label_space);
        $log_msg = $log_msg."\tLabel_space has not been specified; using default of ${label_space}.\n";
    } else {
    
        $log_msg = $log_msg."\tThe following label_space(s) have been specified: ${label_space}.\n";

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
sub warp_atlas_labels_vbm_Runtime_check {
# ------------------
    my ($direction)=@_;
 
#    if ($group eq 'MDT') {
#       $median_images_path = $Hf->get_value('median_images_path');
#    }
# # Set up work
    my $label_transform_chain = $Hf->get_value('label_transform_chain');
    my $label_input_file = $Hf->get_value('label_input_file');
    $label_atlas_nickname = $Hf->get_value('label_atlas_nickname');
    $label_atlas = $Hf->get_value('label_atlas_name');
    
    if (($label_atlas_nickname eq 'NO_KEY') ||  ($label_atlas_nickname eq 'EMPTY_VALUE') ) {
        if (( $label_input_file ne 'NO_KEY') && ($label_input_file ne 'EMPTY_VALUE') ) {
            (my $dummy_path , $label_atlas_nickname) = fileparts($label_input_file,2);
            $label_atlas_nickname =~ s/_(labels|quagmire|mess).*//;

        } else {
            $label_atlas_nickname=$label_atlas;
        }
        $Hf->set_value('label_atlas_nickname',$label_atlas_nickname);
    }
    my $source_label_folder='';
    my $use_default_labels =0;
    
    if (($label_transform_chain ne 'NO_KEY') && ($label_transform_chain ne 'NO_KEY') ) {
        ($source_label_folder, $extra_transform_string)=resolve_transform_chain($label_transform_chain);
    } else {
		undef $source_label_folder;
		undef $extra_transform_string;
    }
    if ( -f $label_input_file ) {
		$atlas_label_path = $label_input_file;
    } else {
		my $label_atlas_dir   = $Hf->get_value('label_atlas_dir');
		if (defined $source_label_folder) {
			$label_atlas_dir = $source_label_folder;
			$label_atlas_dir=~ s/[\/]*$//; # Remove trailing slashes
			(my $dummy, $label_atlas) = fileparts($label_atlas_dir,2);
			}
	
		if (($label_atlas_dir ne 'NO_KEY') && ($label_atlas_dir ne 'EMPTY_VALUE' ) ) { 
			my $labels_folder = "${label_atlas_dir}/labels_${label_atlas}"; # TODO: Will need to add another layer of folders here
			
			if ( ! -e $labels_folder ) {
			$labels_folder = ${label_atlas_dir};
			}
			
			if (($label_input_file ne 'NO_KEY') && ($label_input_file ne 'EMPTY_VALUE') ) {
			# In this case, it takes use specified filename: *_labels.nii.gz or *_quagmire.nii.gz or *_mess.nii.gz
			# In general this must be a file name with extension, but no directory
			# But in theory, anything in the form *_* (where there are NO underscores in the second wildcard string)
			# The first wildcard string is the parent folder, which in turn is in the labels_${label_atlas} folder
			# NOTE: If there is a discrepency between the name of the parent folder and the name of the label file
						#       up to but not including the last underscore, the full file path will need to be specified
			my $second_folder= $label_input_file;
			$second_folder =~ s/_[^_]*$//;
			$atlas_label_path  = "${labels_folder}/${second_folder}/${label_input_file}";
			} else {
			$atlas_label_path  = get_nii_from_inputs($labels_folder,$label_atlas,'(labels|quagmire|mess)');
			}
		} else {
					$use_default_labels = 1;
		}      
    }


    if ($use_default_labels) {
        $atlas_label_path  ="${ATLAS_FOLDER}/chass_symmetric3/chass_symmetric3_labels.nii.gz"; # THIS IS ONLY A TEMPORARY DEFAULT!   
    }

    my ($d1,$n,$d3)=fileparts($atlas_label_path,2);
    my @parts = split('_',$n);
    $label_type = pop(@parts);
    if ($label_type =~ /^[SPIRAL]{3}$/) {
        $label_type = pop(@parts);
    }

    $Hf->set_value('label_type',$label_type);   

    $label_reference_path = $Hf->get_value('label_reference_path');    
    $label_refname = $Hf->get_value('label_refname');
    $mdt_contrast = $Hf->get_value('mdt_contrast');
    $inputs_dir = $Hf->get_value('inputs_dir');
   
    # $predictor_id = $Hf->get_value('predictor_id');
    $template_name = $Hf->get_value('template_name');

    my $header_output = `PrintHeader ${atlas_label_path}`;
    my $max_label_number;
    if ($header_output =~ /Range[\s]*\:[\s]*\[[^,]+,[\s]*([0-9\-\.e\+]+)/) {
        $max_label_number = $1;
        print "Max_label_number = ${max_label_number}\n"; 
    }
    $do_byte = 0;
    $do_short = 0;
    if ($max_label_number <= 255) {
        $do_byte = 1;
    } elsif ($max_label_number <= 65535){
        $do_short = 1;
    }
    
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
            $current_path = $Hf->get_value('median_images_path')."/labels_MDT";
            if (! -e $current_path) {
            mkdir ($current_path,$permissions);
        }
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
            $current_path = "${label_path}/${current_label_space}_${label_refname}_space/${label_atlas_nickname}";
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

        $make_individual_ROIs=$Hf->get_value('make_individual_ROIs');
        if ($make_individual_ROIs eq 'NO_KEY') {
            $make_individual_ROIs=0;
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

    foreach my $runno (uniq(@array_of_runnos)) {
        # 7 March 2019 Find and copy lookup table, if available (look locally first)
        # Note that ONLY ONE file near source labels/quagmire can have the name *lookup.*
        # Otherwise we make no guarantee to proper behavior
        # 2 April 2025 Going to force it to look for only .txt files.

        my $local_lookup = $Hf->get_value("${runno}_${label_atlas_nickname}_label_lookup_table");
        if ($local_lookup eq 'NO_KEY') {
            #my $local_pattern="^${runno}_${label_atlas_nickname}_${label_type}_lookup[.].*\$";
            my $local_pattern="^${runno}_${label_atlas_nickname}_${label_type}_lookup[.].txt\$";
            ($local_lookup) = find_file_by_pattern($current_path,$local_pattern);
            if ((defined $local_lookup) && ( -e $local_lookup) ) {
                $Hf->set_value("${runno}_${label_atlas_nickname}_label_lookup_table",$local_lookup);
            } else {
                my ($atlas_label_dir, $dummy_1, $dummy_2) = fileparts($atlas_label_path,2);
                if ( -d $atlas_label_dir) {
                    my $pattern = "^.*lookup[.].txt\$";
                    my ($source_lookup) = find_file_by_pattern($atlas_label_dir,$pattern);
                    if ((defined $source_lookup) && ( -e $source_lookup)) {
                        my ($aa,$bb,$ext)=fileparts($source_lookup,2);
                        print "aa = $aa ";
                        print "bb = $bb ";
                        print "cc = $cc ";
                        `cp ${source_lookup} ${current_path}/${runno}_${label_atlas_nickname}_${label_type}_lookup${ext}`;
                    }
                    ($local_lookup) = find_file_by_pattern($current_path,$local_pattern);
                    print "3333: ${local_lookup}\n";
                    if ((defined $local_lookup) && ( -e $local_lookup) ) {
						print "4444: ${local_lookup}\n";
                        $Hf->set_value("${runno}_${label_atlas_nickname}_${label_type}_lookup_table",$local_lookup);
                    }
                }
            }
        }   
    }
    my $case = 1;
    my ($dummy,$skip_message)=warp_atlas_labels_Output_check($case,$direction);

    if ($skip_message ne '') {
        print "${skip_message}";
    }

# check for needed input files to produce output files which need to be produced in this step?

}

1;
