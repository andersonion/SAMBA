#!/usr/bin/false
#  calculate_individual_label_statistics_vbm.pm
#  2017/06/16  Created by BJ Anderson, CIVM.

my $PM = " calculate_individual_label_statistics_vbm.pm";
my $VERSION = "2019/04/24";
my $NAME = "Calculate label-wide statistics for all contrast, for an individual runno.";

use strict;
use warnings FATAL => qw(uninitialized);
require Headfile;
require pipeline_utilities;

use Env qw(MATLAB_EXEC_PATH MATLAB_2015b_PATH);
if (! defined($MATLAB_EXEC_PATH)) {
    $MATLAB_EXEC_PATH =  "/cm/shared/workstation_code_dev/matlab_execs";
}
if (! defined($MATLAB_2015b_PATH)) {
    $MATLAB_2015b_PATH =  "/cm/shared/apps/MATLAB/R2015b/";
}
my $matlab_path =  "${MATLAB_2015b_PATH}";

my ($current_path, $image_dir,$work_dir,$runlist,$ch_runlist,$in_folder,$out_folder);
my ($channel_comma_list,$channel_comma_list_2,$mdt_contrast,$space_string,$current_label_space,$labels_dir,$label_atlas_name,$label_atlas_nickname);
my (@array_of_runnos,@channel_array,@initial_channel_array);
#my ($predictor_id); # SAVE FOR LAST ROUND OF LABEL STATS CODE
my ($vx_count);# count of voxels in current space...
my @jobs=();
my (%go_hash,%go_mask);
my $log_msg='';
my $skip=0;
my $go = 1;
my $job;
my $label_type;
my $PM_code = 65;

#my $compilation_date = "20180227_1439";#"20170616_2204"; Updated 27 Feb 2018, BJA--will now ignore any voxels with contrast values of zero (assumed to be masked)

# New enhancements stabilized.
my $compilation_date = "latest";
my $write_individual_stats_executable_path = "$MATLAB_EXEC_PATH/write_individual_stats_executable/${compilation_date}/run_write_individual_stats_exec.sh";
my $write_rat_report_executable_path = "$MATLAB_EXEC_PATH/label_stats_executables/write_rat_report_executable/20171013_1038/run_write_rat_report_exec.sh";

my $out_ext=".nii.gz";
$out_ext=".nhdr";
# ------------------
sub  calculate_individual_label_statistics_vbm {
# ------------------
    ($current_label_space,@initial_channel_array) = @_;
    my $start_time = time;

    calculate_individual_label_statistics_Runtime_check();

    foreach my $runno (@array_of_runnos) {
        $go = $go_hash{$runno};
        if ($go) {
            my $input_labels = "${work_dir}/${runno}_${label_atlas_nickname}_${label_type}${out_ext}";
            my $local_lookup = $Hf->get_value("${runno}_${label_atlas_nickname}_label_lookup_table");
            if ($local_lookup eq 'NO_KEY') {
                undef $local_lookup;
            }
            if($current_label_space =~ /MDT/ ) {
                # in the tset case labelfile hf key was WHS_MDT_labels
                #$input_labels=$Hf->get_value("${label_atlas_nickname}_${current_label_space}_${label_type}${out_ext}")
                $input_labels=$Hf->get_value("${label_atlas_nickname}_${current_label_space}_labels");
            }
            ($job) = calculate_label_statistics($runno,$input_labels,$local_lookup);
            if ($job) {
                push(@jobs,$job);
            }
        }
    }

    my $species = $Hf->get_value_like('U_species.*');
    if ($species =~ /rat/) {
        foreach my $runno (@array_of_runnos) {
            print STDERR 'Halfbaked "Rat" report is being skipped';
            continue ;
            $go = $go_hash{$runno};
            if ($go) {
                ($job) = write_rat_report($runno);

                if ($job) {
                    push(@jobs,$job);
                }
            }
        }
    }
    if (cluster_check() && (scalar(@jobs)>0)) {
        my $interval = 2;
        my $verbose = 1;
        my $done_waiting = cluster_wait_for_jobs($interval,$verbose,@jobs);
        if ($done_waiting) {
            print STDOUT  "  ${label_space} label statistics has been calculated for all runnos; moving on to next step.\n";
        }
    }
    my $case = 2;
    my ($dummy,$error_message)=calculate_individual_label_statistics_Output_check($case);
    my $real_time = vbm_write_stats_for_pm($PM_code,$Hf,$start_time,@jobs);
    @jobs=(); # Clear out the job list, since it will remember everything if this module is used iteratively.
    my $write_path_for_Hf = "${current_path}/stats_calc_${label_atlas_nickname}_${space_string}_temp.headfile";
    if ($error_message ne '') {
        error_out("${error_message}",0);
    } else {
        $Hf->write_headfile($write_path_for_Hf);
    }
    print "$PM took ${real_time} seconds to complete.\n";
}

