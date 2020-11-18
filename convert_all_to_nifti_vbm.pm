#!/usr/bin/false

# convert_all_to_nifti_vbm.pm 

# modified 2014/12/12 BJ Anderson for use in VBM pipeline.
# Based on convert_all_to_nifti.pm, as implemented by seg_pipe_mc
# modified 20130730 james cook, renamed flip_y to flip_x to be more accurate.
# modified 2012/04/27 james cook. Tried to make this generic will special handling for dti from archive cases.
# calls nifti code that can get dims from header
# created 2010/11/02 Sally Gewalt CIVM

my $PM = "convert_all_to_nifti_vbm.pm";
my $VERSION = "2014/12/16";
my $NAME = "Convert input data into the proper format, flipping x and/or z if need be.";

use strict;
use warnings FATAL => qw(uninitialized);

use Env qw(RADISH_PERL_LIB);
if (! defined($RADISH_PERL_LIB)) {
    print STDERR "Cannot find good perl directories, quitting\n";
    exit;
}
use lib split(':',$RADISH_PERL_LIB);
use Headfile;
use pipeline_utilities;
use pull_civm_tensor_data;

# 25 June 2019, BJA: Will try to look for ENV variable to set matlab_execs and runtime paths
use Env qw(MATLAB_EXEC_PATH MATLAB_2015b_PATH); 
if (! defined($MATLAB_EXEC_PATH)) {
    $MATLAB_EXEC_PATH =  "/cm/shared/workstation_code_dev/matlab_execs";
}
if (! defined($MATLAB_2015b_PATH)) {
    $MATLAB_2015b_PATH =  "/cm/shared/apps/MATLAB/R2015b/";
}
my $matlab_path = "${MATLAB_2015b_PATH}";

my ($current_path, $work_dir,$runlist,$ch_runlist,$in_folder,$out_folder,$flip_x,$flip_z,$do_mask);
my (@array_of_runnos,@channel_array);
my (%go_hash,%go_mask,%mask_hash);
my $skip=0;
my $log_msg='';
my (@jobs);
my ($dummy,$error_message);

my $working_image_orientation;
# this exec had been "stable" for a long time. It was in sore need of a couple revisions.
# namely handling inputs are links, and output dir is prescribed.
my $img_exec_version='20170403_1100';
$img_exec_version='stable';
my $img_transform_executable_path ="${MATLAB_EXEC_PATH}/img_transform_executable/$img_exec_version/run_img_transform_exec.sh";

