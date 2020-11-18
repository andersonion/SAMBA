#!/usr/bin/false

# mask_images_vbm.pm 

# modified 2014/12/12 BJ Anderson for use in VBM pipeline.
# Based on convert_all_to_nifti.pm, as implemented by seg_pipe_mc
# modified 20130730 james cook, renamed flip_y to flip_x to be more accurate.
# modified 2012/04/27 james cook. Tried to make this generic will special handling for dti from archive cases.
# calls nifti code that can get dims from header
# created 2010/11/02 Sally Gewalt CIVM

my $PM = "mask_images_vbm.pm";
my $VERSION = "2014/12/23";
my $NAME = "Convert input data into the proper format, flipping x and/or z if need be.";

use strict;
use warnings;

use Headfile;
use pipeline_utilities;
# 25 June 2019, BJA: Will try to look for ENV variable to set matlab_execs and runtime paths
use Env qw(MATLAB_EXEC_PATH MATLAB_2015b_PATH WORKSTATION_HOME); 
if (! defined($MATLAB_EXEC_PATH)) {
   $MATLAB_EXEC_PATH =  "$WORKSTATION_HOME/matlab_execs";
}
if (! defined($MATLAB_2015b_PATH)) {
    $MATLAB_2015b_PATH =  "/cm/shared/apps/MATLAB/R2015b/";
}
my $matlab_path = "${MATLAB_2015b_PATH}";

my ($current_path, $work_dir,$runlist,$ch_runlist,$in_folder,$out_folder,$do_mask,$mask_dir,$template_contrast);
my ($thresh_ref,$default_mask_threshold,$num_morphs,$morph_radius,$dim_divisor, $status_display_level);
my (@array_of_runnos,@channel_array);
my @jobs=();
my (%go_hash,%make_hash,%mask_hash);
my $go=1;
my ($port_atlas_mask_path,$port_atlas_mask);
my ($job);

my $strip_mask_executable_path = "${MATLAB_EXEC_PATH}/strip_mask_executable/20170727_1304/run_strip_mask_exec.sh";
# New verion supports loading nhdr, it still saves nii, but we expect that, and will cheat with a
# CopyImageHeader if we want nhdrs...
$strip_mask_executable_path = "${MATLAB_EXEC_PATH}/strip_mask_executable/latest/run_strip_mask_exec.sh";

if (! defined $dims) {$dims = 3;}
if (! defined $ants_verbosity) {$ants_verbosity = 1;}

