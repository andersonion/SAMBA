#!/usr/bin/false
# apply_warps_to_bvecs.pm 
# Originally written by BJ Anderson, CIVM

use strict;
use warnings;

my $PM = "apply_warps_to_bvecs.pm";
my $VERSION = "2017/04/03";
my $NAME = "Application of affine transforms to bvecs.";
my $DESC = "ants";

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

use civm_simple_util qw(printd $debug_val);
use pull_civm_tensor_data;

my ($runlist,$current_path,$write_path_for_Hf);
my ($pristine_inputs_dir);
my ($template_name,$label_refname);
my (@array_of_runnos,@files_to_create,@files_needed);
my @jobs=();
my (%go_hash,$go_message);
my $go = 1;
my $job;
my ($orientation,$ALS_to_RAS,$ecc_string,$ecc_affine_xform,$nifti_flip);#,$scanner_flip);#$native_to_ALS
my ($results_dir,$final_MDT_results_dir,$almost_results_dir,$almost_MDT_results_dir,$median_images_path, $final_results_dir);

# As of 25 January 2019, 'stable' points to '20190125_1444'
my $compilation_date='20190211_1539';
$compilation_date='stable';
my $bvec_transform_executable_path = "$MATLAB_EXEC_PATH/transform_bvecs_executable/$compilation_date/run_transform_bvecs.sh"; 
my ($current_contrast);
my $current_label_space;

if (! defined $dims) {$dims = 3;}
if (! defined $ants_verbosity) {$ants_verbosity = 1;}

# ------------------
sub apply_warps_to_bvecs {  # Main code
# ------------------
    ($current_label_space) = @_;
    my $direction='f';
    my $start_time = time;
    my $PM_code = 74; # 74 is an arbitrary code (70s for connectivity stuff?), need to set this in a more thoughtful manner.

    apply_warps_to_bvecs_Runtime_check($direction);
    foreach my $runno (@array_of_runnos) {
        $go = $go_hash{$runno};
        if ($go) {
            ($job) = apply_affine_rotation($runno,$direction);
            if ($job) {
                push(@jobs,$job);
            }
        } 
    }
    
    if (cluster_check() && (scalar @jobs)) {
        my $interval = 2;
        my $verbose = 1;
        my $done_waiting = cluster_wait_for_jobs($interval,$verbose,@jobs);
        if ($done_waiting) {
            print STDOUT  "  affine rotations have been applied to the b-vectors for all runnos; moving on to next step.\n";
        }
    }
    my $case = 2;
    my ($dummy,$error_message)=apply_warps_to_bvecs_Output_check($case,$direction);
    my $real_time = vbm_write_stats_for_pm($PM_code,$Hf,$start_time,@jobs);

    #
    # SUPER HORRIBLE KLUDGE because this keeps failing when we're too fast.
    #
    if( $real_time<180 && $error_message ne '') {
	carp("LIGHTNING RUN DEBUG ENGAGED! Module took $real_time seconds,".
	     "and is known to fail erroneously when we're too fast.\n".
	     "Dumping current \"output\" and doing a recheck");
	run_and_watch("pushd \$PWD;cd $current_path; ls -l *ecc*bv*txt;popd");
	($dummy,$error_message)=apply_warps_to_bvecs_Output_check($case,$direction);
	# update our "real time" because we got hit with output delays again. 
	$real_time = vbm_write_stats_for_pm($PM_code,$Hf,$start_time,@jobs);
	# if after a recheck we're still failing, delay a long time.
	my $delay=3;
	if( $error_message ne '') { $delay=30;}
	sleep_with_countdown($delay); 
    }

    @jobs=(); # Clear out the job list, since it will remember everything if this module is used iteratively.
    if ($error_message ne '') {
        error_out("${error_message}",0);
    } else {
        $Hf->write_headfile($write_path_for_Hf);
    }
    print "$PM took ${real_time} seconds to complete.\n";
}