my $out_ext=".nii.gz";
$out_ext=".nhdr";
# ------------------
sub convert_all_to_nifti_vbm {
# ------------------
# convert the source image volumes used in this SOP to nifti format (.nii)
# could use image name (suffix) to figure out datatype
    ($skip) = @_;
    if ( ! defined($skip) || (defined($skip) && $skip eq '' )  ) {$skip = 0;}
    my $start_time = time;
    my $run_again = 1;  
    my $second_run=0;
    # bool to switch between set center on nodes through slurm or, swamp the master node.
    # This was added due to network tomfoolery where nodes may not have mounts.
    my $schedule_set_center=1;
    while ($run_again) {
        convert_all_to_nifti_vbm_Runtime_check();
	
        my @nii_cmds;
        my @nii_files;
        foreach my $runno (@array_of_runnos) {
            foreach my $ch (@channel_array) {
                my $go = $go_hash{$runno}{$ch};
                if ($go) {
                    my $job;
                    my $current_file=get_nii_from_inputs($in_folder,$runno,$ch);
                    my $Hf_key = "original_orientation_${runno}";
		    my $I_key=$Hf_key;
                    # May need to evolve to where each image is checked for proper orientation.
                    #my $Hf_key = "original_orientation_${runno}_${ch}";
                    # Insert orientation finder function here? No, want to out-source, I think.
		    my ($o_ok,$current_orientation)= $Hf->get_value_check($Hf_key);
                    if (! $o_ok ) { 
                        $Hf_key = "original_study_orientation";
			($o_ok,$current_orientation)= $Hf->get_value_check($Hf_key);
			if (! $o_ok ) { 
                            if ((defined $flip_x) || ($flip_z)) { 
                            # Going to assume that these archaic notions will come in pairs.
				carp("flip options are depricated and dangerous! ".
				     "Please use \"original_study_orientation\", with \"original_orientation_RUNNO\"\n".
				     "for non-matching data.\n");
				sleep_with_countdown(30);
                                if (($flip_x) && ($flip_z)) {
                                    $current_orientation = 'PLI';
                                } elsif ($flip_x) {
                                    $current_orientation = 'PRS';
                                } elsif ($flip_z) {
                                    $current_orientation = 'ARI';
                                } else {
                                    $current_orientation = 'ALS';
                                }
                            } else {
				croak "ORIENTATION NOT SET IN startup headfile, ".
				    "previously this was allowed, ".
				    "THAT WASTES TOO MUCH TIME. ".
				    "Figure out your original_study_orientation ".
				    "and add it!";
                                $current_orientation = 'ALS';
                            }
			    $Hf->set_value($I_key,$current_orientation);
                        }
                    } else {
                        print "Using custom orientation for runno $runno: $current_orientation.\n\n";
                    }
                    if ($current_file =~ /[\n]+/) {
                        print "Unable to find input image for $runno and $ch in folder: ${in_folder}.\n".$current_file;
                    } else {
                        # push(@nii_files,$current_file);
			# recenter currently stuck "on", as we can't turn it off in our function,
			# but we're ready to do better.
                        my $please_recenter=1; 
                        ($job,my $nii_cmd) =  set_center_and_orientation_vbm($current_file,$current_path,$current_orientation,$working_image_orientation,$please_recenter,$schedule_set_center);
			push(@nii_cmds,$nii_cmd);
                        if ($job&& $schedule_set_center) {
                            push(@jobs,$job);
                        }
                    }
                }
            }
        }
	if (! $schedule_set_center) {
	    execute_indep_forks(1,"set_orient_".$Hf->get_value('project_id'),@nii_cmds);
	}
        if (cluster_check() && scalar(@jobs)) {
            my $interval = 2;
            my $verbose = 1;
            my $done_waiting = cluster_wait_for_jobs($interval,$verbose,@jobs);
            
            if ($done_waiting) {
                print STDOUT  " Reorienting and recentering for all input images is complete; moving on to next step.\n";
            }
        }

        my $case = 2;
        ($dummy,$error_message)=convert_all_to_nifti_Output_check($case);

        #my $real_time = vbm_write_stats_for_pm($PM,$Hf,$start_time); #moved outside of while loop.
        #print "$PM took ${real_time} seconds to complete.\n";
        if (($error_message eq '') || ($second_run)) {
            $run_again = 0;
        } else {
            if ($civm_ecosystem) {
                print STDOUT " Several jobs have failed, possibly because the input files were not in the right place.\nAttempting to automatically find inputs...\n";
                # this call to get data is very seriously miss-placed. 
                # it forced that code to be terribly smart about what was missing or not.
                # New design goal is to let existing tools do their jobs. 
                # internally pull_civm_tensor_data relies on pull_many calling puller_simple to decide to do work or not. 
                pull_civm_tensor_data();
                $second_run=1;
            } else {
                error_out("${error_message}",0);
            }
        }
    }
    my $real_time = vbm_write_stats_for_pm($PM,$Hf,$start_time);
    if ($error_message ne '') {
        error_out("${error_message}",0);
    } 
    print "$PM took ${real_time} seconds to complete.\n";
    return;
}


