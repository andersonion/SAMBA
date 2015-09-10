#!/usr/local/pipeline-link/perl

# vbm_analysis_vbm.pm 

#  2015/08/06  Added SurfStat support

my $PM = "vbm_analysis_vbm.pm";
my $VERSION = "2015/08/06";
my $NAME = "Run vbm analysis with software of choice.";

use strict;
use warnings;
no warnings qw(bareword);

use vars qw($Hf $BADEXIT $GOODEXIT $test_mode $valid_formats_string $permissions);
require Headfile;
require pipeline_utilities;
#require convert_to_nifti_util;

my $use_Hf;
my ($current_path, $work_dir,$runlist,$ch_runlist,$in_folder,$out_folder,$flip_x,$flip_z,$do_mask);
my ($smoothing_comma_list,$software_list,$channel_comma_list,$template_path,$template_name,$average_mask);
my (@array_of_runnos,@channel_array,@smoothing_params,@software_array);
my ($predictor_id);
my (@group_1_runnos,@group_2_runnos);
my (%go_hash,%go_mask,%smooth_pool_hash,%results_dir_hash,%work_dir_hash);

my $skip=0;

my ($group_1_name,$group_2_name,$group_1_files,$group_2_files);



if (! defined $valid_formats_string) {$valid_formats_string = 'hdr|img|nii';}

if (! defined $dims) {$dims = 3;}

# ------------------
sub vbm_analysis_vbm {
# ------------------
 
    my @args = @_;
    my $start_time = time;
    vbm_analysis_vbm_Runtime_check(@args);


    foreach my $smoothing (@smoothing_params) {
	print "Running smoothing for ${smoothing}\n";
	my $smooth_work = $work_dir_hash{$smoothing};
	my $smooth_results = $results_dir_hash{$smoothing};
	my $smooth_inputs = $smooth_pool_hash{$smoothing};

	foreach my $software (@software_array) {
	    print "Running vbm software: ${software}\n";
	    my $software_results_path = "${smooth_results}/${software}/";
	    if (! -e $software_results_path) {
		mkdir ($software_results_path,$permissions);
	    }

	    foreach my $contrast (@channel_array) {
		print "Running vbm with contrast: ${contrast}\n";
		my (@group_1_files,@group_2_files); 
		foreach my $runno (@group_1_runnos) {
		    my $file = get_nii_from_inputs($smooth_inputs,$runno,$contrast);
		    my ($name,$in_path,$ext) = fileparts($file);
		    my $file_no_path = $name.$ext;
		    push(@group_1_files,$file_no_path);
		}
		
		foreach my $runno (@group_2_runnos) {
		    my $file = get_nii_from_inputs($smooth_inputs,$runno,$contrast);
		    my ($name,$in_path,$ext) = fileparts($file);
		    my $file_no_path = $name.$ext;
		    push(@group_2_files,$file_no_path);
		}
		
		$group_1_files = join(',',@group_1_files);
		$group_2_files = join(',',@group_2_files);
		
		if ($software eq 'surfstat') {
		    surfstat_analysis_vbm($contrast,$smooth_inputs,$software_results_path);
		} else {
		    print "I'm sorry, but VBM software \"$software\" is currently not supported :( \n";
		}
	    }
	}
    }


    my $real_time = write_stats_for_pm($PM,$Hf,$start_time);#,@jobs);
    print "$PM took ${real_time} seconds to complete.\n";


# 	foreach my $ch (@channel_array) {
# 	    my $go = $go_hash{$runno}{$ch};
# 	    if ($go) {
# 		my $current_file=get_nii_from_inputs($in_folder,$runno,$ch);
# 		push(@nii_files,$current_file);
# 	    }
# 	}
#     }
#     if ($nii_files[0] ne '') {
# 	my $message="\n$PM:\nThe following files will be prepared by Matlab for the VBM pipeline:\n".
# 	    join("\n",@nii_files)."\n\n";
# 	print "$message";
#     }


#     foreach my $file (@nii_files) {

# 	my ($name,$in_path,$ext) = fileparts($file);	

# 	my $nifti_args = "\'${in_path}\', \'$name\', \'nii\', \'${current_path}/$name$ext\', 0, 0, ".
#       " 0, 0, 0,0,0, ${flip_x}, ${flip_z},0,0";
# 	if (! $skip) {
# 	my $nifti_command = make_matlab_command('civm_to_nii',$nifti_args,"${name}_",$Hf,0); # 'center_nii'
# 	execute(1, "Recentering nifti images from tensor inputs", $nifti_command);	
# 	}
# 	#push(@nii_cmds,$nifti_command);           
#     }
#    # execute_indep_forks(1,"Recentering nifti images from tensor inputs", @nii_cmds);

#     my $case = 2;
#     my ($dummy,$error_message)=vbm_analysis_Output_check($case);

#     if ($error_message ne '') {
# 	error_out("${error_message}",0);
#     } else {
#     # Clean up matlab junk
# 	`rm ${work_dir}/*.m`;
# 	`rm ${work_dir}/*matlab*`;
#     }

}