# ------------------
sub calculate_individual_label_statistics_Output_check {
# ------------------
    my ($case) = @_;
    my $message_prefix ='';
    my @file_array=();

    my $existing_files_message = '';
    my $missing_files_message = '';

    if ($case == 1) {
        $message_prefix = "  Complete label statistics have been found for the following runnos and will not be re-calculated:\n";
    } elsif ($case == 2) {
        $message_prefix = "  Unable to properly calculate label statistics for the following runnos:\n";
    }   # For Init_check, we could just add the appropriate cases.

    foreach my $runno (@array_of_runnos) {
        #print "$runno\n\n";
        my $sub_existing_files_message='';
        my $sub_missing_files_message='';

        my $file_old = "${current_path}/${runno}_${label_atlas_nickname}_labels_in_${space_string}_space_stats.txt" ;
        my $file = "${current_path}/${runno}_${label_atlas_nickname}_measured_in_${space_string}_space_stats.txt" ;
        my $file_found=0;
        my $missing_contrasts = 0;
        my $header_string;
        # do a hard check on new_type first
        if (data_double_check($file,$case-1)) {
            # 19 March 2019: 'labels' is not a sufficient descriptor anymore, thanks to CCF3_quagmire, etc.
            # Switching to 'measured' as now is hardcoded by write_individual_stats_exec_v2.m
            # $file_1 => "${current_path}/${runno}_${label_atlas_nickname}_measured_in_${space_string}_space_stats.txt" ;

            # do a soft check on old second.
            if (data_double_check($file_old)) {
                $go_hash{$runno}=1;
                push(@file_array,$file);
                $sub_missing_files_message = $sub_missing_files_message."\t$runno";
            } else {
                $file=$file_old;
                $file_found=1;
                $header_string = `head -1 ${file}`;
                # this is for the old header code which we've removd ain favor of simple table saving
                # This WHOLE code is a WASTE OF TIME becuase we just match the contrast to the string ANYWAY!!!.
                #my @c_array_1 = split('=',$header_string);
                #@completed_contrasts = split(',',$c_array_1[1]);
            }
        } else {
            $file_found=1;
            $header_string = `head -1 ${file}`;
            # This WHOLE code is a WASTE OF TIME becuase we just match the contrast to the string ANYWAY!!!.
            #my @c_array_1 = split("\t",$header_string);
            #foreach (@c_array_1) {
            #    if ($_ =~ /^(.*)_mean/) {
            #        push(@completed_contrasts,$1);
            #    }
            #}
        }

        if ($file_found) {
            foreach my $ch (@channel_array) {
                if (! $missing_contrasts) {
                    if ($header_string !~ /($ch)/) {
                        $missing_contrasts = 1;
                    }
                }
            }
            if ($missing_contrasts) {
                $go_hash{$runno}=1;
                push(@file_array,$file);
                $sub_missing_files_message = $sub_missing_files_message."\t$runno";
            } else {
                $go_hash{$runno}=0;
                $sub_existing_files_message = $sub_existing_files_message."\t$runno";
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
        $error_msg =  "$PM:\n${message_prefix}${missing_files_message}in_dir:$current_path\n";
    }

    my $file_array_ref = \@file_array;
    return($file_array_ref,$error_msg);
}


# ------------------
sub calculate_label_statistics {
# ------------------
    my ($runno,$input_labels,$lookup_table) = @_;

    # 15 March 2019, when this option is turned on, intersection of ROI=0
    #   and the zeros of the first listed contrast (we attempt to force this to DWI,
    #   if present) will be treated as null for all contrasts.  This is mainly
    #   to improved memory used by tracking all the indices representing these voxels.
    my ${mask_with_first_contrast}=1;

    if (! defined $lookup_table) { $lookup_table='';}
    my $exec_args ="${runno} ${input_labels} ${channel_comma_list_2} ${image_dir} ${current_path} ${space_string} ${label_atlas_nickname} ${lookup_table} ${mask_with_first_contrast}";

    my $go_message = "$PM: Calculating individual label statistics for runno: ${runno}\n" ;
    my $stop_message = "$PM: Failed to properly calculate individual label statistics for runno: ${runno} \n" ;

    my $jid = 0;
    my $cmd = "${write_individual_stats_executable_path} ${matlab_path} ${exec_args}";
    if (cluster_check) {
        my @test=(0);
        if (defined $reservation) {
            @test =(0,$reservation);
        }
        my $go =1;
        my $home_path = $current_path;
        my $Id= "${runno}_calculate_individual_label_statistics";
        my $verbose = 1; # Will print log only for work done.
        my $mem_request = '512';# min req for matlab exec.

        my $space="label";
        ($mem_request, $vx_count)=refspace_memory_est($mem_request,$space,$Hf,5);
        # We could probably do this ealier, but oh well.
        my $contrast_count=scalar(split(",",$channel_comma_list_2));
        # estimates explaination 8 bytes in 64 bit data,
        # (5 working space + 1 label file) at 64-bits + (num_contrast_images at 64-bit)
        # Estimate is not 100% sensible, idealistically, it should just be labels+1 or 2 contrast images.
        # Clearly we're a little sloppy in there.
        # The reason we're using 5x working space is to leave room for the data table we hold in mem.
        # We started with just lables, then increated to labels+3, and now we're using + 5. Strangely
        # failures were intermittent, some worked even at the low estimate.
        # It's okay for this to over estimate here as the code is reasonably multi-threaded and quick,
        # and this is not the bottleneck code.
        my $est_bytes=$vx_count * ( (5 + 1)*8 + $contrast_count*8 );
        # convert bytes to MiB(not MB)
        $mem_request=ceil($est_bytes/(2**20));
        $jid = cluster_exec($go, $go_message, $cmd, $home_path, $Id, $verbose, $mem_request, @test);
    } else {
        if ( execute($go, $go_message, $cmd) ) {
            $jid=1;
        }
    }
    if ($go && not $jid) {
        error_out($stop_message);
    }
    return($jid);
}


# ------------------
sub write_rat_report {
# ------------------
    my ($runno) = @_;
    my $input_labels = "${work_dir}/${runno}_${label_atlas_nickname}_labels${out_ext}";
    my $spec_id = $Hf->get_value('U_specid');
    my $project_id = $Hf->get_value('U_code');

    #my $exec_args_ ="${runno} {contrast} ${average_mask} ${input_path} ${contrast_path} ${group_1_name} ${group_2_name} ${group_1_files} ${group_2_files}";# Save for part 3..

    my $exec_args ="${runno} ${input_labels} 'e1,rd,fa' ${image_dir} ${current_path} ${project_id} 'Rat' ${spec_id}";

    my $go_message = "$PM: Writing rat report for runno: ${runno}\n" ;
    my $stop_message = "$PM: Failed to properly write rat report for runno: ${runno} \n" ;

    my @test=(0);
    if (defined $reservation) {
        @test =(0,$reservation);
    }
    my $mem_request = '10000';
    my $jid = 0;
    if (cluster_check) {
        my $go =1;
#       my $cmd = $pairwise_cmd.$rename_cmd;
        my $cmd = "${write_rat_report_executable_path} ${matlab_path} ${exec_args}";

        my $home_path = $current_path;
        my $Id= "${runno}_write_rat_report";
        my $verbose = 1; # Will print log only for work done.
        $jid = cluster_exec($go,$go_message , $cmd ,$home_path,$Id,$verbose,$mem_request,@test);
        if (! $jid) {
            error_out($stop_message);
        } else {
            return($jid);
        }
    }
}



# ------------------
sub  calculate_individual_label_statistics_vbm_Init_check {
# ------------------
    my $init_error_msg='';
    my $message_prefix="$PM initialization check:\n";


    # if ($log_msg ne '') {
    #     log_info("${message_prefix}${log_msg}");
    # }

    if ($init_error_msg ne '') {
        $init_error_msg = $message_prefix.$init_error_msg;
    }

    return($init_error_msg);
}

# ------------------
sub  calculate_individual_label_statistics_Runtime_check {
# ------------------

    $mdt_contrast = $Hf->get_value('mdt_contrast');
    $label_atlas_nickname = $Hf->get_value('label_atlas_nickname');
    $label_atlas_name = $Hf->get_value('label_atlas_name');
    if ($label_atlas_nickname eq 'NO_KEY') {
        $label_atlas_nickname=$label_atlas_name;
    }

    $label_type = $Hf->get_value('label_type',$label_type);
    if ($label_type eq 'NO_KEY') {
        $label_type = 'labels';
    }

    my $msg;
    if (! defined $current_label_space) {
        $msg =  "\$current_label_space not explicitly defined. Checking Headfile...";
        $current_label_space = $Hf->get_value('label_space');
    } else {
        $msg = "current_label_space has been explicitly set to: ${current_label_space}";
    }
    printd(35,$msg);

    $space_string='rigid'; # Default
    if ($current_label_space eq 'pre_rigid') {
        $space_string = 'native';
    } elsif (($current_label_space eq 'pre_affine') || ($current_label_space eq 'post_rigid')) {
        $space_string = 'rigid';
    } elsif ($current_label_space eq 'post_affine') {
        $space_string = 'affine';
    } elsif ($current_label_space eq 'MDT') {
        $space_string = 'mdt';
    } elsif ($current_label_space eq 'atlas') {
        $space_string = 'atlas';
    }

    my $label_refname = $Hf->get_value('label_refname');
    $labels_dir = $Hf->get_value('labels_dir');
    $work_dir=$labels_dir;
    $image_dir=$Hf->get_value('label_images_dir');
    my $stat_path=$labels_dir;

    if ( $current_label_space =~ /MDT/ ) {
        # When MDT space but not MDT images, its desireable to move the stats
        # relative to the labels ...
        #  for now we'll fix it by setting labels dir to a lie,
        #  (where we would have saved them IF we were generating new files)
        #
    }
    # checking "the new way" with the post_affine, i Like how it works out,
    # so whis whole block of intermediary will be commented for now.
=item dead_intermediary_code
    if ( $current_label_space !~ /pre_rigid|MDT/ ){
        # It is not clear this path setting should be here at all!
        # In theory the image and stat dir shouldnt need updating right now.
        # just in case I'm wrong, only the two known good cases jump through this.
        my $intermediary_path = "${labels_dir}/${current_label_space}_${label_refname}_space";
        die "HEllo iNTErMedaiaryPath! This code has been disabled due to lack of testing.".
            "Your work is mostly done, but you'll need to measure your own label stats, ".
            "Avizo does a competent job (don't forget to load the lookup table too). \n".
            "(or pick on the programmer to blindly enable this to see what happens:D ).\n".
            "labels_dir=$labels_dir\n".
            "stat_path=$stat_path\n".
            "image_dir=$image_dir\n".
            "inter=$intermediary_path\n".
            "  would expand inter with stats, images, and $label_atlas_nickname";

        my $intermediary_path = "${labels_dir}/${current_label_space}_${label_refname}_space";
        $image_dir = "${intermediary_path}/images/";
        $work_dir="${intermediary_path}/${label_atlas_nickname}/";
        $stat_path = "${work_dir}/stats/";
    }
=cut

    $Hf->set_value('stat_path',${stat_path});
    if (! -e $stat_path) {
        mkdir ($stat_path,$permissions);
    }

    #$current_path = "${stat_path}/individual_label_statistics/";
    $current_path = "${stat_path}";
    if (! -e $current_path) {
        mkdir ($current_path,$permissions);
    }

    my $runlist = $Hf->get_value('all_groups_comma_list');
    if ($runlist eq 'NO_KEY') {
        $runlist = $Hf->get_value('complete_comma_list');
    }
    @array_of_runnos = split(',',$runlist);


    if ( ! scalar(@initial_channel_array) ) {
        $ch_runlist = $Hf->get_value('channel_comma_list');
        @initial_channel_array = split(',',$ch_runlist);
    }
    # Despite what this loop looks like, @channel_array should always be empty when this runs.
    @channel_array=();
    foreach my $contrast (@initial_channel_array) {
        if ($contrast !~ /^(ajax|jac|nii4D)$/i) {
            if ($contrast =~ /^(dwi)$/i) {
                # patch messy upper/lower case dwi by getting whichever we've prescribed
                $contrast=$1;
            }
            push(@channel_array,$contrast);
        }
    }
    @channel_array=uniq(@channel_array);
    $channel_comma_list_2 = join(',',@channel_array);

    my $case = 1;
    my ($dummy,$skip_message)=calculate_individual_label_statistics_Output_check($case);

    if ($skip_message ne '') {
        print "${skip_message}";
    }
}


1;
