#!/usr/bin/false
# set_reference_space_vbm.pm 

#  2015/07/23  BJ Anderson, CIVM -- switched from PrintHeader to fslhd for getting header info, though most of this switch happened in pipeline utilites.
#  2015/03/04  BJ Anderson, CIVM

my $PM = "set_reference_space_vbm.pm";
my $VERSION = "2020/08/12";
my $NAME = "Set the reference spaces to be used for VBM and label analysis.";
my $DESC = "ants";

use strict;
use warnings;
use Scalar::Util qw(looks_like_number);

use civm_simple_util;
use convert_all_to_nifti_vbm;

# 25 June 2019, BJA: Will try to look for ENV variable to set matlab_execs and runtime paths
use Env qw(MATLAB_EXEC_PATH MATLAB_2015b_PATH); 
if (! defined($MATLAB_EXEC_PATH)) {
    $MATLAB_EXEC_PATH =  "/cm/shared/workstation_code_dev/matlab_execs";
}
if (! defined($MATLAB_2015b_PATH)) {
    $MATLAB_2015b_PATH =  "/cm/shared/apps/MATLAB/R2015b/";
}
my $matlab_path = "${MATLAB_2015b_PATH}";

my ($inputs_dir,$pristine_input_dir,$preprocess_dir,$rigid_atlas_name,$rigid_target,$rigid_contrast,$runno_list,$rigid_atlas_path,$original_rigid_atlas_path,$port_atlas_mask);#$current_path,$affine_iter);
my (%reference_space_hash,%reference_path_hash,%input_reference_path_hash,%refspace_hash,%refspace_folder_hash,%refname_hash,%refspace_file_hash);
my ($rigid_name,$rigid_dir,$rigid_ext,$new_rigid_path,$future_rigid_path,$native_ref_name,$translation_dir);
my ($base_images_for_labels);# synonymous with create_labels
my ($log_msg);
my $split_string = ",,,";
my (%file_array_ref,@ref_spaces);
my ($work_to_do_HoA);
my @jobs_1=();
my @jobs_2=();
my $go = 1;
# ref_runno is a multi-level hash, the keys are spaces, the values are runno_hashes.
# runno_hashs are runnos with work to do, and 1 of their image paths which is used 
# to get check if we need a reference space transform, and calculate it.
my %ref_runno_hash;
#my %runno_hash_vba;
#my %runno_hash_label;
my %preferred_contrast_hash;
my $rerun_init_check;

my $img_exec_version='stable';
my $img_transform_executable_path ="${MATLAB_EXEC_PATH}/img_transform_executable/$img_exec_version/run_img_transform_exec.sh";

if (! defined $dims) {$dims = 3;}
if (! defined $ants_verbosity) {$ants_verbosity = 1;}

my $out_ext=".nii.gz";
$out_ext=".nhdr";
# ------------------
sub set_reference_space_vbm {  # Main code
# ------------------
    my $start_time = time;
    set_reference_space_vbm_Runtime_check();

    my $ref_file;
    my $job;
    my @jobs;
    foreach my $space (@ref_spaces) {
        my $work_folder = $refspace_folder_hash{$space};
        my $translation_dir = "${work_folder}/translation_xforms/";
	mkdir ($translation_dir,$permissions) if ! -e $translation_dir;
        $ref_file = $reference_path_hash{$space};
        
        # Hmm, turns out refspace implies this.... 
        my ($v_ok,$data_size)=$Hf->get_value_check("${space}_refsize");
        if(! $v_ok && -e $ref_file ) { 
	    confess "Missing important variable ${space}_refsize";
        }
        my %runno_hash;
        %runno_hash=%{$ref_runno_hash{$space}};
	my $array_ref = $work_to_do_HoA->{$space};
	# for all runnos
	for my $runno (keys %runno_hash) {
	    # First, create the refspacy transform
	    my $in_file = $runno_hash{$runno};
	    my $out_file = "${work_folder}/translation_xforms/${runno}_";#0DerivedInitialMovingTranslation.mat";
	    ($job) = apply_new_reference_space_vbm($in_file,$ref_file,$out_file);
	    my $ref_dep;
	    if ($job) {
		push(@jobs,$job); 
		$ref_dep='afterany:'.$job;
	    }
	    # REALLY the ref file should set the out_ext! 
	    my ($dumdum,$in_name,$in_ext) = fileparts($in_file,2);
	    # second, schedule the apply dependent on transformy being done.
	    my @runno_files=grep /$runno/,@$array_ref;
	    for my $out_file (@runno_files) {
		my ($dumdum,$out_name,$out_ext) = fileparts($out_file,2);
		my $ain_file = "${preprocess_dir}/${out_name}${out_ext}";
		$ain_file = "${preprocess_dir}/${out_name}${in_ext}" if ! -e $ain_file;
		confess "ERROR NO INPUT FILE $ain_file" if ! -e $ain_file;
		($job) = apply_new_reference_space_vbm($ain_file,$ref_file,$out_file,$ref_dep);
		if ($job) {
		    push(@jobs,$job);
		}
	    }
	}
    }
    # All scheduling done.
    if (cluster_check() && (scalar @jobs)) {
        my $interval = 2;
        my $verbose = 1;
        my $done_waiting = cluster_wait_for_jobs($interval,$verbose,@jobs);
        if ($done_waiting) {
            print STDOUT  "  All referencing jobs have completed; moving on to next step.\n";
        } else {
            printd(5,"ERROR on job wait!");
            sleep_with_countdown(3);
        }
    }
    
    foreach my $space (@ref_spaces) {
	# Why is this written to "tmp" first before being moved?
	my $t="${refspace_folder_hash{$space}}/refspace.txt.tmp";
	my $f="${refspace_folder_hash{$space}}/refspace.txt";
	# guard against double refspace.txt 
	if(exists $refspace_file_hash{$f}) {
	    run_and_watch("mv $t $f ");
	    delete $refspace_file_hash{$f};
	}
	# This was a clever Bash syntax chain using ls && gzip but that has proven ugly when debugging
        # Adjusted to be in perl with same idea. 
        # if "ls" command is successful (finds existing items), then executes "gzip" command.
        # "2>" will redirect STDERR to /dev/null (aka nowhere land) so it doesn't spam terminal.
        # While the first inclination is to use run_and_watch, we dont care at all if we succeed or fail here.
        # We only care if there is work found to do, so we'll simply capture output to let this fail quietly.
        #my @gzippable_file=run_and_watch("ls ${refspace_folder_hash{$space}}/*.nii  2> /dev/null","\t",0);
        my @gzippable_file=`ls ${refspace_folder_hash{$space}}/*.nii  2> /dev/null`;
        chomp(@gzippable_file);
        # tests each thing found in gzippable file, but we really only ever run one time
        foreach (@gzippable_file){ 
            if ( $_ ne '' ) {
		log_info("Inline compression of nii extension files in folder ${refspace_folder_hash{$space}}");
                run_and_watch("gzip -v ${refspace_folder_hash{$space}}/*.nii");
                last;
            }
        }
    }
    
    my $case = 2;
    my ($dummy,$error_message)=set_reference_space_Output_check($case);

    my $real_time = vbm_write_stats_for_pm($PM,$Hf,$start_time,@jobs);
    print "$PM took ${real_time} seconds to complete.\n";

    if ($error_message ne '') {
        error_out("${error_message}",0);
    } 
}