# # ------------------
# sub vbm_analysis_Output_check {
# # ------------------

#     my ($case) = @_;
#     my $message_prefix ='';
#     my ($file_1);
#     my @file_array=();

#     my $existing_files_message = '';
#     my $missing_files_message = '';

    
#     if ($case == 1) {
# 	$message_prefix = "  Prepared niftis have been found for the following runnos and will not be re-prepared:\n";
#     } elsif ($case == 2) {
# 	 $message_prefix = "  Unable to properly prepare niftis for the following runnos and channels:\n";
#     }   # For Init_check, we could just add the appropriate cases.
    
#     foreach my $runno (@array_of_runnos) {
# 	my $sub_existing_files_message='';
# 	my $sub_missing_files_message='';
	
# 	foreach my $ch (@channel_array) {
# 	    $file_1 = get_nii_from_inputs($current_path,$runno,$ch);
# 	    if ((data_double_check($file_1) ) || ((! $do_mask) &&  ($file_1 =~ /.*masked\.nii / ))) {
# 		$go_hash{$runno}{$ch}=1;
# 		push(@file_array,$file_1);
# 		$sub_missing_files_message = $sub_missing_files_message."\t$ch";
# 	    } else {
# 		$go_hash{$runno}{$ch}=0;
# 		$sub_existing_files_message = $sub_existing_files_message."\t$ch";
# 	    }
# 	}
# 	if (($sub_existing_files_message ne '') && ($case == 1)) {
# 	    $existing_files_message = $existing_files_message.$runno."\t".$sub_existing_files_message."\n";
# 	} elsif (($sub_missing_files_message ne '') && ($case == 2)) {
# 	    $missing_files_message =$missing_files_message. $runno."\t".$sub_missing_files_message."\n";
# 	}
#     }
     
#     my $error_msg='';
    
#     if (($existing_files_message ne '') && ($case == 1)) {
# 	$error_msg =  "$PM:\n${message_prefix}${existing_files_message}\n";
#     } elsif (($missing_files_message ne '') && ($case == 2)) {
# 	$error_msg =  "$PM:\n${message_prefix}${missing_files_message}\n";
#     }
     
#     my $file_array_ref = \@file_array;
#     return($file_array_ref,$error_msg);
# }


# ------------------
sub surfstat_analysis_vbm {
# ------------------
    my ($contrast,$input_path,$results_master_path) = @_;
    my $contrast_path = "${results_master_path}/${contrast}/";
    if (! -e $contrast_path) {
	mkdir ($contrast_path,$permissions);
    }

    my $surfstat_args ="\'$contrast\', \'${average_mask}'\, \'${input_path}\', \'${contrast_path}\', \'${group_1_name}\', \'${group_2_name}\',\'${group_1_files}\',\'${group_2_files}\'";

    my $surfstat_command = make_matlab_command('surfstat_for_vbm_pipeline',$surfstat_args,"surfstat_with_${contrast}_for_${predictor_id}_",$Hf,0); # 'center_nii'
    print "surfstat command = ${surfstat_command}\n";
    my $state = execute(1, "Running SurfStat with contrast: \"${contrast}\" for predictor \"${predictor_id}\"", $surfstat_command);
    print "Current state = $state\n";
    return();
}
# ------------------
sub vbm_analysis_vbm_Init_check {
# ------------------

    return('');
}