# ------------------
sub convert_all_to_nifti_Output_check {
# ------------------

    my ($case) = @_;
    my $message_prefix ='';
    my ($file_1);
    my @file_array=();

    my $existing_files_message = '';
    my $missing_files_message = '';

    
    if ($case == 1) {
        $message_prefix = "  Prepared images have been found for the following runnos and will not be re-prepared:\n";
    } elsif ($case == 2) {
        $message_prefix = "  Unable to properly prepare images for the following runnos and channels:\n";
    }   # For Init_check, we could just add the appropriate cases.
    
    foreach my $runno (@array_of_runnos) {
        my $sub_existing_files_message='';
        my $sub_missing_files_message='';
        foreach my $ch (@channel_array) {
            $file_1 = get_nii_from_inputs($current_path,$runno,$ch);
            #print "File_1 = ${file_1}\n\n";
            my $unfounded =0;
            if ($file_1 =~ /[\n]+/) {
                $file_1 = "${current_path}/${runno}_${ch}.nii";
                $unfounded = 1;
            }
#die "here";
            if ((data_double_check($file_1,$file_1.'.gz') == 2 ) || ((! $pre_masked) && $unfounded &&  ($file_1 !~ /.*masked\.nii/))) { # 15 January 2016: Trying this instead, below fails for mixed masked/pre_masked (phantoms, for example).
                # if ((data_double_check($file_1) ) || ((! $do_mask) &&  (($file_1 =~ /.*masked\.nii/) || ($file_1 =~ /.*masked\.nii\.gz/)))) { # 6 January 2016: updated to look for .nii.gz as well.
                $go_hash{$runno}{$ch}=1;
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
sub set_center_and_orientation_vbm {
# ------------------
    my ($input_file,$output_folder,$current_orientation,$desired_orientation,$recenter,$go) = @_;
    if (! defined $recenter) {$recenter=1;} # Unused for now.

    my $matlab_exec_args='';
    my $jid = 0;
    if (! defined $go) {$go = 1; }
    my ($go_message, $stop_message);

    my $mem_request = '40000'; # Should test to get an idea of actual mem usage.
    my $space="vbm";
    ($mem_request,my $vx_count)=refspace_memory_est($mem_request,$space,$Hf);
#    if ($current_orientation eq $desired_orientation) {
    # Hope to have a function that easily and quickly diddles with the header to recenter it...may incorporate into matlab exec instead, though.
#    } else {
    $matlab_exec_args="${input_file} ${current_orientation} ${desired_orientation} ${output_folder}";
    my $cmd = "${img_transform_executable_path} ${matlab_path} ${matlab_exec_args}";
    #
    # NEED TO GET SMARTER again, 
    # If current_orientation == desired_orientation... 
    # and nhdr ... 
    # presume we have good center/and orientation.
    # BUT WE STILL process the file to transform by header.
    my ($p,$n,$e)=fileparts($input_file,2);
    if($current_orientation eq $desired_orientation && $e eq '.nhdr') {
	carp("experimental startup from nhdr engaged. INPUT HEADERS MUST BE CORRECT AND CENTERED.");
	my $reconditioned_dir=$output_folder;
	$reconditioned_dir=File::Spec->catdir($p,"conv_nhdr");
	mkdir $reconditioned_dir if ! -e $reconditioned_dir;
	my $nhdr_sg=File::Spec->catfile($reconditioned_dir,$n.$out_ext);
	my $nhdr_out=File::Spec->catfile($output_folder,$n.$out_ext);
	$matlab_exec_args="${nhdr_sg} ${current_orientation} ${desired_orientation} ${output_folder}";
	#$cmd = "${img_transform_executable_path} ${matlab_path} ${matlab_exec_args}";
	$cmd = "";
	# only run the nhdr adjust if we're missing or older.
	if( ! -e $nhdr_sg || ( -M $nhdr_sg ) > ( -M $input_file) ){ 
	    my $Wcmd=sprintf("WarpImageMultiTransform 3 %s %s ".
			 " --use-NN ".
			 " --reslice-by-header --tightest-bounding-box ".
			 "",
			 $input_file, $nhdr_sg);
	    my ($vx_sc,$est_bytes)=ants::estimate_memory($Wcmd,$vx_count);
	    # convert bytes to MB(not MiB).
	    $mem_request=ceil($est_bytes/1000/1000);
	    #$cmd=$cmd." && $Wcmd";
	    $cmd=$Wcmd;
	}
	my $c_cmd="ants_center_image $nhdr_sg $nhdr_out";
	if($cmd eq ''){
	    $cmd=$c_cmd;
	} else {
	    $cmd=$cmd." && ".$c_cmd;
	}
    } elsif( $e eq '.nhdr') {
	error_out("NHDR but not properly oriented! $input_file marked $current_orientation! (instead of $desired_orientation)");
    }

    $go_message = "$PM: Reorienting from ${current_orientation} to ${desired_orientation}, and recentering image: ${input_file}\n" ;
    $stop_message = "$PM: Failed to properly reorientate to ${desired_orientation} and recenter file: ${input_file}\n" ;
    
    if (cluster_check()) {
	my @test=(0);
	if (defined $reservation) {
	    @test =(0,$reservation);
	}
        my $home_path = $current_path;
        my $Id= "set_${desired_orientation}_${n}_orientation_and_center";
        my $verbose = 1; # Will print log only for work done.

        $jid = cluster_exec($go,$go_message , $cmd ,$home_path,$Id,$verbose,$mem_request,@test);
        if ($go && ( not $jid ) ){
	    error_out($stop_message);
	}
    }
    return($jid,$cmd);
}


# ------------------
sub convert_all_to_nifti_vbm_Init_check {
# ------------------

    my $init_error_msg='';
    my $message_prefix="$PM initialization check:\n";

    my $optional_runno_string=''; 
    # TODO: BJ, finish this thought, whatever it was. It seems like I had planned on looping over the outlier runnos, if any. 
    # OR this was anticipating a pm to autodetect coarse orientation.
    
    my $orientation_type = 'working_image_orientation';
    my $orientation_error_msg_prefix="I'm sorry, but an invalid ${orientation_type} has been requested ${optional_runno_string}: ";    
    my $orientation_error_msg_suffix=".\n\tOrientation must be allcaps and contain 3 of the following letters: A or P, L or R, S or I.\n"; 
    my $desired_orientation = $Hf->get_value($orientation_type);
    my $da = $desired_orientation;
    my $error_flag=0;
    if ($da  eq 'NO_KEY') {
        $da = 'ALS'; # This will soon change to RAS as the default, 'ALS' is historically what we've used.
        $Hf->set_value($orientation_type,$da);
        $log_msg = $log_msg."\nNo ${orientation_type}${optional_runno_string} has been specified; using default orientation of ${da}. \n";   
    } elsif ($da =~ /[^ALSRPI]/ ) {
        $error_flag=1;
    } elsif (($da =~ /[A]/)&& ($da =~ /[P]/)) {
        $error_flag=1;
    } elsif (($da =~ /[I]/)&& ($da =~ /[S]/)) {
        $error_flag=1;
    } elsif (($da =~ /[L]/)&& ($da =~ /[R]/)) {
        $error_flag=1;
    } else {
        $Hf->set_value($orientation_type,$da);
        $log_msg = $log_msg."\nUsing ${da} for {orientation_type}${optional_runno_string}, as requested. \n";
    }

    if ($error_flag) {
        $init_error_msg=$init_error_msg.$orientation_error_msg_prefix.$da.$orientation_error_msg_suffix;
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
sub convert_all_to_nifti_vbm_Runtime_check {
# ------------------

# # Set up work
    $in_folder = $Hf->get_value('pristine_input_dir');
    $work_dir = $Hf->get_value('dir_work');
#    $work_dir = $Hf->get_value('preprocess_dir');
#   $current_path = $Hf->get_value('inputs_dir');
    $current_path = $Hf->get_value('preprocess_dir');

    $working_image_orientation = $Hf->get_value('working_image_orientation');
    my $original_study_orientation = $Hf->get_value('original_study_orientation');

    if ($original_study_orientation eq 'NO_KEY') {
        $flip_x = $Hf->get_value('flip_x'); # Will phase out soon...
        if ($flip_x eq 'NO_KEY') {
            #undef $flip_x;
            $Hf->set_value('flip_x',0);
        }
        $flip_z = $Hf->get_value('flip_z'); # Will phase out soon...
        if ($flip_z eq 'NO_KEY') {
            #undef $flip_z;
            $Hf->set_value('flip_z',0);
        }
    }

    $do_mask = $Hf->get_value('do_mask');

#    opendir(DIR,$in_folder) or die ("$PM: could not open project inputs folder!";
#    my @nii_files = grep(/\.nii$/,readdir(DIR));

    if ($current_path eq 'NO_KEY') {
#       $current_path = "${work_dir}/base_images";
        $current_path = "${work_dir}/preprocess";
#       $Hf->set_value('inputs_dir',$current_path);     
        $Hf->set_value('preprocess_dir',$current_path);
    }
    if (! -e $current_path) {
        mkdir ($current_path,$permissions);
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
    my ($dummy,$skip_message)=convert_all_to_nifti_Output_check($case);

    if ($skip_message ne '') {
        print "${skip_message}";
    }
    ($dummy,$skip_message)=convert_all_to_nifti_Output_check($case);
    if ($skip_message ne '') {
        print "${skip_message}";
    }
}


1;

