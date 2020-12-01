#!/usr/bin/false

# mask_for_mdt_vbm.pm


# Used matlab call for skull stripping that was implemented in mask_images_vbm.pm
# created 2015/02/06 BJ Anderson CIVM

my $PM = "mask_for_mdt_vbm.pm";
my $VERSION = "2014/12/23";
my $NAME = "Creates an eroded mask from MDT image for use with VBM analysis. If input images for MDT were already skull-stripped, then the raw mask will be created from the non-zero elemnts of the MDT image.";

use strict;
use warnings FATAL => qw(uninitialized);

#use vars used to be here
require Headfile;
require pipeline_utilities;
#require convert_to_nifti_util;


my ($current_path,$template_contrast,$erode_radius);
my ($do_mask,$pre_masked,$mdt_skull_strip,$default_mask_threshold);
my $do_vba_mask;
my ($incumbent_raw_mask, $incumbent_eroded_mask);
my $go=1;

my $out_ext=".nii.gz";
$out_ext=".nhdr";
# ------------------
sub mask_for_mdt_vbm {
# ------------------

    my $start_time = time;
    my $nifti_command;
    my $nifti_args;

    $erode_radius=3;

    mask_for_mdt_vbm_Runtime_check();


## Make mask from MDT for use with VBM module, using the template contrast (usually dwi).

    my $job=0;
    my $eroded_mask_path;
    if ($go) {
        my $mask_source="${current_path}/MDT_${template_contrast}${out_ext}";    #.gz added 22 October 2015
        my $raw_mask_path = "${current_path}/MDT_mask${out_ext}";

        if ($mdt_skull_strip) {
            my $mask_threshold = $default_mask_threshold;
            my $num_morphs = 5;
            my $morph_radius = 2;
            my $dim_divisor = 2;
            my $status_display_level=0;

            if (data_double_check($raw_mask_path)) {
                $nifti_args ="\'$mask_source\', $dim_divisor, $mask_threshold, \'$raw_mask_path\',$num_morphs , $morph_radius,$status_display_level";
                $nifti_command = make_matlab_command('strip_mask',$nifti_args,"MDT_${template_contrast}_",$Hf,0); # 'center_nii'
                execute(1, "Creating mask for MDT using ${template_contrast} channel", $nifti_command);
                $Hf->set_value('MDT_raw_mask',$raw_mask_path);
            }
        }
        ($job,$eroded_mask_path) = extract_and_erode_mask($mask_source,$raw_mask_path);
    }

    if (cluster_check() && ($job)) {
        my $interval = 1;
        my $verbose = 1;
        my $done_waiting = cluster_wait_for_jobs($interval,$verbose,$job);

        if ($done_waiting) {
            print STDOUT  "  MDT mask has been created; moving on to next step.\n";
        }
    }
    my $case = 2;
    my ($dummy,$error_message)=mask_for_mdt_Output_check($case);

    my $real_time;
    if ($job) {
        $real_time = vbm_write_stats_for_pm($PM,$Hf,$start_time,$job);
    } else {
        $real_time = vbm_write_stats_for_pm($PM,$Hf,$start_time);
    }

    if ($error_message ne '') {
        error_out("${error_message}",0);
    } else {
        if (($go) && ($mdt_skull_strip)) {
            # Clean up matlab junk
            my @matlab_stubs=`ls ${current_path}/*.m 2> /dev/null`;
            my @matlab_files=`ls ${current_path}/*matlab* 2> /dev/null`;
            chomp(@matlab_stubs);chomp(@matlab_files);
            if(scalar(@matlab_stubs) || scalar(@matlab_files) ) {
                my $rm_cmd=sprintf("rm -v %s",sprintf("%s ",@matlab_stubs,@matlab_files));
                #cluck("Testing:$PM\n\t$rm_cmd");sleep_with_countdown(15);
                run_and_watch("$rm_cmd");
            }
        }
    }
    print "$PM took ${real_time} seconds to complete.\n";
}


# ------------------
sub mask_for_mdt_Output_check {
# ------------------

    my ($case) = @_;
    my $message_prefix ='';
    my @file_array=();
    my ($file_1);
    my $mask_suf="_er${erode_radius}${out_ext}";
    # Thought about making the erroded mask optional based on do_vba
    # but that significantly complicates things
    #if (! $do_vba_mask ) {
    # $mask_suf=".nii.gz";
    #}
    if ($incumbent_eroded_mask ne 'NO_KEY'){
        $file_1 = $incumbent_eroded_mask;
    } else {
        # Need this file to be uncompressed for later use; removed .gz 26 Oct 2015.
        $file_1 = "${current_path}/MDT_mask$mask_suf";
    }
    # hard sloppy update old path to new
    my $former_path= "${current_path}/MDT_mask_e${erode_radius}${out_ext}";
    if ( -e $former_path ) {
        qx/mv $former_path $file_1/;
    }

    my $existing_files_message = '';
    my $missing_files_message = '';

    if ($case == 1) {
        $message_prefix = " Eroded MDT mask has already been found and will not be regenerated.";
    } elsif ($case == 2) {
        $message_prefix = "  Unable to properly generate eroded MDT mask.";
    }   # For Init_check, we could just add the appropriate cases.
    undef $go;
    if (data_double_check($file_1,$case-1)) {
        # Expected file not found, Lets try an accidentally gzipped file.
        # A "rare" edge case where this is likely is: blanket gzipping all nifti's
        if ($file_1 !~ /\.gz$/) {
            if (! data_double_check($file_1.".gz")) {
                # Sloppy cleaning up behavior where we decompress the mask here,
                # if we dont want it compressed we should say so when we create it.
                # we dont check hard for output in this case, mostly because this case shouldn't happen.
                # we'll rely on failing to gunzip to crash the pipe.

                #Is -f safe to use?
                run_and_watch("gunzip -f ${file_1}.gz");
                $go = 0;
            }
        }
    } else {
        $go = 0;
    }

    if(defined $go && ! $go ) {
        $Hf->set_value('MDT_eroded_mask',$file_1);
        $existing_files_message = $existing_files_message."\n";
    } else {
        $go = 1;
        push(@file_array,$file_1);
        $missing_files_message = $missing_files_message."\n";
    }

    my $error_msg='';

    if (($existing_files_message ne '') && ($case == 1)) {
        $error_msg =  "$PM:\n${message_prefix}${existing_files_message}\n";
    } elsif (($missing_files_message ne '') && ($case == 2)) {
        $error_msg =  "$PM:\n${message_prefix}${missing_files_message}\n";
    }

    my $file_array_ref =  \@file_array;
    return($file_array_ref,$error_msg);
}


