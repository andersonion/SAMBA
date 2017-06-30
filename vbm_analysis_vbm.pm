#!/usr/local/pipeline-link/perl

# vbm_analysis_vbm.pm 

#  2015/08/06  Added SurfStat support
#  2015/12/23  Added basic SPM support
#  2017/06/20  Added fsl non-parametric testing support


my $PM = "vbm_analysis_vbm.pm";
my $VERSION = "2017/06/20";
my $NAME = "Run vbm analysis with software of choice.";

use strict;
use warnings;
use Scalar::Util qw(looks_like_number);
no warnings qw(bareword);

use Env qw(PIPELINE_PATH);
use vars qw($Hf $BADEXIT $GOODEXIT $valid_formats_string $permissions $reservation $schedule_backup_jobs);
$schedule_backup_jobs = 1; # Will probably want to make this universal eventually...
require Headfile;
require pipeline_utilities;
#require convert_to_nifti_util;

my $use_Hf;
my ($current_path, $work_dir,$runlist,$ch_runlist,$in_folder,$out_folder,$flip_x,$flip_z,$do_mask);
my ($smoothing_comma_list,$software_list,$channel_comma_list,$template_path,$template_name,$average_mask);
my $min_cluster_size='';
my (@array_of_runnos,@channel_array,@smoothing_params,@software_array);
my ($predictor_id);
my (@group_1_runnos,@group_2_runnos);
my (%go_hash,%go_mask,%smooth_pool_hash,%results_dir_hash,%work_dir_hash);
my $log_msg='';
my $supported_vbm_software = '(surfstat|spm|ANTsR|fsl|nonparametric)';
my $skip=0;
my ($job);
my @jobs=();
my ($group_1_name,$group_2_name,$group_1_files,$group_2_files);
my (@fdr_mask_array, @thresh_masks ,@ROI_masks,@mask_names,@ROIs_needed);
my ($fdr_masks,$thresh_masks,$ROI_masks,$mask_folder);
my $use_template_images;

my ($nonparametric_permutations,$number_of_nonparametric_seeds,$number_of_test_contrasts,$nii4D,$con_file,$mat_file,$fsl_cluster_size,$tfce_extent,$variance_smoothing_kernal_in_mm,$randomise_options,$default_nonparametric_job_size,$local_work_dir,$local_sub_name,$label_atlas_name,$mdt_labels); # Nonparametric testing variables.
my ($cmbt_analysis,$tfce_analysis);
my $randomise_cleanup_script="${PIPELINE_PATH}/support/fsl_randomise_parallel_cleanup_bash_script.txt";
if (! defined $valid_formats_string) {$valid_formats_string = 'hdr|img|nii';}

if (! defined $dims) {$dims = 3;}


my $matlab_path = '/cm/shared/apps/MATLAB/R2015b/'; #Need to make this more general, i.e. look somewhere else for the proper and/or current version.

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
	    my $software_results_path;
	    my $software_work_path;
	    print "Running vba software: ${software}\n";
	    if ($software eq 'spm') {
		$software_work_path = "${smooth_work}/${software}/";
		if (! -e $software_work_path) {
		    mkdir ($software_work_path,$permissions);
		}
	    } else {
		$software_results_path = "${smooth_results}/${software}/";
		if (! -e $software_results_path) {
		    mkdir ($software_results_path,$permissions);
		}
	    }
	    foreach my $contrast (@channel_array) {
		print "Running vbm with contrast: ${contrast}\n";
		my (@group_1_files,@group_2_files); 
		foreach my $runno (@group_1_runnos) {
		    my $file = get_nii_from_inputs($smooth_inputs,$runno,$contrast);
		    my ($in_path,$name,$ext) = fileparts($file,2);
		    my $file_no_path = $name.$ext;
		    push(@group_1_files,$file_no_path);
		}
		
		foreach my $runno (@group_2_runnos) {
		    my $file = get_nii_from_inputs($smooth_inputs,$runno,$contrast);
		    my ($in_path,$name,$ext) = fileparts($file,2);
		    my $file_no_path = $name.$ext;
		    push(@group_2_files,$file_no_path);
		}
		
		$group_1_files = join(',',@group_1_files);
		$group_2_files = join(',',@group_2_files);
		
		if ($software eq 'surfstat') {
		    surfstat_analysis_vbm($contrast,$smooth_inputs,$software_results_path);
		   # `gzip ${software_results_path}/${contrast}/*.nii`; # Hopefully will be unnecessary after 20 Dec 2016 due to updated SurfStat function.
		} elsif ($software eq 'spm') {
		    spm_analysis_vbm($contrast,$smooth_inputs,$software_work_path);
		} elsif ($software eq 'antsr') {
		    antsr_analysis_vbm($contrast,$smooth_inputs,$software_results_path);
		} elsif ($software eq 'fsl') {
		    fsl_nonparametric_analysis_vbm($contrast,$smooth_inputs,$software_results_path);
		} else {
		    print "I'm sorry, but VBM software \"$software\" is currently not supported :( \n";
		}
	    }
	}
    }


    my $real_time = write_stats_for_pm($PM,$Hf,$start_time);#,@jobs);
    print "$PM took ${real_time} seconds to complete.\n";


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
sub antsr_analysis_vbm {
# ------------------
    my ($contrast,$input_path,$results_master_path) = @_;
    my $contrast_path = "${results_master_path}/${contrast}/";
    if (! -e $contrast_path) {
	mkdir ($contrast_path,$permissions);
    }

    my $antsr_args ="\'$contrast\', \'${average_mask}'\, \'${input_path}\', \'${input_path}\', \'${contrast_path}\', \'${group_1_name}\', \'${group_2_name}\',\'${group_1_files}\',\'${group_2_files}\',\'${min_cluster_size}\'";

    my $Id = "ANTsR_VBA_for_${contrast}";
    my $in_source = "/home/rja20/cluster_code/workstation_code/analysis/vbm_pipe/ANTsR_vba_fx.R";
    my $function = "ANTsR_vba";
    my ($stub_path,$R_function,$R_args,$source) = make_R_stub($function,$antsr_args,$Id,$contrast_path,$in_source);
    my $copy_of_function_command='';

    open(my $fh, '<:encoding(UTF-8)', $source)
	or die "Could not open file '$source' $!";
		
    while (my $row = <$fh>) {
#	chomp $row;
	#print "$row\n";
	$copy_of_function_command = $copy_of_function_command."\## ".$row;
    }
    close($fh);

    # if (open SESAME, ">$source") {
    #   foreach my $line (@msg) {
    #     print SESAME $line;
    #   }
    #   close SESAME;
    #   print STDERR "  Wrote or re-wrote $filepath.\n";
    # }
    # else {
    #   print STDERR  "ERROR: Cannot open file $filepath, can\'t writeTextFile\n";
    #   return 0;
    # }

    my @test = (0);
    my $go_message = "I guess we're testing out ANTsR vbm analysis here...\n";
    my $mem_request = 120000;
    my $antsr_command = "Rscript ${stub_path} --save\n"; 
    print "ANTsR command = ${antsr_command}\n";

    if (defined $reservation) {
	@test =(0,$reservation);
    }
    
    my $jid = 0;
    if (cluster_check) {    
     	my $cmd = $antsr_command.$copy_of_function_command;
	my $go = 1;
     	my $home_path = $contrast_path;
    	my $batch_folder = $home_path.'/sbatch/';
#    	my $Id= "${moving_runno}_to_${fixed_runno}_create_pairwise_warp";
    	my $verbose = 2; # Will print log only for work done.
    	$jid = cluster_exec($go, $go_message, $cmd ,$home_path,$Id,$verbose,$mem_request,@test);     
    	if (! $jid) {
    	    error_out();
    	}
    } # else {
    # 	my @cmds = ($pairwise_cmd,  "ln -s ${out_warp} ${new_warp}", "ln -s ${out_inverse} ${new_inverse}","rm ${out_affine} ");
    # 	if (! execute($go, $go_message, @cmds) ) {
    # 	    error_out($stop_message);
    # 	}
    # }

    # if (((!-e $new_warp) | (!-e $new_inverse)) && ($jid == 0)) {
    # 	error_out($stop_message);
    # }
    # print "** $PM created ${new_warp} and ${new_inverse}\n";
  
     return($jid);
}