# ------------------
sub apply_warps_to_bvecs_Output_check {
# ------------------
    my ($case, $direction) = @_;
    my $message_prefix ='';
    my ($out_file,$dir_string);
    if ($direction eq 'f' ) {
        $dir_string = 'forward';
    } elsif ($direction eq 'i') {
        $dir_string = 'inverse';
    } else {
        error_out("$PM: direction of warp \"$direction \"not recognized. Use \"f\" for forward and \"i\" for inverse.\n");
    }
    my @file_array=();
    if ($case == 1) {
	$message_prefix = "  ${dir_string} affine rotations have already been applied to the bvecs for the following runno(s) and will not be recalculated:\n";
    } elsif ($case == 2) {
	$message_prefix = "  Unable to apply ${dir_string} affine rotations to the bvecs for the following runno(s):\n";
    }   # For Init_check, we could just add the appropriate cases.

    my $existing_files_message = '';
    my $missing_files_message = '';
    foreach my $runno (@array_of_runnos) {
	if ($direction eq 'f' ) {
            $out_file = "${current_path}/${runno}_${orientation}_uhz${ecc_string}_bvecs.txt";
        } 
	if (data_double_check($out_file,$case-1)) {
            $go_hash{$runno}=1;
            push(@file_array,$out_file);
            #push(@files_to_create,$full_file); # This code may be activated for use with Init_check and generating lists of work to be done.
            $missing_files_message = $missing_files_message."\t$runno\n";#  :\t( $out_file )\n";
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
        $error_msg =  "$PM($current_label_space):\n${message_prefix}${existing_files_message}";
    } elsif (($missing_files_message ne '') && ($case == 2)) {
        $error_msg =  "$PM($current_label_space):\n${message_prefix}${missing_files_message}";
    }

    my $file_array_ref = \@file_array;
    return($file_array_ref,$error_msg);
}

# ------------------
sub apply_warps_to_bvecs_Input_check {
# ------------------

}


# ------------------
sub apply_affine_rotation {
# ------------------
    my ($runno,$direction) = @_;
    my ($cmd);
    my $out_file = '';
    my $direction_string = '';
    my ($start,$stop);
    my $reference_image;
    my $option_letter = "t";

    my $v_ok;
    
    my $mdt_warp_string = $Hf->get_value('forward_label_xforms');
    my $mdt_warp_train;

    $out_file = "${current_path}/${runno}_${orientation}${ecc_string}_bvecs.txt";
    
    if ($direction eq 'f') {
        $direction_string = 'forward';
        if ($current_label_space eq 'pre_rigid') {
            $start=0;
            $stop=0;
            $option_letter = '';
        } elsif (($current_label_space eq 'pre_affine') ||($current_label_space eq 'post_rigid')) {
            $start=3;
            $stop=3;
        } elsif ($current_label_space eq 'post_affine') {
            $start=2;
            $stop=3;
        } elsif (($current_label_space eq 'MDT') || ($current_label_space eq 'atlas')) {
	    $start=1;
	    $stop=3;
        }
    }

=item disable
    my $RAS_results_dir;
    if ($convert_labels_to_RAS) {
	die "dirty little convert to RAS";
        $RAS_results_dir = "${final_results_dir}/${runno}/";
        if (! -e  $RAS_results_dir) {
            mkdir ( $RAS_results_dir,$permissions);
        }
    }
=cut

    # my $image_to_warp = get_nii_from_inputs($inputs_dir,$runno,$current_contrast); 
    # Look up the bvecs we hope to have grabbed already.
    ($v_ok,my $original_bvecs ) = $Hf->get_value_check("original_bvecs_${runno}");
    my ($diffusion_headfile )= find_file_by_pattern(${pristine_inputs_dir},'(tensor|diffusion).*'.$runno.'.*headfile',0);
    # Only b_table is allowed now, so if we ever find not b_table, we say value is bad.
    if ( ${original_bvecs} !~ m/b_?table/ ) { 
        $v_ok=0; }
    if ( ! $v_ok || ! -e ${original_bvecs}) {
        # On not finding them, try a re-init to fill that in.
	
	#
	# Conceptually dirty data grabbing very late in processing.
	#
=item disabled data fetch code
        pull_civm_tensor_data_Init_check();     
        ($v_ok,$original_bvecs ) = $Hf->get_value_check("original_bvecs_${runno}");
        if ( ${original_bvecs} !~ m/b_?table/ ) { 
            $v_ok=0; }
        if ( ! $v_ok || ! -e ${original_bvecs}) {
	    # Still missing, or not reasonably set, try to fetch them
            # (this is for new data... and will fail the pipeline on old data. :( )
	    # The fail behavior has been "patched" to allow it to continue.
            pull_civm_tensor_data($runno,'b_table');
            ($v_ok,$original_bvecs ) = $Hf->get_value_check("original_bvecs_${runno}");
        }
=cut
        if ( ${original_bvecs} !~ m/b_?table/ ) { 
            $v_ok=0; }
	if ( ! $v_ok || ! -e ${original_bvecs}) {
            my $grad_matrix=File::Spec->catfile(${pristine_inputs_dir},"${runno}_gradient_matrix.txt");
            my $bval_file=File::Spec->catfile(${pristine_inputs_dir},"${runno}_input_bvals.txt");
            $original_bvecs=File::Spec->catfile(${pristine_inputs_dir},"${runno}_b_table.txt");
            if ( ! -e $original_bvecs || ( ! -e $grad_matrix || ! -e $bval_file )  ) {
		require IPC::Cmd;
		IPC::Cmd->import(qw/can_run/);
		#use File::Which;
		#if ( -x which("gradmaker") ) {
		if ( can_run("gradmaker") ) {
		    my $cmd="gradmaker ${diffusion_headfile} ${grad_matrix}";
                    #printd(0,$cmd."\n");sleep_with_countdown(12);# a debug print and wait.
		    if ( ! -e $grad_matrix) { 
                    run_and_watch($cmd);
		    }
		    if ( ! -e $bval_file ) {
			$cmd=sprintf("get_bval $diffusion_headfile");
			my @c_out=run_and_watch($cmd);
			write_array_to_file($bval_file,\@c_out);
		    }
                }
                # HAHA Single code required to run this!
                # but we had to add to perl lib? So why dont we as part of diffusion_calc's installation?
                # Hacked that for now, its always part of the lib(via settings)
                require dsi_studio;
                dsi_studio::make_btable($grad_matrix,$bval_file,$original_bvecs);
            }
            $Hf->set_value("original_bvecs_${runno}",${original_bvecs});
        }
    }
    if ( ! -e ${original_bvecs} ||  ${original_bvecs} !~ m/b_?table/ ) { 
        confess("missing/bad original bvector file for $runno! Cannot proceed"); 
    } else {
        #printd(0,"Found bvecs for $runno at $original_bvecs\n");
        #sleep_with_countdown(3);
    }
    my $scanner_flip='';
    if ( $civm_ecosystem && $eddy_current_correction) {
	if ( defined $diffusion_headfile ) { 
	    my $dHf= new Headfile('ro',$diffusion_headfile);
	    error_out("Trouble reading $diffusion_headfile") if (! $dHf->check());
	    $dHf->read_headfile();
	    ($v_ok,my $scanner)=$dHf->get_value_like_check('U_scanner');
	    error_out("problem finding scanner in $diffusion_headfile" ) if (! $v_ok );
	    my $sHf=load_deps($scanner,'scanner');
	    if (! defined $sHf ) { 
		error_out("Problem loading scanner constants for scanner $scanner!");
	    }
	    # bvec_flips if set will be a space separated array of things in order.
	    ($v_ok,my $bvec_flips)=$sHf->get_value_check('scanner_bvec_flip');
	    if(! $v_ok ) { 
		printd(5,"This scanner does not specify any bvector flipping.\n".
		       "That doesn't mean there isn't, just that we havn't checked, ".
		       "and saved the info to scanner_deps.\n".
		       "carefully validate your subsequent diffusion or connectomic calculations!\n");
		sleep_with_countdown(3);
	    } else {
		$scanner_flip=join(" -",split(" ",$bvec_flips));
		$scanner_flip=" -".$scanner_flip;
	    }
	} else {
	    error_out("Problem finding inputs headfile for $runno");
	}
    }

    my $max_bval_test = $Hf->get_value("max_bvalue_${runno}");
    my $bval_string = '';
    if ($max_bval_test ne 'NO_KEY') {
        $bval_string = " -b ${max_bval_test} ";
    }

    # Determine what we have set as the native orientation for a given runno
    # (from convert_all_to_nifti_vbm)
    my $Hf_key = "original_orientation_${runno}";
    my ($o_ok,$current_orientation)= $Hf->get_value_check($Hf_key);
    if (! $o_ok ) { 
	$Hf_key = "original_study_orientation";
	($o_ok,$current_orientation)= $Hf->get_value_check($Hf_key);
	if (! $o_ok ) { 
	    die "Orientation mixup";
	}
    }
    ($v_ok,my $current_vorder) = $Hf->get_value_check('working_image_orientation');
    if ($v_ok ) {
	$current_vorder= 'RAS';
    }

    my $native_to_ALS = $current_orientation.'_to_'.$current_vorder;

    # Find the right format for calling ecc_xforms ($exes_from_zeros, $xform_type), if requested
    my $exes_from_zeros;
    my $temp_runno = $runno;

    my $xform_type='';
    my $VerboseProgramming=0; # ;-) 
    if ($eddy_current_correction) {
        my $xforms_found=0;
        if (! $VerboseProgramming) { 
            my $xform_pat="xform_(${temp_runno})_m([0-9]+)\.(.*)0GenericAffine\.(.*)\$";
            my @xforms=find_file_by_pattern("${pristine_inputs_dir}",$xform_pat);
            if ( scalar(@xforms) ) {
		#
		# DIRTY in-line behavior switch and copy to kludge mounted directory problems.
		#
		# if any are not in a path with ecc_xforms, try to move any.
		my $ecc_dir=File::Spec->catdir($pristine_inputs_dir,"ecc_xforms");
		if (! -d $ecc_dir ) {
		    mkdir(File::Spec->catdir($pristine_inputs_dir,"ecc_xforms"),$permissions);
		}
		my @t_xforms=grep(!/ecc_xforms/,@xforms);
		if ( scalar(@t_xforms) ) {
		    run_and_watch("find $pristine_inputs_dir -maxdepth 1 -name 'xform*' -exec mv {} $ecc_dir/ ".'\;');
		    @xforms=find_file_by_pattern("${pristine_inputs_dir}",$xform_pat);
		    if (! scalar(@xforms) ) {
			confess("Xform organize fail!"); }
		}
		symbolic_link_cleanup($ecc_dir,$PM);
                $xforms_found=1;
		# using xform 1 out of the list to simplify our regex sytax a bit.
                my $xform_1=$xforms[0];
                $xform_1 =~ /$xform_pat/x;
                (my $tr,my $nstr,$xform_type,my $t_ext)=($1,$2,$3,$4);
                $exes_from_zeros=sprintf "X" x length($nstr);
                #confess "test stop, check X are right len and xform type matches               $exes_from_zeros, $xform_type, ($xform_1)";
            } else {
                confess ("Failed to find transforms with $xform_pat in $pristine_inputs_dir, Is this diffusion_calc data? That needs its data manually added to the inputs a great deal of the time.");
            }
	} else {
=item Verbose bleh	    
            my $zero_tester = '1';
            if ($temp_runno =~ s/(\_m[0]+)$//){}
            for my $type ('nii','nhdr'){
                if ($xforms_found==0) {
                    my $test_ecc_affine_xform = "${pristine_inputs_dir}/xform_${temp_runno}_m${zero_tester}.${type}0GenericAffine.mat"; # This is assuming that we are dealing with the outputs of tensor_create, as of April 2017
                    if (data_double_check($test_ecc_affine_xform)) {
                        $zero_tester = '01';
                        $test_ecc_affine_xform = "${pristine_inputs_dir}/xform_${temp_runno}_m${zero_tester}.${type}0GenericAffine.mat";
                        if (data_double_check($test_ecc_affine_xform)) {
                            $zero_tester = '001';
                            $test_ecc_affine_xform = "${pristine_inputs_dir}/xform_${temp_runno}_m${zero_tester}.${type}0GenericAffine.mat";
                            if (data_double_check($test_ecc_affine_xform)) {
                            } else {
                                $exes_from_zeros = 'XXX';
                                $xforms_found=1;
                            }
                        } else {
                            $exes_from_zeros = 'XX';
                            $xforms_found=1;
                        }
                    } else {
                        $exes_from_zeros = 'X';
                        $xforms_found=1;
                    }   
                    if ($xforms_found) {
                        $xform_type=$type;
                    } 
                }
            }
=cut
        } # end VerboseProgramming Check.
        if (! $xforms_found) {
            $eddy_current_correction=0; 
            die ("You dirty rat, you don't have the xforms you need to do ecc!");
        }
    }
    if ($eddy_current_correction) {
        # This is assuming that we are dealing with the outputs of tensor_create, as of April 2017
        $ecc_affine_xform = "${pristine_inputs_dir}/ecc_xforms/xform_${temp_runno}_m${exes_from_zeros}.${xform_type}0GenericAffine.mat"; 
        $ecc_string = '_ecc';
    } else {
        $ecc_affine_xform = '';
        $ecc_string = '';
        my $message_prefix="$PM:\n";
        my $log_msg = "No eddy current correction has been applied to bvecs for runno ${runno}.";
            log_info("${message_prefix}${log_msg}");
    }
    # uhz in filename reflects that we force upper hemisphere.
    $out_file = "${current_path}/${runno}_${orientation}_uhz${ecc_string}_bvecs.txt";
    my $out_file_prefix =  "${current_path}/${runno}_${orientation}";
    my $warp_string = $Hf->get_value("${direction_string}_xforms_${runno}");
    if ($warp_string eq 'NO_KEY') {
        $warp_string=$Hf->get_value("mdt_${direction_string}_xforms_${runno}")
    }

    my $warp_train = format_transforms_for_command_line($warp_string,$option_letter,$start,$stop);
    if ($current_label_space eq 'atlas') {
        $mdt_warp_train=format_transforms_for_command_line($mdt_warp_string);
        $warp_train= $mdt_warp_train.' '.$warp_train;
    }
    # If co-reg is performed with nhdr (nrrd headers), then the (-1,-1,1 aka -z) so-called nifti-flip AFTER ecc affine xforms
    # REMEMBER: this means that it will appear BEFORE it in the transform stack, since the transforms are applied in reverse order a la ANTs 
    my $ecc_and_affine_flips= " ${ecc_affine_xform} ${nifti_flip} ";
    if ($xform_type eq 'nhdr') {
        $ecc_and_affine_flips= " ${nifti_flip} ${ecc_affine_xform} ";
    }

    $cmd = "${bvec_transform_executable_path} ${matlab_path} ${original_bvecs} -o ${out_file_prefix} ${bval_string} ${ALS_to_RAS} ${warp_train} ${native_to_ALS} ${ecc_and_affine_flips} ${scanner_flip};\n";  
=item disable
    if ($convert_labels_to_RAS){
        my $copy_bvecs_cmd= "cp ${out_file} ${RAS_results_dir};\n";
           $cmd=$cmd.$copy_bvecs_cmd;
        ($out_file) =~ s/(bvecs\.txt)$/bvals\.txt/;
            my $copy_bvals_cmd= "cp ${out_file} ${RAS_results_dir};\n";
            $cmd=$cmd.$copy_bvals_cmd;
                
    }
=cut
    my @cmds = ($cmd);
    $go_message =  "$PM: apply ${direction_string} affine rotations to bvecs for ${runno}";
    my $stop_message = "$PM: could not apply ${direction_string} affine rotations to bvecs  for  ${runno}:\n${cmd}\n";

    my $jid = 0;
    if (cluster_check) {
	my @test=(0);
	if (defined $reservation) {
	    @test =(0,$reservation);
	}
	my $home_path = $current_path;
        my $Id= "${runno}_apply_${direction_string}_affine_rotations_to_bvecs";
        my $verbose = 1; # Will print log only for work done.
	my $mem_request = 3000;  # Added 23 November 2016,  Will need to make this smarter later.
        $jid = cluster_exec($go, $go_message, $cmd ,$home_path,$Id,$verbose,$mem_request,@test);     
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
        error_out("$PM: could not start for bvecs with ${direction_string} affine rotations  applied for ${runno}: ${out_file}");
    }
    print "** $PM expected output: ${out_file}\n";

    return($jid,$out_file);
}

# ------------------
sub apply_warps_to_bvecs_Init_check {
# ------------------

    my $init_error_msg='';
    my $message_prefix="$PM:\n";
    my $v_ok;

    # hf grabbing globals and over writing those globals caused a strange code conflict in here.
    # While these are supposed to be globals we're not gonna re-read from hf.
    #($v_ok,$do_connectivity) = $Hf->get_value('do_connectivity');
    #if ($v_ok && ($do_connectivity == 1)) {
    if ($do_connectivity == 1) {
	#($v_ok,$eddy_current_correction) = $Hf->get_value('eddy_current_correction');
        #if (! $v_ok) {
	#$Hf->set_value('eddy_current_correction',0);
	#$eddy_current_correction=0;
        #}
    }
    #($v_ok,$runlist) = $Hf->get_value('complete_comma_list');
    #if ($v_ok) {
    if(defined ($complete_comma_list) ) {
        @array_of_runnos = split(',',$complete_comma_list);        
    } else {
	$init_error_msg=$init_error_msg." Need complete_comma_list";
	@array_of_runnos = ();
    }
=item
    ($v_ok, my $scanner) = $Hf->get_value_check('scanner');
    if(! $v_ok, $civm_ecosystem) {
	if ($eddy_current_correction == 1 ) { 
	    $init_error_msg=$init_error_msg." eddy correciton requires intimate knowlege of the scanner!".
		" And I Don't have that yet! WILL NOT correct, thanks former coder.";
	    $eddy_current_correction=0;
	}
    }
=cut
    
    if ($init_error_msg ne '') {
	$init_error_msg = $message_prefix.$init_error_msg;
    }
    return($init_error_msg);
}

# ------------------
sub apply_warps_to_bvecs_Runtime_check {
# ------------------
    my ($direction)=@_;
    my $v_ok;
    # Set up work
    $pristine_inputs_dir = $Hf->get_value('pristine_input_dir');

    $template_name = $Hf->get_value('template_name');
    $label_reference = $Hf->get_value('label_reference');
    $label_refname = $Hf->get_value('label_refname');
    
    my $msg;
    if (! defined $current_label_space) {
        $msg =  "\$current_label_space not explicitly defined. Checking Headfile...\n";
        $current_label_space = $Hf->get_value('label_space');
    } else {
        $msg =  "current_label_space has been explicitly set to: ${current_label_space}\n";
    }
    printd(35,$msg);

    #$results_dir = $Hf->get_value('results_dir');
    $current_path = $Hf->get_value('label_images_dir');
    if (! -e $current_path) {
	confess("Missing expected directory:$current_path");
        mkdir ($current_path,$permissions);
    }
    # moving to init
    #$runlist = $Hf->get_value('complete_comma_list');
    
    $ecc_string = '';
    #($v_ok,my $eddy_current_correction) = $Hf->get_value_check('eddy_current_correction');
    #if ($v_ok && ($eddy_current_correction == 1)) {
    if($eddy_current_correction == 1) {
        $ecc_string = '_ecc';
    }  
    
   # 22 January 2019, BJA: Moved this code to actual apply xform sub; need to determine
   # "native" for each runno, via code copied from convert_all_to_nifti_vbm
   # $native_to_ALS = ''; # Previously global to this PM
   # my $flip_x = $Hf->get_value('flip_x');
   # my $flip_z = $Hf->get_value('flip_z');
   # if ($flip_x) {
   #    $native_to_ALS = $native_to_ALS." -z ";
   # }
   # if ($flip_z) {
   #    $native_to_ALS = $native_to_ALS." -x ";
   # }

    my $convert_images_to_RAS=$Hf->get_value('convert_labels_to_RAS');
    $ALS_to_RAS = '';
    ($v_ok,my $current_vorder)= $Hf->get_value_check('working_image_orientation');
    if (! $v_ok) {
	$current_vorder= 'RAS';
    }
    $orientation = $current_vorder;
    if (($convert_images_to_RAS ne 'NO_KEY') && ($convert_images_to_RAS == 1)) {
	die "bboroking!";
        $ALS_to_RAS = " ${current_vorder}_to_RAS ";
        $orientation = 'RAS';
    }       

    $write_path_for_Hf = "${current_path}/${template_name}_temp.headfile";
=item
    $scanner_flip='';
    ###########################################################################
    # Correcting for scanner behavior and eddy currents IS REALLY THE JOB OF THE DIFFUSION CODE!
    # Putting it here generates all sorts of trouble! Especially in needing to read the minds of 
    # many people!
    # We will support an exceedingly limited HACK here to get the right orientaiton offsets.
    # The truth of scanner orientation is that it is not agilent 9t, or agilent 7t it is 
    # hostname specific, SO that is the ugly method we'll do here. 
    # IF we're a civm scanner, Then we'll use scanner orients, and we'll get it from the scanner 
    # constants.
    # Otherwise We'll warn loudly (and slowly) if you asked for something we shouldnt do.
    #
    # Also, this code belongs in init :p
    #
    ($v_ok, my $scanner) = $Hf->get_value_check('scanner');
    if ( ! $v_ok ) { 
	
    }
    if ($scanner eq 'Agilent_9T') {
	# This has been tested...may need a better methods for figuring this shit out.
        $scanner_flip=' -x  ';
    } elsif ($scanner eq 'Agilent_7T') {
        # This has NOT been tested and could be WRONG...may need a better methods for figuring this shit out.
        $scanner_flip=' -y  '; 
    } elsif ($scanner eq 'Bruker_7T') {
	# This has NOT  been tested and should be WRONG...may need a better methods for figuring this shit out.
        $scanner_flip=' -z  ';
    } else {
	# FFS, NO WONDER BVEC CORRECTION IS FRAUGHT!
	croak "UNSET hf param! WILL NOT correct, thanks former coder.";
        $scanner_flip = ' -x '; # Let's assume it's 9T data for now.
    }
    # 
    ###########################################################################
=cut

    $nifti_flip = ' -z '; # For now we will assume that we are using default niis.  Can get the proper info from PrintHeader if we want to get fancy.

#   Functionize?
=item
moving to init
    if ($runlist eq 'EMPTY_VALUE') {
        @array_of_runnos = ();
    } else {
        @array_of_runnos = split(',',$runlist);
    }
=cut
#
    my $case = 1;
    my ($dummy,$skip_message)=apply_warps_to_bvecs_Output_check($case,$direction);

    if ($skip_message ne '') {
        print "${skip_message}";
    }
# check for needed input files to produce output files which need to be produced in this step?
    return;
}

1;