# ------------------
sub set_reference_space_Output_check {
# ------------------
    my ($case) = @_;
    my $full_error_msg;
    
    foreach my $space (@ref_spaces) {
        my @file_array;
        my $message_prefix ='';  
        @file_array=();
        my $work_folder = $refspace_folder_hash{$space};
        my $ref_file = $reference_path_hash{$space};
        my $refspace = $refspace_hash{$space};
        print "refspace = $refspace\n";
        my $space_string = $space;
        if ((! $base_images_for_labels) && ($create_labels) && ($space eq 'vbm')) {
            $space_string = "vbm and label";
        }

        if ($case == 1) {
            $message_prefix = "  The following images for ${space_string} analysis in folder ${work_folder} have already been properly referenced\n".
                "and will not be reprocessed :\n";
        } elsif ($case == 2) {
            $message_prefix = "  Unable to properly set the ${space_string} reference \n".
                "\t($refspace)\n".
                "\tfor images in folder ${work_folder}:\n";
        }   # For Init_check, we could just add the appropriate cases.

        my $existing_files_message = '';
        my $missing_files_message = '';

        my @files_to_check;
        my %runno_hash;
        if ($case == 1) {
            print "$PM: Checking ${space} and preprocess folders...";
            #opendir(DIR, $preprocess_dir);
            #@files_to_check = grep(/(\.nii)+(\.gz)*$/ ,readdir(DIR));# @input_files;
            #@files_to_check=sort(@files_to_check);
	    @files_to_check = find_file_by_pattern($preprocess_dir,".*$valid_formats_string\$",1);
	    foreach(@files_to_check){
		$_=basename $_; }
        } else {
            print "$PM: Checking ${space} folder...";
            my $array_ref = $work_to_do_HoA->{$space};
            @files_to_check = @$array_ref;
        }

        foreach my $file (@files_to_check) {
            # it appears like if we're in input mode $file doesnt have a path, 
            # but if we're in output mode it does.
            # That is a special level of unnecessary confusion
            # out_file always has a path to compensate.
            my $out_file;
            if ($case == 1) {
                # $in_file = $preprocess_dir.'/'.$file;
                $out_file = $work_folder.'/'.$file;
                # The snippet of regex below will find 0 or 1 instances of '.gz' 
                # at the end of the filename, and 'replace' it with '.gz.
                # Functionally, this will just add '.gz.' to any un-gzipped files
                # In this case, the we are looking for an output file (which will ALWAYS be gzipped)
                # that corresponds to an input file that may or may not be gzipped.
		$out_file =~ s/(\.gz)?$/\.gz/ if $out_file =~ /nii/x;
            } else {
                $out_file = $file;
            }
            printd(1,".");
            
	    carp("WARNING: double_check temporarily disabled");
            #if (data_double_check($out_file,$case-1)) { 
	    if (data_double_check($out_file,0)) { 
                # Outfile not found.
                if ($case == 1) {
                    # Input mode because we didnt try to do this yet.
                    # Add first file found to runno_hash.
                    # print "\n${out_file} added to list of files to be re-referenced.\n";
                    my $temp_var = $file;
                    if ($temp_var =~ s/(_masked)//i){}
                    if ($temp_var =~ /^([^\.]+)_([^_\.])+\..+/) { 
                        # Split file into RUNNO_contrast, 
                        # (Only takes last _ -> end for contrast. 
                        # We could improve that by forcing runnos to not have underscores in them.
                        # This is made harder by virtue of tacking a gz on everything
                        # We dont use contrast so commenting that out.
                        # This is part of the general trouble of runno as specid this pipeline has.
                        my $runno = $1;
                        #my $contrast = $2;
                        if (! defined $runno_hash{$runno}) {
                            $runno_hash{$runno}= $preprocess_dir.'/'.$file;
                        }
                    }
                }
                push(@file_array,$out_file);
                my ($tp,$tn,$te)=fileparts($file,2);
                $missing_files_message = $missing_files_message."   Missing: $tn$te\n";
            } elsif (! compare_two_reference_spaces($out_file,$refspace)) {
                print "\n${out_file} added to list of files to be re-referenced.\n";
                push(@file_array,$out_file);
                my ($tp,$tn,$te)=fileparts($file,2);
                $missing_files_message = $missing_files_message."   Inconsistent ref: $tn$te\n:        $input_reference_path_hash{$space}\n";
            } else {
                $existing_files_message = $existing_files_message."   $file\n";
            }
        }
        print("\n");
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
        $file_array_ref{$space} = \@file_array;
        
        if ($case == 1) {
            $ref_runno_hash{$space}=\%runno_hash;
        }

        # THIS IS DOING WORK IN A CHECK FUNCTION THAT IS VERY NAUGHTY.
        if ($case == 2) {
            # James's highly suspecs that we didnt do slow disk checking for the results 
            # of this we were at the mercy of slow disk problems due to this cleanup.
            # So, all the better to throw this out, many parts have been made more
            # symbolic link friendly, and as such this is less and less useful. 
            # (not that he'll ever admit it was useful :p ) 
            carp("Symbolic link cleanup skipped on $refspace_folder_hash{$space}");
            #symbolic_link_cleanup($refspace_folder_hash{$space},$PM);
        }
    }
    return(\%file_array_ref,$full_error_msg);
}

# ------------------
sub get_translation_xform_to_ref_space_vbm {
# ------------------

    my ($in_file,$ref_file,$out_file)=@_;

}

# ------------------
sub apply_new_reference_space_vbm {
# ------------------
    my ($in_file,$ref_file,$out_file,$dependency)=@_;

    # Do reg is off for any output images
    # HANDLED PER the out_file conditional below.
    my $do_registration = 1; 
    
    my $test_dim = 3;
    my $opt_e_string='';
    if ($out_file =~ m/.*[.]($valid_formats_string)$/x) {
	my @hdr=ants::PrintHeader($in_file);
	my @dim_lines=grep /[\s]+dim\[[0-7]\]/x, @hdr;
	($test_dim = $dim_lines[0]) =~ /.*=[\s]*([0-9]+)[\s*]/x;
	my @dims=split(' ',get_image_dims($in_file));
	if ($test_dim > 3 && scalar(@dims) > 3) {
	    $opt_e_string = ' -e 3 ';
	}
        if ($in_file =~ /tensor/) {
            # Testing value for -f option, as per https://github.com/ANTsX/ANTs/wiki/Warp-and-reorient-a-diffusion-tensor-image
            $opt_e_string = ' -e 2 -f 0.00007'; 
        }
        $do_registration = 0;
    }
    my $interp = "Linear"; # Default    
    my $in_spacing = get_spacing_from_header($in_file);
    my $ref_spacing = get_spacing_from_header($ref_file);
    if ($in_spacing eq $ref_spacing
	|| $in_file =~ /(mask|Mask|MASK)\./) {
        $interp = "NearestNeighbor";
    }
    # CMD appears to be run when cluster
    # @cmds appears to be run when not cluster.
    my $cmd='';
    # CMD_SEP is a temp measure for conjoining multiple commands in a one liner
    my $CMD_SEP=";\n";
    $CMD_SEP=" && ";
    my @cmds;
    my $translation_transform;
    my $mem_request = '0'; # set to magic value 0 to request whole node.
    #print "Test output = ".compare_two_reference_spaces($in_file,$ref_file)."\n\n\n";
    #print "Do registration? ${do_registration}\n\n\n";
    if ($do_registration) {
        # in, ref, check out. out_file is a ants file prefix
        $translation_transform = "${out_file}0DerivedInitialMovingTranslation.mat";
        if ( ! compare_two_reference_spaces($in_file,$ref_file)) {
	    #Data::Dump::dump("Diff ref\n\t$ref_file\n\t$in_file\n");die 'Test';
            # FORMERLY HAD mkdir for path dir of out_file
	    # Also had oe option resolution into opt_e_string. 
	    # but antreg doesnt take opt_e_string!
	    my $excess_transform =  "${out_file}1Translation.mat" ;
            my $translation_cmd = "antsRegistration -v ${ants_verbosity} -d ${dims} -t Translation[1] -r [${ref_file},${in_file},1] -m Mattes[${ref_file},${in_file},1,32,None] -c [0,1e-8,20] -f 8 -s 4 -z 0 -o ${out_file}";
            my $remove_cmd = "rm ${excess_transform}";
            if (data_double_check($translation_transform)) {
                push(@cmds,$translation_cmd);
                push(@cmds,$remove_cmd);
            } else {
                printd(45,"$translation_transform ready, not regnerating\n");
                $log_msg="Skipped $translation_cmd && $remove_cmd";
            }
        } else {
            my $affine_identity = $Hf->get_value('affine_identity_matrix');
            $cmd = "ln -s ${affine_identity} ${translation_transform}";
	    if( ! -e ${translation_transform}){
		push(@cmds,$cmd);
	    } else {
		$log_msg="Skipped affine_identity replication $cmd";
	    }
        }
    } else {
        if (compare_two_reference_spaces($in_file,$ref_file)) {
            # same_refspace
            $cmd = "ln -s ${in_file} ${out_file}";
            print "Linking $in_file to $out_file\n\n";
            push(@cmds,$cmd);
	    if ($in_file =~ /[.]n?hdr/x){
		my $data_file;
		($data_file = $in_file)=~ s/[.]hdr$/.img/x;
		if ($in_file =~ /[.]nhdr/x){
		    my @hdr; load_file_to_array($in_file,\@hdr);
		    chomp(@hdr);
		    ($data_file)=grep /^[\s]*data[\s_]*file[\s]*:.*/x, @hdr;
		    $data_file=~s/^([^:]+:)(.*)$/$2/x;
		    $data_file=trim($data_file);
		}
		my $idat=File::Spec->catfile(dirname($in_file),$data_file);
		my $odat=File::Spec->catfile(dirname($out_file),$data_file);
		$cmd=sprintf("ln -s %s %s",$idat,$odat);
		#die "link dat:$data_file $cmd\n$in_file,$out_file";
		push(@cmds,$cmd);
	    }
        } else {
            # this code runs when we've already aligned one contrast of a set. 
	    # it should apply that alignment to the next.
            my $runno;
            my $gz = '';
            if ($out_file =~ s/(\.gz)$//) {$gz = '.gz';}
            my ($out_path,$out_name,$dummy_2) = fileparts($out_file,2);
            $out_file = $out_file.$gz;
            $out_name =~ s/(_masked)//i;
	    # We are assuming that underscores are not allowed in "specimen/runno" names! 14 June 2016
            if ($out_name =~ /([^\.]+)_[^_\.]+/) {
                $runno = $1;
            }
            
            # Copied from earlier location, may enable in the future when its found this is actually in use.
            #$test_dim =  `fslhd ${in_file} | grep dim4 | grep -v pix | xargs | cut -d ' ' -f2` 
            #    || croak("ERROR Reading $in_file for header bits");
            #if (! looks_like_number($test_dim) ) {
            #    error_out("Problem gathering dim infro from $in_file"); 
            #}
            #if ($in_file =~ /tensor/) {
            #    # Testing value for -f option, as per https://github.com/ANTsX/ANTs/wiki/Warp-and-reorient-a-diffusion-tensor-image
            #    $opt_e_string = ' -e 2 -f 0.00007'; 
            #} elsif ($test_dim > 1) {
            #    $opt_e_string = ' -e 3 ';
            #}
            
            $translation_transform = "${out_path}/translation_xforms/${runno}_0DerivedInitialMovingTranslation.mat";
            $cmd = "antsApplyTransforms -v ${ants_verbosity} -d ${dims} ${opt_e_string} -i ${in_file} -r ${ref_file}  -n $interp  -o ${out_file} -t ${translation_transform}";
	    
	    my $space='vbm';# or label... could use get_value_like_check... to get both refsizes
	    ($mem_request,my $vx_count)=refspace_memory_est($mem_request,$space,$Hf);
	    my ($vx_sc,$est_bytes)=ants::estimate_memory($cmd,$vx_count);
	    # convert bytes to MB(not MiB).
	    my $expected_max_mem=ceil($est_bytes/1000/1000);
	    printd(45,"Expected amount of memory required to apply warps: ${expected_max_mem} MB.\n");
	    if ($expected_max_mem > $mem_request) {
		$mem_request = $expected_max_mem;
	    }
            push(@cmds,$cmd);
        }  
    }
    
    my @list = split('/',$in_file);
    my $short_filename = pop(@list);

    my @test = (0);
    #if (defined $reservation) { 
    # Undefs are fun, just pass it :)
    # Added dependency to let this properly chain off our other work.
    #@test =(0,$reservation);
    #}
    @test=(0,$reservation,$dependency);
    $cmd=join($CMD_SEP,@cmds);
    my $go_message =  "$PM: Apply reference space of ${ref_file} to ${short_filename}";
    my $stop_message = "$PM: Unable to apply reference space of ${ref_file} to ${short_filename}:  $cmd\n";
    my $jid = 0;
    if ($cmd){
        if (cluster_check) {
            my ($home_path,$dummy1,$dummy2) = fileparts($out_file,2);
            my $Id= "${short_filename}_reference_to_proper_space";
            my $verbose = 1; # Will print log only for work done.
            $jid = cluster_exec($go, $go_message, $cmd,$home_path,$Id,$verbose,$mem_request,@test);     
            if (not $jid) {
                error_out($stop_message);
            }
        } else {
            if (! execute($go, $go_message, @cmds) ) {
                error_out($stop_message);
            }
        }

    }
    
    return($jid);
}


# ------------------
sub set_reference_space_vbm_Init_check {
# ------------------
# WARNING NAUGHTY CHECK IS DOING WORK.
    # no inputs at current, sneaking everything though the headfile.
    #my @args=@_;
    my @init_jobs;
    my $vx_count=1;
    my $init_error_msg='';
    my $message_prefix="$PM initialization check:\n";

    $pristine_input_dir = $Hf->get_value('pristine_input_dir');    
    $inputs_dir = $Hf->get_value('inputs_dir');
    $preprocess_dir = $Hf->get_value('preprocess_dir');

    #mkdir ($preprocess_dir,$permissions) if ! -e $preprocess_dir;
    #mkdir ($inputs_dir,$permissions) if ! -e $inputs_dir;

    my ($v_ok,$v_ok2);
    ($v_ok, my $resample_images) = $Hf->get_value_check('resample_images');
    ($v_ok2, my $resample_factor) = $Hf->get_value_check('resample_factor');
    #if (($resample_factor ne 'NO_KEY') ||($resample_images ne 'NO_KEY') ) { ## Need to finish fleshing out this logic!
    if ($v_ok || $v_ok2) {
        carp("Resampling on");
        sleep_with_countdown(5);
        if (($resample_images == 0) || ($resample_images =~ /^(no|off)$/i) ) {
            $resample_images=0;
            $resample_factor=1;
        } else {    
            if (($resample_images == 1) || ($resample_images == 2) || ($resample_images =~ /^(yes|on)$/i) ) {
                # Default is downsample by a factor of 2x
                $resample_images=1;
                $resample_factor=2;
            } elsif ($resample_images !~ /[\-a-zA-Z]/) {
                # We're going to cross our fingers and hope that by excluding letters and negative signs
                # that we're left with valid positive numbers by which we can multiply the voxelsize
                # Also note that "resample factor" is more accurately "downsample factor"
            } else {
                # Throw dying error.
                my $resample_error="Bad resample_images field specified ${resample_images}. Only positive real numbers allowed.\n";
                $init_error_msg=$init_error_msg.$resample_error;
            }
        }
    } elsif (($resample_images eq 'NO_KEY' ) && ($resample_factor ne 'NO_KEY') ) {
        # We assume that the resample factor has already been checked & will automatically be passed on
        $resample_images=1;
    } else {
        $resample_images=0;
        $resample_factor=1;
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
    
    ($v_ok, $reference_space_hash{'vbm'})=$Hf->get_value_check('vbm_reference_space');
    #if ((! defined $reference_space_hash{'vbm'}) || ($reference_space_hash{'vbm'} eq ('NO_KEY' || '' || 'UNDEFINED_VALUE'))) {
    if(! $v_ok){
        $log_msg=$log_msg."\tNo VBM reference space specified.  Will use native image space.\n";
        $reference_space_hash{'vbm'} = 'native';
    }
    ($v_ok, $reference_space_hash{'label'})=$Hf->get_value_check('label_reference_space');         
    $base_images_for_labels = 0;
    if ($create_labels) {
        #if ((! defined $reference_space_hash{'label'}) || ($reference_space_hash{'label'} eq (('NO_KEY') || ('') || ($reference_space_hash{'vbm'})))) {
        if (! $v_ok) {
            $log_msg=$log_msg."\tNo label reference space specified.  Will inherit from VBM reference space.\n";
            $reference_space_hash{'label'}=$reference_space_hash{'vbm'};
            $Hf->set_value('label_reference_space',$reference_space_hash{'label'});
            $refspace_folder_hash{'label'} = $inputs_dir;          
        } else {
            $base_images_for_labels = 1; 
        }
    }
    
    $Hf->set_value('base_images_for_labels',$base_images_for_labels);    
    
    my @ref_spaces;
    @ref_spaces = ("vbm");
    if ($create_labels) {#($base_images_for_labels) {
        push(@ref_spaces,"label");
    }
    
    foreach my $space (@ref_spaces) {    
        my ($ref_error,$for_labels)=('',0);
        if ($space eq "label") {
            $for_labels = 1;
        }
	($input_reference_path_hash{$space},$reference_path_hash{$space},$refname_hash{$space},$ref_error) = set_reference_path_vbm($reference_space_hash{$space},$for_labels);
        #Data::Dump::dump($input_reference_path_hash{$space},$reference_path_hash{$space},$refname_hash{$space},$ref_error);
        #print "REF TESTING "; exit 1; 
	
	my ($v_ok,$refsize)=$Hf->get_value_check("${space}_refsize");
	#if(! $v_ok && $RS{$space}{'input'} eq 'rerun_init_check_later' ) {
	if(! $v_ok &&  $input_reference_path_hash{$space} eq 'rerun_init_check_later' ) {
	    # "destish" ref not available, soo we grab direct from input.
	    # IN MANY SITUATIONS THIS CANNOT WORK!!!! 
	    # THIS will work if we have native ref, but can be in the wrong order.
	    # This may be okay becuase in the other situations, the real ref fil will exist. 
	    (my $v_ok, my $ch_runlist) = $Hf->get_value_check('channel_comma_list');
	    croak("Missing critical working folder settings") if ! $v_ok;
	    my @channels=split(',',$ch_runlist);
	    my $c_channel=$channels[0];
	    my $ref_runno=$Hf->get_value('ref_runno');
	    my $t_ref = get_nii_from_inputs($pristine_input_dir,$ref_runno,$c_channel);
	    $refsize="NOT FOUND";
	    if ($t_ref !~ /[\n]+/) {	    
		$refsize=get_image_dims($t_ref);
	    } else {
		confess("Can't set refsize:".$t_ref);
	    }
	} elsif( -e $input_reference_path_hash{$space} ) { #$RS{$space}{'input'} ) {
	    #$refsize=get_image_dims($RS{$space}{'input'},$Hf);
	    $refsize=get_image_dims($input_reference_path_hash{$space});
	}
	$Hf->set_value("${space}_refsize",$refsize); 
	
        if ($input_reference_path_hash{$space} eq 'rerun_init_check_later') {
            my $log_msg = "Reference spaces not set yet. Will rerun upon start of set_reference_space module.";
            log_info("${message_prefix}${log_msg}");
	    $rerun_init_check=1;
            return($init_error_msg);
        } else {
	    $Hf->set_value("${space}_reference_path",$reference_path_hash{$space});
            $Hf->set_value("${space}_input_reference_path",$input_reference_path_hash{$space});
            $Hf->set_value("${space}_reference_space",$reference_space_hash{$space});
            #my $bounding_box_and_spacing = get_bounding_box_and_spacing_from_header($reference_path_hash{$space});
            my $bounding_box_and_spacing = get_bounding_box_and_spacing_from_header($input_reference_path_hash{$space},1);

            $refspace_hash{$space} = $bounding_box_and_spacing;
            $Hf->set_value("${space}_refspace",$refspace_hash{$space});
	    #EX refspace, {[0.015 0.015 0.015], [12.21 19.77 9.21]} 0.015x0.015x0.015
	    # ... {[first vox], [last vox]}, spacing. 
	    # In theory directionality is also hiding in this.... but we probably don't maintain negative signs correctly.
	    # Thought I could be clever and use PrintHeader one time, but it turns out we dont save the hf in time.
	    # Switched to fslhd
	    #
	    # vox first, last, size
	    my ($vx_f,$vx_l,$vx_s) = $bounding_box_and_spacing =~ m/{([^,]+),[ ]([^}]+)}[ ](.+)/;
	    $vx_f=~s/[\[\]]//g; $vx_l=~s/[\[\]]//g;
	    my @vf=split(" ",$vx_f); my @vl=split(" ",$vx_l); my @vs=split("x",$vx_s);
	    my @fov;
	    my @dx;
	    for(my $vi=0;$vi<scalar(@vl);$vi++) {
		$fov[$vi]=$vl[$vi]-$vf[$vi] || die "fov calc err d $vi";
		$fov[$vi]=round($fov[$vi],4);
		$dx[$vi]=$fov[$vi]/$vs[$vi] || die "dim calc err d $vi";
		$dx[$vi]=round($dx[$vi]);
	    }
	    my ($v_ok,$refsize)=$Hf->get_value_check("${space}_refsize");
	    #if(! defined $refsize) {
	    #cluck "Hf Err fetching refsize"; $v_ok=0; }
	    if(! $v_ok && -e $input_reference_path_hash{$space} ) { 
		# Oh ants PrintHeader, why you always slow :( 
		#(my $refsize)=run_and_watch("PrintHeader $input_reference_path_hash{$space} 2"); chomp($refsize); $refsize=~s/x/ /g;
		#(my $refsize)=run_and_watch("fslhd $input_reference_path_hash{$space}|grep '^dim[1-3]'|cut -d ' ' -f2-|xargs");
		#chomp($refsize); $refsize=trim($refsize);
		my $refsize=get_image_dims($input_reference_path_hash{$space});
		if($refsize ne join(" ",@dx) ) {
		    confess "Error getting refsize from bounding box for space:$space".$refsize.' ne '.join(" ",@dx);
		}
		$Hf->set_value("${space}_refsize",$refsize);
		my @d=split(" ",$refsize);
		foreach(@d){
		    $vx_count*=$_; }
	    }
	    if ((defined $ref_error) && ($ref_error ne '')) {
                $init_error_msg=$init_error_msg.$ref_error;
            }
            $log_msg=$log_msg."\tReference path for ${space} analysis is ${reference_path_hash{${space}}}\n";

        }
    }
    # The way this var is set up NO MATTER WHAT, set ref init will run one more time just before Runtime
    if($do_mask && ! defined $rerun_init_check){
	carp("set ref rerun_init force");
	$rerun_init_check = 1;
    }
    if($rerun_init_check) {
	carp("CANNOT COMPLETE INIT, RERUN LATER");
	return($init_error_msg);
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
    if (($base_images_for_labels) && ($refspace_hash{'vbm'} eq $refspace_hash{'label'})) {
        $base_images_for_labels = 0;
        $Hf->set_value('label_reference_path',$reference_path_hash{'vbm'});     
        $Hf->set_value('label_refname',$refname_hash{'vbm'});
        $Hf->set_value('label_refspace',$refspace_hash{'vbm'});
        $Hf->set_value('label_refspace_path',$inputs_dir);
    }
    $Hf->set_value('base_images_for_labels',$base_images_for_labels);
        
    if ($base_images_for_labels) {
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

    # Changed 1 September 2016: Implemented uniform processing for reference
    #    files. Feed source directly into function for creating a centered
    #    binary mass in the reference image.  This should automatically handle
    #    all centering issues, including re-centering the rigid atlas target.
    my $string=$refspace_folder_hash{'vbm'};
    $Hf->set_value('vbm_refspace_folder',$refspace_folder_hash{'vbm'});
    $Hf->set_value("vbm_reference_path",$reference_path_hash{'vbm'});
    if ($create_labels){ 
        $Hf->set_value('label_refspace_folder',$refspace_folder_hash{'label'});
        if ($base_images_for_labels) {
            $Hf->set_value('label_reference_path',$reference_path_hash{'label'});
        } else {
            $Hf->set_value("label_reference_path",$reference_path_hash{'vbm'});
        } 
    }
    (my $v_ok_ran,$rigid_atlas_name) = $Hf->get_value_check('rigid_atlas_name');
    (my $v_ok_rc, $rigid_contrast) = $Hf->get_value_check('rigid_contrast');
    (my $v_ok_rt, $rigid_target) = $Hf->get_value_check('rigid_target');
    if (! $v_ok_ran) {
	# Not atlas, check other possiblities
	if (! $v_ok_rt) {
	    # No rigid reg
            $Hf->set_value('rigid_atlas_path','null');
            $Hf->set_value('rigid_contrast','null');
            $log_msg=$log_msg."\tNo rigid target or atlas has been specified. No rigid registration will be performed. Rigid contrast is \"null\".\n";
        } elsif ($runno_list =~ /[,]*${rigid_target}[,]*}/) {
	    # rigid_target is a member of the runno list. 
	    # find it in the preprocess_dir... 
	    $original_rigid_atlas_path=get_nii_from_inputs($inputs_dir,$rigid_target,$rigid_contrast);
	    $rigid_atlas_path=get_nii_from_inputs($preprocess_dir,$rigid_target,$rigid_contrast);
	    # This path doesnt have a new line, eg a file was found... 
	    if ($original_rigid_atlas_path !~ /[\n]+/) {
		$log_msg=$log_msg."\tA runno has been specified as the rigid target; setting ${original_rigid_atlas_path} as the expected rigid atlas path.\n";
	    } else {
		# ERROR condition, file not found.
		$init_error_msg=$init_error_msg."The desired target for rigid registration appears to be runno: ${rigid_target}, ".
		    "but could not locate appropriate image.\nError message is: ${rigid_atlas_path}";          
	    }
	} elsif ($v_ok_rt && data_double_check($rigid_target)) {
	    # rigid target specified and missing
	    $log_msg=$log_msg."\tNo valid rigid targets have been implied or specified (${rigid_target} could not be validated). Rigid registration will be skipped.\n";
	    die "MISSING:$rigid_atlas_path" if ! -e $rigid_atlas_path;
	} elsif($v_ok_rt) {
	    $log_msg=$log_msg."\tThe specified file to be used as the original rigid target exists: ${rigid_target}. (Note: it has not been verified to be a valid image.)\n";
	    $original_rigid_atlas_path=$rigid_target;
	} else {
	    die "UNEXPECTED CODE PATH";
	}
    } else {
        if (! $v_ok_rc) {
            $init_error_msg=$init_error_msg."No rigid contrast has been specified. Please set this to proceed.\n";
        } else {
            my $rigid_atlas_dir = File::Spec->catdir(${WORKSTATION_DATA},"atlas",${rigid_atlas_name});
	    # BROKEN SETUP HACK!
            $rigid_atlas_dir =~ s/\/data/\/CIVMdata/ if ! -d $rigid_atlas_dir;
            my $expected_rigid_atlas_path = "${rigid_atlas_dir}${rigid_atlas_name}_${rigid_contrast}.nii";
	    $rigid_atlas_path = get_nii_from_inputs($preprocess_dir,$rigid_atlas_name,$rigid_contrast);
	    $original_rigid_atlas_path = get_nii_from_inputs($rigid_atlas_dir,$rigid_atlas_name,$rigid_contrast);
	    if( $rigid_atlas_path =~ /[\n]+/ && $original_rigid_atlas_path =~ /[\n]+/) {
		# NEITHER FOUND Error.
		$init_error_msg = $init_error_msg."For rigid contrast ${rigid_contrast}: missing atlas nifti file ${expected_rigid_atlas_path}  (note optional \'.gz\')\n" 
	    } elsif($rigid_atlas_path =~ /[\n]+/x) {
		# One must be found, so if it was not the rigid... we need transcribe original 
		# WARNING CODER, THIS WORK USED TO BE A REPLICATE IN mask_images_vbm AND set_reference_space_vbm.
                # That code has finally been disabled and this code has been ravaged to clean out
		# double speak and redundancy.
		my ($p,$n,$e)=fileparts($original_rigid_atlas_path,2);
		$rigid_atlas_path=File::Spec->catfile(${preprocess_dir},$n.$e);
		my $cmd="cp ${original_rigid_atlas_path} $rigid_atlas_path";
		# mem estimate of voxelcount@64-bit x2 volumes
		my $mem_request=ceil($vx_count*8*2/1000/1000);
		# BLARG THIS CONSTRUCT IS BAD... GONNA MAKE IT WORSE BY ADDING nhdr support via WarpImageMultiTransform.
		if( $e eq ".nhdr") {
		    my $input_file=$original_rigid_atlas_path;
		    my $output_folder=$preprocess_dir;
		    carp("experimental startup from nhdr engaged.");
		    my $reconditioned_dir=File::Spec->catdir($preprocess_dir,"conv_nhdr");
		    mkdir $reconditioned_dir if ! -e $reconditioned_dir;
		    my $nhdr_sg=File::Spec->catfile($reconditioned_dir,$n.".nii");
		    my $matlab_exec_args="${nhdr_sg} RAS RAS ${output_folder}";
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
			$cmd=$cmd." && $Wcmd";
		    }
		} elsif ($original_rigid_atlas_path !~ /\.gz$/ 
			 && $original_rigid_atlas_path =~ /[.]nii/) {
		    # WHY DO WE WANT TO GZIP SO BADLY!
		    carp("WARNING: Input atlas not gzipped, We're going to gzip it!");
		    $rigid_atlas_path=$rigid_atlas_path.".gz";
		    $cmd="gzip -c ${original_rigid_atlas_path} > ${rigid_atlas_path} && touch -r ${original_rigid_atlas_path} ${rigid_atlas_path}";
		}
		my @test=(0);
		my $go_message =  "$PM: set reference space rep atlas to preprocess";
		my $stop_message = "$PM: could not fetch atlas file into preprocess:  $cmd\n";
		my $jid = 0;
		if ($cmd){
		    mkdir ($preprocess_dir,$permissions) if ! -e $preprocess_dir;
		    mkdir ($inputs_dir,$permissions) if ! -e $inputs_dir;
		    if (cluster_check) {
			my $Id= "rigid_reference_cache";
			my $verbose = 1; # Will print log only for work done.
			$jid = cluster_exec($go, $go_message, $cmd,$preprocess_dir,$Id,$verbose,$mem_request,@test);
			if (not $jid) {
			    error_out($stop_message);
			}
			push(@init_jobs,$jid);
		    } else {
			if (! execute($go, $go_message, $cmd) ) {
			    error_out($stop_message);
			}
		    }
		}
		if( ! -e $rigid_atlas_path && ! scalar(@init_jobs) ) {
		    error_out("MISSING:$rigid_atlas_path and not scheduled.");
		}
	    }
	    $Hf->set_value('rigid_atlas_path',$rigid_atlas_path);
            $Hf->set_value('original_rigid_atlas_path',$original_rigid_atlas_path);
	    if(! -e $original_rigid_atlas_path ) {error_out("ERRONOUSDATA:$original_rigid_atlas_path");}   
        }
    }
    if (defined $log_msg && $log_msg ne '') {
        log_info("${message_prefix}${log_msg}");
    }
    if(defined $init_error_msg && $init_error_msg ne '') {
        $init_error_msg = $message_prefix.$init_error_msg;
    }
    return($init_error_msg,\@init_jobs);
}

#---------------------
sub set_reference_path_vbm {
#---------------------
    my ($ref_option,$for_labels) = @_;
    my $ref_string; 
    $inputs_dir = $Hf->get_value('inputs_dir');
    my $ref_path='';
    my $input_ref_path;
    my $error_message;
    
    my $which_space='vbm';
    if ($for_labels) {
        $which_space = 'label';
    }
    my $ref_folder= $refspace_folder_hash{${which_space}};    

    if (! data_double_check($ref_option)) {
        my ($r_path,$r_name,$r_extension) = fileparts($ref_option,2);
#       print "r_name = ${r_name}\n\n\n\n";
	#if ($r_extension =~ m/^[.]{1}(hdr|img|nii|nii\.gz)$/) {
	if ($r_extension =~ m/^[.]($valid_formats_string)$/x) {
            $log_msg=$log_msg."\tThe selected ${which_space} reference space is an [acceptable] arbitrary file: ${ref_option}\n";
            $input_ref_path=$ref_option;
            if ($r_name =~ /^reference_file_([^\.]*)([.]$valid_formats_string)?$/x) {
                $ref_path = "${ref_folder}/${r_name}${out_ext}";
                $ref_string=$1;
                print "ref_path = ${ref_path};\n\nref_string=${ref_string}\n\n\n"; ####
            } else {
                $r_name =~ s/([^0-9a-zA-Z]*)//g;
                $r_name =~ m/(^[\w]{2,8})/;
                $ref_string = "c_$1";  # "c" stands for custom
                $ref_path="${ref_folder}/reference_file_${ref_string}${out_ext}";
            }
            print "ref_string = ${ref_string}\n\nref_path = ${ref_path}\n\n\n";
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
    if (! -d $atlas_dir_perhaps) {
        if ($atlas_dir_perhaps =~ s/\/data/\/CIVMdata/) {}
    } 


    if (-d $atlas_dir_perhaps) {
        $log_msg=$log_msg."\tThe ${which_space} reference space will be inherited from the ${ref_option} atlas.\n";
        $input_ref_path = get_nii_from_inputs($atlas_dir_perhaps,$ref_option,$rigid_contrast);
        if (($input_ref_path =~ /[\n]+/) || (data_double_check($input_ref_path))) {
            $error_message = $error_message.$input_ref_path;
        }
        $ref_string="a_${ref_option}"; # "a" stands for atlas
        $ref_path="${ref_folder}/reference_file_${ref_string}${out_ext}";
        $log_msg=$log_msg."\tThe full ${which_space} input reference path is ${input_ref_path}\n";
    } else {
        
        my $ref_runno;#=$Hf->get_value('ref_runno');
        my $preprocess_dir = $Hf->get_value('preprocess_dir');
        if ($runno_list =~ /[,]*${ref_option}[,]*/ ) {
            $ref_runno=$ref_option;
        } else {
            my @control_runnos= split(',',$Hf->get_value('control_comma_list')); #switched from "control" to "template" 1 May 2018
            $ref_runno = shift(@control_runnos);
        }
        print " Ref_runno = ${ref_runno}\n";
        $Hf->set_value('ref_runno',$ref_runno);
        #$ref_path = get_nii_from_inputs($preprocess_dir,"native_reference",$ref_runno);
        #$ref_path = get_nii_from_inputs($preprocess_dir,"reference_image_native",$ref_runno);# Updated 1 September 2016

        my $ch_runlist = $Hf->get_value('channel_comma_list');
        my @channels=split(',',$ch_runlist);
        my $c_channel=$channels[0];
        if ($c_channel =~ /nii4D/) {$c_channel=$channels[1];}
        #No, not nii4D 26 October 2018
        $input_ref_path = get_nii_from_inputs($preprocess_dir,$ref_runno,$c_channel);
        #$input_ref_path = get_nii_from_inputs($preprocess_dir,$ref_runno,""); # Will stick with looking for ANY contrast from $ . 16 March 2017
        
        $error_message='';      
        if ($input_ref_path =~ /[\n]+/) {
            if ( defined $rerun_init_check && $rerun_init_check) {
                $error_message =  "Unable to find any input image for ${ref_runno} in folder(s): ${preprocess_dir}\nnor in ${pristine_input_dir}.\n";
            } else {
                $input_ref_path =  'rerun_init_check_later';
                print "Will need to rerun the initialization protocol for ${PM} later...\n\n";
            }
        }
        
        $ref_string="native";
        $ref_path="${ref_folder}/reference_image_native_${ref_runno}${out_ext}";
        
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
    # N dimensions, NOT the size of dimensions    
    $dims=$Hf->get_value('image_dimensions');

    if ( defined $rerun_init_check && $rerun_init_check) {
        # Initially thought htis was a rare case, its actually the norm when 
	# native ref space.
        carp('rerun_init set_reference_space_vbm_runtime');
	$rerun_init_check = 0;
        my ($init_error_message_2) = set_reference_space_vbm_Init_check();
    }

    mkdir ($inputs_dir,$permissions)if ! -e $inputs_dir;
    mkdir ($preprocess_dir,$permissions)if ! -e $preprocess_dir;
    $base_images_for_labels = $Hf->get_value('base_images_for_labels');
    $refspace_folder_hash{'vbm'} = $Hf->get_value('vbm_refspace_folder');
    $refspace_folder_hash{'label'} = $Hf->get_value('label_refspace_folder');
    
    my $intermediary_path = "${inputs_dir}/reffed_for_labels";
    if ($base_images_for_labels) {
        $intermediary_path = "${inputs_dir}/reffed_for_labels";
	mkdir ($intermediary_path,$permissions) if ! -e $intermediary_path;
	mkdir ($refspace_folder_hash{'label'},$permissions) if ! -e $refspace_folder_hash{'label'};
    }
    
## TRYING TO MOVE THIS CODE TO INIT_CHECK, 16 March 2017 --> Just kidding, keep this here, rerun init check if native ref file not found. 20 March 2017
    # Not clear when these wouldn't have the same values.
    @ref_spaces = ("vbm");
    if ($base_images_for_labels) {
	# HOLY FUCK STICKS, THIS HAS TO RESET HERE BECAUSE "baSE_IMAges_FOr_laBEls" is NOT create_labels!, it also incorporates "vbm & label are different refspaces".
	push(@ref_spaces,"label");
    }
    my %centered_masses;
    my @center_mass_gen;
    foreach my $space (@ref_spaces) {
        $reference_space_hash{$space} = $Hf->get_value("${space}_reference_space");
        my $inpath = $Hf->get_value("${space}_input_reference_path");
        my $outpath = $Hf->get_value("${space}_reference_path");
        $refspace_hash{$space} = $Hf->get_value("${space}_refspace");
        $refname_hash{$space} =  $Hf->get_value("${space}_refname");

        if (data_double_check($inpath)) {
	    confess("SILLY nANNERY missing:".$inpath);
            #$inpath="${inpath}.gz"; # We're assuming that it exists, but isn't found because it has been gzipped. 16 March 2017
        }
        # 2020-01-29
        # New fail condition spotted here where we try to operate on a 'plain' named file, 
        # but only a _masked named file is available.
        # Suspicion is that we dont wait for code the way we might mean to, 
        # and this code is prepared/scheduled to run while another is busy renaming things.
        # 2020-08-07 these failures are(seem) more repeatable with larger data
	if (! exists $centered_masses{$outpath} && data_double_check($outpath,0)){
	    # Becuase we DO NOT control out headers in matlab very much we replicate our input header onto the output file.
	    # (Internally create centered has been upgrade to read nii or nhdr, and write back to same format.)
            my $mat_id = "REF_".${refname_hash{$space}};
            #my $name = "REF_${refname_hash{$space}}";
	    my $t_ref = file_add_suffix($outpath,"_tmp");
            #my $nifti_args = "\'${inpath}\' , \'${outpath}\'";
            my $nifti_args = "\'${inpath}\' , \'${t_ref}\'";
            #my $nifti_command = make_matlab_command('create_centered_mass_from_image_array',$nifti_args,"${name}_",$Hf,0); # 'center_nii'
            my $cuboid_gen = make_matlab_command('create_centered_mass_from_image_array',$nifti_args,"${mat_id}_",$Hf,0); # 'center_nii'
	    $cuboid_gen=$cuboid_gen." && "."CopyImageHeaderInformation $inpath $t_ref $outpath 1 1 1 0"." && "."rm \"$t_ref\"";
	    push(@center_mass_gen,$cuboid_gen);
	}
        # 4 Feb 2019--use ResampleImageBySpacing here to create up/downsampled working space if desired.
        #$Hf->get_value('resample_images');
        #ResampleImageBySpacing 3 $in_ref $out_ref 0.18 0.18 0.18 0 0 1
        #my $bounding_box_and_spacing = get_bounding_box_and_spacing_from_header(${out_ref});
        #$refspace_hash{$space} = $bounding_box_and_spacing;
        #$Hf->set_value("${space}_refspace",$refspace_hash{$space});
        # write refspace_temp.txt (for human purposes, in case this module fails)
        my $ref_tmp=File::Spec->catfile($refspace_folder_hash{$space},"refspace.txt.tmp");
	my $ref_out=File::Spec->catfile($refspace_folder_hash{$space},"refspace.txt");
        if ( ! -e $ref_tmp && ! -e $ref_out) {
	    $refspace_file_hash{$ref_out}=$ref_tmp;
            write_refspace_txt($refspace_hash{$space},$refname_hash{$space},$refspace_folder_hash{$space},$split_string,"refspace.txt.tmp");
	    #write_refspace_txt($refspace_hash{$space},$refname_hash{$space},$ref_tmp,$split_string);
        } else {
            printd(5,"WARNING, $ref_tmp or $ref_out exists, not overwriting.\n");
        }
    }
    if(scalar(@center_mass_gen)){
	execute_indep_forks(1, "Creating a dummy centered mass for referencing purposes", @center_mass_gen);
    }


##  2 February 2016: Had "fixed" this code several months ago, however it was sending the re-centered rigid atlas to base_images, and not even 
##  creating a version for the preprocess folder. The rigid atlas will only be rereferenced if it is found in preprocess, which for new VBA runs
##  would not be the case.  Thus we would have a recentered atlas with its own reference space being used for rigid registration, resulting in
##  unknown behavior.  An example would be that all of our images get "shoved" to the top of their bounding box and the top of the brain gets lightly
##  trimmed off.  Also, we will assume that this file will be in .gz format.  If not, then it will be gzipped.

    if ($base_images_for_labels) {
        #`cp ${refspace_folder_hash{"vbm"}}/*\.nii* ${refspace_folder_hash{"label"}}`;
        #run_and_watch("cp ".${refspace_folder_hash{"vbm"}}."/*\.nii* ".${refspace_folder_hash{"label"}});
	carp("Linking instead of copy");
	# SUSPICIOUS ! This is wildcard linking! that cant be right!
	# The intent is super unclear! maybe we're trying to link equivalent ref cuboids? but the flag used obfucsates that...
	run_and_watch("ln -sv ".${refspace_folder_hash{"vbm"}}."/*\.nii* ".${refspace_folder_hash{"label"}});
        #run_and_watch("ln -sv ".${ref_folder_hash{"vbm"}}."/*\.nii* ".${ref_folder_hash{"label"}});
	#run_and_watch("ln -sv ".$RS{'vbm'}{'folder'}."/*\.nii* ".$RS{'label'}{'folder'});
    }   
    my $case = 1;
    my $skip_message;
    # how messy, we use this to set PM scoped globals instead of returning :( 
    ($work_to_do_HoA,$skip_message)=set_reference_space_Output_check($case);
    
    if ($skip_message ne '') {
        print "${skip_message}";
    }
}

sub refspace_memory_est {
    my($mem_request,$space,$Hf,$volume_count)=@_;
    $volume_count=4 if ! defined $volume_count;
    my ( $v_ok,$refsize)=$Hf->get_value_check("${space}_refsize");
    # a defacto okay enough guess at vox count... when this was first created. 
    my $vx_count = 512 * 256 * 256;
    if( $v_ok) { 
	my @d=split(" ",$refsize);
	$vx_count=1;
	foreach(@d){
	    $vx_count*=$_; }
	# 512 vx @64bit * volumes, in MB for slurm, (NOT MiB);
	$mem_request = ceil(512 + $vx_count * 8 * $volume_count /1000/1000);
    } else {
	carp("Cannot set appropriate memory size by volume size (${space}_refsize not ready), using defacto limit $mem_request");
	if ( defined $rerun_init_check) {
	    sleep_with_countdown(3) if $rerun_init_check == 0; }
    }
    $mem_request=max($mem_request,512);
    return ($mem_request,$vx_count);
}

sub get_refsize_from_file {
    # Original poor name for this.
    return get_image_dims(@_);
}
sub get_image_dims {
    my($file)=@_;
    # New Fangled PrintHeader with forced output caching(disabled)
    my @hdr;ants::PrintHeader($file,\@hdr);
    my ($dimline)=grep /.*Size\s+.*/x, @hdr;
    my @dims= $dimline =~ /([0-9]+)/gx;
    # remove len 1 dims
    while($dims[$#dims] eq 1 && $#dims>-1){
	pop(@dims);
    }
    my $im_size=join(' ',@dims);
    return $im_size;
}
1;

