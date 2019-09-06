#!/usr/bin/false
# warp_atlas_labels_vbm.pm 
# Originally written by BJ Anderson, CIVM




my $PM = "warp_atlas_labels_vbm.pm";
my $VERSION = "2014/12/11";
my $NAME = "Application of warps derived from the calculation of the Minimum Deformation Template.";
my $DESC = "ants";

use strict;
use warnings;

require Headfile;
require pipeline_utilities;
use civm_simple_util qw(find_file_by_pattern filesystem_search);
use List::Util qw(max);

# 25 June 2019, BJA: Will try to look for ENV variable to set matlab_execs and runtime paths
use Env qw(MATLAB_EXEC_PATH MATLAB_2015b_PATH); 
if (! defined($MATLAB_EXEC_PATH)) {
   $MATLAB_EXEC_PATH =  "/cm/shared/workstation_code_dev/matlab_execs";
}
if (! defined($MATLAB_2015b_PATH)) {
    $MATLAB_2015b_PATH =  "/cm/shared/apps/MATLAB/R2015b/";
}
my $matlab_path = "${MATLAB_2015b_PATH}";

my $do_inverse_bool = 0;
my ($atlas,$rigid_contrast,$mdt_contrast, $runlist,$work_path,$rigid_path,$current_path,$write_path_for_Hf);
my ($xform_code,$xform_path,$xform_suffix,$domain_dir,$domain_path,$inputs_dir,$results_dir,$final_results_dir,$median_images_path);
my ($mdt_path,$template_name, $diffeo_path,$work_done);
my ($label_reference_path,$label_refname,$do_byte,$do_short);
my ($fsl_odt); # To replace do_byte and do_short, just set fsl_odt when appropriate, else it'll be undefined.
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

# Great deal of confuxtion regarding variable names!
# These two are symonyms, due to the greate specificity of label_atlas_name,
# AND THAT ITs the headfile key, we've adjusted to use that.
# label_atlas     
# label_atlas_name 

# This is an alternative for your outputs.(commonly WHS,coudl be CCF3)
# This is Convolved with the "label_type" and some code errroneously uses either.
# label_atlas_nickname

# proper format for atlas data(going forward)
#{label_atlas_name}_{contrast}.{supported_img_ext}
#labels/{label_atlas_nickname}/{label_atlas_name}_{label_atlas_nickname}_{label_type}.{supported_img_ext}
#eg, for chass_symmetric3_RAS atlas, 
# label_atlas_name=chass_symmetric3_RAS
# contrast = dwi|fa|ad|rd|md
# supported_img_ext =  nii|nhdr|ngz
# label_type= labels|quagmire|mess
# label_atlas_nickname=WHS|CCF3|CCF3CON
# dwi would be
#   chass_symmetric3_RAS_dwi.nii.gz
# labels would be
#   labels/WHS/chass_symmetric3_RAS_WHS_labels.nii.gz
# or
#   labels/CCF3/chass_symmetric3_RAS_CCF3_labels.nii.gz


# label_path was folder for output, often regional_stats_dir
# further messy, internal to headfiles its labels_dir
# THIS HAS BEEN CONVERTED TO labels_dir


# More synonyms. This one we kinda like, becuase it takes the specific 
# label_reference_path and converst it to the generic idea "reference_image"
# Noteably, this needs to be in the outputspace.
# 
# label_reference_path
# reference_image

# atlas_label_path, AND image_to_warp, are the selected label file,
# Now converting that to label_input_file to unify vars 
# becuase it fits the "exactly this file" idea.
# Now it may have been resolved automatically, which seems okay.
# atlas_label_path
# label_input_file
# image_to_warp

# concept cleanup vars
my ($labels_dir);



if (! defined $ants_verbosity) {$ants_verbosity = 1;}

my $make_individual_ROIs=0;
my $final_MDT_results_dir;
my $almost_results_dir;
my $almost_MDT_results_dir;

