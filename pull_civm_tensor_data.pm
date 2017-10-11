#!/usr/local/pipeline-link/perl
# oull_civm_tensor_data.pm
# Originally from mid-Spring 2017; written by BJ Anderson, CIVM
#
# Initially appended to vbm_pipeline_workflow; extracted on 16 June 2017

# All my includes and requires are belong to us.
# use ...

my $PM = 'pull_civm_tensor_data.pm'; 

use strict;
use warnings;
#no warnings qw(uninitialized bareword);

use Cwd qw(abs_path);  # Verified as "necessary".
use File::Basename;
use List::Util qw(min max reduce); # Verified as "necessary".
use List::MoreUtils qw(uniq first_index); # Verfified as "necessary".
use vars qw($Hf $BADEXIT $GOODEXIT $permissions $valid_formats_string $nodes $reservation);
use Env qw(ANTSPATH PATH BIGGUS_DISKUS WORKSTATION_DATA WORKSTATION_HOME);

$ENV{'PATH'}=$ANTSPATH.':'.$PATH;
$ENV{'WORKSTATION_HOME'}="/cm/shared/workstation_code_dev";
$GOODEXIT = 0;
$BADEXIT  = 1;
my $ERROR_EXIT=$BADEXIT;
$permissions = 0755;
my $interval = 0.1; ##Normally 1
$valid_formats_string = 'hdr|img|nii';

# a do it again variable, will allow you to pull data from another vbm_run


umask(002); # Despite this, there is almost guaranteed to be issues with permissions for multi-user applications.

use lib dirname(abs_path($0));
use Env qw(RADISH_PERL_LIB);
if (! defined($RADISH_PERL_LIB)) {
    print STDERR "Cannot find good perl directories, quitting\n";
    exit;
}
use lib split(':',$RADISH_PERL_LIB);

# require ...
require Headfile;
#require retrieve_archived_data;
#require study_variables_vbm;
use vars qw($Hf $recon_machine $project_name);
#my $do_connectivity=1; ### ONLY TEMPORARY--SHOULD BE DELETED ASAP!!!!
#my $eddy_current_correction=1; ### ONLY TEMPORARY--SHOULD BE DELETED ASAP!!!!