# ------------------
sub spm_analysis_vbm {
# ------------------
    my ($contrast,$input_path,$work_master_path) = @_;
    my $contrast_path = "${work_master_path}/${contrast}/";

#make work directories
    if (! -e $contrast_path) {
	mkdir ($contrast_path,$permissions);
    }

    my $group_1_path = $contrast_path.'/'.$group_1_name;
    my $group_2_path = $contrast_path.'/'.$group_2_name;
    if (! -e $group_1_path) {
	mkdir ($group_1_path,$permissions);
    }
    if (! -e $group_2_path) {
	mkdir ($group_2_path,$permissions);
    }


# relative link to smoothed pool

    my @group_1_array = split(',',$group_1_files);
    my @group_2_array = split(',',$group_2_files);

    foreach my $file (@group_1_array){
	my $old_file = "../../../smoothed_image_pool/${file}";
	my $linked_file = "${group_1_path}/${file}";
	`ln -s ${old_file} ${linked_file}`;
    }

   foreach my $file (@group_2_array){
	my $old_file = "../../../smoothed_image_pool/${file}";
	my $linked_file = "${group_2_path}/${file}";
	`ln -s ${old_file} ${linked_file}`;
    }
    
    return();
}

# ------------------
sub surfstat_analysis_vbm {
# ------------------
    my ($contrast,$input_path,$results_master_path) = @_;
    my $contrast_path = "${results_master_path}/${contrast}/";
    if (! -e $contrast_path) {
	mkdir ($contrast_path,$permissions);
    }
    
    my $surfstat_args ="\'$contrast\', \'${average_mask}'\, \'${input_path}\', \'${contrast_path}\', \'${group_1_name}\', \'${group_2_name}\',\'${group_1_files}\',\'${group_2_files}\'";
    my $surfstat_args_2 ="${contrast} ${average_mask} ${input_path} ${contrast_path} ${group_1_name} ${group_2_name} ${group_1_files} ${group_2_files}";
    my $exec_testing =1;
    if ($exec_testing) {
	my $executable_path = "/home/rja20/cluster_code/workstation_code/analysis/vbm_pipe/surfstat_executable/AS/run_surfstat_for_vbm_pipeline_exec.sh"; #Trying to rectify the issue of slurm job not terminating...ever
	my $go_message = "$PM: Running SurfStat with contrast: \"${contrast}\" for predictor \"${predictor_id}\"\n" ;
	my $stop_message = "$PM: Failed to properly run SurfStat with contrast: \"${contrast}\" for predictor \"${predictor_id}\"\n" ;
	
	my @test=(0);
	if (defined $reservation) {
	    @test =(0,$reservation);
	}
	my $mem_request = '10000';
	my $jid = 0;
	if (cluster_check) {
	    my $go =1;	    
#	my $cmd = $pairwise_cmd.$rename_cmd;
	    my $cmd = "${executable_path} ${matlab_path} ${surfstat_args_2}";
	    
	    my $home_path = $current_path;
	    my $Id= "${contrast}_surfstat_VBA_for_${group_1_name}_vs_${group_2_name}";
	    my $verbose = 2; # Will print log only for work done.
	    $jid = cluster_exec($go,$go_message , $cmd ,$home_path,$Id,$verbose,$mem_request,@test);     
	    if (! $jid) {
		error_out($stop_message);
	    }
	}
    } else {
	my $surfstat_command = make_matlab_command('surfstat_for_vbm_pipeline',$surfstat_args,"surfstat_with_${contrast}_for_${predictor_id}_",$Hf,0); # 'center_nii'
	print "surfstat command = ${surfstat_command}\n";
	my $state = execute(1, "Running SurfStat with contrast: \"${contrast}\" for predictor \"${predictor_id}\"", $surfstat_command);
	print "Current state = $state\n";
    }
    return();
}