# ------------------
sub extract_and_erode_mask {
    # ------------------

    my ($mask_source,$raw_mask) = @_;
    my $out_path =   "${current_path}/MDT_mask_er${erode_radius}${out_ext}";
    my ($mask_command_1,$mask_command_2);

    if (data_double_check($raw_mask)) {
        $mask_command_1 = "ImageMath 3 ${raw_mask} ThresholdAtMean ${mask_source} 0.0001;\n"; # Alex's approach(?)
        # $mask_command_1 = "ThresholdImage 3 ${mask_source} ${raw_mask} 0.00001 1000000000;\n"; #BJs simple mask approach
        $Hf->set_value('MDT_raw_mask',$raw_mask);
    } else {
        $mask_command_1 = '';
    }
    #my $CMD_SEP=" && \\";

    $mask_command_2 = "ImageMath 3 ${out_path} ME ${raw_mask} ${erode_radius};\n";
    if ($do_vba_mask ){
        #$mask_command_2="";
    }

    my $cmd = $mask_command_1.$mask_command_2;
    my @cmds = ($mask_command_1,$mask_command_2);

    my $go_message = "$PM: Extractinging mask from MDT ${template_contrast} image." ;
    my $stop_message = "$PM: unable to extract mask from MDT ${template_contrast} image:\n${mask_command_1}\n${mask_command_2}\n" ;

    my $jid = 0;
    if (cluster_check) {
        my @test=(0);
        if (defined $reservation) {
            @test =(0,$reservation);
        }
        my $home_path = $current_path;
        my $Id= "extract_mask_from_MDT_${template_contrast}";
        my $verbose = 1; # Will print log only for work done.
        my $mem_request = 30000;  # Added 23 November 2016,  Will need to make this smarter later.
        $jid = cluster_exec($go,$go_message, $cmd ,$home_path,$Id,$verbose,$mem_request,@test);
        if (not $jid) {
            #error_out($stop_message);
        }
    } else {
        if ( execute($go, $go_message, @cmds) ) {
			$jid=1;
            #error_out($stop_message);
        }
    }

    if ($go && (not $jid)) {
        #error_out("$PM: could not start for MDT mask: ${out_path}");
        error_out($stop_message);
    }
    print "** $PM expected output: ${out_path}\n";

    return($jid,$out_path);
}


# ------------------
sub mask_for_mdt_vbm_Init_check {
# ------------------

    return('');
}


# ------------------
sub mask_for_mdt_vbm_Runtime_check {
# ------------------

# # Set up work
    $do_mask = $Hf->get_value('do_mask');
    $do_vba_mask = $Hf->get_value('do_vba');
    $pre_masked = $Hf->get_value('pre_masked');
    $incumbent_raw_mask = $Hf->get_value('MDT_raw_mask');
    $incumbent_eroded_mask = $Hf->get_value('MDT_eroded_mask');



    if ((! $pre_masked) && (! $do_mask)) {
        # If the input data was not masked, and the pipeline didn't mask it, then MDT needs to be skull stripped.
        $mdt_skull_strip = 1;
    } else {
        # should = 0, =1 is for testing purposes
        # OR do we want to apply the skull-stripping algorithm regardless?
        $mdt_skull_strip = 0;
    }
    $current_path = $Hf->get_value('median_images_path');

    $template_contrast = $Hf->get_value('skull_strip_contrast');

    if (($template_contrast eq 'NO_KEY') || ($template_contrast eq 'UNDEFINED_VALUE') || ($template_contrast eq '')) {
        my $channel_comma_list=$Hf->get_value('channel_comma_list');

        if (${channel_comma_list} =~ /[,]?(dwi)[,]?/i) {
            $template_contrast=$1;

        } else {
            my @channels = split(',',$channel_comma_list);
            $template_contrast=$channels[0];

        }


    }

    $default_mask_threshold=5;#$Hf->get_value('threshold_code');
    #                         # -1 use imagej (like evan and his dti pipe)
    #                         # 0-100 use threshold_zero 0-100,
    #                         # 100-inf is set threshold.

    my $case = 1;
    my ($dummy,$skip_message)=mask_for_mdt_Output_check($case);

    if ($skip_message ne '') {
        print "${skip_message}";
    }


}


1;