#---------------------
sub pull_civm_tensor_data_Init_check {
#---------------------

    my $init_error_msg='';
    my $message_prefix="$PM initialization check:\n";
    my $log_msg='';
    my $inputs_dir = $Hf->get_value('pristine_input_dir');
    my $decision_whether_or_not_to_run_this_code = $Hf->get_value('do_connectivity');
    if ($decision_whether_or_not_to_run_this_code){
	my $complete_runno_list=$Hf->get_value('complete_comma_list');
	my @array_of_runnos = split(',',$complete_runno_list);
	@array_of_runnos = uniq(@array_of_runnos);
	foreach my $runno (@array_of_runnos) {
	    my $gradient_file='';
	    if (-d $inputs_dir) {
		opendir(DIR, $inputs_dir);
		my @input_files_0= grep(/^($runno).*(gradient_matrix)(\.txt)?$/i ,readdir(DIR));
		$gradient_file = $inputs_dir.'/'.$input_files_0[0];
		if ($gradient_file =~ s/(\/\/)/\//) {}
	    }

	    if ($gradient_file ne '') {
		$Hf->set_value("original_bvecs_${runno}",$gradient_file);
		$log_msg = $log_msg."\tSetting the [presumed] original bvecs for runno \"${runno}\" as ${gradient_file}.\n";
	    }
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
sub find_my_tensor_data {
#---------------------
    my ($local_runno) = @_;

    #  As of 25 April 2017: 
    #  If $recon_machine is set, and a singular and appropriate tensor headfile can be found there, then all data associated with a given runno will
    #  be pulled off of that machine.
    #
    #  Otherwise, the code will search a list of potential recon machines (including atlasdb), noting all the qualifying headfiles that are found.
    #  If only one is found, then that runnos data will be pulled from the corresponding recon machines.
    #  If more than one is found, then an error will be thrown, encouraging the user to clean up the recon stations if they are satisfied with the archived data.
    #  If the archived data is bad, and the user is hoping to use a fresh run of tensor_create, then the appropriate_recon machine will need to be specified.
    #  The downfall of this is that only one recon_machine can be specified at the start of a pipeline run, but can possibly be circumvented by multiple runs.
    #
    #  Note that it is possible to find more than one tensor_create results folder on a machine...the use of wildcards make this somewhat precarious, with no 
    #  current solution.  puller_simple is used, which is believed to find the most recent match of the wildcard search.  If multiple tensor_creates are ran on
    #  the same machine, it might accidentally (and silently) pull unwanted data.  This can also occur when poor runno naming conventions are used, namely when
    #  one runno is an appended version of another runno, e.g. N54321 and N54321_26.  This might lead to pulling N54321_26 when requesting N54321. Don't say you
    #  weren't warned...
 
    
    my @recon_machines = qw(atlasdb
        gluster
        andros
        piper
        delos
        vidconfmac
        crete
        sifnos
        milos
        panorama
        rhodos
        syros
        tinos); # James has a function to automatically compiling a valid list... 

# 10 July 2017: removed naxos temporarily until we better address "dead machine" issue.

    if ((defined $recon_machine) && ($recon_machine ne 'NO_KEY') && ($recon_machine ne '')) {
	unshift(@recon_machines,$recon_machine);
    } else {
	$recon_machine='';
    }
    @recon_machines = uniq(@recon_machines);
    
    
    my $inputs_dir = $Hf->get_value('pristine_input_dir');
    my $message_prefix="vbm_pipeline_workflow.pm::pull_data_for_connectivity::find_my_tensor_data:\n";
    my $message_body='';
    my $error_prefix = "${message_prefix}The following errors were encountered while trying to locate remote tensor  data:\n";
    my $error_body='';
    
    my $log_msg='';
    my $tmp_log_msg='';
    my $local_message_prefix="Attempting to retrieve data for runno: ${local_runno}\n";
    my $error_msg='';
    my $tmp_error_msg='';
    my $tmp_error_prefix = "Error while trying to retrieve data for runno: ${local_runno}\n";
    
    my @tensor_recon_machines;
    my $tensor_recon_machine;
    
    #my $local_message_prefix="Attempting to retrieve data from ${current_recon_machine} for runno: ${local_runno}\n";
    
   # my $look_in_local_folder = 0;
    my $local_folder = "${inputs_dir}/${local_runno}_tmp/";
    
    ## Get tensor and raw headfiles
    my ($tensor_headfile,$raw_headfile);
    my $tensor_headfile_exists = 0;
    my $raw_headfile_exists = 0;
    if (-d $inputs_dir) {
	opendir(DIR, $inputs_dir);
	## Look for local tensor headfile
	my @input_files_1= grep(/^tensor($local_runno).*\.headfile(\.gz)?$/i ,readdir(DIR));
	if ($#input_files_1 > 0) {
	    confess("More than 1 tensor headfile detected for runno \"${local_runno}\"; it appears invalid and/or ambiguous runnos are being used.");
	}
	$tensor_headfile = $input_files_1[0];
	if ((defined $tensor_headfile) && ($tensor_headfile ne '')) {
	    $tensor_headfile_exists=1;
	    $tensor_headfile = "${inputs_dir}/${tensor_headfile}";
	}
    }
    
    my $little_engine_that_did;
    my @possible_tensor_recon_machines;
    if ($tensor_headfile_exists) {
	## Pull out engine name, and to list of possible locations to look for data, after glusterspace and atlasdb;
	my $temp_tensor_Hf = new Headfile ('rw', $tensor_headfile);
	my $msg_1 = "tensor headfile = ${tensor_headfile}\n";
	printd(30,$msg_1); # At the threshold of still printing, but almost clucking.
	$temp_tensor_Hf->read_headfile;
	$little_engine_that_did = $temp_tensor_Hf->get_value('engine');
	if ($little_engine_that_did eq 'NO_KEY') {
	    $little_engine_that_did = $temp_tensor_Hf->get_value('engine-computer-name');
	}
	my $msg_2 = "little engine that did = ${little_engine_that_did}\n";
	printd(30,$msg_2);

	@possible_tensor_recon_machines = ('gluster',$little_engine_that_did,'atlasdb'); # 10 July 2017: reversed order of importance
	if ((defined $recon_machine) && ($recon_machine ne 'NO_KEY') && ($recon_machine ne '')) {
	    unshift(@possible_tensor_recon_machines,$recon_machine);
	}
	@possible_tensor_recon_machines = uniq(@possible_tensor_recon_machines);
    } else {
	@possible_tensor_recon_machines = @recon_machines;
    }
    
    
    my @original_tensor_headfiles;
    my @temp_tensor_headfiles;
    
    ## Cycle through possible locations until we successfully pull in a tensor headfile, while noting location of data.
    foreach my $current_recon_machine (@possible_tensor_recon_machines){
	#print("searching ${current_recon_machine}...\n");
	my $archive_prefix = '';
	my $machine_suffix = '';		
	if ($current_recon_machine eq 'atlasdb') {
	    $archive_prefix = "${project_name}/research/";
	} else {
	    $machine_suffix = "-DTI-results";
	}
	
	my $pull_headfile_cmd;
	if ($current_recon_machine eq 'gluster') {
	    ## Look for local tensor results directory
	    my $main_dir = "/glusterspace/";
	    if (-d $main_dir) {
		opendir(DIR, $main_dir);
		my @gluster_contents= grep(/^tensor($local_runno).*${machine_suffix}$/i ,readdir(DIR));
		if ($#gluster_contents > -1){
		    for my $current_dir (@gluster_contents) {
			if (-d $current_dir) {
			    push(@tensor_recon_machines,'gluster');
			    
			    $tmp_log_msg = "Tensor_create \"results\" folder for runno \"${local_runno}\" found locally at ${current_dir}\n";
			    $log_msg = $log_msg.$tmp_log_msg;
			    if (! $tensor_headfile_exists) {
				`cp ${current_dir}/tensor${local_runno}*headfile ${inputs_dir}/`;
				my $latest_headfile = `ls -rt ${local_folder}/tensor*headfile | tail -1`;
				chomp($latest_headfile);
				my ($dummy_1,$f,$e) = fileparts($latest_headfile,3);
				my $temp_headfile_name = $local_folder.'/'.$current_recon_machine.'_'.$f.$e;
				`mv ${latest_headfile} ${temp_headfile_name}`;
				push(@original_tensor_headfiles,$latest_headfile);
				push(@temp_tensor_headfiles,$temp_headfile_name);
				$tensor_headfile_exists=1;
				$tensor_headfile = $latest_headfile;
				$tmp_log_msg =$tmp_log_msg."tensor headfile \"${tensor_headfile}\" successfully copied to inputs directory.\n";
			    }
			    
			}
		    }
		} else {
		    $tmp_log_msg = "Unable to find a valid tensor headfile for runno \"${local_runno}\" on machine: ${current_recon_machine}\n\tTrying other locations...\n";
		    $log_msg = $log_msg.$tmp_log_msg;
		}
	    }
	} else {
	    $pull_headfile_cmd = "puller_simple -D 0 -f file -or ${current_recon_machine} ${archive_prefix}tensor${local_runno}*${machine_suffix}/tensor${local_runno}*headfile ${local_folder}/";
	 
	    `${pull_headfile_cmd} 2>&1`;
	    my $unsuccessful_pull_of_tensor_headfile = $?;
	    #print "\$unsuccessful_pull_of_tensor_headfile = ${unsuccessful_pull_of_tensor_headfile}\n\n";
	    if ($unsuccessful_pull_of_tensor_headfile) {
		$tmp_log_msg = "Unable to find a valid tensor headfile for runno \"${local_runno}\" on machine: ${current_recon_machine}\n\tTrying other locations...\n";
		$log_msg = $log_msg.$tmp_log_msg;
		#print "Puller command =\n${pull_headfile_cmd}\n\n${tmp_log_msg}\n\n\n";
	    } else {
	       	push(@tensor_recon_machines,$current_recon_machine);
		my $latest_headfile = `ls -rt ${local_folder}/tensor*headfile | tail -1`;
		chomp($latest_headfile);
		my ($dummy_1,$f,$e) = fileparts($latest_headfile,3);
		my $temp_headfile_name = $local_folder.'/'.$current_recon_machine.'_'.$f.$e;
		`mv ${latest_headfile} ${temp_headfile_name}`;
		push(@original_tensor_headfiles,$latest_headfile);
		push(@temp_tensor_headfiles,$temp_headfile_name);
		
		$tensor_headfile = $temp_headfile_name;#temp solution only !!!
 
		$tmp_log_msg = "Tensor headfile for runno \"${local_runno}\" found on machine: ${current_recon_machine}\n";
		$log_msg = $log_msg.$tmp_log_msg;
	    }
	}	
    }
    print "${tensor_headfile}\n\n";
    my $pos;
    if ((! defined $tensor_headfile) || ($tensor_headfile eq '')) {
	$tmp_error_msg = "No proper tensor headfile found ANYWHERE for runno: \"${local_runno}\".\n";
	$error_msg = $error_msg.$tmp_error_msg;
	$tensor_recon_machine='';
#	print "NO Tensor found anywhere...\n\n\n";
    } elsif ((@tensor_recon_machines) && ($#tensor_recon_machines > 0) && (($recon_machine eq '') || ($recon_machine eq 'NO_KEY'))) {
	$tmp_error_msg = "Multiple tensor headfiles found for runno: \"${local_runno}\" on these machines:\n";
	$error_msg = $error_msg.$tmp_error_msg;
	for (@tensor_recon_machines) {
	    $error_msg=$error_msg."\t$_\n";
	}
	$tmp_error_msg = "If this data has been satisfactorally archived, please clean up the corresponding folders and files on the workstations.\n".
	    "Otherwise, you may be able to successfully pull the data by setting the variable \$recon_machine to the machine where the desired data lives,".
	    " and then running again.\n";
	$error_msg = $error_msg.$tmp_error_msg;
    } elsif ($#tensor_recon_machines == 0) {
	#$tmp_log_msg = "Only one tensor headfile for  runno \"${local_runno}\" was found on ${tensor_recon_machines}[0]\n\tAny missing data will be pulled from here.\n";
	$tmp_log_msg = "Only one tensor headfile for runno \"${local_runno}\" was found on ${tensor_recon_machines[0]}\n\tAny missing data will be pulled from here.\n";
	$log_msg = $log_msg.$tmp_log_msg;
	$pos = 0;
	$tensor_recon_machine = $tensor_recon_machines[0];
    } elsif (($recon_machine ne '') && ($recon_machine ne 'NO_KEY')) {
	#$pos = grep { $tensor_recon_machines[$_] eq "${recon_machine}" } 0..$#tensor_recon_machines;
	$pos = first_index { /${recon_machine}/ } @tensor_recon_machines;
	$tensor_recon_machine =  $tensor_recon_machines[$pos];
	$tmp_log_msg = "A tensor headfile for runno \"${local_runno}\" was found on \$recon_machine ${tensor_recon_machine}\n\tAny missing data will be pulled from here.\n";
	$log_msg = $log_msg.$tmp_log_msg;
    }
	
    if (defined $pos) {
	my ($dummy_1,$f,$e) = fileparts($original_tensor_headfiles[$pos],3);
	$tensor_headfile = "${inputs_dir}/${f}${e}";
	my $temp_file = $temp_tensor_headfiles[$pos];
	`mv  ${temp_file} ${tensor_headfile}`;
	$tmp_log_msg = "Tensor headfile for runno \"${local_runno}\" is: ${tensor_headfile}\n";
	$log_msg = $log_msg.$tmp_log_msg;
    }
    
    if ( -d $local_folder) {
	`rm -r ${local_folder}`;
    }

    if ($log_msg ne '') {
	$message_body=$message_body."\n".$local_message_prefix.$log_msg;
    }
    if ($error_msg ne '') {
	$error_body=$error_body."\n".$tmp_error_prefix.$error_msg;
    }
    return($tensor_headfile,$tensor_recon_machine,$log_msg,$error_msg);

}
#---------------------
sub pull_civm_tensor_data {
#---------------------
    my @recon_machines = qw(atlasdb
        gluster
        andros
        piper
        delos
        vidconfmac
        crete
        sifnos
        milos
        panorama
        rhodos
        syros
        tinos); # James has a function to automatically compiling a valid list... 
    
# 10 July 2017: removed naxos temporarily until we better address "dead machine" issue. 

    if ((defined $recon_machine) && ($recon_machine ne 'NO_KEY') && ($recon_machine ne '')) {
	unshift(@recon_machines,$recon_machine);
    }
    @recon_machines = uniq(@recon_machines);

    my $complete_runno_list=$Hf->get_value('complete_comma_list');
    my @array_of_runnos = split(',',$complete_runno_list);
    @array_of_runnos = uniq(@array_of_runnos);
    my $complete_channel_list=$Hf->get_value('channel_comma_list');
    my @array_of_channels = split(',',$complete_channel_list);
    
    my %where_to_find_tensor_data;

    my $inputs_dir = $Hf->get_value('pristine_input_dir');
    my $message_prefix="vbm_pipeline_workflow.pm::pull_data_for_connectivity:\n";
    my $message_body='';
    my $error_prefix = "${message_prefix}The following errors were encountered while trying to retrieve remote tensor data:\n";
    my $error_body='';
    foreach my $runno (@array_of_runnos) { 
	my $log_msg='';
	my $tmp_log_msg='';
	my $local_message_prefix="Attempting to retrieve data for runno: ${runno}\n";
	my $error_msg='';
	my $tmp_error_msg='';
	my $tmp_error_prefix = "Error while trying to retrieve data for runno: ${runno}\n";

	print "${local_message_prefix}";

	my $look_in_local_folder = 0;
	my $local_folder = "${inputs_dir}/${runno}_tmp2/";
	
	my $tensor_headfile;

	if ($do_connectivity) {
	    ## Look for local tensor headfile
	    if (-d $inputs_dir) {
		opendir(DIR, $inputs_dir);	
		my @input_files_1= grep(/^tensor($runno).*\.headfile(\.gz)?$/i ,readdir(DIR));
		if ($#input_files_1 > 0) {
		    $tmp_error_msg = "More than 1 tensor headfile detected for runno \"${runno}\"; it appears invalid and/or ambiguous runnos are being used.\n";
		    $error_msg = $error_msg.$tmp_error_msg;
		}
		$tensor_headfile = $input_files_1[0];

		if ((defined $tensor_headfile) && ($tensor_headfile ne '')) {
		    $tensor_headfile = "${inputs_dir}/${tensor_headfile}";
		} else {
		    my ($temp_headfile,$data_home,$find_log_msg,$find_error_msg,$archive_prefix,$machine_suffix) =query_data_home(\%where_to_find_tensor_data,$runno);
		    $log_msg=$log_msg.$find_log_msg;
		    $error_msg=$error_msg.$find_error_msg;
		    $tensor_headfile= $temp_headfile;
		}
	    }

	    my $gradient_file;
	    if (($tensor_headfile) && ( -f $tensor_headfile)) {
		my $tensor_Hf = new Headfile ('rw', $tensor_headfile);
		$tensor_Hf->read_headfile;
		# 10 April 2017, BJA: it's too much of a hassle to pull the bvecs file then try to figure out how to incorporate the bvals...
		#     From now on we'll process these ourselves from the tensor headfile.
		
		my $original_gradient_location = $tensor_Hf->get_value('dti-recon-gradmat-file'); ## Unsure if this will work for Bruker...
		my ($o_grad_path,$grad_filename,$grad_ext) = fileparts($original_gradient_location,2);
		my $gradient_file = "${inputs_dir}/${runno}_${grad_filename}${grad_ext}";
		my ($num_bvecs,$v_dim,@Hf_gradients);
		my $raw_headfile;
		if (data_double_check($gradient_file)) {
		    ## Look for local raw headfile
		    if (-d $inputs_dir) {
			opendir(DIR, $inputs_dir);
			my @input_files_2= grep(/^($runno).*\.headfile(\.gz)?$/i ,readdir(DIR));
			if ($#input_files_2 > 0) {
			    $tmp_error_msg = "More than 1 raw headfile detected for runno \"${runno}\"...". 
				"\tIt appears invalid and/or ambiguous runnos are being used. BEHAVE YOURSELF!";
			    $error_msg=$error_msg.$tmp_error_msg;
			}
			$raw_headfile = $input_files_2[0];
			if ((defined $raw_headfile)&& ($raw_headfile ne '')) {
			    $raw_headfile = "${inputs_dir}/${raw_headfile}";
			} else {
			    my $raw_machine_found=0;		    
			    ##Cycle through possible locations until we successfully pull in a raw headfile, while noting location of data.
			    foreach my $current_recon_machine (@recon_machines){
				if (! $raw_machine_found) {
				    my $archive_prefix_or_runno = $runno."/";
				    if ($current_recon_machine eq 'atlasdb') {
					$archive_prefix_or_runno = "${project_name}/";
				    }
				
				    my $pull_headfile_cmd;
				    if ($current_recon_machine eq 'gluster') {
					## Look for local tensor results directory
					my $main_dir = "/glusterspace/";
					if (-d $main_dir) {
					    opendir(DIR, $main_dir);
					    my @gluster_contents= grep(/^($runno).*$/i ,readdir(DIR));
					    for my $current_dir (@gluster_contents) {
						if (-d $current_dir) {
						    #$raw_recon_machine = 'gluster';
						    $raw_machine_found = 1;
						    $tmp_log_msg = "Raw recon folder for runno \"${runno}\" found locally at ${current_dir}\n";
						    
						   # my $input_headfile = `ls -t ${current_dir}/${runno}*headfile | tail -1`;
						    my $input_headfile = `ls -rt ${current_dir}/${runno}*/${runno}*/${runno}*headfile | head -1`;
						    chomp($input_headfile);
						    `cp ${input_headfile} ${inputs_dir}/`;
						    $raw_headfile = `ls -t ${inputs_dir}/${runno}*headfile | head -1`; 
						    chomp($raw_headfile);
						    if ($raw_headfile !~ /"no such file"/) { 
							$raw_machine_found=1;
							$tmp_log_msg =$tmp_log_msg."raw headfile \"${raw_headfile}\" successfully copied to inputs directory.\n";
						    } else {
							$tmp_log_msg = $tmp_log_msg."Unable to find a valid raw headfile for runno \"${runno}\" ".
							    "in ${current_dir}\n\tTrying other locations...\n";
						    }
						}
						$log_msg = $log_msg.$tmp_log_msg;
					    }
					}
					
				    } else {
					$pull_headfile_cmd = "puller_simple -D 0 -f file -or ${current_recon_machine} ${archive_prefix_or_runno}${runno}*/${runno}*headfile ${inputs_dir}/";
					 `${pull_headfile_cmd} 2>&1`;
					my $unsuccessful_pull_of_raw_headfile = $?;
					if ($unsuccessful_pull_of_raw_headfile) {
					    $tmp_log_msg = $tmp_log_msg."Unable to find a valid raw headfile for runno \"${runno}\" on machine:".
						" ${current_recon_machine}\n\tTrying other locations...\n";
					    $log_msg = $log_msg.$tmp_log_msg;
					} else {
					    $raw_machine_found = 1;
					    #$raw_headfile = `ls -rt ${inputs_dir}/${runno}*headfile | tail -1`;
					    $raw_headfile = `ls -t ${inputs_dir}/${runno}*headfile | head -1`;
					    chomp($raw_headfile);
					    $tmp_log_msg = $tmp_log_msg."Raw headfile for runno \"${runno}\"found on machine: ${current_recon_machine}\n.\n";
					    $log_msg = $log_msg.$tmp_log_msg;
					}
				    }
				}
			    }
			}
		    }
			
		    if (($raw_headfile eq '') || (! defined $raw_headfile)) {
			$tmp_log_msg = "No proper raw headfile found ANYWHERE for runno: \"${runno}\".\n".
			    "\tWill attempt to use tensor headfile instead: ${tensor_headfile}";
			$log_msg = $log_msg.$tmp_log_msg;
		    }
		
		
		    if ( -f $raw_headfile) {
			($num_bvecs,$v_dim,@Hf_gradients) =  build_bvec_array_from_raw_headfile($raw_headfile);
		    } else{
			# This code is based on the shenanigans of tensor_create, as found in main_tensor.pl
			my $Hf_grad_info =  $tensor_Hf->get_value("gradient_matrix_auto");
			#parse bvecs
			if ($Hf_grad_info ne 'NO_KEY'){
			    my ($grad_dim_info,$Hf_grad_string) = split(',',$Hf_grad_info);
			    @Hf_gradients = split(' ',$Hf_grad_string);
			    ($num_bvecs,$v_dim) = split(':',$grad_dim_info);
			}
		    }		
		    
		    if ((defined $num_bvecs) && ($num_bvecs > 6)) {
			#parse bvals
			my $Bruker_data = 0; ### Temporarily only supporting Agilent data!
			
			my $approx_Hf_bval_handle='';
			my $Hf_bval_handle='';
			if (! $Bruker_data) { # Right now (06 April 2017) we're assuming Agilent data
			    $approx_Hf_bval_handle = "z_Agilent_bvalue";
			}
			my $Hf_bval_info = $tensor_Hf->get_value_like($approx_Hf_bval_handle);
			my ($bval_dim_info,$Hf_bval_string) = split(',',$Hf_bval_info);
			my @Hf_bvals = split(' ',$Hf_bval_string);
			my ($num_bvals,$bval_dim) = split(':',$bval_dim_info);
			my $single_bval =0;
			if (($num_bvals eq 'NO_KEY') || ($num_bvals eq '') || ($num_bvals != $num_bvecs)) { # If stuff blows up, let's default to assuming a single max_bvalue
			    $single_bval=1;
			    $approx_Hf_bval_handle = "max_bval";
			    $Hf_bval_info = $tensor_Hf->get_value_like($approx_Hf_bval_handle);
			    if ($Hf_bval_info eq 'NO_KEY') {
				$approx_Hf_bval_handle = "maxB-value";
				$Hf_bval_info = $tensor_Hf->get_value_like($approx_Hf_bval_handle);
			    }
			    $Hf->set_value("max_bvalue_${runno}",$Hf_bval_info);
			}
			
			## combine bvals and bvecs into one table
			
			my @gradient_matrix;
			for (my $bb=0;($bb < $num_bvecs); $bb++) {
			    $tmp_log_msg = "Creating combined bval/bvec b-table from headfile: ${tensor_headfile}.";
			    $log_msg = $tmp_log_msg;
			    
			    my @temp_array;
			    my $nonzero_test = 0;
			    for (my $ii=0; ($ii < $v_dim); $ii++) {
				my $temp_val = shift(@Hf_gradients);
				push(@temp_array,$temp_val);
				if (! $nonzero_test) {
				    if ($temp_val ne '0') { # We are assuming that zero will always be stored in headfile as '0' (nor '0.0', '0.000', etc.
					$nonzero_test = 1;
				    }
				}
			    }
			    my $current_bval=0;
			    if ($single_bval) {
				if ($nonzero_test) {
				    $current_bval = $Hf_bval_info;
				}
			    } else {
				my $new_bval = shift(@Hf_bvals);
				if ($nonzero_test) {
				    $current_bval = $new_bval;
				}
			    }
			    
			    my $b_string = join(', ',($current_bval,@temp_array));
			    push(@gradient_matrix,$b_string."\n");
			    $tmp_log_msg = ".";
			    $log_msg = $tmp_log_msg;
			}
			write_array_to_file($gradient_file,\@gradient_matrix);
			$tmp_log_msg = "\nDone creating b-table: ${gradient_file} for ${num_bvecs} bval/bvec entries.\n";
			$log_msg = $tmp_log_msg;
		    }	
		}
		
		$Hf->set_value("original_bvecs_${runno}",$gradient_file);
	    } else {
		$tmp_error_msg = "No tensor headfile could be found for runno \"${runno}\"...".
		    "\tUnable to determine what gradient matrix to look for, and therefore the gradient table may have not been created,".
		    "and certainly hasn't been recorded for future processing.\n";
		$error_msg = $tmp_error_msg;
	    }
	}
	
	## With proper headfiles in hand, try to pull/copy data from appropriate sources
	
	# Look for more then two xform_$runno...mat files (ecc affine transforms)
	if ($do_connectivity){
	    if ((defined $eddy_current_correction) && ($eddy_current_correction ne 'NO_KEY') && ($eddy_current_correction == 1)) {
		my $temp_runno = $runno;
		if ($temp_runno =~ s/(\_m[0]+)$//){}
		my $number_of_ecc_xforms =  `ls ${inputs_dir}/xform_${temp_runno}*.mat | wc -l`;
		
		print "number_of_ecc_xforms = ${number_of_ecc_xforms}\n\n";
		if ($number_of_ecc_xforms < 6) { # For DTI, the minimum number of non-b0's is 6!
		    my ($dummy_headfile,$data_home,$find_log_msg,$find_error_msg,$archive_prefix,$machine_suffix) =  query_data_home(\%where_to_find_tensor_data,$runno);
		    $log_msg=$log_msg.$find_log_msg;
		    $error_msg=$error_msg.$find_error_msg;
		    my $pull_folder_cmd;
		    if ($data_home eq 'gluster') {
			$pull_folder_cmd = "cp /glusterspace/tensor${runno}*${machine_suffix}/* ${local_folder}/";
		    } else {
			$pull_folder_cmd = "puller_simple  -or ${data_home} ${archive_prefix}tensor${runno}*${machine_suffix}/ ${local_folder}/";
		    }
		    `${pull_folder_cmd} 2>&1`;
		    my $unsuccessful_flag = $?;
		    $tmp_log_msg = "Pulling tensor results folder for runno \"${runno}\" with command:\n\t${pull_folder_cmd}\n";
		    $log_msg = $log_msg.$tmp_log_msg;
		    if ($unsuccessful_flag) {
			$tmp_log_msg = "\tTensor results folder was NOT successfully copied to the inputs directory!\n";
			$log_msg = $log_msg.$tmp_log_msg;

			$tmp_error_msg=$tmp_log_msg;
			$error_msg = $tmp_error_msg;
		    } else {
			my $mv_folder_cmd = "mv ${local_folder}/xform*mat ${inputs_dir}";
			`${mv_folder_cmd} 2>&1`;
			$tmp_log_msg = "\tTensor results folder was SUCCESSFULLY copied to the inputs directory!\n";
			$log_msg = $log_msg.$tmp_log_msg;
			$look_in_local_folder = 1;
		    }
		}
	    }
	}
	
	# get any specified "traditional" dti images
	foreach my $contrast (@array_of_channels) {
	    my $test_file =  get_nii_from_inputs($inputs_dir,$runno,$contrast);
	    my $pull_file_cmd='';
	    
	    if ($test_file =~ /[\n]+/) {
		if ($look_in_local_folder) {
		    $test_file =  get_nii_from_inputs($local_folder,$runno,$contrast);
		    if ($test_file =~ /[\n]+/) {

			my ($dummy_headfile,$data_home,$find_log_msg,$find_error_msg,$archive_prefix,$machine_suffix) = query_data_home(\%where_to_find_tensor_data,$runno);

			if ($contrast eq 'tensor') {
			    if ($machine_suffix =~ s/results/work/) {}
			}

			$log_msg=$log_msg.$find_log_msg;
			$error_msg=$error_msg.$find_error_msg;
		
			if ($data_home eq 'gluster') {
			    $pull_file_cmd = "cp /glusterspace/tensor${runno}*${machine_suffix}/${runno}*${contrast}.nii* ${inputs_dir}/";
			} else {
			    $pull_file_cmd = "puller_simple -f file -or ${data_home} ${archive_prefix}tensor${runno}*${machine_suffix}/${runno}*${contrast}.nii* ${inputs_dir}/";
			}
			`${pull_file_cmd} 2>&1`;
			
			#$log_msg = $log_msg.$tmp_log_msg;
		    } else {
			$pull_file_cmd = "mv ${test_file} ${inputs_dir}/";
			`${pull_file_cmd} 2>&1`;
			#$tmp_log_msg = `mv ${test_file} ${inputs_dir}`;
			#$log_msg = $log_msg.$tmp_log_msg;
		    }
		} else {
		    my ($dummy_headfile,$data_home,$find_log_msg,$find_error_msg,$archive_prefix,$machine_suffix) =query_data_home(\%where_to_find_tensor_data,$runno);
		    $log_msg=$log_msg.$find_log_msg;
		    print($find_log_msg."\n\n");#####
		    $error_msg=$error_msg.$find_error_msg;
		    if ($data_home eq 'gluster') {
			$pull_file_cmd = "cp /glusterspace/tensor${runno}*${machine_suffix}/${runno}*${contrast}.nii* ${inputs_dir}/";
		    } else {
			$pull_file_cmd = "puller_simple -f file -or ${data_home} ${archive_prefix}tensor${runno}*${machine_suffix}/${runno}*${contrast}.nii* ${inputs_dir}/";
		    }
		    `${pull_file_cmd} 2>&1`;
		    #if ($data_home eq 'gluster') {
			#$tmp_log_msg = `cp /glusterspace/tensor${runno}*${machine_suffix}/${runno}*${contrast}.nii* ${inputs_dir}/`;
		    #} else {
		        #$pull_file_cmd = "puller_simple -f file -or ${data_home} ${archive_prefix}tensor${runno}*${machine_suffix}/${runno}*${contrast}.nii* ${inputs_dir}/";
			#$tmp_log_msg = `${pull_file_cmd}`;
		    #}
		    #$log_msg = $log_msg.$tmp_log_msg;
		}
	    }
	}
	
	if ($do_connectivity){
	    # get nii4D
	    my $nii4D = get_nii_from_inputs($inputs_dir,$runno,'nii4D');
	    my $orig_nii4D;
	   
	    if ($nii4D =~ /[\n]+/) {
		$orig_nii4D =  get_nii_from_inputs($inputs_dir,'nii4D',$runno); # tensor_create outputs nii4D_$runno.nii.gz
		if ($orig_nii4D =~ /[\n]+/) {
		    my $pull_nii4D_cmd;#(see below) Removed * after .nii so we don't accidentally pull fiber tracking results.  Let's just hope what we want is uncompressed. 11 April 2017, BJA
		    if ($look_in_local_folder) {
			my $test_file =  get_nii_from_inputs($local_folder,'nii4D',$runno);
			if ($test_file =~ /[\n]+/) {
			    my ($dummy_headfile,$data_home,$find_log_msg,$find_error_msg,$archive_prefix,$machine_suffix) = query_data_home(\%where_to_find_tensor_data,$runno);
			    $log_msg=$log_msg.$find_log_msg;
			    $error_msg=$error_msg.$find_error_msg;
			    
			    if ($data_home eq 'gluster') {
				$pull_nii4D_cmd= `cp /glusterspace/tensor${runno}*${machine_suffix}/nii4D_${runno}*.nii* ${inputs_dir}/`;		      
			    } else {
				$pull_nii4D_cmd = "puller_simple -f file -or ${data_home} ${archive_prefix}/tensor${runno}*${machine_suffix}/nii4D_${runno}*.nii ${inputs_dir}/";
			    }
			    `${pull_nii4D_cmd} 2>&1`;
			} else {
			    my $mv_cmd = "mv ${test_file} ${inputs_dir}";
			    `${mv_cmd} 2>&1`;
			}
		    } else {
			my ($dummy_headfile,$data_home,$find_log_msg,$find_error_msg,$archive_prefix,$machine_suffix) = query_data_home(\%where_to_find_tensor_data,$runno);
			$log_msg=$log_msg.$find_log_msg;
			$error_msg=$error_msg.$find_error_msg;
			if ($data_home eq 'gluster') {
			    $pull_nii4D_cmd= `cp /glusterspace/tensor${runno}*${machine_suffix}/nii4D_${runno}*.nii* ${inputs_dir}/`;		      
			} else {
			    $pull_nii4D_cmd = "puller_simple -f file -or ${data_home} ${archive_prefix}/tensor${runno}*${machine_suffix}/nii4D_${runno}*.nii ${inputs_dir}/";
			}
			`${pull_nii4D_cmd} 2>&1`;
			# if ($data_home eq 'gluster') {
			#     $tmp_log_msg = `cp /glusterspace/tensor${runno}*${machine_suffix}/nii4D_${runno}*.nii* ${inputs_dir}/`;
			# } else {
			#     $pull_nii4D_cmd = "puller_simple -f file -or ${data_home} ${archive_prefix}/tensor${runno}*${machine_suffix}/nii4D_${runno}*.nii ${inputs_dir}/";
			#     $tmp_log_msg = `${pull_nii4D_cmd}`;
			# }
			# $log_msg = $log_msg.$tmp_log_msg;
		    }
		}
		$orig_nii4D =  get_nii_from_inputs($inputs_dir,'nii4D',$runno); # tensor_create outputs nii4D_$runno.nii.gz
		#print "third nii4D = ${orig_nii4D}\n\n";
		if ($orig_nii4D !~ /[\n]+/) {
		    my $new_nii4D = "${inputs_dir}/${runno}_nii4D.nii";
		    if ($orig_nii4D =~ /'.gz'/) {
			$new_nii4D = $new_nii4D.'.gz';
		    }
		    $tmp_log_msg = `mv ${orig_nii4D} ${new_nii4D}`;
		    $log_msg = $log_msg.$tmp_log_msg;
		} else {
		    $error_msg = $error_msg."Despite best efforts, unable to produce a nii4D for runno \"${runno}\"\n";
		}
	    }
	}
	# Clean up temporary results folder
	if ($look_in_local_folder) {
	    if ( -d $local_folder) {
		`rm -r ${local_folder}`;
	    }
	}
	
	if ($log_msg ne '') {
	    $message_body=$message_body."\n".$local_message_prefix.$log_msg;
	}
	if ($error_msg ne '') {
	    $error_body=$error_body."\n".$tmp_error_prefix.$error_msg;
	}	
    }
    
    if ($message_body ne '') {
	log_info("${message_prefix}${message_body}");
    }
    
    if ($error_body ne '')  {
	error_out("${error_prefix}${error_body}");
    }
    #`rm ${inputs_dir}/._*`; # James fixed this bug on 24 April 2017
}

#---------------------
sub  build_bvec_array_from_raw_headfile{ # Code extracted and lightly adapted from diffusion/tensor_pipe/main_tensor.pl, 24 April 2017, BJA
#---------------------
    my ($input_headfile,$data_prefix) =@_;
    if (! defined $data_prefix) {
	$data_prefix = 'z_Agilent_';
    }
    
    my $grad_max=0; 
    my $grad_min=100000000000000;
    my $n_Bvalues;
    my @Hf_gradients;
    my $vector_dimension = 3; # We will assume 3D vectors
    
    #print "Opening input data headfile: ${input_headfile}\n";
    my $HfInput = new Headfile ('ro', $input_headfile);
    if (! $HfInput->check)         {error_out("Problem opening input runno headfile; ${input_headfile}");}
    
    if (! $HfInput->read_headfile) {error_out("Could not read input runno headfile: ${input_headfile}");}
    #$HfInput->print_headfile();
    print "input headfile = $input_headfile\n\n\n";
    if ( $HfInput->get_value_like("${data_prefix}dro") !~ "(NO_KEY|UNDEFINED_VALUE|EMPTY_VALUE)" )  {
	if ( $HfInput->get_value_like("${data_prefix}array") ne '(dro,dpe,dsl)' ) {
	    error_out('Agilent gradient table may not be in proper format, NOTIFIY JAMES');
	}
	#vector data format, dim1:dim2:dimn, data1 data2 datan[:NEWLINE:]

	my ($xd,$yd,$zd);
	my ($xv,$yv,$zv);
	my (@xva,@yva,@zva);
	($xd,$xv)=split(',',$HfInput->get_value_like("${data_prefix}dro"));
	($yd,$yv)=split(',',$HfInput->get_value_like("${data_prefix}dpe"));
	($zd,$zv)=split(',',$HfInput->get_value_like("${data_prefix}dsl"));
	@xva=split(' ',$xv);
	@yva=split(' ',$yv);
	@zva=split(' ',$zv);

	$n_Bvalues = $#xva + 1;

	if ( (reduce { $a * $b } 1,split(':',$xd)) !=($#xva+1) 
	     || (reduce { $a * $b } 1,split(':',$yd)) !=($#yva+1) 
	     || (reduce { $a * $b } 1,split(':',$zd)) !=($#zva+1) ) {
	    my@nvals;
	    push(@nvals,reduce { $a * $b } 1,split(':',$xd));
	    push(@nvals,reduce { $a * $b } 1,split(':',$yd));
	    push(@nvals,reduce { $a * $b } 1,split(':',$zd));
	    my @elem;
	    push(@elem,$#xva+1);
	    push(@elem,$#yva+1);
	    push(@elem,$#zva+1);
	    error_out("Did not get agilent table properly ".join(" ",@nvals)." doesnt match ".join(" " ,@elem));
	}
	for(my $i=0;$i<$n_Bvalues;$i++){
	    my ($xg,$yg,$zg)=-1;
	    $xg=$xva[$i];
	    $yg=$yva[$i];
	    $zg=$zva[$i];
	    push(@Hf_gradients,($xg, $yg, $zg));
	    my $min_v=min( (abs($xg), abs($yg), abs($zg) ) );
	    if ($min_v<$grad_min){$grad_min=$min_v;}
	    my $max_v=max( (abs($xg), abs($yg), abs($zg) ) );
	    if ($max_v>$grad_max){$grad_max=$max_v;}
	}
    } else {
	error_out("Did not find Agilent variable \"${data_prefix}dro\"".$HfInput->get_value_like("${data_prefix}dro") ) ;
    }		

    return ($n_Bvalues,$vector_dimension,@Hf_gradients);    
}

#---------------------
sub query_data_home{
#---------------------
   my ($home_array_ref,$runno)=@_;
   my $data_home;
   my $log_msg='';
   my $find_error_msg='';
   my $found_headfile;
   if ( exists $home_array_ref->{$runno}) {
       $data_home = $home_array_ref->{$runno};
  #if ( exist $home_array_ref => {$runno}) {
  #     $data_home = $home_array_ref => {$runno};
       $log_msg = "For runno \"${runno}\", retrieving tensor data from machine: ${data_home}.\n";
   } else {
       $log_msg = "No data home set for runno \"${runno}\"; will attempt to find its remote location.\n";
   }

   if (! defined $data_home) {
       my $find_log_msg='';
       ($found_headfile,$data_home,$find_log_msg,$find_error_msg) = find_my_tensor_data($runno);
       if ($data_home) { # We want to return a defined value, but if it is empty/zero, that means we failed to find what we wanted (as opposed to code failure).
	   $log_msg = $log_msg.$find_log_msg;
	   $home_array_ref->{$runno}=$data_home;
	   $log_msg = $log_msg."Data home found for runno \"${runno}\" on machine \"${data_home}\"\n";
       }
   }
   #print "for some runno, ${runno}: \"".$home_array_ref->{$runno}."\"\n\n";
   #print " this should be \"${data_home}\"\n\n";
   my $archive_prefix = '';
   my $machine_suffix = '';		
   if ($data_home eq 'atlasdb') {
       $archive_prefix = "${project_name}/research/";
   } else {
       $machine_suffix = "-DTI-results";
   }
   return ($found_headfile,$data_home,$log_msg,$find_error_msg,$archive_prefix,$machine_suffix);
}