# ------------------
sub fsl_nonparametric_analysis_vbm {
# ------------------
    my ($contrast,$input_path,$results_master_path) = @_;

    my $contrast_path = "${results_master_path}/${contrast}/";
    if (! -e $contrast_path) {
	mkdir ($contrast_path,$permissions);
    }

    fsl_nonparametric_analysis_prep($contrast,$input_path);

    my $local_results_path = "${contrast_path}/${local_sub_name}_${nonparametric_permutations}_perms/";
    if (! -e $local_results_path) {
	mkdir ($local_results_path,$permissions);
    }


    $number_of_test_contrasts=`head -2 $con_file | tail -1 | cut -d ' ' -f 2`;
    
    my $prefix = "${contrast}_nonparametric_testing";
    my $master_job_name="fsl_nonparametric_testing_for_${local_sub_name}_${contrast}";
    my @expected_outputs = ();
    
    
    my $remaining_permutations = $nonparametric_permutations;
    my $seed;
    my %cleanup_string;
    my @output_key_list = ('_','_glm_cope_','_glm_pe_','_glm_sigmasqr_','_glm_varcope_'); # This corresponds to the raw ttest and glm  outputs.
    
    if ($randomise_options =~ /\ -T\ / ) { # $tfce_analysis
	my @t_keys = ('_tfce_','_tfce_p_','_tfce_corrp_');
	push(@output_key_list,@t_keys);
    }
    
    if ($cmbt_analysis)  { # $cmbt_analysis
	my @c_keys = ('_clusterm_','_clusterm_corrp_');
	push(@output_key_list,@c_keys);
    }
    
    if ($randomise_options =~ /\ -x\ /) {
	my @x_keys = ('_vox_p_','_vox_corrp_');
	push(@output_key_list,@x_keys);
    }

   if ($randomise_options =~ /\ -P\ /) {
	my @P_keys = ('_perm_');
	push(@output_key_list,@P_keys);
    }
    
    
    for ($seed = 1; $remaining_permutations > 0 ;$seed++) {
	# ($seed,$num_of_perms,$output_path,$prefix,$contrast_number)
	my $c_permutations = $default_nonparametric_job_size;
	$c_permutations =  min($c_permutations,$remaining_permutations);
	$remaining_permutations = $remaining_permutations - $c_permutations;
	
	for (my $test_contrast = 1; $test_contrast <= $number_of_test_contrasts; $test_contrast++) {
	    my $expected_perms = $c_permutations;
	    if ($seed > 1) {$expected_perms++;} 
	    my $rfix = $local_results_path.$prefix;
	    my $rfix_S = '${rd}'.$prefix; 
	    my $cfix = "${local_work_dir}/${prefix}_SEED${seed}x${expected_perms}";
	    my $cfix_S = '${wd}'."${prefix}_SEED${seed}x${expected_perms}";
	    my $cfix2 = "tstat${test_contrast}.nii.gz";
	    my $c_file; #current [full] file
	    my $r_file; #results [full] file 
	    my $c_file_short; #current file string with directory variable
	    my $r_file_short; #result file string with directory variable
	    my @expected_p_outputs=(); # The expected outputs of each parallel process
	    my %temp_remove_commands;	    

	    for my $output_key (@output_key_list) {
		if ($output_key !~ /_perm_/) { 
		    $c_file="${cfix}${output_key}${cfix2}";
		    $c_file_short="${cfix_S}${output_key}${cfix2}";
		    $r_file = "${rfix}${output_key}${cfix2}";
		    $r_file_short = "${rfix_S}${output_key}${cfix2}";
		    if ( ($output_key =~ /^_$/) || ($output_key =~ /^_cluster/) || ($output_key =~ /^_glm/)) {
			if ($seed == 1) {
			    $cleanup_string{$output_key}{$test_contrast} = "cp ${c_file_short} ${r_file_short};\n";
			    push(@expected_p_outputs,$c_file);
			    push(@expected_outputs,$r_file);
			} else {
			    if ($output_key =~ /^_$/) { # We only ask for --glm_outputs and cluster stats when calling seed1, so don't need to remove for other seeds.
				#$cleanup_string{$output_key}{$test_contrast}  = "$cleanup_string{$output_key}{$test_contrast} rm ${c_file};\n";
				$temp_remove_commands{$output_key} = " rm ${c_file_short};\n";
			    }
			}
		    } else {
			push(@expected_p_outputs,$c_file);
			if ($seed == 1) {
			    $cleanup_string{$output_key}{$test_contrast}  = "fslmaths ${c_file_short} ";
			    push(@expected_outputs,$r_file);
			} else {
			    $cleanup_string{$output_key}{$test_contrast}  = "$cleanup_string{$output_key}{$test_contrast} -add ${c_file_short} ";
			}		    
		    }

		} else {
		    my $cfix3 = "tstat${test_contrast}.txt";
		    $c_file="${cfix}${output_key}${cfix3}";
		    $c_file_short="${cfix_S}${output_key}${cfix3}";
		    $r_file = "${rfix}${output_key}${cfix3}";
		    $r_file_short = "${rfix_S}${output_key}${cfix3}";
		    if ($seed == 1) {
			$cleanup_string{$output_key}{$test_contrast}  = "cat ${c_file_short} > ${r_file_short};\n ";
			push(@expected_outputs,$r_file);
		    } else {
			$cleanup_string{$output_key}{$test_contrast}  = $cleanup_string{$output_key}{$test_contrast}."tail -n +2 ${c_file_short} >> ${r_file_short};\n ";
		    }
		    push(@expected_p_outputs,$c_file);
		}
	    }
	    if (data_double_check(@expected_outputs)) {
		if (data_double_check(@expected_p_outputs)) { # If any one of the expected outputs is missing, the work will be performed.
		    for my $output_key (@output_key_list) {
			if ($temp_remove_commands{$output_key}) {
			    $cleanup_string{$output_key}{$test_contrast} = $cleanup_string{$output_key}{$test_contrast}.$temp_remove_commands{$output_key};
			}
		    }
		    
		    ($job) = parallelized_randomise($seed,$c_permutations,$local_work_dir,$prefix,$contrast,$master_job_name,$test_contrast);
		    my @j_array = split(',',$job);
		    if ($j_array[0] > 1) {
			push(@jobs,$job);
		    }
		}
	    }	    
	}
    }
    
  # Schedule defragmentation...

    my $scale =  $default_nonparametric_job_size/$nonparametric_permutations;
    for (my $test_contrast = 1; $test_contrast <= $number_of_test_contrasts; $test_contrast++) {
	for my $output_key (@output_key_list) {
	    if (! (($output_key =~ /^_$/) || ($output_key =~ /^_cluster/)|| ($output_key =~ /^_perm/) || ($output_key =~ /^_glm/)) ) {
		#my $rfix = "${local_results_path}/${prefix}";
		my $rfix = '${rd}'."${prefix}";
		my $cfix2 = "tstat${test_contrast}.nii.gz";
		my $r_file = "${rfix}${output_key}${cfix2}";
		$cleanup_string{$output_key}{$test_contrast}  = "$cleanup_string{$output_key}{$test_contrast} -mul ${scale} ${r_file};\n";
	    }
	}
    }


    
    my $number_of_jobs = scalar(@jobs);
    if ($number_of_jobs) {
	print " Number of jobs = ${number_of_jobs}\n";
    }
    my $jobs=join(',',@jobs);
    
    my $defrag_cmd='';
    for my $key1 (@output_key_list) {
	for (my $test_contrast = 1; $test_contrast <= $number_of_test_contrasts; $test_contrast++) {

	    my $cfix2;
	    if ($key1 !~ /_perm_/ ) {
		$cfix2 = "tstat${test_contrast}.nii.gz";
	    } else{ 
		$cfix2 = "tstat${test_contrast}.txt";
	    }
	    my $result_file = "${local_results_path}/${prefix}${key1}${cfix2}";
	    #  my $new_string =  join(' -add ',split(' ',$cleanup_string{$key1}{$test_contrast}));
	    if (! -e $result_file) {
		$defrag_cmd= $defrag_cmd.$cleanup_string{$key1}{$test_contrast};
	    }
	}
    }

    # And add the fdr and masking jobs...sure, why not?

    unshift(@mask_names,'brain');
    for my $mask_name (@mask_names) {
	my $c_mask;
	for (my $test_contrast = 1; $test_contrast <= $number_of_test_contrasts; $test_contrast++) {
	    if ($mask_name eq 'brain') {
		$c_mask = $average_mask;
	    } else {
		$c_mask = "${mask_folder}/${mask_name}.nii.gz";
	    }
	    my $input_image = "${local_results_path}/${prefix}_vox_p_tstat${test_contrast}";
	    my $masked_image ="${input_image}_masked_with_${mask_name}";
	    my $fdr_image = "${masked_image}";###
	    $input_image = $input_image.'.nii.gz';
	    $masked_image = $masked_image.'.nii.gz';
	    if (data_double_check($masked_image)) {
		my $mask_image_cmd = "fslmaths ${input_image} -mas ${c_mask} ${masked_image}";
		$defrag_cmd= $defrag_cmd.$mask_image_cmd.";\n";
	    }
## Codus interuptus here	    
	    
	}

#	for my $nonparametric_alpha (@nonparametric_alphas) {


#	}

    }

    # Schedule defragmentation ans other post processing jobs...
    
    if ($defrag_cmd ne '') {

	$defrag_cmd = 'wd='.$local_work_dir.";\n".'rd='.$local_results_path.";\n".$defrag_cmd;
	
	my @test=(0,0,'singleton');
	if (defined $reservation) {
	    @test =(0,$reservation,'singleton');
	}
	
	my $go_message = "$PM: Cleaning up fsl nonparametric testing for contrast: ${contrast}\n" ;
	my $stop_message = "$PM: Failed to properly clean up data for fsl nonparametric testing in folder: ${local_work_dir}  \n" ;
	
	
	my $mem_request = '17600';
	my $cleanup_jid = 0;
	if (cluster_check) {
	    my $go =1;	    
	    my $home_path = $local_results_path;  # Changed from local_work_dir to local_results_path to keep bookkeeping closer to final data.
	    my $Id= $master_job_name;
	    my $verbose =0; # These commands can be quite spammy, so will suppress. They can be found in the sbatch folder.
	    $cleanup_jid = cluster_exec($go,$go_message , $defrag_cmd,$home_path,$Id,$verbose,$mem_request,@test);     
	} else {
	    `${defrag_cmd}`;
	}
	
	if ($jobs) {
	    print STDOUT "SLURM: Waiting for jobs $jobs to complete via singleton job dependency of ${cleanup_jid}.\n";
	} else {
	    print STDOUT "SLURM: Waiting for jobs ${cleanup_jid} to complete.\n";
	}

	if (cluster_check() && ($cleanup_jid)) {
	    my $interval = 2;
	    my $verbose = 1;
	    my $done_waiting = cluster_wait_for_jobs($interval,$verbose,($cleanup_jid));
	    
	    if ($done_waiting) {
		print STDOUT  " Clean up is complete for fsl nonparametric testing of ${contrast} for ${local_sub_name}; moving on to next step.\n";
	    }
	}

    }
    return();
}

