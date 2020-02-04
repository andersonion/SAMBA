#!/usr/bin/perl

use strict;
use warnings;
use Carp qw(carp croak cluck confess);

use File::Basename;
use Getopt::Std;
use Scalar::Util qw(looks_like_number);

use Env qw(RADISH_PERL_LIB BIGGUS_DISKUS);
die "Cannot find good perl directories, quitting" unless defined($RADISH_PERL_LIB);
use lib split(':',$RADISH_PERL_LIB);
use pipeline_utilities;
use Headfile;

#use SAMBA_global_variables; 
use civm_simple_util qw(activity_log can_dump load_file_to_array write_array_to_file find_file_by_pattern is_writable round printd whoami whowasi debugloc sleep_with_countdown $debug_val $debug_locator);

my $PM = 'pull_multi.pm';

# First step: look for data in project_code/runno (or project_code_2,3,.../runno)
#  if found, create link

#exit pull_multi();
sub pull_multi {
    # this function is informed of what to go and get. It should NOT 
    # understand input definitions instead it should call puller_simply rather blindly.
    #
    # TODAY, it has tensor definitions baked into the code calls. 
    # Diffusion will be added to that, and it will be allowed to handle 
    # those two only, and STOP growing.
    # TODAY, it links clean names into inputs, That belongs someplace else. 
    # The "Best" replacement path is to create a definition sensitive pull 
    # call and run that, making this whole function obsolete.
    # THEN link that output as desired name into the "inputs" folder. 

    # ex data.
    #my @runnos=('S96500','N56497','N56505','N56247','N56500');
    #my @contrasts=('fa','gfa','dwi','m*GenericAffine*','b_table');
    #my @machines=('dusom_civm','delos','piper');
    # project_name isnt in the HF provided, BUT it is a globaly global.
    #$project_code=$Hf->get_value_check('project_name');
    #my $inputs_dir="$BIGGUS_DISKUS/test_VBM-inputs";
    my ($r_a,$c_r,$m_r,$Hf)=@_;
    my @runnos=@$r_a;
    my @contrasts=@$c_r;
    my @machines=@$m_r;
    #$Hf->print();die;
    #Data::Dump::dump(@_);die;
    #Data::Dump::dump((\@runnos,\@contrasts,\@machines));die;
    my $cmd='';
    my @master_cmd_list=();
    # setting "normal" variable usage internal just this hack from SAMBA variable project_name
    my $project_code = $project_name; 
    if ($project_code =~ /enam/ ) {
        #Data::Dump::dump((\@runnos,\@contrasts,\@machines));die;
    }
    my $inputs_dir=$Hf->get_value('pristine_input_dir');
    for my $runno (@runnos) {
        for my $contrast (@contrasts) {
            my @c_cmds;
            my $file_prefix='';
            my $target_dir = "${BIGGUS_DISKUS}/${project_code}/${runno}";
            # Magic contrast 'm*GenericAffine*'
            if ($contrast =~ /^m\*GenericAffine\*$/ ){
                $target_dir = "${BIGGUS_DISKUS}/${project_code}/${runno}/ecc_xforms";
                $file_prefix='xform_';
            }
            # Magic contrast 'nii4D'
            #my $swap_order=0;
            # Initially thought swap order would be okay, but its not a uniform swap order :( 
            # all of these special handling cases 
            #if ($contrast =~ /nii4D/ ){
            #($runno,$contrast)=($contrast,$runno);
            #$swap_order=1;
            #}
            my $file_search_string = "/${file_prefix}${runno}*_${contrast}.*";
            # Magic contrast 'nii4D'
            if ($contrast =~ /nii4D/ ){
                $file_search_string = "/${file_prefix}${contrast}*_${runno}*.*nii*";
            }
            # Magic contrast 'tensor*headfile'
            if ($contrast =~ /tensor\*headfile/ ){
                $file_search_string = "/${file_prefix}tensor*${runno}*.headfile";
                #confess "getting tensor * headfile with $file_search_string";
            }
            # Magic contrast 'diffusion*headfile'
            if ($contrast =~ /diffusion\*headfile/ ){
                $file_search_string = "/${file_prefix}diffusion*${runno}*.headfile";
                #confess "getting tensor * headfile with $file_search_string";
            }
            # If we swapped runno and contrast put it back.
            #if ($swap_order){
                #($runno,$contrast)=($contrast,$runno);
            #}

	    # 4 February 2020 (Tues): BJA Adding hack to see if a nii4D_$runno.nii* is in the inputs folder already, and creating a symlink to $runno_nii4D.nii*
	    my $search_machines=1;
	    if ($contrast =~ /nii4D/ ){
		my $local_nii4D=`ls -1 ${inputs_dir}/${file_search_string} 2>/dev/null | head`;
		chomp($local_nii4D);
		my $target_nii4D=`ls -1 ${inputs_dir}/${file_prefix}${runno}_${contrast}.nii* 2>/dev/null | head`;
		chomp($target_nii4D);

		if (${target_nii4D} eq '') { 
		    if ( -e  $local_nii4D ) {
			my $gz_test = `gzip -t ${local_nii4D} 2<&1 | wc -l`;
			my $gz='.gz';
			if ($gz_test > 0) {$gz='';}
			$target_nii4D="${inputs_dir}/${file_prefix}${runno}_${contrast}.nii${gz}";
			` ln -s ${local_nii4D} ${target_nii4D}`;
			if ( -e $target_nii4D){
			    $search_machines=0;
			}

		    }
		}
	    }  # End most of BJ's Hack


	    if ($search_machines){ # BJ's Hack is turn off this block of code after properly linking nii4D inputs, which would otherwise always run by default.
		for my $machine (@machines) {
		    my $archive_prefix='';
		    my $machine_suffix='';
		    my $multi='';
		    my $r_e_flags='-re';    
		    if ($machine =~ /dusom_civm/ ){
			$archive_prefix = "${project_code}/research/";
		    } else {
			$machine_suffix = "-DTI-results";
		    }
		    
		    if ($file_prefix eq 'xform_') { $multi= '-M'; ${r_e_flags}='';}
		    my $psfs = "${archive_prefix}tensor${runno}*${machine_suffix}${file_search_string}";
		    my $puller_simple_options=" -f file ${multi} -o ${r_e_flags} ${machine} ${psfs} ${target_dir}";
		    my $c_cmd = "puller_simple -D0 ${puller_simple_options}";
		    
		    push(@c_cmds,$c_cmd);
		}
		
		my $inputs_file = File::Spec->catfile(${inputs_dir},"${runno}_${contrast}");
		# Warning!!! shell and perl variable mixing generates odd looking escapes here, 
		# ext_and_gz is shell variable so is in_f.
		my $l_cmd = "in_f=\$(ls ${target_dir}${file_search_string}); if [ ! -z \"\$in_f\" ];then ext_and_gz=\$(basename \$in_f |sed 's:^.*\\([.]nii.*\\)\$:\\1:'); if [ ! -z \"\$ext_and_gz\" ];then ln -sf \$in_f $inputs_file\$ext_and_gz;else echo error getting ext from \$in_f;fi;fi;";

		if ($contrast =~ /(tensor|diffusion)\*headfile|m\*GenericAffine/ ){
		    $l_cmd="in_f=\$(ls ${target_dir}${file_search_string}); if [ ! -z \"\$in_f\" ];then ln -sf \$in_f $inputs_dir;fi;";
		}
		push(@master_cmd_list,' '.join(' || ',@c_cmds).' ; '.$l_cmd);
		#push(@master_cmd_list,$l_cmd);
	    }
	}
    }
    #$debug_val=50;
    Data::Dump::dump(@master_cmd_list) if $debug_val > 35; 
    confess if ($debug_val >= 50 && $debug_val < 100 ) ;
    return execute_indep_forks(1,"get my data",@master_cmd_list);
    #print "Return = $return";
} 
1;