#my $make_ROIs_executable_path = "/glusterspace/BJ/run_Labels_to_ROIs_exec.sh";
my $make_ROIs_executable_path = "${MATLAB_EXEC_PATH}/Labels_to_ROIs_executable/20161006_1100/run_Labels_to_ROIs_exec.sh";
my $img_transform_executable_path ="${MATLAB_EXEC_PATH}/img_transform_executable/20170403_1100/run_img_transform_exe.sh";

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
    # Runtime_check includes outputcheck.
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
	# Symbolic link cleanup not appropriate here 
	# because WE DIDNT MAKE ANY WE WANT CLEANED :p
        #symbolic_link_cleanup($current_path,$PM);
    }
    my @jobs_2;
    if ($convert_labels_to_RAS == 1) {
die;die;die;# no seriously, die.
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
    if(! defined $label_atlas_nickname ) {
	Data::Dump::dump($label_input_file);die;
    }
    if ($case == 1) {
        $message_prefix = "  ${label_atlas_nickname} label sets have already been created for the following runno(s) and will not be recalculated:\n";
    } elsif ($case == 2) {
        $message_prefix = "  Unable to create ${label_atlas_nickname} label sets for the following runno(s):\n";
    }   # For Init_check, we could just add the appropriate cases.
    my $existing_files_message = '';
    my $missing_files_message = '';
    #my $out_file = "${current_path}/${mdt_contrast}_labels_warp_${runno}.nii.gz";
    foreach my $runno (@array_of_runnos) {
	if ($group eq 'MDT' 
	    || $current_label_space =~ /MDT/ 
	    ) {
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
    use Env('WORKSTATION_DATA');
    my $atlases_path="${WORKSTATION_DATA}/atlas";
    if (! defined $direction) {$direction =1;}
    confess "Direction not implemented!" if (! $direction);
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
    if ( $debug_val>=55){
        Data::Dump::dump(("Node Names:",\@node_names),("Node Folders:",\@node_folders));
    }
    for (my $ii=1;$ii<(scalar @node_names);$ii++) {
        my $edge_string = '';
        my $other_node_name = $node_names[$ii-1];
        my $c_node_name = $node_names[$ii];
        #my ($transform_back_dir )= glob("${node_folders[$ii]}/transforms_${other_node_name}/${other_node_name}_to_*");
        my $for_pat="${node_folders[$ii]}/transforms/${other_node_name}_to_*";
        my $back_pat="${node_folders[$ii-1]}/transforms/${other_node_name}_to_${c_node_name}";
        my ($transform_back_dir )= glob($for_pat);
        my ($transform_forward_dir) = glob($back_pat);
	my @components;
        if ((defined $transform_back_dir) && (-e ${transform_back_dir})) {
            printd(45,"Standard backward looking transform folder\n");
	    @components=run_and_watch("ls -r ${transform_back_dir}/_*");
        } elsif ((defined $transform_forward_dir) && (-e ${transform_forward_dir})) {
            printd(45,"Alternate forward looking transform folder\n");
	    @components=run_and_watch("ls -r ${transform_forward_dir}/_*");
        } else {
            error_out("Missing expected dir ~ $for_pat, and didnt find alternate ~ $back_pat");
        }
	chomp(@components);
	$edge_string = join(' ',@components);
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
    # May want to let space = MDT here in addition to group
    if ($group eq 'MDT' 
	|| $current_label_space =~ /MDT/ 
	) {
	$out_file = "${current_path}/MDT_${label_atlas_nickname}_${label_type}.nii.gz";
    } else {
        $out_file = "${current_path}/${runno}_${label_atlas_nickname}_${label_type}.nii.gz";
    }
    # What are start and stop!!!
    my ($start,$stop);
    # get label set from atlas #get_nii_from_inputs($inputs_dir,$runno,$current_contrast); 
    my $image_to_warp = $atlas_label_path;
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
    my $mdt_warp_string = $Hf->get_value('inverse_label_xforms');
    my $mdt_warp_train='';
    my $warp_train='';
    my $warp_prefix= '-t '; # Moved all creation of "-t" to here to avoid "-t -t ..." fiasco. 3 May 2017, BJA
    my $warp_string;
    my $create_cmd;
    my $option_letter = '';
    my $raw_warp;
    if ($runno ne 'MDT') {
        my $add_warp_string = $Hf->get_value("forward_xforms_${runno}");
        if ($add_warp_string eq 'NO_KEY') {
            $add_warp_string=$Hf->get_value("mdt_forward_xforms_${runno}")
        }
    } 
    $reference_image = $label_reference_path;
    # We gotta stop guessing what the user wants!
    #if (data_double_check($reference_image)) {
    #$reference_image=$reference_image.'.gz';
    #}
    die "ERROR WITH SPECIFIED label_reference_path" if ! -e $reference_image;
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
        $create_cmd = "antsApplyTransforms --float -v ${ants_verbosity} -d 3 -i ${label_input_file} -o ${out_file} -r ${reference_image} -n NearestNeighbor ${warp_train};\n"; 
        my $smoothing_sigma = 1;
        my $smooth_cmd = "SmoothImage 3 ${out_file} ${smoothing_sigma} ${out_file} 0 1;\n";
        $create_cmd=$create_cmd.$smooth_cmd;
    } else {
        my @ref_array=split( ' ',$Hf->get_value('label_refspace'));
        my $voxel_size=pop(@ref_array);
        #$create_cmd = "antsApplyTransforms --float -v ${ants_verbosity} -d 3 -i ${label_input_file} -o ${out_file} -r ${reference_image} -n MultiLabel[$voxel_size,2] ${warp_train};\n";
        # 11 March 2019: Removing "--float" option so that it will, OUT OF NECESSITY for the ABA/CCF3 case, use double for calculations and save out as such.
        $create_cmd = "antsApplyTransforms -v ${ants_verbosity} -d 3 -i ${label_input_file} -o ${out_file} -r ${reference_image} -n MultiLabel[$voxel_size,2] ${warp_train};\n";
    }
    
    if ($do_byte) { # Smoothing added 15 March 2017
	my $byte_cmd = "fslmaths ${out_file} -add 0 ${out_file} -odt char;\n"; 
        $cmd =$create_cmd.$byte_cmd;
    } elsif ($do_short) { # Added support for 32-bit labels, i.e. CCF3_quagmire
	my $short_cmd = "fslmaths ${out_file} -add 0 ${out_file} -odt short;\n";
        $cmd = $create_cmd.$short_cmd;
    } elsif( defined $fsl_odt ){
	my $fsl_conv = "fslmaths ${out_file} -add 0 ${out_file} -odt $fsl_odt;\n"; 
	$cmd = $create_cmd.$fsl_conv;
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
        my $verbose = 1; # Will print log only for work done.
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

    #if ((!-e $out_file) && (not $jid)) {
    if ($go && (not $jid)) {
        error_out("$PM: could not start for ${label_atlas_nickname} label set for ${runno}: ${out_file}");
    }
    print "** $PM expected output: ${out_file}\n";
    
    return($jid,$out_file);
}

# ------------------
sub convert_labels_to_RAS {
# ------------------
    die "dirty vestigal friend";
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
                
        my $go_2 = 1;
        if (cluster_check) {
            my $home_path = $current_path;
            my $Id= "converting_${label_atlas_nickname}_labels_for_${runno}_to_RAS_orientation";
            my $verbose = 1; # Will print log only for work done.
	    my $mem_request = 30000;  # Added 23 November 2016,  Will need to make this smarter later.
	    my @test=(0);
	    if (defined $reservation) {
		@test =(0,$reservation);
	    }
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
    #if (0) { # Code was moved from vbm_pipeline_workflow.pm, and we want to deactivate it for now.
    #if (($create_labels eq 'NO_KEY') && (defined $label_atlas_name)){
    #    $create_labels = 1;
    #} elsif (! defined $label_atlas_name) {
    #    $create_labels = 0;
    #}
    #$Hf->set_value('create_labels',$create_labels);
    #}
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
    # Set up work
    # label_input_file, eg user exact specificaiton override mode.
    (my $use_l_in,$label_input_file) = $Hf->get_value_check('label_input_file');
    (my $use_l_a_n,$label_atlas_nickname) = $Hf->get_value_check('label_atlas_nickname');
    # Label_atlas_name is ALWAYS SET, but nickname may not be.
    $label_atlas_name = $Hf->get_value('label_atlas_name');
    if (! $use_l_a_n ) {
        if ( $use_l_in ) {
            (my $dummy_path , $label_atlas_nickname) = fileparts($label_input_file,2);
	    # convert filename to nick name with expectation that nickname is just in front of labeltype keyword.
	    # Dont get confused that this is the inverse of what you're looking for!
            $label_atlas_nickname =~ s/_($samba_label_types).*//x;
	    printd(5,"Calculated label_atlas_nickname -> $label_atlas_nickname\n");die "Programmer testing";
        } else {
            $label_atlas_nickname=$label_atlas_name;
        }
        $Hf->set_value('label_atlas_nickname',$label_atlas_nickname);
    }
    # Label_atlas_dir is only used here to get the base directory of the labeling atlas. 
    # It's set in create_affine_reg_to_atlas_Init_check, OR by the user on input.
    my ($use_lad,$label_atlas_dir)   = $Hf->get_value_check('label_atlas_dir');
    my ($use_l_t_c,$label_transform_chain) = $Hf->get_value_check('label_transform_chain');
    if ($use_l_t_c ) {
	# Assumptions
	#   label_transform_chain is complete, from starting post to all but the current link.
	#   We only specify if we want it, It superceeds all the other things. 
	($label_atlas_dir, $extra_transform_string)=resolve_transform_chain($label_transform_chain);
	if (! defined $label_atlas_dir){
	    die "Error resolving transform chain from $label_transform_chain";
	}
	$label_atlas_dir=~ s/[\/]*$//; # Remove trailing slashes
	(my $dummy, $label_atlas_name) = fileparts($label_atlas_dir,2);
    }
    if ($use_lad ) {
	# We got the "label_atlas_dir" which is the base for the whole atlas and the labels can be nested deeper
	# So we make a list of good places to look, in order, and we take the first valid.
	# Unfortunately we could be hiding behind a label_atlas_nickname, AND if the user didnt set that to the 
	# right one we'll fail.
	# I think that means we'd like to deprecate label_atlas_dir auto-resolve behavior.
	    my @l_folders;
	    # When there is only one choice inside a labels or labels_label_atlas_name folder we could just use that, 
	    # and treat it as a nick name. 
	    # Hey lets resvolve nickname here If it's not been set explicitly.
	    # So, that is :
	    my @available_nicks;
	    @available_nicks=filesystem_search(File::Spec->catdir($label_atlas_dir,"labels"),  "^[^_].*", 1, '-d' );
	    # trim the search base off
	    foreach(@available_nicks) { $_=basename $_; }# $_=~s/$td//gx; }
	    #Data::Dump::dump(@available_nicks);
	    my $an_info='';
	    if( ! $use_l_a_n ) {
		if(scalar(@available_nicks)>1){
		    $an_info="please set a label_atlas_nickname from available nicks:".join(",",@available_nicks);
		    if(scalar(@available_nicks)==1){
			# Guessing is really only okay when there's just one.
			printd(5,"Guessed the nickname for the label output changing $label_atlas_nickname into $available_nicks[0]\n");		    $label_atlas_nickname=$available_nicks[0];
		    }
		}
	    }
	    # BUT guessing things is what made all this code so tough to begin with.
	    # The bestest way to fix it would probably be leave metadata with the atlas folder itself instead 
	    # of forcing some conventions deep in here.
	    # Lets set that... when we have no nickname set, look for metadata
	    push(@l_folders,File::Spec->catdir($label_atlas_dir,"labels","$label_atlas_nickname"));
	    push(@l_folders,File::Spec->catdir($label_atlas_dir,"labels_${label_atlas_name}","$label_atlas_nickname"));
	    push(@l_folders,File::Spec->catdir($label_atlas_dir,"labels_${label_atlas_name}"));
	    push(@l_folders,File::Spec->catdir($label_atlas_dir,"labels"));
	    push(@l_folders,$label_atlas_dir);
	    #Oh multi_choice_dir, another abomination of process.
	    $label_atlas_dir=multi_choice_dir(\@l_folders);
	    if ( ! -e $label_atlas_dir ) {
		error_out("Problem finding label_atlas_dir!");
            }
	    $label_input_file = get_nii_from_inputs($label_atlas_dir,$label_atlas_name,'('.$samba_label_types.')');
	    if ( ! -f "$label_input_file" ) {
		error_out("label_input_dir auto resolution of label file failed, $label_input_file".$an_info); }
    } else {
	#$use_default_labels = 1;
	# Default labels fail,
	die "this condidtion should be unreachable, contact programmer";
	# THIS TEMPORARY DEFAULT IS NOW DEACTIVATED!   
	$label_input_file  ="${WORKSTATION_DATA}/atlas/chass_symmetric3_RAS/chass_symmetric3_RAS_labels.nii.gz"; 
    }
    # label_input_file  stands in as an alternateive to guessing everything based on one key detail.
    if ( $use_l_in ) {
	if (! -f $label_input_file ) { 
	    error_out("label_input_file specified, and was not found. Please fix your input (omit or specify a valid path) and re-start DebugInfo: use($use_l_in) file($label_input_file)");
	}
    }

    # Notate which "label type" we're dealing with, (mess|quagmire|labels)
    # Being senstitive to the frequent orientation postfix.
    #my ($d1,$n,$d3)=fileparts($label_input_file,2);
    #my @parts = split('_',$n);
    #$label_type = pop(@parts);
    #if ($label_type =~ /^[SPIRAL]{3}$/) {
    #    $label_type = pop(@parts);
    #}
    # More concisely
    # TAKE CARE WITH THIS REGEX, this is extracting a word, NOT searching and replacing,
    # that moves where the parenthesis belongs!
    ( $label_type ) = $label_input_file =~ /($samba_label_types)/x;
    $Hf->set_value('label_type',$label_type);   

    $label_reference_path = $Hf->get_value('label_reference_path');
    $label_refname = $Hf->get_value('label_refname');
    $mdt_contrast = $Hf->get_value('mdt_contrast');
    $inputs_dir = $Hf->get_value('inputs_dir');
    
    # $predictor_id = $Hf->get_value('predictor_id');
    $template_name = $Hf->get_value('template_name');

    #
    # SLOPPY WAY TO FIND MAX LABEL NUMBER! 
    #
    # TODO: look at the label lookup table and get max number.
    #       That will trash poorly curated atlas data. AND THAT IS PERFECT! 
    #       Atlases SHOULD be well curated, else WHY are they an atlas?
    #my $header_output = `PrintHeader ${label_input_file}`;
    my $header_output = join("\n",run_and_watch("PrintHeader ${label_input_file}") );
    my $max_label_number;
    if ($header_output =~ /Range[\s]*\:[\s]*\[[^,]+,[\s]*([0-9\-\.e\+]+)/) {
        $max_label_number = $1;
        print "Max_label_number = ${max_label_number}\n"; 
    }
    # Now will always be false because fsl_odt superceeds them
    $do_byte = 0;
    $do_short = 0;
    if ($max_label_number <= 255) {
        #$do_byte = 1;
	$fsl_odt="char";
    } elsif ($max_label_number <= 65535){
        #$do_short = 1;
	# NOTE: No ushort available.
	# reports back:
	#   Error: Unknown datatype "ushort" - Possible datatypes are: char short int float double input
	$fsl_odt="short";
    }
    
    my $msg;
    if (! defined $current_label_space || $current_label_space eq '' ) {
	$msg = "\$current_label_space not explicitly defined. Checking Headfile...";
	$current_label_space = $Hf->get_value('label_space');
	carp("inline space setting discouraged, Tell your programmer");
	sleep(1);die($msg);
    } else {
	$msg = "current_label_space has been explicitly set to: ${current_label_space}";
    }
    printd(35,$msg);
    
    #$labels_dir = $Hf->get_value('labels_dir');
    #if ($labels_dir eq 'NO_KEY') {
    # This was erroneously set earlier by other modules! 
    # This code was REPLICATED in three other places!
    # Trying to have it active only here because this is where we use it.
    #2019-08-28 The grand task of unentangle labled bits
    #$work_path = $Hf->get_value('regional_stats_dir');
    #$labels_dir = "${work_path}/labels";
    $labels_dir = $Hf->get_value('regional_stats_dir')
	."/${current_label_space}_${label_refname}_space";
    $Hf->set_value('labels_dir',$labels_dir);
    #}
    if (! -e $labels_dir) {
	use File::Path qw(mkpath);
	mkpath($labels_dir,0,$permissions);
    }
    #}
    if ($group eq 'MDT'
	|| $current_label_space =~ /MDT/ 
	) {
        $current_path = $Hf->get_value('median_images_path')."/labels_MDT";
    } else {
	$current_path = "$labels_dir";
    }
    
    if (! -e $current_path) {
	mkdir ($current_path,$permissions);
    }
    print " $PM: current path is ${current_path}\n";
=item disabled code
    $results_dir = $Hf->get_value('results_dir');
    (my $f_ok,$convert_labels_to_RAS)=$Hf->get_value_check('convert_labels_to_RAS');
    if ( ! $f_ok ) { $convert_labels_to_RAS=0; }
    if ($convert_labels_to_RAS == 1) {
	# ONE set of data should come out IN WORKING ORIENTATION! ALWAYS!
	# If you choose to work in something besides RAS that's on you!
	# if we want to support "additional" orientations we should 
	# blanket replicate all "results" into new orientation.
	die "THIS IS OUTMODED AND BAD";
        #$almost_MDT_results_dir = "${results_dir}/labels/";
        $almost_MDT_results_dir = "${results_dir}/connectomics/";
        if (! -e $almost_MDT_results_dir) {
            mkdir ($almost_MDT_results_dir,$permissions);
        }

        #$final_MDT_results_dir = "${almost_MDT_results_dir}/${label_atlas_name}/";
        $final_MDT_results_dir = "${almost_MDT_results_dir}/MDT/";
        if (! -e $final_MDT_results_dir) {
            mkdir ($final_MDT_results_dir,$permissions);
        }

        #$almost_results_dir = "${results_dir}/labels/${current_label_space}_${label_refname}_space/";
        $almost_results_dir = "${results_dir}/connectomics/";
        if (! -e $almost_results_dir) {
            mkdir ($almost_results_dir,$permissions);
        }

        #$final_results_dir = "${almost_results_dir}/${label_atlas_name}/";

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
=cut

    $write_path_for_Hf = "${current_path}/.${template_name}_wal_temp.headfile";
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
        my $local_lookup = $Hf->get_value("${runno}_${label_atlas_nickname}_label_lookup_table");
        if ($local_lookup eq 'NO_KEY') {
            my $local_pattern="^${runno}_${label_atlas_nickname}_${label_type}_lookup[.].*\$"; 
	    ($local_lookup) = find_file_by_pattern($current_path,$local_pattern,1);
            if ((defined $local_lookup) && ( -e $local_lookup) ) {
                $Hf->set_value("${runno}_${label_atlas_nickname}_label_lookup_table",$local_lookup);
            } else {
                my ($atlas_label_dir, $dummy_1, $dummy_2) = fileparts($label_input_file,2);
                if ( -d "$atlas_label_dir" ) {
                    my $pattern = "^.*lookup[.].*\$";
                    my ($source_lookup) = find_file_by_pattern($atlas_label_dir,$pattern,1);

                    if ((defined $source_lookup) && ( -e $source_lookup)) {
                        my ($aa,$bb,$ext)=fileparts($source_lookup,2);
                        run_and_watch("cp ${source_lookup} ${current_path}/${runno}_${label_atlas_nickname}_${label_type}_lookup${ext}");
                    }
                    ($local_lookup) = find_file_by_pattern($current_path,$local_pattern,1);
		    #Data::Dump::dump($source_lookup,$label_input_file,$atlas_label_dir,$current_path,$local_lookup);
                    if ((defined $local_lookup) && ( -e $local_lookup) ) {
                        $Hf->set_value("${runno}_${label_atlas_nickname}_label_lookup_table",$local_lookup);
                    } else {
			die "I insist you have a lookup table, and try though I might I could not get one.";
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
