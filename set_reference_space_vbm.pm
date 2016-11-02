#!/usr/local/pipeline-link/perl
# set_reference_space_vbm.pm 

#  2015/07/23  BJ Anderson, CIVM -- switched from PrintHeader to fslhd for getting header info, though most of this switch happened in pipeline utilites.
#  2015/03/04  BJ Anderson, CIVM

my $PM = "set_reference_space_vbm.pm";
my $VERSION = "2015/03/04";
my $NAME = "Set the reference spaces to be used for VBM and label analysis.";
my $DESC = "ants";

use strict;
use warnings;
no warnings qw(uninitialized bareword);

use vars qw($Hf $BADEXIT $GOODEXIT $test_mode $permissions);
require Headfile;
require pipeline_utilities;
require civm_simple_util;
require convert_all_to_nifti_vbm;

my ($inputs_dir,$preprocess_dir,$rigid_atlas_name,$rigid_target,$rigid_contrast,$runno_list,$rigid_atlas_path,,$original_rigid_atlas_path,$port_atlas_mask);#$current_path,$affine_iter);
my (%reference_space_hash,%reference_path_hash,%input_reference_path_hash,%refspace_hash,%refspace_folder_hash,%refname_hash,%refspace_file_hash);
my ($rigid_name,$rigid_dir,$rigid_ext,$new_rigid_path,$future_rigid_path,$native_ref_name,$translation_dir);
my ($process_dir_for_labels);
my ($log_msg);
my $split_string = ",,,";
my (%file_array_ref,@spaces);
my ($work_to_do_HoA);
my (@jobs_1,@jobs_2);
my $dims;
my $go = 1;
my $job;
my %runno_hash_vba;
my %runno_hash_label;

my %preferred_contrast_hash;