# ------------------
sub fsl_nonparametric_analysis_prep {
# ------------------
    my ($contrast,$input_path) = @_;
    
    if (defined $Hf) { 
	$use_Hf = 1;
    } elsif (! defined $Hf) {
	$use_Hf = 0;
    } else {
	print "\$Hf is confusing.  This shouldn't be happening.\n";
    }
    if ($use_Hf) {
	$nonparametric_permutations = $Hf->get_value('nonparametric_permutations');
	$number_of_nonparametric_seeds = $Hf->get_value('number_of_nonparametric_seeds');
    }

    ## Begin randomise command options.

    # Threshold-Free Cluster Enhancement business...
    $tfce_analysis = 1; # Initially will default to always on...just creating the code in case of future optionalization.
    $tfce_extent = 0.8; # Hardcoding this as a default for now...but is a module-wide variable which eventually can be accessed via $Hf.
    my $tfce_options='';

    if ($tfce_analysis) {
	$tfce_options = " -T --tfce_E=${tfce_extent} ";
    }

    # Cluster-mass-based thresholding business...
    $cmbt_analysis = 1; # Initially will default to always on...just creating the code in case of future optionalization.
    $fsl_cluster_size = 100 ; # Hardcoding this as a default for now...but is a module-wide variable which eventually can be accessed via $Hf.

    # Variance smoothing business...
    my $variance_smoothing = 1;  # Initially will default to always on...just creating the code in case of future optionalization.
    $variance_smoothing_kernal_in_mm =  0.2; # Hardcoding this as a default for now...but is a module-wide variable which eventually can be accessed via $Hf.
    my $v_smoothing_options='';

    if ($variance_smoothing) {
	$v_smoothing_options  = " -v ${variance_smoothing_kernal_in_mm} ";
    }

    my $output_options = " -x -P -R "; # Originally  --glm_output and -R was here, but it is only needed for the first (or any) seed, as it is derived from the unpermuted case.

    $randomise_options = " ${output_options} ${tfce_options} ${v_smoothing_options} ";
    ## End randomise command options.


    my @d_array= split('/',$input_path);
    pop(@d_array); 
    push(@d_array,'fsl');
    my $fsl_local_work_directory = join('/',@d_array);
   
    if (! -e $fsl_local_work_directory ) {
	mkdir ($fsl_local_work_directory,$permissions);
    }
    my $n1 = $#group_1_runnos + 1;
    my $n2 = $#group_2_runnos + 1;
    $local_sub_name = "groups_of_${n1}_and_${n2}";
    $local_work_dir = "${fsl_local_work_directory}/${local_sub_name}/";
    if (! -e $local_work_dir ) {
	mkdir ($local_work_dir,$permissions);
    }

    my $setup_cmds='';

    my $local_prefix = "${local_work_dir}${local_sub_name}";
    $con_file = "${local_prefix}.con";
    $mat_file = "${local_prefix}.mat";
    my $m_flag=''; # else $m_flag = ' -m ';
    if (data_double_check($con_file,$mat_file)) {
	my $con_mat_cmd = "design_ttest2 ${local_prefix} ${n1} ${n2} ${m_flag}";
	$setup_cmds=$setup_cmds.$con_mat_cmd.";\n";
    }

    $nii4D = "${local_work_dir}${local_sub_name}_nii4D_${contrast}.nii.gz";
    if (data_double_check($nii4D)) {
	my $dim_plus = $dims + 1;
	my $make_nii4D_cmd = "ImageMath ${dim_plus} ${nii4D} TimeSeriesAssemble 1 0";
	for my $current_name_ext (split(',',$group_1_files)) {
	    my $current_file = "${input_path}/${current_name_ext}";
	    $make_nii4D_cmd = "${make_nii4D_cmd} ${current_file}";
	}
	
	for my $current_name_ext (split(',',$group_2_files)) {
	    my $current_file = "${input_path}/${current_name_ext}";
	    $make_nii4D_cmd = "${make_nii4D_cmd} ${current_file}";
	}
	$setup_cmds=$setup_cmds.$make_nii4D_cmd.";\n";
    }

    my $go_message = "$PM: Setting up fsl nonparametric testing for contrast: ${contrast}\n" ;
    my $stop_message = "$PM: Failed to properly set up data for fsl nonparametric testing in folder: ${local_work_dir}  \n" ;
    
    my $jid = 0;
    if ($setup_cmds ne '') {
	my @test=(0);
	if (defined $reservation) {
	    @test =(0,$reservation);
	}
	my $mem_request = '17600'; #
	#my $jid = 0;
	if (cluster_check) {
	    my $go =1;	    
	    my $home_path = $local_work_dir;
	    my $Id= "setup_for_fsl_nonparametric_testing_with_n${n1}_and_n${n2}";
	    my $verbose = 2; 
	    $jid = cluster_exec($go,$go_message , $setup_cmds,$home_path,$Id,$verbose,$mem_request,@test);     

	    #return($jid);
	} else {
	    `${setup_cmds}`;
	   # return(1);
	}
    }

    if (cluster_check() && ($jid)){
	my $interval = 2;
	my $verbose = 1;
	my $done_waiting = cluster_wait_for_jobs($interval,$verbose,($jid));
	
	if ($done_waiting) {
	    print STDOUT  " Set up is complete for fsl nonparametric testing for ${local_sub_name} ; moving on to next step.\n";
	}
    }

    #fsl_nonparametric_analysis_Output_check();

}