# ------------------
sub vbm_analysis_vbm_Runtime_check {
# ------------------
    if (defined $Hf) { 
	$use_Hf = 1;
    } elsif (! defined $Hf) {
	$use_Hf = 0;
    } else {
	print "\$Hf is confusing.  This shouldn't be happening.\n";
    }



    my $directory_prefix='';

    if ($use_Hf) {
	$template_path = $Hf->get_value('template_work_dir');
	$current_path = $Hf->get_value('vbm_analysis_path');
	if ($current_path eq 'NO_KEY') {
	    $current_path = "${template_path}/vbm_analysis";
	    $Hf->set_value('vbm_analysis_path',$current_path);
	}
	if (! -e $current_path) {
	    mkdir ($current_path,$permissions);
	}

	$directory_prefix = $current_path;
	if ($directory_prefix =~ s/\/glusterspace//) { }

	$software_list = $Hf->get_value('vbm_analysis_software');
	if ($software_list eq 'NO_KEY') { ## Should this go in init_check?
	    $software_list = "surfstat"; 
	    $Hf->set_value('vbm_analysis_software',$software_list);
	}
	@software_array = split(',',$software_list);

	$channel_comma_list = $Hf->get_value('channel_comma_list');
	@channel_array = split(',',$channel_comma_list);

	$smoothing_comma_list = $Hf->get_value('smoothing_comma_list');


	if ($smoothing_comma_list eq 'NO_KEY') { ## Should this go in init_check?
	    $smoothing_comma_list = "3vox"; 
	    $Hf->set_value('smoothing_comma_list',$smoothing_comma_list);
	}

	@smoothing_params = split(',',$smoothing_comma_list);

	$template_name = $Hf->get_value('template_name');

    }

    my $template_images_path = $Hf->get_value('mdt_images_path');
    my $registered_images_path = $Hf->get_value('reg_images_path');

    my $runlist = $Hf->get_value('complete_comma_list');
    my @array_of_runnos = split(',',$runlist);
    my $runno_OR_list = join("|",@array_of_runnos);

    my @all_input_dirs = ($template_images_path,$registered_images_path);
    my @files_to_link; 

    foreach my $directory (@all_input_dirs) {
	if (-d $directory) {
	    opendir(DIR, $directory);
	    my @files_in_dir = grep(/(${runno_OR_list}).*(\.${valid_formats_string})+(\.gz)*$/ ,readdir(DIR));# @input_files;
	    foreach my $current_file (@files_in_dir) {
		my $full_file = $directory.'/'.$current_file;
		push (@files_to_link,$full_file);		
	    }
	}
    }

    my @already_processed;
    foreach my $smoothing (@smoothing_params) {
	my $input_smoothing = $smoothing;
	my $mm_not_voxels = 0;
	my $units = 'vox';
	
	# Strip off units and white space (if any).
	if ($smoothing =~ s/[\s]*(vox|voxel|voxels|mm)$//) {
	    $units = $1;
	    if ($units eq 'mm') {	
		${mm_not_voxels} = 1;
	    } else {
		$units = 'vox';
	    }
	}
	my $smoothing_string = $smoothing;
	if ($smoothing_string =~ s/(\.){1}/p/) {}

	my $smoothing_with_units_string = $smoothing_string.$units;
	my $smoothing_with_units = $smoothing.$units;
	my $already_smoothed = join('|',@already_processed);

	if ($smoothing_with_units =~ /^(${already_smoothed})$/) { 
	    print "$PM: Work for specified smoothing \"${input_smoothing}\" has already been completed as \"$1\".\n";
	} else {
	    print "$PM: Specified smoothing \"${input_smoothing}\" being processed as \"${smoothing_with_units}\".\n";
	    my $folder_suffix = "${smoothing_with_units_string}_smoothing"; 
	    my $file_suffix = "s${smoothing_with_units_string}";
	    
	    my $local_folder_name  = $directory_prefix.'/'.$template_name.'_'.$folder_suffix;
	    my ($local_inputs,$local_work,$local_results,$local_Hf)=make_process_dirs($local_folder_name);
	    foreach my $file (@files_to_link) {
		my ($file_name,$file_path,$file_ext) = fileparts($file);
		my $linked_file = $local_inputs."/".$file_name.$file_ext;
		#`ln -f $file ${linked_file}`;  # Using -f will "force" the link to refresh with the most recent data.
		link($file,$linked_file);
	    }
	    my $pool_path = $local_work.'/smoothed_image_pool/';
	    if (! -e $pool_path) {
		mkdir ($pool_path,$permissions);
	    }
	    $results_dir_hash{$smoothing_with_units} = $local_results;
	    $work_dir_hash{$smoothing_with_units} = $local_work;
	    $smooth_pool_hash{$smoothing_with_units} = $pool_path;
	    smooth_images_vbm($smoothing_with_units,$pool_path,$file_suffix,$local_inputs);
	    push (@already_processed,$smoothing_with_units);
	}
    }
    @smoothing_params = @already_processed;

    $predictor_id = $Hf->get_value('predictor_id');
    if ($predictor_id eq 'NO_KEY') {
	$group_1_name = 'control';
	$group_2_name = 'treated';
	
    } else {	
	if ($predictor_id =~ /([^_]+)_(|vs_|VS_|Vs_){1}([^_]+)/) {
	    $group_1_name = $1;
	    if (($3 ne '') || (defined $3)) {
		$group_2_name = $3;
	    } else {
		$group_2_name = 'others';
	    }
	}
    }

    my $group_1_runnos = $Hf->get_value('control_comma_list');
    @group_1_runnos = split(',',$group_1_runnos);
    my $group_2_runnos = $Hf->get_value('compare_comma_list');
    @group_2_runnos = split(',',$group_2_runnos);

    $average_mask = $Hf->get_value('MDT_eroded_mask');


#     $runlist = $Hf->get_value('complete_comma_list');
#     @array_of_runnos = split(',',$runlist);
 
#     $ch_runlist = $Hf->get_value('channel_comma_list');
#     @channel_array = split(',',$ch_runlist);

#     my $case = 1;
#     my ($dummy,$skip_message)=vbm_analysis_Output_check($case);

#     if ($skip_message ne '') {
# 	print "${skip_message}";
#     }


}


1;