# ------------------
sub set_reference_space_vbm {  # Main code
# ------------------
    my $start_time = time;
     set_reference_space_vbm_Runtime_check();
     my $ref_file;
     foreach my $V_or_L (@spaces) {
	 my $work_folder = $refspace_folder_hash{$V_or_L};
	 my $translation_dir = "${work_folder}/translation_xforms/";

	 if (! -e $translation_dir ) {
	     mkdir ($translation_dir,$permissions);
	 }

	 $ref_file = $reference_path_hash{$V_or_L};
	 my %hashish = %$work_to_do_HoA;

	 my %runno_hash;
	 if ($V_or_L eq "vbm") {
	     %runno_hash = %runno_hash_vba;
	 } else {
	     %runno_hash = %runno_hash_label;
	 }
	 foreach my $runno (keys %runno_hash) {
	     my $in_file = $runno_hash{$runno};
	     my $out_file = "${work_folder}/translation_xforms/${runno}_";#0DerivedInitialMovingTranslation.mat";
	     ($job) = apply_new_reference_space_vbm($in_file,$ref_file,$out_file);
	     if ($job > 1) {
		 push(@jobs_1,$job);
	     }   
	 }

	 if (cluster_check() && ($#jobs_1 != -1)) {
	     my $interval = 1;
	     my $verbose = 1;
	     my $done_waiting = cluster_wait_for_jobs($interval,$verbose,@jobs_1);
	     
	     if ($done_waiting) {
		 print STDOUT  "  All translation alignment referencing jobs have completed; moving on to next step.\n";
	     }
	 }
    
     
	 my $array_ref = $hashish{$V_or_L};
	 foreach my $out_file (@$array_ref) {
	     my ($in_name,$dumdum,$in_ext) = fileparts($out_file);
	     my $in_file = "${preprocess_dir}/${in_name}${in_ext}";
	     ($job) = apply_new_reference_space_vbm($in_file,$ref_file,$out_file);
	     if ($job > 1) {
		 push(@jobs_2,$job);
	     }
	 }
     }
    
    
     if (cluster_check() && ($#jobs_2 != -1)) {
	 my $interval = 2;
	 my $verbose = 1;
	 my $done_waiting = cluster_wait_for_jobs($interval,$verbose,@jobs_2);

	 if ($done_waiting) {
	     print STDOUT  "  All referencing jobs have completed; moving on to next step.\n";
	 }
     }
    
    my $case = 2;
    my ($dummy,$error_message)=set_reference_space_Output_check($case);

    my @jobs = (@jobs_1,@jobs_2);    
    my $real_time = write_stats_for_pm($PM,$Hf,$start_time,@jobs);
    print "$PM took ${real_time} seconds to complete.\n";
    
    if ($error_message ne '') {
	error_out("${error_message}",0);
    } else {
	foreach my $space (@spaces) {
	    `mv ${refspace_folder_hash{$space}}/refspace.txt.tmp ${refspace_folder_hash{$space}}/refspace.txt`;
	}
    }
}


# ------------------
sub set_reference_space_Output_check {
# ------------------
     my ($case) = @_;
     my $full_error_msg;
 
 
     foreach my $V_or_L (@spaces) {
	 my @file_array;
	 my $message_prefix ='';  
	 @file_array=();
	 my $work_folder = $refspace_folder_hash{$V_or_L};
	 my $ref_file = $reference_path_hash{$V_or_L};
	 my $refspace = $refspace_hash{$V_or_L};
	 print "refspace = $refspace\n";
	 my $space_string = $V_or_L;
	 if ((! $process_dir_for_labels) && ($create_labels==1) && ($V_or_L eq 'vbm')) {
	     $space_string = "vbm and label";
	 }

	 if ($case == 1) {
	     $message_prefix = "  The following images for ${space_string} analysis in folder ${work_folder} have already been properly referrenced\n and will not be reprocessed :\n";
	 } elsif ($case == 2) {
	     $message_prefix = "  Unable to properly set the ${space_string} reference for the following images in folder ${work_folder}:\n";
	 }   # For Init_check, we could just add the appropriate cases.


	 my $existing_files_message = '';
	 my $missing_files_message = '';

	 my @files_to_check;
	 my %runno_hash;
	 if ($case == 1) {
	     print "$PM: Checking ${V_or_L} and preprocess folders...";
	     opendir(DIR, $preprocess_dir);
	     @files_to_check = grep(/(\.nii)+(\.gz)*$/ ,readdir(DIR));# @input_files;
	     @files_to_check=sort(@files_to_check);
	 } else {
	     print "$PM: Checking ${V_or_L} folder...";
	     my %hashish = %$work_to_do_HoA;
	     my $array_ref = $hashish{$V_or_L};
	     @files_to_check = @$array_ref;
	 }

	 
	 foreach my $file (@files_to_check) {
	     
	     my $out_file;
	     if ($case == 1) {
		 # $in_file = $preprocess_dir.'/'.$file;
		 $out_file = $work_folder.'/'.$file;
	     } else {
		 $out_file = $file;
	     }
	     print ".";
	     
	     if ((data_double_check($out_file)) && (data_double_check($out_file.'.gz'))) {
		 if ($case == 1) {
		    # print "\n${out_file} added to list of files to be re-referenced.\n";
		     my $test_file = $file;
		     if ($test_file =~ s/(_masked)//i){}
		     if ($test_file =~ /^([^\.]+)_([^_\.])+\..+/) { # We are assuming that underscores are not allowed in contrast names! 14 June 2016 ## Forgot about "masked"...OOF, that hurt! 14 October 2016
			 my $runno = $1;
			 my $contrast = $2;
			 if (! defined $runno_hash{$runno}) {
			     $runno_hash{$runno}= $preprocess_dir.'/'.$file;
			     print "runno_hash{${runno}}= $runno_hash{$runno}\n\n"; ##
			 }
		     }
		 }
		 push(@file_array,$out_file);	     
		 $missing_files_message = $missing_files_message."   $file \n";
	     } elsif (! compare_two_reference_spaces($out_file,$refspace)) {
		 print "\n${out_file} FUCKITY FUCK FUCK added to list of files to be re-referenced.\n";
		 push(@file_array,$out_file);	     
		 $missing_files_message = $missing_files_message."   $file \n";
	     } else {
		 $existing_files_message = $existing_files_message."   $file \n";
	     }
	 }
	 #print "\n";
	 if (($existing_files_message ne '') && ($case == 1)) {
	     $existing_files_message = $existing_files_message."\n";
	 } elsif (($missing_files_message ne '') && ($case == 2)) {
	     $missing_files_message = $missing_files_message."\n";
	 }
	 
	 my $error_msg='';
	 
	 if (($existing_files_message ne '') && ($case == 1)) {
	     $error_msg =  $error_msg."$PM:\n${message_prefix}${existing_files_message}";
	 } elsif (($missing_files_message ne '') && ($case == 2)) {
	     $error_msg =  $error_msg."$PM:\n${message_prefix}${missing_files_message}";
	 }
	 $full_error_msg = $full_error_msg.$error_msg;	 
	 $file_array_ref{$V_or_L} = \@file_array;

	 if ($case == 1) {
	     if ($V_or_L eq 'vbm') {
		 %runno_hash_vba = %runno_hash;
	     } else {
		 %runno_hash_label = %runno_hash;
	     }
	 }
	 if ($case == 2) {
	     symbolic_link_cleanup($refspace_folder_hash{$V_or_L},$PM);
	 }
     }
     return(\%file_array_ref,$full_error_msg);
}

# ------------------
sub apply_new_reference_space_vbm {
# ------------------
    my ($in_file,$ref_file,$out_file)=@_;
    my $do_registration = 1;    
    if ($out_file =~ /\.nii(\.gz)?/) {
	$do_registration = 0;
    }

    my $interp = "Linear"; # Default    
    my $in_spacing = get_spacing_from_header($in_file);
    my $ref_spacing = get_spacing_from_header($ref_file);
    if ($in_spacing eq $ref_spacing) {
	$interp = "NearestNeighbor";
    }
    if ($in_file =~ /(mask|Mask|MASK)\./) {
	$interp="NearestNeighbor";
    }
    
    my $cmd;
    my @cmds;
    my $translation_transform;
    if ($do_registration) {
	if (! compare_two_reference_spaces($in_file,$ref_file)) {	  
	    my ($dummy_1,$out_path,$dummy_2) = fileparts($out_file);
	    if (! -d $out_path ) {
		mkdir ($out_path,$permissions);
	    }

	    $translation_transform = "${out_file}0DerivedInitialMovingTranslation.mat" ;
	    my $excess_transform =  "${out_file}1Translation.mat" ;
	    if (data_double_check($translation_transform)) {
		my $translation_cmd = "antsRegistration -d ${dims} -t Translation[1] -r [${ref_file},${in_file},1] -m Mattes[${ref_file},${in_file},1,32,None] -c [0,1e-8,20] -f 8 -s 4 -z 0 -o ${out_file};\n";
		my $remove_cmd = "rm ${excess_transform};\n";
		$cmd = $translation_cmd.$remove_cmd;
		@cmds = ($translation_cmd,$remove_cmd);
	    } 
	} else {
	    my $affine_identity = $Hf->get_value('affine_identity_matrix');
	    $cmd = "cp ${affine_identity} ${translation_transform};\n";
	    @cmds = ($cmd);
	}
    } else {
	if (compare_two_reference_spaces($in_file,$ref_file)) {
	    $cmd = "ln -s ${in_file} ${out_file}";
	    print "Linking $in_file to $out_file\n\n";
	} else {
	    my $runno;
	    my $gz = '';
	    if ($out_file =~ s/(\.gz)$//) {$gz = '.gz';}
	    my ($out_name,$out_path,$dummy_2) = fileparts($out_file);
	    $out_file = $out_file.'.gz';
	    if ($out_name =~ s/(_masked)//i) {}
	    if ($out_name =~ /([^\.]+)_[^_\.]+/) { # We are assuming that underscores are not allowed in contrast names! 14 June 2016
		$runno = $1;
	    }
	    #my ($dummy_1,$out_path,$dummy_2) = fileparts($out_file);

	    $translation_transform = "${out_path}/translation_xforms/${runno}_0DerivedInitialMovingTranslation.mat";
	    $cmd = "antsApplyTransforms -d 3 -i ${in_file} -r ${ref_file}  -n $interp  -o ${out_file} -t ${translation_transform};\n"; 
	    @cmds = ($cmd);
	}  
    }
	
    my @list = split('/',$in_file);
    my $short_filename = pop(@list);
    
    my $go_message =  "$PM: Apply reference space of ${ref_file} to ${short_filename}";
    my $stop_message = "$PM: Unable to apply reference space of ${ref_file} to ${short_filename}:  $cmd\n";
    
    my $jid = 0;
    if ($cmd){
	if (cluster_check) {
	    my ($dummy1,$home_path,$dummy2) = fileparts($out_file);
	    my $Id= "${short_filename}_reference_to_proper_space";
	    my $verbose = 2; # Will print log only for work done.
	    $jid = cluster_exec($go, $go_message, $cmd,$home_path,$Id,$verbose);     
	    if (! $jid) {
		error_out($stop_message);
	    }
	} else {
	    if (! execute($go, $go_message, @cmds) ) {
		error_out($stop_message);
	    }
	}
	if (data_double_check($out_file)  && ($jid == 0)) {
	    error_out("$PM: could not properly create translation transform and/or apply reference: ${out_file}");
	    print "** $PM: apply reference created ${out_file}\n";
	}
    }
    
    return($jid);
}


#---------------------
sub prep_atlas_for_referencing_vbm {
#---------------------
    my ($in_path,$out_path);
    my ($dummy1,$dummy2);
    my ($nifti_args,$name,$nifti_command);
    my ($rigid_atlas_mask_path,$rigid_mask_name,$rigid_mask_ext,$mask_ref,$copy_cmd);
    
#    $future_rigid_path = "${inputs_dir}/${rigid_name}${rigid_ext}";
#    if ($future_rigid_path !~ /\.gz$/) { 
#	$future_rigid_path = $future_rigid_path.'.gz';
#    }

    $rigid_atlas_mask_path = get_nii_from_inputs($rigid_dir,'',"mask");
    if ($rigid_atlas_mask_path =~ /[\n]+/) {
	$mask_ref = 'NULL';
    } else {
	($rigid_mask_name,$dummy1,$rigid_mask_ext) = fileparts($rigid_atlas_mask_path);
	#$mask_ref = "${preprocess_dir}/${rigid_mask_name}_recentered${rigid_mask_ext}";
	$mask_ref = "${preprocess_dir}/${rigid_mask_name}_recentered${rigid_mask_ext}";    }

    ##KLUDGE
    # Skip the attempt to use the mask for recentering for now, at least until the matlab command can be fixed...
    $mask_ref = "NULL";

    #KLUDGE


    my $new_rigid_mask_path;
    my $delete_rigid_atlas_mask=0;
    if (($mask_ref ne 'NULL') && (! data_double_check($rigid_atlas_mask_path))) {
	#print "This should NOT be happening.\n\n\n";
	$out_path = $mask_ref;
	$in_path = $rigid_atlas_mask_path;
	$nifti_args = "\'${in_path}\', \'${out_path}\', 0, 0, 0";
	$name= $rigid_mask_name;
	$nifti_command = make_matlab_command('center_nii_around_center_of_mass',$nifti_args,"${name}_",$Hf,0); # 'center_nii'
	execute_log(1, "Recentering ${name} atlas mask around its center of mass", $nifti_command);
	`$nifti_command`;
	$delete_rigid_atlas_mask = 1;
	$new_rigid_mask_path=$out_path;
    } else {
	$mask_ref = 'NULL';
    }
    
    my $last_cmd;

    if ($new_rigid_path ne '') {
	if ($mask_ref ne 'NULL') { 
	    $copy_cmd = "CopyImageHeaderInformation ${mask_ref} ${rigid_atlas_path} ${new_rigid_path} 1 1 1";
	    $last_cmd=$copy_cmd;
	    execute_log(1,"Recentering ${rigid_atlas_path} via copying header info from ${rigid_atlas_mask_path} ",$copy_cmd);
	    `$copy_cmd`;
	} else {
	    $out_path = $new_rigid_path;
	    if ($out_path =~ s/\.gz$//) {}
	    $in_path = $rigid_atlas_path;
	    $nifti_args = "\'${in_path}\', \'${out_path}\', 0, 0, 0";
	    $name= $rigid_atlas_name;
	    $nifti_command = make_matlab_command('center_nii_around_center_of_mass',$nifti_args,"${name}_",$Hf,0); # 'center_nii'
	    execute_log(1, "Recentering ${name} atlas around its center of mass", $nifti_command);
	    `$nifti_command`;
	    `gzip $out_path`;

	    $last_cmd=$nifti_command;
	}
	
	if (data_double_check($new_rigid_path)) {
	    error_out("Failed to create recentered copy of ${rigid_atlas_path}: ${new_rigid_path}\nMost recent command: ${last_cmd}");
	} else {
	    $Hf->set_value('rigid_atlas_path',$future_rigid_path);
	    log_info("Properly referenced rigid atlas path is expected to be ${future_rigid_path}\n(Derived from ${rigid_atlas_path}");
	}
    }
    
    if ($delete_rigid_atlas_mask) {
	my $rm_cmd = "rm ${new_rigid_mask_path}";
#	execute_log(1,"Deleting extraneous mask: ${new_rigid_mask_path}",$rm_cmd);
#	`$rm_cmd`;
    }
}


# ------------------
sub set_reference_space_vbm_Init_check {
# ------------------
    my $init_error_msg='';
    my $message_prefix="$PM initialization check:\n";

    $preprocess_dir = $Hf->get_value('preprocess_dir');
    $inputs_dir = $Hf->get_value('inputs_dir');

    if (! -e $preprocess_dir ) {
	    mkdir ($preprocess_dir,$permissions);
    }

    if (! -e $inputs_dir ) {
	    mkdir ($inputs_dir,$permissions);
    }

    my $create_labels= $Hf->get_value('create_labels');
    my $do_mask= $Hf->get_value('do_mask');
    
    my $rigid_work_dir = $Hf->get_value('rigid_work_dir');
    my $label_image_inputs_dir;

    $inputs_dir = $Hf->get_value('inputs_dir');
    $rigid_contrast = $Hf->get_value('rigid_contrast'); 
    $runno_list= $Hf->get_value('complete_comma_list');

    $refspace_folder_hash{'vbm'} = $inputs_dir;

    ($refspace_hash{'existing_vbm'},$refname_hash{'existing_vbm'})=read_refspace_txt($inputs_dir,$split_string);
    
    $reference_space_hash{'vbm'}=$Hf->get_value('vbm_reference_space');
    $reference_space_hash{'label'}=$Hf->get_value('label_reference_space');     

    if ((! defined $reference_space_hash{'vbm'}) || ($reference_space_hash{'vbm'} eq ('NO_KEY' || ''))) {
	$log_msg=$log_msg."\tNo VBM reference space specified.  Will use native image space.\n";
	$reference_space_hash{'vbm'} = 'native';
    }
    

    $process_dir_for_labels =0;
    if ($create_labels == 1) {
	$process_dir_for_labels = 1;

	if ((! defined $reference_space_hash{'label'}) || ($reference_space_hash{'label'} eq (('NO_KEY') || ('') || ($reference_space_hash{'vbm'})))) {
	    
	    $log_msg=$log_msg."\tNo label reference space specified.  Will inherit from VBM reference space.\n";
	    $reference_space_hash{'label'}=$reference_space_hash{'vbm'};
	    $Hf->set_value('label_reference_space',$reference_space_hash{'label'});
	    $process_dir_for_labels = 0;
	    $refspace_folder_hash{'label'} = $inputs_dir;	   
	} 

    }

    $Hf->set_value('base_images_for_labels',$process_dir_for_labels);    

    my @spaces;
    if ($create_labels) {#($process_dir_for_labels) {
	@spaces = ("vbm","label");
    } else {
	@spaces = ("vbm");
    }

    foreach my $V_or_L (@spaces) {    
	my ($ref_error,$for_labels);
	if ($V_or_L eq "label") {
	    $for_labels = 1;
	} else {	
	    $for_labels = 0;
	}

	($input_reference_path_hash{$V_or_L},$reference_path_hash{$V_or_L},$refname_hash{$V_or_L},$ref_error) = set_reference_path_vbm($reference_space_hash{$V_or_L},$for_labels);
	$Hf->set_value("${V_or_L}_reference_path",$reference_path_hash{$V_or_L});
	$Hf->set_value("${V_or_L}_input_reference_path",$input_reference_path_hash{$V_or_L});
	#my $bounding_box_and_spacing = get_bounding_box_and_spacing_from_header($reference_path_hash{$V_or_L});
	my $bounding_box_and_spacing = get_bounding_box_and_spacing_from_header($input_reference_path_hash{$V_or_L});

	$refspace_hash{$V_or_L} = $bounding_box_and_spacing;
	$Hf->set_value("${V_or_L}_refspace",$refspace_hash{$V_or_L});

	if ($ref_error ne '') {
	    $init_error_msg=$init_error_msg.$ref_error;
	}
	
	$log_msg=$log_msg."\tReference path for ${V_or_L} analysis is ${reference_path_hash{${V_or_L}}}\n";
	
    }
    
    my $dir_work = $Hf->get_value('dir_work');
    
    my $rigid_work_path = "${dir_work}/${rigid_contrast}";
    
    $Hf->set_value('rigid_work_dir',$rigid_work_path);
    
    if ($refspace_hash{'existing_vbm'}) {
	if ($refspace_hash{'vbm'} ne $refspace_hash{'existing_vbm'}) {
	    $init_error_msg=$init_error_msg."WARNING\n\tWARNING\n\t\tWARNING\nThere is an existing vbm reference space which is not consistent with the one currently specified.".
		"\nExisting bounding box/spacing: ${refspace_hash{'existing_vbm'}}\nSpecified bounding box/spacing: ${refspace_hash{'vbm'}}\n\n".
		"If you really intend to change the vbm reference space, run the following commands and then try rerunning the pipeline:\n".
		"mv ${rigid_work_path} ${rigid_work_path}_${refname_hash{'existing_vbm'}}\n".
		"mv ${inputs_dir} ${inputs_dir}_${refname_hash{'existing_vbm'}}\n\n".
		"If ${rigid_work_path} does not exist, but another previous \'rigid_work_dir\' (as noted in headfiles) does exist, it is highly recommended to adjust the first command to properly back up the folder.\n";
	} else {
	    if ($refname_hash{'vbm'} ne $refname_hash{'existing_vbm'}) {
		$log_msg=$log_msg."\tThe specified vbm reference space is identical to the existing vbm reference space.  Existing vbm reference string will be used.\n".
		    "\trefname_hash{\'vbm\'} = ${refname_hash{'existing_vbm'}} INSTEAD of ${refname_hash{'vbm'}}\n";
		$Hf->set_value('vbm_refname',$refname_hash{'existing_vbm'});
		$refname_hash{'vbm'}=$refname_hash{'existing_vbm'};
		$Hf->set_value('vbm_refspace',$refspace_hash{'existing_vbm'});
		$refspace_hash{'vbm'}=$refspace_hash{'existing_vbm'};
		
	    }
	}
    }
    if (($process_dir_for_labels == 1) && ($refspace_hash{'vbm'} eq $refspace_hash{'label'})) {
	$process_dir_for_labels = 0;
	$Hf->set_value('label_reference_path',$reference_path_hash{'vbm'});	
	$Hf->set_value('label_refname',$refname_hash{'vbm'});
	$Hf->set_value('label_refspace',$refspace_hash{'vbm'});
	$Hf->set_value('label_refspace_path',$inputs_dir);
    }
    $Hf->set_value('base_images_for_labels',$process_dir_for_labels);
  
    
    if ($process_dir_for_labels == 1) {
	my $intermediary_path = "${inputs_dir}/reffed_for_labels";
	my $current_folder;
	my $existence = 1;
	for (my $i=1; $existence== 1; $i++) {
	    $current_folder =  "${intermediary_path}/ref_$i";
	    if (! -d "${current_folder}") {
		$existence = 0;
		$refspace_folder_hash{'label'} = $current_folder;
		$log_msg=$log_msg."\tCreating new base images folder for label space \"ref_$i\": ${refspace_folder_hash{'label'}}\n";
	    } else {

		($refspace_hash{'existing_label'},$refname_hash{'existing_label'}) = read_refspace_txt($current_folder,$split_string);

		if ($refspace_hash{'label'} eq $refspace_hash{'existing_label'}) {

		    $existence = 0;
		    $refspace_folder_hash{'label'} = $current_folder;

		    if ($refname_hash{'label'} ne $refname_hash{'existing_label'}) {
			$log_msg=$log_msg."\tThe specified label reference space is identical to the existing label reference space.".
			    " Existing label reference string will be used.\n".
			    "\t\'label_refname\' = ${refname_hash{'existing_label'}} INSTEAD of ${refname_hash{'label'}}\n";
			$Hf->set_value('label_refname',$refname_hash{'existing_label'});
			$refname_hash{'label'} = $refname_hash{'existing_label'};
		    }
		} 
	    }    
	}
	
    }

    # Changed 1 September 2016: Implemented uniform processing for reference files. Feed source directly into function
    #    for creating a centered binary mass in the reference image.  This should automatically handle all centering 
    #    issues, including re-centering the rigid atlas target.

    # my $native_ref_file = "${preprocess_dir}/${native_ref_name}";
    # my $local_ref_file;
    # if ($refname_hash{'vbm'} eq "native") {
    # 	#$local_ref_file = "${refspace_folder_hash{'vbm'}}/${native_ref_name}";
    # 	my $local_path = "${refspace_folder_hash{'vbm'}}/";
    # 	$local_ref_file = "${local_path}/${native_ref_name}";
    # 	if (data_double_check($local_ref_file)) {
    # 	    my $name = "centered_mass_for_${native_ref_name}";
    # 	    `cp ${native_ref_file} ${local_ref_file}`;
    # 	    #recenter_nii_function($local_ref_file,$local_path,0,$Hf);
    # 	    my $nifti_args = "\'${local_ref_file}\'";
    # 	    my $nifti_command = make_matlab_command('create_centered_mass_from_image_array',$nifti_args,"${name}_",$Hf,0); # 'center_nii'
    # 	    execute(1, "Creating a dummy centered mass for referencing purposes", $nifti_command);
    # 	}
    # 	$reference_path_hash{'vbm'} = $local_ref_file;
    # }
    
    
    # if ($refname_hash{'label'} eq "native") {
    # 	if ($refname_hash{'vbm'} ne "native") {
    # 	    my $local_path = "${refspace_folder_hash{'label'}}/";
    # 	    #$local_ref_file = "${refspace_folder_hash{'label'}}/${native_ref_name}";
    # 	    $local_ref_file = "${local_path}/${native_ref_name}";
    # 	    if (data_double_check($local_ref_file)) {
    # 		my $name = "centered_mass_for_${native_ref_name}";
    # 		`cp ${native_ref_file} ${local_ref_file}`;
    # 		#recenter_nii_function($local_ref_file,$local_path,0,$Hf);
    # 		my $nifti_args = "\'${local_ref_file}\'";
    # 		my $nifti_command = make_matlab_command('create_centered_mass_from_image_array',$nifti_args,"${name}_",$Hf,0); # 'center_nii'
    # 		execute(1, "Creating a dummy centered mass for referencing purposes", $nifti_command);
    # 	    }
    # 	}
    # 	$reference_path_hash{'label'} = $local_ref_file;
    # }
    

    $Hf->set_value('vbm_refspace_folder',$refspace_folder_hash{'vbm'});
    $Hf->set_value("vbm_reference_path",$reference_path_hash{'vbm'});


    if ($create_labels==1){ 
	$Hf->set_value('label_refspace_folder',$refspace_folder_hash{'label'});
	if ($process_dir_for_labels) {
	    $Hf->set_value('label_reference_path',$reference_path_hash{'label'});
	} else {
	    $Hf->set_value("label_reference_path",$reference_path_hash{'vbm'});
	} 
    }

    
    $rigid_atlas_name = $Hf->get_value('rigid_atlas_name');
    $rigid_contrast = $Hf->get_value('rigid_contrast');
    $rigid_target = $Hf->get_value('rigid_target');
    
    my $this_path;
    if ($rigid_atlas_name eq 'NO_KEY') {
	if ($rigid_target eq 'NO_KEY') {
	    $Hf->set_value('rigid_atlas_path','null');
	    $Hf->set_value('rigid_contrast','null');
	    $log_msg=$log_msg."\tNo rigid target or atlas has been specified. No rigid registration will be performed. Rigid contrast is \"null\".\n";
	} else {
	    if ($runno_list =~ /[,]*${rigid_target}[,]*}/) {
		$this_path=get_nii_from_inputs($preprocess_dir,$rigid_target,$rigid_contrast);
		if ($this_path !~ /[\n]+/) {
		   my ($this_name,$dumdum,$this_ext)= fileparts($this_path);
		   my $that_path = "${inputs_dir}/${this_name}${this_ext}";
		   #$Hf->set_value('rigid_atlas_path',$that_path);
		   $Hf->set_value('original_rigid_atlas_path',$that_path); #Updated 1 September 2016
		   $log_msg=$log_msg."\tA runno has been specified as the rigid target; setting ${that_path} as the expected rigid atlas path.\n";
		} else {
		    $init_error_msg=$init_error_msg."The desired target for rigid registration appears to be runno: ${rigid_target}, ".
			"but could not locate appropriate image.\nError message is: ${this_path}";	    
		}
	    } else {
		if (data_double_check($rigid_target)) {
		    $log_msg=$log_msg."\tNo valid rigid targets have been implied or specified (${rigid_target} could not be validated). Rigid registration will be skipped.\n";
		    $Hf->set_value('rigid_atlas_path','');
		    $Hf->set_value('original_rigid_atlas_path',''); # Added 1 September 2016
		} else {
		    $log_msg=$log_msg."\tThe specified file to be used as the original rigid target exists: ${rigid_target}. (Note: it has not been verified to be a valid image.)\n";
		   # $Hf->set_value('rigid_atlas_path',$rigid_target);
		    $Hf->set_value('original_rigid_atlas_path',$rigid_target);#Updated 1 September 2016
		}
	    }
	}
    } else {
	if ($rigid_contrast eq 'NO_KEY') {
	    $init_error_msg=$init_error_msg."No rigid contrast has been specified. Please set this to proceed.\n";
	} else {
	    my $rigid_atlas_dir   = "${WORKSTATION_DATA}/atlas/${rigid_atlas_name}/";
	    my $expected_rigid_atlas_path = "${rigid_atlas_dir}${rigid_atlas_name}_${rigid_contrast}.nii";
	    #$rigid_atlas_path  = get_nii_from_inputs($rigid_atlas_dir,$rigid_atlas_name,$rigid_contrast);

	    $rigid_atlas_path =  "${inputs_dir}/${rigid_atlas_name}_${rigid_contrast}.nii";#Added 1 September 2016
	    if (data_double_check($rigid_atlas_path))  {
		$rigid_atlas_path=$rigid_atlas_path.'.gz';
		if (data_double_check($rigid_atlas_path))  {
		    $original_rigid_atlas_path  = get_nii_from_inputs($preprocess_dir,$rigid_atlas_name,$rigid_contrast);
		    if ($original_rigid_atlas_path =~ /[\n]+/) {
			$original_rigid_atlas_path  = get_nii_from_inputs($rigid_atlas_dir,$rigid_atlas_name,$rigid_contrast);#Updated 1 September 2016
			if (data_double_check($original_rigid_atlas_path))  { # Updated 1 September 2016
			    $init_error_msg = $init_error_msg."For rigid contrast ${rigid_contrast}: missing atlas nifti file ${expected_rigid_atlas_path}  (note optional \'.gz\')\n";
			} else {
			    `cp ${original_rigid_atlas_path} ${preprocess_dir}`;
			    if ($original_rigid_atlas_path !~ /\.gz$/) {
				`gzip ${preprocess_dir}/${rigid_atlas_name}_${rigid_contrast}.nii`;
			    } 
			}
		    }
		} else {
		    `gzip ${rigid_atlas_path}`;
		    #$rigid_atlas_path=$rigid_atlas_path.'.gz'; #If things break, look here! 27 Sept 2016
		    $original_rigid_atlas_path = $expected_rigid_atlas_path;
		}
	    } else {
		$original_rigid_atlas_path = $expected_rigid_atlas_path;
	    }
	    
	    $Hf->set_value('rigid_atlas_path',$rigid_atlas_path);
	    $Hf->set_value('original_rigid_atlas_path',$original_rigid_atlas_path); # Updated 1 September 2016
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

#---------------------
sub set_reference_path_vbm {
#---------------------
    my ($ref_option,$for_labels) = @_;
    my $ref_string; 
    $inputs_dir = $Hf->get_value('inputs_dir');
    my $ref_path;
    my $input_ref_path;
    my $error_message;
    
    my $which_space='vbm';
    if ($for_labels) {
	$which_space = 'label';
    }
    my $ref_folder= $refspace_folder_hash{${which_space}};    

    if (! data_double_check($ref_option)) {
	my ($r_name,$r_path,$r_extension) = fileparts($ref_option);
	if ($r_extension =~ m/^[.]{1}(hdr|img|nii|nii\.gz)$/) {
	    $log_msg=$log_msg."\tThe selected ${which_space} reference space is an [acceptable] arbitrary file: ${ref_option}\n";
	    $input_ref_path=$ref_option;
	    $r_name =~ s/([^0-9a-zA-Z]*)//g;
	    $r_name =~ m/(^[\w]{2,8})/;
	    $ref_string = "c_$1";  # "c" stands for custom
	    $ref_path="${ref_folder}/reference_file_${ref_string}.nii.gz";
	} else {
	    $error_message="The arbitrary file selected for defining ${which_space} reference space exists but is NOT  in an acceptable format:\n${ref_option}\n";
	}
    }


    if ($ref_path ne '') {
	if ($for_labels) {
	    $Hf->set_value('label_refname',$ref_string);
	} else {
	    $Hf->set_value('vbm_refname',$ref_string); 
	}

	$log_msg=$log_msg."\tThe ${which_space} reference string/name = ${ref_string}\n";
	#return($ref_path,$ref_string,$error_message);
	return($input_ref_path,$ref_path,$ref_string,$error_message); #Updated 1 September 2016
    }
    
    my $atlas_dir_perhaps = "${WORKSTATION_DATA}/atlas/${ref_option}";
    
    if (-d $atlas_dir_perhaps) {
	$log_msg=$log_msg."\tThe ${which_space} reference space will be inherited from the ${ref_option} atlas.\n";
	$input_ref_path = get_nii_from_inputs($atlas_dir_perhaps,$ref_option,$rigid_contrast);
	if (($input_ref_path =~ /[\n]+/) || (data_double_check($input_ref_path))) {
	    $error_message = $error_message.$input_ref_path;
	}
	$ref_string="a_${ref_option}"; # "a" stands for atlas
	$ref_path="${ref_folder}/reference_file_${ref_string}.nii.gz";
	$log_msg=$log_msg."\tThe full ${which_space} input reference path is ${input_ref_path}\n";
    } else {
	my $ref_runno;
	my $preprocess_dir = $Hf->get_value('preprocess_dir');
	if ($runno_list =~ /[,]*${ref_option}[,]*/ ) {
	    $ref_runno=$ref_option;
	} else {
	    my @control_runnos= split(',',$Hf->get_value('control_comma_list'));
	    $ref_runno = shift(@control_runnos);
	}
	print " Ref_runno = ${ref_runno}\n";
	#$ref_path = get_nii_from_inputs($preprocess_dir,"native_reference",$ref_runno);
	#$ref_path = get_nii_from_inputs($preprocess_dir,"reference_image_native",$ref_runno);# Updated 1 September 2016
	
	$input_ref_path = get_nii_from_inputs($preprocess_dir,$ref_runno,"");
	$ref_string="native";
	$ref_path="${ref_folder}/reference_image_native_${ref_runno}.nii.gz";
	
	$error_message='';
	#} else {
#	$error_message = $error_message.$file;
	#   }
	
	$log_msg=$log_msg."\tThe ${which_space} reference space will be inherited from the native base images.\n\tThe full reference path is ${ref_path}\n";
	
    }


    if ($for_labels) {
	$Hf->set_value('label_refname',$ref_string);
    } else {
	$Hf->set_value('vbm_refname',$ref_string);
    }
    
    $log_msg=$log_msg."\tThe ${which_space} reference string/name = ${ref_string}\n";
    
    return($input_ref_path,$ref_path,$ref_string,$error_message);
}

# ------------------
sub set_reference_space_vbm_Runtime_check {
# ------------------
    $preprocess_dir = $Hf->get_value('preprocess_dir');
    $inputs_dir = $Hf->get_value('inputs_dir');
    $dims=$Hf->get_value('image_dimensions');

    if (! -e $preprocess_dir ) {
	    mkdir ($preprocess_dir,$permissions);
    }

    if (! -e $inputs_dir ) {
	    mkdir ($inputs_dir,$permissions);
    }

 

    $process_dir_for_labels = $Hf->get_value('base_images_for_labels');
    $refspace_folder_hash{'vbm'} = $Hf->get_value('vbm_refspace_folder');
    $refspace_folder_hash{'label'} = $Hf->get_value('label_refspace_folder');
    
    my $intermediary_path = "${inputs_dir}/reffed_for_labels";
    if ($process_dir_for_labels == 1) {
	$intermediary_path = "${inputs_dir}/reffed_for_labels";
	if (! -e $intermediary_path) {
	    mkdir ($intermediary_path,$permissions);
	}
	
	if (! -e $refspace_folder_hash{'label'} ) {
	    mkdir ($refspace_folder_hash{'label'},$permissions);
	}
    }
    

    if ($process_dir_for_labels) {
	@spaces = ("vbm","label");
    } else {
	@spaces = ("vbm");
    }
    foreach my $V_or_L (@spaces) {
	$reference_space_hash{$V_or_L} = $Hf->get_value("${V_or_L}_reference_space");
	my $inpath = $Hf->get_value("${V_or_L}_input_reference_path");
	my $outpath = $Hf->get_value("${V_or_L}_reference_path");
	$refspace_hash{$V_or_L} = $Hf->get_value("${V_or_L}_refspace");
	$refname_hash{$V_or_L} =  $Hf->get_value("${V_or_L}_refname");



	if (data_double_check($outpath)) {
	    my $name = "centered_mass_for_${refname_hash{$V_or_L}}";
	    my $nifti_args = "\'${inpath}\' , \'${outpath}\'";
	    my $nifti_command = make_matlab_command('create_centered_mass_from_image_array',$nifti_args,"${name}_",$Hf,0); # 'center_nii'
	    execute(1, "Creating a dummy centered mass for referencing purposes", $nifti_command);
	}

        # write refspace_temp.txt (for human purposes, in case this module fails)
	write_refspace_txt($refspace_hash{$V_or_L},$refname_hash{$V_or_L},$refspace_folder_hash{$V_or_L},$split_string,"refspace.txt.tmp")
    }


##  2 February 2016: Had "fixed" this code several months ago, however it was sending the re-centered rigid atlas to base_images, and not even 
##  creating a version for the preprocess folder. The rigid atlas will only be rereferenced if it is found in preprocess, which for new VBA runs
##  would not be the case.  Thus we would have a recentered atlas with its own reference space being used for rigid registration, resulting in
##  unknown behavior.  An example would be that all of our images get "shoved" to the top of their bounding box and the top of the brain gets lightly
##  trimmed off.  Also, we will assume that this file will be in .gz format.  If not, then it will be gzipped.

    # $rigid_atlas_path=$Hf->get_value('rigid_atlas_path');

    # if (! data_double_check($rigid_atlas_path)) {
    # 	my $original_gz = '';
    # 	if ($rigid_atlas_path =~ s/\.gz$//) {$original_gz = '.gz';}
    # 	($rigid_name,$rigid_dir,$rigid_ext) = fileparts($rigid_atlas_path);
    # 	$new_rigid_path="${preprocess_dir}/${rigid_name}${rigid_ext}";
    # 	$future_rigid_path="${inputs_dir}/${rigid_name}${rigid_ext}";

    # 	if ($future_rigid_path =~ s/\.gz$//) {}

    # 	if (! data_double_check($future_rigid_path)) {
    # 	    `gzip ${future_rigid_path}`;
    # 	}

    # 	$future_rigid_path = $future_rigid_path.'.gz';

    # 	$new_rigid_path = $new_rigid_path.'.gz';

    # 	if (data_double_check($future_rigid_path)) {
    # 	    if (data_double_check($new_rigid_path)) {
    # 		if ($new_rigid_path =~ s/\.gz$//) {}
    # 		if (! data_double_check($new_rigid_path)) {
    # 		    `gzip ${new_rigid_path}`;
    # 		}
    # 		#$new_rigid_path = $new_rigid_path.'.gz';
		
    # 		if ((data_double_check($new_rigid_path)) && (data_double_check($new_rigid_path.'gz'))) {
    # 		    `cp ${rigid_atlas_path} ${new_rigid_path}${original_gz}`;
    # 		    if (! $original_gz) {
    # 			`gzip ${new_rigid_path}`;
    # 		    }
    # 		    #	prep_atlas_for_referencing_vbm();
    # 		    #    } else {
    # 		}
    # 	    }
    # 	    $Hf->set_value('rigid_atlas_path',$future_rigid_path);
	
    # 	} else {
    # 	    $Hf->set_value('rigid_atlas_path',$future_rigid_path);
    # 	}
    # }

    if ($process_dir_for_labels == 1) {
	`cp ${refspace_folder_hash{"vbm"}}/*\.nii* ${refspace_folder_hash{"label"}}`;
    }   
    my $case = 1;
    my $skip_message;
    ($work_to_do_HoA,$skip_message)=set_reference_space_Output_check($case);
    
    if ($skip_message ne '') {
	print "${skip_message}";
    }
}
1;