# ------------------
sub parallelized_randomise {
# ------------------
    my ($seed,$num_of_perms,$output_path,$prefix,$contrast,$job_name,$contrast_number) = @_;

    if (! defined $contrast_number) {$contrast_number = 1;}
    my $output=$output_path.'/'.$prefix;
    my $glm_option = '';
    my $cmbt_options='';
    if ($seed == 1) {
	$glm_option = ' --glm_output ';
	$cmbt_options='';
	if ($cmbt_analysis) {
	    $cmbt_options = " -C ${fsl_cluster_size} ";
	}
    } else {
	$num_of_perms = $num_of_perms + 1;
    }

    # check for expected output first? -- should, but will have to add later, once I have a better idea of what that looks like...
    my $cmd = "randomise -i ${nii4D} -m ${average_mask} -d ${mat_file} -t ${con_file} ${randomise_options} ${glm_option} ${cmbt_options} -n ${num_of_perms} -o ${output}_SEED${seed}x${num_of_perms} --seed=${seed} --skipTo=${contrast_number}";
    my $go_message ="$PM: Running fsl nonparametric testing for contrast: ${contrast}\n" ;
    my @test=(0);
    if (defined $reservation) {
	@test =(0,$reservation);
    }
    
    my $mem_request = '7600'; # Processes appear to be single-threaded...trying to stuff as many jobs onto a node as there are [virtual?] cores...
    my $jid = 0;
    if (cluster_check) {
	my $go =1;	    
	my $home_path = $local_work_dir;
	my $Id= $job_name;
	my $verbose = 2; # Will print log only for work done.
	$jid = cluster_exec($go,$go_message , $cmd,$home_path,$Id,$verbose,$mem_request,@test);     
	
	return($jid);
    } else {
	`${cmd}`;
	return(0);
    }
}



