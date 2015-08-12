#!/usr/local/pipeline-link/perl

# vbm_analysis_vbm.pm 

#  2015/08/06  Added SurfStat support

my $PM = "vbm_analysis_vbm.pm";
my $VERSION = "2015/08/06";
my $NAME = "Run vbm analysis with software of choice.";

use strict;
use warnings;
no warnings qw(bareword);

use vars qw($Hf $BADEXIT $GOODEXIT $test_mode $permissions);
require Headfile;
require pipeline_utilities;
#require convert_to_nifti_util;

my $use_Hf;
my ($current_path, $work_dir,$runlist,$ch_runlist,$in_folder,$out_folder,$flip_x,$flip_z,$do_mask);
my ($smoothing_comma_list,$software_list,$channel_comma_list,$template_path,$template_name);
my (@array_of_runnos,@channel_array,@smoothing_params);

my (%go_hash,%go_mask,%mask_hash);

my $skip=0;



# ------------------
sub vbm_analysis_vbm {
# ------------------
    print "$PM: use_Hf = ${use_Hf}\n\n";
    my @args = @_;
    vbm_analysis_vbm_Runtime_check(@args);


 #    foreach my $smoothing (@smoothing_params) {

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



}

# # ------------------
# sub vbm_analysis_vbm_Init_check {
# # ------------------

#     return('');
# }

# ------------------
sub vbm_analysis_vbm_Runtime_check {
# ------------------
    if (defined $Hf) { 
	$use_Hf = 1;
	print "Fuck one\n";
    } elsif (! defined $Hf) {
	$use_Hf = 0;
	print "Fuck two\n";
    } else {
	print "\$Hf is a confusing hooch.  This shouldn't be happening.\n";
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

	$channel_comma_list = $Hf->get_value('channel_comma_list');
	$smoothing_comma_list = $Hf->get_value('smoothing_comma_list');


	if ($smoothing_comma_list eq 'NO_KEY') { ## Should this go in init_check?
	    $smoothing_comma_list = "3vox"; 
	    $Hf->set_value('smoothing_comma_list',$smoothing_comma_list);
	}

	@smoothing_params = split(',',$smoothing_comma_list);

	$template_name = $Hf->get_value('template_name');

    }

    foreach my $smoothing (@smoothing_params) {
	my $local_folder_name  = $directory_prefix.'/'.$template_name.'_'.$smoothing.'_smoothing';
	my ($local_inputs,$local_work,$local_results,$local_Hf)=make_process_dirs($local_folder_name);




    }
# # # Set up work
#     $in_folder = $Hf->get_value('pristine_input_dir');
#     $work_dir = $Hf->get_value('dir_work');
#     $current_path = $Hf->get_value('inputs_dir');


# #    opendir(DIR,$in_folder) or die ("$PM: could not open project inputs folder!";
# #    my @nii_files = grep(/\.nii$/,readdir(DIR));

#     if ($current_path eq 'NO_KEY') {
# 	$current_path = "${work_dir}/base_images";
#  	$Hf->set_value('input_dir',$current_path); 	
#     }
#     if (! -e $current_path) {
# 	mkdir ($current_path,$permissions);
#     }

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