my $out_ext=".nii.gz";
$out_ext=".nhdr";
# ------------------
sub mask_images_vbm {
# ------------------
    my $start_time = time;
    mask_images_vbm_Runtime_check();

    my @nii_cmds;
    my @nii_files;

## Make/find masks for each runno using the template contrast (usually dwi).
    foreach my $runno (@array_of_runnos) {
        my $go = $make_hash{$runno};
        if ($go) {
            my $current_file=get_nii_from_inputs($current_path,$runno,$template_contrast);
	    my $mask_threshold=$default_mask_threshold;
            if (($thresh_ref ne "NO_KEY") && ($$thresh_ref{$runno})){
                $mask_threshold = $$thresh_ref{$runno};
            }
 	    # "current" here is probably preprocess
            my $mask_path = get_nii_from_inputs($current_path,$runno,'mask');
	    if (data_double_check($mask_path,0))  {
		# try again with segregated masks folder
		$mask_path = get_nii_from_inputs($mask_dir,$runno,'mask');
	    }
            if (data_double_check($mask_path,0))  {
		# no mask available. set specificly mask file
                $mask_path = "${mask_dir}/${runno}_${template_contrast}_mask\.nii";
            }
            my $ported_mask = $mask_dir.'/'.$runno.'_port_mask.nii';
	    if( $out_ext =~ /nhdr/){
		$mask_path =~ s/(^.+)[.]nii(?:[.]gz)?$/$1.nhdr/;
	    }
            $mask_hash{$runno} = $mask_path;
            if ( (! -e $mask_path) && (! -e $mask_path.".gz")  ){
                if ( (! $port_atlas_mask) 
		     || $port_atlas_mask && (! -e $ported_mask) && (! -e $ported_mask.'.gz') ) {
                    ($job) =  strip_mask_vbm($current_file,$mask_path,$mask_threshold);
                    if ($job) {
                        push(@jobs,$job);
                    }
                }
            }
        }
    }

    if (cluster_check() && (@jobs)) {
        my $interval = 2;
        my $verbose = 1;
        my $done_waiting = cluster_wait_for_jobs($interval,$verbose,@jobs);
        if ($done_waiting) {
            print STDOUT  " Automated skull-stripping/mask generation based on ; moving on to next step.\n";
        }
    }

    @jobs=();
    if ($port_atlas_mask) {
        my $atlas_mask =$Hf->get_value('port_atlas_mask_path') ;
        foreach my $runno (@array_of_runnos) {
            my $go = $make_hash{$runno};
            if ($do_mask && $go){               
                my $ported_mask = $mask_dir.'/'.$runno.'_port_mask'.${out_ext};
                if (data_double_check($ported_mask)) {
                    ($job) = port_atlas_mask_vbm($runno,$atlas_mask,$ported_mask);
                    if ($job) {
                        push(@jobs,$job);
                    }
                }
                $mask_hash{$runno} = $ported_mask;
            }
        }
        
        if (cluster_check() && ($#jobs != -1)) {
            my $interval = 2;
            my $verbose = 1;
            my $done_waiting = cluster_wait_for_jobs($interval,$verbose,@jobs);
            
            if ($done_waiting) {
                print STDOUT  "  All port_atlas_mask jobs have completed; moving on to next step.\n";
            }
        }
    }
    @jobs=(); # Reset job array;
## Apply masks to all images in each runno set.
    foreach my $runno (@array_of_runnos) {
        foreach my $ch (@channel_array) {
            my $go = $go_hash{$runno}{$ch};
            if ($go) {
                if ($do_mask) {
                    ($job) = mask_one_image($runno,$ch);
                } else {
                    ($job) = rename_one_image($runno,$ch);
                }   
                if ($job) {
                    push(@jobs,$job);
                }
            }
        }
    }

    if (cluster_check() && (@jobs)) {
        my $interval = 1;
        my $verbose = 1;
        my $done_waiting = cluster_wait_for_jobs($interval,$verbose,@jobs);

        if ($done_waiting) {
            print STDOUT  "  mask image jobs complete; will moving on to next step. Verifying masked data...\n";
        }
    }

    my $case = 2;
    my ($missing_files_ref,$error_message)=mask_images_Output_check($case);

    my $real_time = vbm_write_stats_for_pm($PM,$Hf,$start_time,@jobs);
    print "$PM took ${real_time} seconds to complete.\n";

    if (($error_message ne '') && ($do_mask)) {
        error_out("${error_message}"."Not Found:\n\t".join("\n\t",@$missing_files_ref),0);
    } else {
        # Clean up matlab junk
	#if (`ls ${work_dir} | grep -E /.m$/`) {
        #    `rm ${work_dir}/*.m`;
        #}
        #if (`ls ${work_dir} | grep -E /matlab/`) {
        #    `rm ${work_dir}/*matlab*`;
        #}
	# if "ls" command is successful (finds existing items), then executes "rm" command.
	# "2>" will redirect STDERR to /dev/null (aka nowhere land) so it doesn't spam terminal.
	# While the first inclination is to use run_and_watch, we dont care at all if we succeed or fail here.
	# We only care if there is work found to do, so we'll simply capture output to let this fail quietly.
	# Added -v to rm because wildcard rm is scary !
	my @matlab_stubs=`ls ${work_dir}/*.m 2> /dev/null`;
	my @matlab_files=`ls ${work_dir}/*matlab* 2> /dev/null`;
	chomp(@matlab_stubs);chomp(@matlab_files);
	if(scalar(@matlab_stubs) || scalar(@matlab_files) ) {
	    my $rm_cmd=sprintf("rm -v %s",sprintf("%s ",@matlab_stubs,@matlab_files));
	    #cluck("Testing:$PM\n\t$rm_cmd");sleep_with_countdown(15);
	    run_and_watch("$rm_cmd");
	}
    }
}


# ------------------
sub mask_images_Output_check {
# ------------------

    my ($case) = @_;
    my $message_prefix ='';
    my @missing_files=();

    my $existing_files_message = '';
    my $missing_files_message = '';

    if ($case == 1) {
        if ($do_mask) {
            $message_prefix = "  Masked images have been found for the following runno(s) and will not be re-processed:\n";
        } else {
            $message_prefix = "  Unmasked and properly named images have been found for the following runno(s) and will not be re-processed:\n";
        }
    } elsif ($case == 2) {
        if ($do_mask) {
            $message_prefix = "  Unable to properly mask images for the following runno(s) and channel(s):\n";
        } else {
            $message_prefix = "  Unable to properly rename the unmasked images for the following runno(s) and channel(s):\n";
        }
    }   # For Init_check, we could just add the appropriate cases.

    foreach my $runno (@array_of_runnos) {
	my $sub_existing_files_message='';
	my $sub_missing_files_message='';
	foreach my $ch (@channel_array) {
	    my $file_path;
	    # oh this is hard, there are 4 potential files when we factor in optional... gzipping... 
	    # only one should ever be found .... 
	    my @infiles;
	    my @outfiles;
	    # input files
	    $file_path = "${current_path}/${runno}_${ch}.${out_ext}";
	    push(@infiles,$file_path);
	    push(@infiles,$file_path.'.gz') if $out_ext =~ /[.]nii$/x;
	    if ($do_mask) {
		$file_path = "${current_path}/${runno}_${ch}_masked${out_ext}";
		push(@outfiles,$file_path.'.gz') if $out_ext =~ /[.]nii$/x;
		push(@outfiles,$file_path);
	    }
	    
	    # immediate check for input.
	    my $in_count=data_double_check(@infiles,0);
	    if (scalar(@outfiles) 
		&& scalar(@outfiles) == data_double_check(@outfiles,  ( $case-1 && $do_mask ) ) 
		|| $in_count != scalar(@infiles) ) {
		# Would like to not do slow disk mode when do_mask is 0.
		# I think just combining case-1 and do_mask will work.
		$go_hash{$runno}{$ch}=1;
		push(@missing_files,$file_path);
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

	if (($sub_missing_files_message ne '') && ($case == 1)) {
	    $make_hash{$runno} = $do_mask;
	} else {
	    $make_hash{$runno} = 0;
	}

    }
     
    my $error_msg='';
    if (($existing_files_message ne '') && ($case == 1)) {
	$error_msg =  "$PM:\n${message_prefix}${existing_files_message}\n";
    } elsif (($missing_files_message ne '') && ($case == 2)) {
	$error_msg =  "$PM:\n${message_prefix}${missing_files_message}\n";
    }
     
    my $missing_files_ref = \@missing_files;
    return($missing_files_ref,$error_msg);
}

# ------------------
sub strip_mask_vbm {
# ------------------
    my ($input_file,$mask_path,$mask_threshold) = @_;

    my $jid = 0;
    my ($go_message, $stop_message);

    my $matlab_exec_args="${input_file} ${dim_divisor} ${mask_threshold} ${mask_path} ${num_morphs} ${morph_radius} ${status_display_level}";
    $go_message = "$PM: Creating mask from file: ${input_file}\n" ;
    $stop_message = "$PM: Failed to properly create mask from file: ${input_file}\n" ;

    my $cmd = "${strip_mask_executable_path} ${matlab_path} ${matlab_exec_args}";
    if( $out_ext =~ /nhdr/){
	(my $mout = $mask_path)=~s/(^.+)[.]nii(?:[.]gz)?$/$1.nhdr/;
	$cmd=$cmd." && "."CopyImageHeaderInformation $input_file $mask_path $mout 1 1 1 0";
    }
    if (cluster_check) {
	my @test=(0);
	if (defined $reservation) {
	    @test =(0,$reservation);
	}
	my $go =1;	    
	
	my $home_path = $current_path;
	my $Id= "creating_mask_from_contrast_${template_contrast}";
	my $verbose = 2; # Will print log only for work done.
	my $mem_request = '40000'; # Should test to get an idea of actual mem usage.
	my $space="label";
	($mem_request)=refspace_memory_est($mem_request,$space,$Hf);

	$jid = cluster_exec($go,$go_message , $cmd ,$home_path,$Id,$verbose,$mem_request,@test);     
	if (not $jid) {
	    error_out($stop_message);
	}
    } else {
	execute(1,"strip_mask",$cmd);
    }

    return($jid);
}




# ------------------
sub port_atlas_mask_vbm {
# ------------------
    my ($runno,$atlas_mask,$port_mask) = @_;

    my $input_mask = $mask_hash{$runno};
    my $new_mask = $mask_dir.'/'.$runno.'_atlas_mask'.${out_ext}; # 2 Feb 2016: added '.gz'
    
     my $current_norm_mask = "${mask_dir}/${runno}_norm_mask${out_ext}";# 2 Feb 2016: added '.gz'
    my $out_prefix = $mask_dir.'/'.$runno."_mask_";
   # my $port_mask = $mask_dir.'/'.$runno.'_port_mask.nii';
    my $temp_out_file = $out_prefix."0GenericAffine.mat";
    my ($cmd,$norm_command,$atlas_mask_reg_command,$apply_xform_command,$new_norm_command,$cleanup_command);

    $new_norm_command = "ImageMath 3 $port_mask Normalize $new_mask;\n";
    $cleanup_command=$cleanup_command."if [ -e \"${port_mask}\" ]\nthen\n\tif [ -e \"${new_mask}\" ]\n\tthen\n\t\trm ${new_mask};\n";

    my $mem_request = 60000;
    my $space="label";
    ($mem_request,my $vx_count)=refspace_memory_est($mem_request,$space,$Hf);
    
    if (! -e $new_mask) {
	$apply_xform_command = "antsApplyTransforms -v ${ants_verbosity} --float -d ${dims} -i $atlas_mask -o $new_mask -t [${temp_out_file}, 1] -r $current_norm_mask -n NearestNeighbor".
	    "\niMath 3 ${new_mask} MD ${new_mask} 2 1 ball 1;\nSmoothImage 3 ${new_mask} 1 ${new_mask} 0 1;\n"; #BJA, 19 Oct 2017: Added radius=2 dilation, and then smoothing of new mask.Added
	$cleanup_command=$cleanup_command."\t\tif [ -e \"${temp_out_file}\" ]\n\t\tthen\n\t\t\trm ${temp_out_file};\n";
	
	my ($vx_sc,$est_bytes)=ants::estimate_memory($apply_xform_command,$vx_count);
	# convert bytes to MB(not MiB).
	$mem_request=ceil($est_bytes/1000/1000);
	if (! -e $temp_out_file) {
	    $atlas_mask_reg_command = "antsRegistration -v ${ants_verbosity} -d ${dims} -r [$atlas_mask,$current_norm_mask,1] ".
#		" -m MeanSquares[$atlas_mask,$current_norm_mask,1,32,random,0.3] -t translation[0.1] -c [3000x3000x0x0,1.e-8,20] ".
#		" -m MeanSquares[$atlas_mask,$current_norm_mask,1,32,random,0.3] -t rigid[0.1] -c [3000x3000x0x0,1.e-8,20] ".
		" -m MeanSquares[$atlas_mask,$current_norm_mask,1,32,random,0.3] -t affine[0.1] -c [3000x3000x0x0,1.e-8,20] ". 
		" -s 4x2x1x0.5vox -f 6x4x2x1 -l 1 -u 1 -z 1 -o $out_prefix;\n";# --affine-gradient-descent-option 0.05x0.5x1.e-4x1.e-4";
	
	    $cleanup_command=$cleanup_command."\t\t\tif [ -e \"${current_norm_mask}\" ]\n\t\t\tthen\n\t\t\t\trm ${current_norm_mask};\n\t\t\tfi\n";
	    if (! -e $current_norm_mask) {
		$norm_command = "ImageMath 3 $current_norm_mask Normalize $input_mask;\n";
	    }
	    
	    ($vx_sc,$est_bytes)=ants::estimate_memory($atlas_mask_reg_command,$vx_count);
	    # convert bytes to MB(not MiB).
	    $mem_request=ceil($est_bytes/1000/1000);
	}
	$cleanup_command=$cleanup_command."\t\tfi\n";
    }
    $cleanup_command=$cleanup_command."\tfi\nfi\n";
    
    $cmd = $norm_command.$atlas_mask_reg_command.$apply_xform_command.$new_norm_command;#.$cleanup_command;
    my @cmds =  ($norm_command,$atlas_mask_reg_command,$apply_xform_command,$new_norm_command,$cleanup_command);
    my $go_message =  "$PM: Creating port atlas mask for ${runno}\n";
    my $stop_message = "$PM: Unable to create port atas mask for ${runno}:  $cmd\n";
    
    my $jid = 0;
    if (cluster_check) {
	my @test = (0);
	if (defined $reservation) {
	    @test =(0,$reservation);
	}
	my ($home_path,$dummy1,$dummy2) = fileparts($port_mask,2);
	my $Id= "${runno}_create_port_atlas_mask";
	my $verbose = 2; # Will print log only for work done.
	$jid = cluster_exec($go, $go_message, $cmd,$home_path,$Id,$verbose,$mem_request,@test);     
	if (not $jid) {
	    error_out($stop_message);
	}
    } else {
	if (! execute($go, $go_message, @cmds) ) {
	    error_out($stop_message);
	}
	$jid=1;
    }

    if ($go && (not $jid)) {
	error_out("$PM: could not start port atlas mask: ${port_mask}");
    }
    print "** $PM expected output: ${port_mask}\n";

    return($jid);
}



# ------------------
sub mask_one_image {
# ------------------
    my ($runno,$ch) = @_;
    my $runno_mask;
#    if ($port_atlas_mask) {
#	$runno_mask=$mask_dir.'/'.$runno.'_port_mask.nii';
#    } else {
	$runno_mask = $mask_hash{$runno};
#    }
    my $out_path = "${current_path}/${runno}_${ch}_masked${out_ext}"; # 12 Feb 2016: Added .gz
    my $centered_path = get_nii_from_inputs($current_path,$runno,$ch);
    if($out_path eq $centered_path) {
	$centered_path=~ s/_masked//;
	if(! -e $centered_path) {
	    $centered_path=~ s/([.]?gz)$//;
	}
	cluck("mask_one_image defficient! out and in paths identical!, adjust input in hopes to perform a missed cleanup operation.\n\tnew input=$centered_path\n\toutput=   $out_path");
    }

    my $cmd_vars="i='$centered_path';\n".
	"m='$runno_mask';\n".
	"o='$out_path';\n";
    #my $apply_cmd = "fslmaths ${centered_path} -mas ${runno_mask} ${out_path} -odt \"input\";"; # 7 March 2016, Switched from ants ImageMath command to fslmaths, as fslmaths should be able to automatically handle color_fa images. (dim =4 instead of 3).
    my $apply_cmd = "fslmaths \${i} -mas \${m} \${o} -odt \"input\";";
    if( $out_ext =~ /nhdr/){
	$apply_cmd =  "ImageMath ${dims} ${out_path} m ${centered_path} ${runno_mask};";
    }
    my $im_a_real_tensor = '';
    if ($centered_path =~ /tensor/){
	$im_a_real_tensor = '1';
    }
    #my $apply_cmd =  "ImageMath ${dims} ${out_path} m ${centered_path} ${runno_mask};\n";
    #my $copy_hd_cmd = '';#"CopyImageHeaderInformation ${centered_path} ${out_path} ${out_path} 1 1 1 ${im_a_real_tensor};\n"; # 24 Feb 2018, disabling, function seems to be broken and wreaking havoc
    #my $cleanup_cmd = "if [[ -f ${out_path} ]];then\n".
    #"\tfn=\$(basename $centered_path);\n".
    #"\td=\$(dirname $centered_path);\n".
    #"\tif [[ ! -d \$d/unmasked ]];then mkdir \$d/unmasked;fi;\n".
    #"\tif [[ -e $centered_path ]];then\n".
    #"\t\tmv ${centered_path} \$d/unmasked/\$fn && ( gzip \$d/unmasked/\$fn & )\n".
    #"\tfi\n".
    #"fi\n";

    # these gzip commands run in background dont work,
    # Probably because slurm spots their creation and kills them on job end?
    # So, we've set up to sbatch them in the background... :D 
    my $cleanup_cmd = "if [[ -f \${o} ]];then\n".
	"\tfn=\$(basename \${i});\n".
	"\td=\$(dirname \${i});\n".
	"\tif [[ ! -d \$d/unmasked ]];then mkdir \$d/unmasked;fi;\n".
	"\tif [[ -e \${i} ]];then\n".
	"\tcbatch=\"\$d/unmasked/compresss_\${fn}.bash\";\n".
	"\techo '#!/usr/bin/env bash' > \${cbatch};\n".
	"\techo \"gzip -v \$d/unmasked/\$fn\" >> \${cbatch};\n".
	"\t\tmv \${i} \$d/unmasked/\$fn && sbatch --out=\${d}/unmasked/slurm-%j.out \${cbatch}\n".
	"\tfi\n".
	"fi\n";

    my @cmds;
    push(@cmds,$cmd_vars);
    push(@cmds,$apply_cmd) if ! -e $out_path;
    push(@cmds,$cleanup_cmd);
    
    my $go_message = "$PM: Applying mask created by ${template_contrast} image of runno $runno" ;
    my $stop_message = "$PM: could not apply ${template_contrast} mask to ${centered_path}:\n${apply_cmd}\n" ;

    my $cmd = join("\n",@cmds);
    my $jid = 0;
    if (cluster_check) {
	my @test = (0);
	if (defined $reservation) {
	    @test =(0,$reservation);
	}
	my $home_path = $current_path;
	my $Id= "${runno}_${ch}_apply_${template_contrast}_mask";
	my $verbose = 2; # Will print log only for work done.
	my $mem_request = 100000; # 12 April 2017, BJA: upped mem req from 60000 because of nii4Ds...may need to even go higher	
	$jid = cluster_exec($go,$go_message, $cmd ,$home_path,$Id,$verbose,$mem_request,@test);     
	if (! $jid) {
	    error_out($stop_message);
	}
    } else {
	if (! execute($go, $go_message, @cmds) ) {
	    error_out($stop_message);
	}
	$jid=1;
    }

    if ($go && (not $jid)) {
	error_out("$PM: could not start for masked image: ${out_path}");
    }
    print "** $PM expected output: ${out_path}\n";
  
    return($jid);
}

# ------------------
sub rename_one_image {
# ------------------
    my ($runno,$ch) = @_;
    my $centered_path = get_nii_from_inputs($current_path,$runno,$ch); ## THIS IS WHERE THINGS PROBABLY BROKE  24 October 2018 (Wed)
    my $out_path = "${current_path}/${runno}_${ch}${out_ext}"; # 12 Feb 2016: Added .gz
    
    my $rename_cmd = "mv ${centered_path} ${out_path}";

    my $cmd = $rename_cmd;
    my @cmds = ($rename_cmd);

    my $go_message = "$PM: Renaming unmasked image from \"${centered_path}\" to \"${out_path}\"." ;
    my $stop_message = "$PM: Unable to rename unmasked image from \"${centered_path}\" to \"${out_path}\":\n${rename_cmd}\n";
    
    my $jid = 0;
    if (cluster_check) {
	my @test = (0);    
	if (defined $reservation) {
	    @test =(0,$reservation);
	}
	my $home_path = $current_path;
	my $Id= "${runno}_${ch}_rename_unmasked_image";
	my $verbose = 2; # Will print log only for work done.
	my $mem_request = 100;
	$jid = cluster_exec($go,$go_message, $cmd ,$home_path,$Id,$verbose,$mem_request,@test);     
	if (! $jid) {
	    error_out($stop_message);
	}
    } else {
	if (! execute($go, $go_message, @cmds) ) {
	    error_out($stop_message);
	}
	$jid=1;
    }

    if ($go && (not $jid)) {
        error_out("$PM: could not start for unmasked image: ${out_path}");
    }
    print "** $PM expected output: ${out_path}\n";
  
    return($jid);
}



# ------------------
sub mask_images_vbm_Init_check {
# ------------------
# WARNING NAUGHTY CHECK IS DOING WORK.
    my $init_error_msg='';
    my $message_prefix="$PM initialization check:\n";
    my $log_msg='';

    (my $v_ok,$pre_masked) = $Hf->get_value_check('pre_masked');
    if(! $v_ok) {
	carp("Pre-masked unspecified assuming mask required");
	$pre_masked=0;
	sleep_with_countdown(3);
    }

    ($v_ok,$do_mask) = $Hf->get_value_check('do_mask');
    if ($do_mask !~ /^(1|0)$/ || ! $v_ok) {
        $init_error_msg=$init_error_msg."Variable 'do_mask' (${do_mask}) is not valid; please change to 1 or 0.";
    }
    $do_mask=0 if ! $v_ok;

    ($v_ok,$port_atlas_mask) = $Hf->get_value_check('port_atlas_mask');
    if ($pre_masked  == 1) {
        $do_mask = 0;
        $Hf->set_value('do_mask',$do_mask);
        $port_atlas_mask = 0;
        $Hf->set_value('port_atlas_mask',$port_atlas_mask);
        $log_msg=$log_msg."\tImages have been pre-masked. No skull cracking today :(\n";
    }
    $port_atlas_mask=0 if ! $v_ok;

    my $rigid_atlas_name = $Hf->get_value('rigid_atlas_name');
    $rigid_contrast = $Hf->get_value('rigid_contrast');
########
    my $source_rigid_atlas_path;
    my $runno_list= $Hf->get_value('complete_comma_list');
    my $preprocess_dir = $Hf->get_value('preprocess_dir');
    my $inputs_dir = $Hf->get_value('inputs_dir');
    my $rigid_target = $Hf->get_value('rigid_target');
    
    # Validate the vars are set or die, these vars should be handled by set_reference_space
    my @rigid_vars=qw(rigid_atlas_name rigid_contrast );
    push(@rigid_vars,qw(rigid_atlas_path original_rigid_atlas_path)) if $do_mask && $port_atlas_mask;
    my @errors;
    foreach (@rigid_vars) {
	my($v_ok,$v)=$Hf->get_value_check($_);
	push(@errors,"$_") if !$v_ok;
    }
    confess("Error with hf keys for rigid\n\t".join("\n\t",@errors)) if scalar(@errors);
########
    ## Set default mask for porting here!
    my $default_mask = "${WORKSTATION_DATA}/atlas/chass_symmetric2/chass_symmetric2_mask${out_ext}"; 
    if (($do_mask == 1) && ($port_atlas_mask == 1)) {
	confess("PORT ATLAS MASK NOT TESTED RECENTLY"); 
	###
	#
	#
	# WARNING PROGRAMMER! This is a redundant pile of re-resolve atlas data! 
	#   DO NOT FINISH THIS MESS!
	# FIX THIS BY ensuring set_reference_space_init_check has occured.
	# THEN pull those resolved values in here!
	#
	#
	###
	$port_atlas_mask_path = $Hf->get_value('port_atlas_mask_path');
        #print "Port atlas mask path = ${port_atlas_mask_path}\n\n";
        if ($port_atlas_mask_path eq 'NO_KEY') {
            #print "source_rigid_atlas_path = ${source_rigid_atlas_path}\n\n\n\n";
            my ($dummy1,$rigid_dir,$dummy2);
            if (! data_double_check($source_rigid_atlas_path)){
		($rigid_dir,$dummy1,$dummy2) = fileparts($source_rigid_atlas_path,2);
		$port_atlas_mask_path = get_nii_from_inputs($rigid_dir,$rigid_atlas_name,'mask');
		#print "Port atlas mask path = ${port_atlas_mask_path}\n\n"; #####
		#pause(15);
		if ($port_atlas_mask_path =~ /[\n]+/) {
		    my ($dummy1,$original_rigid_dir,$dummy2);
		    ($original_rigid_dir,$dummy1,$dummy2) = fileparts($source_rigid_atlas_path,2);
		    $port_atlas_mask_path = get_nii_from_inputs($original_rigid_dir,$rigid_atlas_name,'mask');      
		    if ($port_atlas_mask_path =~ /[\n]+/) {
			$port_atlas_mask_path=$default_mask;  # Use default mask
			die "default_mask $default_mask not found " if ! -e $default_mask;
			$log_msg=$log_msg."\tNo atlas mask specified; porting default atlas mask: ${port_atlas_mask_path}\n";
		    } else {
			run_and_watch("cp ${port_atlas_mask} ${rigid_dir}");
		    }
		} else {
		    $log_msg=$log_msg."\tNo atlas mask specified; porting rigid ${rigid_atlas_name} atlas mask: ${port_atlas_mask_path}\n";
		}
	    } else {
		$port_atlas_mask_path=$default_mask;  # Use default mask
		die "default_mask $default_mask not found " if ! -e $default_mask;
		$log_msg=$log_msg."\nNo atlas mask specified and rigid atlas being used; porting default atlas mask: ${port_atlas_mask_path}\n";
	    }
	}  
	
	if (data_double_check($port_atlas_mask_path)) {
	    $init_error_msg=$init_error_msg."Unable to port atlas mask (i.e. file does not exist): ${port_atlas_mask_path}\n";
	} else {
	    $Hf->set_value('port_atlas_mask_path',$port_atlas_mask_path);
	}
    }

    my $threshold_code;
    if ($do_mask) {
        $threshold_code = $Hf->get_value('threshold_code');
        if (($threshold_code eq 'NO_KEY') || ($threshold_code eq 'UNDEFINED_VALUE')) {
            $threshold_code = 4;
            $Hf->set_value('threshold_code',$threshold_code);
            $log_msg=$log_msg."\tThreshold code for skull-stripping is not set. Will use default value of ${threshold_code}.\n";
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
sub mask_images_vbm_Runtime_check {
# ------------------

# # Set up work
    $port_atlas_mask=$Hf->get_value('port_atlas_mask');
    $in_folder = $Hf->get_value('pristine_input_dir');
    $work_dir = $Hf->get_value('dir_work');
    #$current_path = $Hf->get_value('inputs_dir');  # Dammit, "input" or "inputs"???
    $current_path = $Hf->get_value('preprocess_dir');
    $do_mask = $Hf->get_value('do_mask');
    $mask_dir = $Hf->get_value('mask_dir');
    (my $tc_isbad,$template_contrast) = $Hf->get_value_check('skull_strip_contrast');

    if ($tc_isbad ==0) {
        
    #if ($template_contrast eq ('' || 'NO_KEY' || 'UNDEFINED_VALUE')) {
        my $ch_runlist=$Hf->get_value('channel_comma_list');
        if ($ch_runlist =~ /(dwi)/i) {
                $template_contrast = $1;
            } else {
                my @channels = split(',',$ch_runlist);
                $template_contrast = shift(@channels);    
        }
        $Hf->set_value('skull_strip_contrast',${template_contrast});
    }
    $thresh_ref = $Hf->get_value('threshold_hash_reference');
    $default_mask_threshold=$Hf->get_value('threshold_code'); # Do this on an the basis of individual runnos
                        # -1 use imagej (like evan and his dti pipe)
                        # 0-100 use threshold_zero 0-100, 
                        # 100-inf is set threshold.


    $num_morphs = 5; # Need to make these user-specifiable for mask tuning
    $morph_radius = 2; # Need to make these user-specifiable for mask tuning
    #$dim_divisor = 2; #Changed to 1, BJA 14 March 2017
    $dim_divisor = 1;

    $status_display_level=0;

    if ($mask_dir eq 'NO_KEY') {
        $mask_dir = "${current_path}/masks";
        $Hf->set_value('mask_dir',$mask_dir); # Dammit, "input" or "inputs"??? 	
    }

    if ((! -e $mask_dir) && ($do_mask)) {
        mkdir ($mask_dir,$permissions);
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
    my ($dummy,$skip_message)=mask_images_Output_check($case);

    if ($skip_message ne '') {
	print "${skip_message}";
    }


}


1;