# ------------------
sub make_custom_masks {
# ------------------
    my ($mask_dir,$mdt_labels) = @_;


  # Create ROI-based masks  # Will only support single ROIs for now?
   # SET  $mask_dir # @fdr_mask_array = split(',',$fdr_masks);
    my $make_mask_cmds='';
    #my $available_contrasts = join(' ',@channel_array);
    my $ROI_options = 'ROI label';

    # # Sort out the requested types of masks...
    # for my $mask_string (@fdr_mask_array) {
    # 	my @mask_parameters = split(':',$mask_string);
    # 	my $mask_type = shift(@mask_parameters);
    # 	if ((looks_like_number($mask_type)) || ($ROI_options =~ /${mask_type}/i)) {
    # 	    if (looks_like_number($mask_type)) {
    # 		unshift(@mask_parameters,$mask_type);
    # 	    }
    # 	    push(@ROI_masks,join(':',@mask_parameters));
    # 	    push(@ROIs_needed,@mask_parameters);
    # 	} elsif ($available_contrasts =~ /${mask_type}/i){
    # 	    if ($#mask_parameters > 1) { # i.e. are more than a min and possibly max values remaining in array?
    # 		push(@erroneous_masks,$mask_string);
    # 	    } else {
    # 		push(@thresh_masks,$mask_string);
    # 	    }
    # 	} else {
    # 	    push(@erroneous_masks,$mask_string);
    # 	}
    # }
    

    my @unique_ROIs = uniq(split(':',join(':',@ROIs_needed)));
    
    for my $u_ROI (@unique_ROIs) {
	my $mask_path = "${mask_dir}/${label_atlas_name}_ROI${u_ROI}.nii.gz";
	if (data_double_check($mask_path)) {
	    my $u_mask_cmd = "fslmaths ${mdt_labels} -thr ${u_ROI} -uthr ${u_ROI} ${mask_path}";
	    $make_mask_cmds=$make_mask_cmds.$u_mask_cmd.";\n";
	}   	
    }
    
    for my $ROI_mask (@ROI_masks) {
	my @ROIs = split(':',$ROI_mask);
	my $name_string = "ROI".join('_',@ROIs);
	push(@mask_names,$name_string);
	if ($#ROIs) {
	    my $mask_path = "${mask_dir}/${label_atlas_name}_${name_string}_mask.nii.gz";
	    if (data_double_check($mask_path)) {
		my $add_mask_cmd;
		my $roi_counter = 1;
		for my $ROI (@ROIs) {
		    my $c_mask_path = "${mask_dir}/${label_atlas_name}_ROI${ROI}.nii.gz";
		    if ($roi_counter == 1) {
			$add_mask_cmd = $add_mask_cmd."fslmaths ${c_mask_path} ";
		    } else {
			$add_mask_cmd = $add_mask_cmd."-add ${c_mask_path} ";
		    }
		    $roi_counter=$roi_counter+1;
		}
		$add_mask_cmd = $add_mask_cmd."${mask_path};\nfslmaths ${mask_path} -bin ${mask_path}";
		$make_mask_cmds=$make_mask_cmds.$add_mask_cmd.";\n";
	    }
	}
    }


    for my $thresh_mask (@thresh_masks) {
	my @mask_parameters = split(':',$thresh_mask);
	my $mask_contrast = shift(@mask_parameters);
	my $min_threshold = shift(@mask_parameters);
	my $max_threshold='';
	if (@mask_parameters) {
	    $max_threshold = shift(@mask_parameters);
	    if ($min_threshold > $max_threshold) {
		my $tmp = $min_threshold;
		$min_threshold = $max_threshold;
		$max_threshold = $tmp;
	    }
	}

	my $max_string = '';
	my $max_cmd='';
	if ($max_threshold) {
	    $max_string = "_max${max_threshold}";
	    if ($max_string =~ s/^([-]+)/neg/) {}
	    if ($max_string =~ s/[\.]+/p/) {}
	    $max_cmd = " -uthr ${max_threshold} ";
	}

	my $min_string = "_min${min_threshold}";
	if ($min_string =~ s/^([-]+)/neg/) {}
	if ($min_string =~ s/[\.]+/p/) {}
	
	my $include_zero_string = '';
	if (($min_threshold < 0) && ($max_threshold > 0)) {
	    $include_zero_string = " -fillh "; # This allows us to handle contrasts where zero might be a valid value (CT for example), but also the masked region value.
	}
	
	my $name_string = "${mask_contrast}${min_string}${max_string}";
	push(@mask_names,$name_string);
	# Let's assume that the MDT images are in the same directory as MDT labelset...
	my ($mdt_dir,$dummy,$dummy2) = fileparts($mdt_labels,2);
	my $contrast_image = get_nii_from_inputs($mdt_dir,'MDT',$mask_contrast);
	my $mask_path = "${mask_dir}/${name_string}_mask.nii.gz";
	if (data_double_check($mask_path)) {
	    my $thresh_mask_cmd = "fslmaths ${contrast_image} -thr ${min_threshold} ${max_cmd} -abs -bin ${include_zero_string} ${mask_path};\nfslmath";
	    $make_mask_cmds=$make_mask_cmds.$thresh_mask_cmd.";\n";
	}
    }


    my $go_message = "$PM: Creating custom masks in ${mask_dir}.\n" ;
    my $stop_message = "$PM: Failed to properly create custom masks in: ${mask_dir}  \n" ;
    
    my $jid = 0;
    if ($make_mask_cmds ne '') {
	my @test=(0);
	if (defined $reservation) {
	    @test =(0,$reservation);
	}
	my $mem_request = '17600'; #
	#my $jid = 0;
	if (cluster_check) {
	    my $go =1;	    
	    my $home_path = $mask_dir;
	    my $Id= "creating_custom_VBA_masks";
	    my $verbose = 2; 
	    $jid = cluster_exec($go,$go_message , $make_mask_cmds,$home_path,$Id,$verbose,$mem_request,@test);     

	    #return($jid);
	} else {
	    `${make_mask_cmds}`;
	   # return(1);
	}
    }

    if (cluster_check() && ($jid)){
	my $interval = 2;
	my $verbose = 1;
	my $done_waiting = cluster_wait_for_jobs($interval,$verbose,($jid));
	
	if ($done_waiting) {
	    print STDOUT  " Completed custom mask creation for VBA ; moving on to next step.\n";
	}
    }

    return();

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
sub vbm_analysis_vbm_Init_check {
# ------------------
    my $init_error_msg='';
    my $message_prefix="$PM initialization check:\n";


    my $vba_contrast_comma_list = $Hf->get_value('vba_contrast_comma_list');
    if ($vba_contrast_comma_list eq 'NO_KEY') { ## Should this go in init_check? # New feature to allow limited VBA/VBM analysis, 
	# used for reproccessing corrected Jacobians (07 Dec 2015);
	$vba_contrast_comma_list = $Hf->get_value('channel_comma_list');
    }
    @channel_array = split(',',$vba_contrast_comma_list);

    $software_list = $Hf->get_value('vba_analysis_software');
    if ($software_list eq 'NO_KEY') {
	$software_list = "surfstat"; 
	$Hf->set_value('vba_analysis_software',$software_list);
    }
    @software_array = split(',',$software_list);
    
    $software_list = '';
    my @temp_software_array;
    my $cluster_stats=0;
    
    foreach my $software (@software_array) {
	if ($software =~ /${supported_vbm_software}/i) {
	    if ($software =~ /^surfstat$/i) {
		$software = 'surfstat';
	    } elsif ($software =~ /^spm$/i) {
		$software = 'spm';
	    } elsif ($software =~ /^antsr$/i) {
		$software = 'antsr';
		$cluster_stats = 1;
	    } elsif ($software =~ /^fsl$/i) {
		$software = 'fsl';
		$log_msg = $log_msg."\tNon-parametric testing will be performed with: ${software}. \n";
	    } elsif ($software =~ /^nonparametric$/i) {
		$software = 'fsl';
		$log_msg = $log_msg."\tNon-parametric testing will be performed with: ${software}. \n";
	    }
	    
	    push(@temp_software_array,$software);

	    if ($software eq 'fsl') {
		$default_nonparametric_job_size = 25; # We expect to keep this hardcoded...might we need to decrease this for large data sets?
		my $default_nonparametric_permutations = 5000;
		$default_nonparametric_permutations = $default_nonparametric_job_size*(ceil($default_nonparametric_permutations/$default_nonparametric_job_size));
		my $minimum_nonparametric_permutations = 1500;
		$minimum_nonparametric_permutations = $default_nonparametric_job_size*(ceil($minimum_nonparametric_permutations/$default_nonparametric_job_size));

		my $requested_permutations = $Hf->get_value('nonparametric_permutations');
		if ($requested_permutations eq 'NO_KEY') {
		    $nonparametric_permutations = $default_nonparametric_permutations;
		    $log_msg = $log_msg."\tNo number of non-parametric testing permutations specified; using default (${nonparametric_permutations}). \n";
		} elsif (! looks_like_number($requested_permutations)) {
		    $nonparametric_permutations = $default_nonparametric_permutations;
		    $log_msg = $log_msg."\tAn invalid value of non-parametric testing permutations has been requested (${requested_permutations}); using default (${nonparametric_permutations}). \n";
		} elsif ($requested_permutations < $minimum_nonparametric_permutations) {
		    $nonparametric_permutations = $minimum_nonparametric_permutations;
		    $log_msg = $log_msg."\tThe requested number of non-parametric testing permutations (${requested_permutations}) is less than the minimum (${minimum_nonparametric_permutations}); using ${nonparametric_permutations}. \n";
		} elsif ($requested_permutations >= $minimum_nonparametric_permutations) {
		    $nonparametric_permutations = $default_nonparametric_job_size*(ceil($requested_permutations/$default_nonparametric_job_size));
		    #$nonparametric_permutations = floor($requested_permutations);
		    $log_msg = $log_msg."\tUsing the specified [integer-esque] number of non-parametric testing permutations (${nonparametric_permutations}). (The requested number of non-parametric testing permutations was ${requested_permutations}.)  \n";
		} else {
		    $nonparametric_permutations = $default_nonparametric_permutations;
		    $log_msg = $log_msg."\tAn invalid value of non-parametric testing permutations has been requested (${requested_permutations}); using default (${nonparametric_permutations}). \n";
		}

		$Hf->set_value('nonparametric_permutations',$nonparametric_permutations);
		$number_of_nonparametric_seeds = ceil($nonparametric_permutations/$default_nonparametric_job_size);
		$Hf->set_value('number_of_nonparametric_seeds',$number_of_nonparametric_seeds);
$log_msg = $log_msg."\tThis will be performed in ${number_of_nonparametric_seeds} parallel jobs per design contrast (typically 2), featuring ${default_nonparametric_job_size} permutations each. \n";
	    }

	    
	    $log_msg = $log_msg."\n\tVBA will be performed with software: ${software} \n";   
	} else {
	    $init_error_msg=$init_error_msg."I'm sorry, but VBM software \"${software}\" is currently not supported :( \n";
	}
    }

    $software_list = join(',',@temp_software_array);
    $Hf->set_value('vba_analysis_software',$software_list);
    $min_cluster_size = $Hf->get_value('minimum_vba_cluster_size');
    if (($min_cluster_size eq 'NO_KEY') && ($cluster_stats)) {
	$min_cluster_size = 200; 
	$Hf->set_value('minimum_vba_cluster_size',$min_cluster_size);
	$log_msg = $log_msg."\tMinimum cluster size for ANTsR VBA cluster analysis not specified; using default of 200.\n";
	print "min_cluster_size = ${min_cluster_size}\n";
    }

    $fdr_masks = $Hf->get_value('fdr_masks');
    if ($fdr_masks eq 'NO_KEY') {
	@fdr_mask_array=();
    } else {
	@fdr_mask_array = split(',',$fdr_masks);
    }
    
    # my @thresh_masks;
    # my @ROI_masks;
    my @erroneous_masks;
    # my @ROIs_needed;
    # my @mask_names;
    
    my $available_contrasts = join(' ',(@channel_array,'rd','jac','ajax')); # Need to include potentially derived contrasts
    my $ROI_options = 'ROI label';
    
    # Sort out the requested types of masks...
    for my $mask_string (@fdr_mask_array) {
	my @mask_parameters = split(':',$mask_string);
	my $mask_type = shift(@mask_parameters);
	if ((looks_like_number($mask_type)) || ($ROI_options =~ /${mask_type}/i)) {
	    if (looks_like_number($mask_type)) {
		unshift(@mask_parameters,$mask_type);
	    }
	    push(@ROI_masks,join(':',@mask_parameters));
	    push(@ROIs_needed,@mask_parameters);
	} elsif ($available_contrasts =~ /${mask_type}/i){
	    if ($#mask_parameters > 1) { # i.e. are more than a min and possibly max values remaining in array?
		push(@erroneous_masks,$mask_string);
	    } else {
		push(@thresh_masks,$mask_string);
	    }
	} else {
	    push(@erroneous_masks,$mask_string);
	}
    }
    
    if (@thresh_masks){
	$thresh_masks =  join(',',@thresh_masks);
	$Hf->set_value('thresh_masks',$thresh_masks);
    }
    
    if (@ROI_masks){
	$ROI_masks =  join(',',@ROI_masks);
	$Hf->set_value('ROI_masks',$ROI_masks);
    }
    
    if (@erroneous_masks){
	for my $error_mask_string (@erroneous_masks) {
	    $init_error_msg = $init_error_msg. "An invalid or imparsable request was made for a VBA fdr mask: \"${error_mask_string}\".\n";
	}
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
	$current_path = $Hf->get_value('vba_analysis_path');
	if ($current_path eq 'NO_KEY') {
	    $current_path = "${template_path}/vbm_analysis";
	    $Hf->set_value('vba_analysis_path',$current_path);

	    $thresh_masks = $Hf->get_value('thresh_masks');
	    if ($thresh_masks eq 'NO_KEY') {
		@thresh_masks=();
	    } else {
		@thresh_masks = split(',',$thresh_masks);
	    }


	    $ROI_masks = $Hf->get_value('ROI_masks');
	    if ($ROI_masks eq 'NO_KEY') {
		@ROI_masks=();
	    } else {
		@ROI_masks = split(',',$ROI_masks);
	    }

	    $label_atlas_name = $Hf->get_value('label_atlas_name');	
	    $mdt_labels = $Hf->get_value("${label_atlas_name}_MDT_labels");	
	}
	if (! -e $current_path) {
	    mkdir ($current_path,$permissions);
	}

	$directory_prefix = $current_path;
	if ($directory_prefix =~ s/\/glusterspace//) { }

	$software_list = $Hf->get_value('vba_analysis_software');
	if ($software_list eq 'NO_KEY') { ## Should this go in init_check?
	    $software_list = "surfstat"; 
	    $Hf->set_value('vba_analysis_software',$software_list);
	}
	@software_array = split(',',$software_list);

	my $vba_contrast_comma_list = $Hf->get_value('vba_contrast_comma_list');
	if ($vba_contrast_comma_list eq 'NO_KEY') { ## Should this go in init_check? # New feature to allow limited VBA/VBM analysis, 
	    # used for reproccessing corrected Jacobians (07 Dec 2015);
	    $vba_contrast_comma_list = $Hf->get_value('channel_comma_list');
	}
	@channel_array = split(',',$vba_contrast_comma_list);

	$smoothing_comma_list = $Hf->get_value('smoothing_comma_list');


	if ($smoothing_comma_list eq 'NO_KEY') { ## Should this go in init_check?
	    $smoothing_comma_list = "3vox"; 
	    $Hf->set_value('smoothing_comma_list',$smoothing_comma_list);
	}

	@smoothing_params = split(',',$smoothing_comma_list);

	$template_name = $Hf->get_value('template_name');
	$min_cluster_size = $Hf->get_value('minimum_vba_cluster_size');
    }

    my $template_images_path = $Hf->get_value('mdt_images_path');
    my $registered_images_path = $Hf->get_value('reg_images_path');

    my $runlist = $Hf->get_value('all_groups_comma_list');
    if ($runlist eq 'NO_KEY') {
	$runlist = $Hf->get_value('complete_comma_list');
    }

    my @array_of_runnos;
    
    if ($runlist eq 'EMPTY_VALUE') {
	@array_of_runnos = ();
    } else {
	@array_of_runnos = split(',',$runlist);
    }

    my $runno_OR_list = join("|",@array_of_runnos);

    my $mdt_creation_strategy = $Hf->get_value('mdt_creation_strategy');

    if (${mdt_creation_strategy} eq 'iterative') {
	$use_template_images = 0;
    }

    my @all_input_dirs;
    if ($use_template_images) {
	@all_input_dirs = ($template_images_path,$registered_images_path);
    } else {
	@all_input_dirs = ($registered_images_path); #BJA, 4 Jan 2017: Added this fix because previously it would pull from the template path. This is not set up to be backward compatible, although we got involved in related shenanigans with the Reacher (O'Brien) data.
    } 


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

    my ($local_inputs,$local_work,$local_results,$local_Hf);
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
	    ($local_inputs,$local_work,$local_results,$local_Hf)=make_process_dirs($local_folder_name);
	    foreach my $file (@files_to_link) {
		my ($file_path,$file_name,$file_ext) = fileparts($file,2);
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
	if ($predictor_id =~ /([^_]+)_(''|vs_|VS_|Vs_){1}([^_]+)/) {
	    $group_1_name = $1;
	    if (($3 ne '') || (defined $3)) {
		$group_2_name = $3;
	    } else {
		$group_2_name = 'others';
	    }
	}
    }

    my $group_1_runnos = $Hf->get_value('group_1_runnos');
    if ($group_1_runnos eq 'NO_KEY') {
	$group_1_runnos = $Hf->get_value('control_comma_list');
    }
    @group_1_runnos = split(',',$group_1_runnos);

    my $group_2_runnos = $Hf->get_value('group_2_runnos');
    if ($group_2_runnos eq 'NO_KEY'){ 
	$group_2_runnos = $Hf->get_value('compare_comma_list');
    }
    @group_2_runnos = split(',',$group_2_runnos);

    $average_mask = $Hf->get_value('MDT_eroded_mask');

    $mask_folder = $local_work."/masks/";
    if (! -e $mask_folder) {
	mkdir ($mask_folder,$permissions);
    }
    make_custom_masks($mask_folder,$mdt_labels);    
    
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

