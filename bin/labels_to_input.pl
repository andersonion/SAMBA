#!/usr/bin/env perl
# To keep up with ever improving boiler plate ideas, this exists to capture them
# Boilerplate code is rarely updated, but often it's a good idea.
# So this'll exist as a record of the "current standard" maybe, riddled with me 
# explaining things to ... me.
# 
# Special sha-bang finds default perl. This should be correct most the time from here forward.
use strict;
use warnings FATAL => qw(uninitialized);
# carp and friends, backtrace yn, fatal yn
use Carp qw(cluck confess carp croak);
our $DEF_WARN=$SIG{__WARN__};
our $DEF_DIE=$SIG{__DIE__};
# Seems like it'd be great to have this signal handler dependent on debug_val.
# hard to wire that into a general concept.
#$SIG{__WARN__} = sub { cluck "Undef value: @_" if $_[0] =~ /undefined|uninitialized/;&{$DEF_WARN}(@_) };
$SIG{__WARN__} = sub { cluck "Undef value: @_" if $_[0] =~ /undefined|uninitialized/;
if(defined $DEF_WARN) { &{$DEF_WARN}(@_)} };


#### VAR CHECK
# Note, vars will have to be hardcoded becuased this is a check for env.
# That means, ONLY variables which will certainly exist should be here.
# BOILER PLATE
BEGIN {
    # we could import radish_perl_lib direct to an array, however that complicates the if def checking.
    my @env_vars=qw(RADISH_PERL_LIB BIGGUS_DISKUS WORKSTATION_DATA WORKSTATION_HOME);
    my @errors;
    use Env @env_vars;
    foreach (@env_vars ) {
	push(@errors,"ENV missing: $_") if (! defined(eval("\$$_")) );
    }
    die "Setup incomplete:\n\t".join("\n\t",@errors)."\n  quitting.\n" if @errors;
}
use lib split(':',$RADISH_PERL_LIB);
# my absolute fav civm_simple_util components.
use civm_simple_util qw(activity_log printd $debug_val);
# On the fence about including pipe utils every time
use pipeline_utilities;
# pipeline_utilities uses GOODEXIT and BADEXIT, but it doesnt choose for you which you want. 
$GOODEXIT = 0;
$BADEXIT  = 1;
# END BOILER PLATE
use Headfile;
use civm_simple_util qw(trim);

# needs to take pre_rigid refspace labels and transform them back through the translator to input space.
# We may need to re-create our ref image becuase we're running someplace else.
# Args then are translation tform, "pristine input" ref_image label file


sub main {

    my (@input_things)=@_;
    my $options ={};

    # An original dwi
    ${$options->{"translator=s"}}="";
    ${$options->{"dwi_path=s"}}="";
    # In the off chance our dwi is already a good reference
    ${$options->{"dwi_is_ref"}}=0;
    #
    ${$options->{"runno_base=s"}}="";
    ${$options->{"dir_work=s"}}="";    
    # If labels, we'll be connectoming. Otherwise we'll just track a TDI
    ${$options->{"labels_in=s"}}="";
    ${$options->{"labels_out=s"}}="";
    ${$options->{"label_lookup=s"}}="";
    # label_filename in the output label_subdir ?
    # re-orient labels from currentorientation,neworientation
    ${$options->{"label_reorient=s"}}="";

    # ugly issue when deref-ing scalars
    # If we want scalar refs, options'll be broken down.
    # They'll probably be set proper by getoptions, then we break the connection between the option hash
    # and the proscribed scalar, so MAYBE that's alright?
    ${$options->{"auto_opt_deref_scalar!"}}=1;
    # used this as chance to debug preserve_k and found a lot of ugly interactions with non-pure option names.
    #${$options->{"auto_opt_preserve_k"}}=0;
    ${$options->{"opt_feedback_testing"}}=0;

    # @input_things will be eaten up if we pass it by ref, eg \@
    # If we want to preserve it, do plain @
    # OR, if we want to eat @ARGV dont pass anything
    $options=auto_opt($options,\@input_things);

    # Since sometimes we're looking for other machines to know things about them, it doesnt fail
    # if we fail to load, so we should check if its a valid var return.
    my $ED=load_engine_deps() || die "Failure to load settings for computer";
    $ED->print("Engine Settings") if $debug_val>=100;



    #open_log($options->{"dir_work"});
    ###
    # extened opt checking
    my @o_code=split('[ ,-:]+',$options->{"label_reorient"});
    if (scalar(@o_code) != 2 ) {
	error_out("Bad re-orientation request($options->{label_reorient}), need two comma separated elements!");
    }
    ###

    ###
    # Env finding
    # tie env path to path array for convenience
    use Env qw(@PATH);
    # add ants path to beginning of path
    unshift(@PATH,$ED->get_value('engine_app_ants_dir'));
    ###

    ### Set up or find dwi reference.
    my @cmds;
    my $ref_dwi="";
    if(! $options->{"dwi_is_ref"} ){
	if (! -e $options->{"dwi_path"}){
	    error_out("Missing dwi at ".$options->{"dwi_path"});
	}
	
	$ref_dwi=File::Spec->catfile($options->{"dir_work"},"ref_dwi.nii");
	my @__args=($options->{"dwi_path"},
		    trim($o_code[1]),
		    trim($o_code[0]),
		    $ref_dwi,
		    "1",
		    "1"
	    );
	my $mat_args="'".join("', '",@__args)."'";
	push(@cmds,make_matlab_command_nohf("img_transform_exec",$mat_args,
					    $options->{"runno_base"}."_dwi_to_".$o_code[0]."_",
					    $options->{"dir_work"}
					    ,$ED->get_value("engine_app_matlab")
					    ,File::Spec->catfile($options->{"dir_work"},$options->{"runno_base"}."_dwi_reorient_matlab.log")
					    ,$ED->get_value("engine_app_matlab_opts"), 0)
	    ) if(! -e $ref_dwi);
	
    } else {
	$ref_dwi=$options->{"dwi_path"};
    }
    
=item ants command to move from analysis to preprocess
    echo "Run ants apply for to translate into preprocess";
    antsApplyTransforms -d 3 -e 0 -o $labels_pre -i $labels -r $pre_refspace -t [$tform,1] --interpolation NearestNeighbor
=cut
    my $label_tmp=File::Spec->catfile($options->{"dir_work"},"labels_tmp.nii.gz");
    my $cmd=File::Spec->catfile($ED->get_value('engine_app_ants_dir'),"antsApplyTransforms")
	." -d 3 -e 0 -o $label_tmp -i $options->{labels_in} -r $ref_dwi -t [$options->{translator},0] --interpolation NearestNeighbor";
    push(@cmds,$cmd) if (! -e $label_tmp);
    
=item bash code to move from preprocess to inputs
	tform='R:\19.gaj.43\200316-1_1\slicer\SAMBA_temp\VBM_19gaj43_'"${RIGID_ATLAS}"''"${SUFFIX}"'-inputs\PREPROCESS_to_INPUTS.mat';
    echo "Run ants apply to reorient back to input";
    antsApplyTransforms  -d 3 -e 0 -o $labels_input -i $labels_pre -r $input_refspace --interpolation NearestNeighbor -t $tform
=cut

    #% function niiout=img_transform_exec(img,current_vorder,desired_vorder,output_path,write_transform,recenter)
    my @__args=($label_tmp,
		trim($o_code[0]),
		trim($o_code[1]),
		$options->{"labels_out"},
		"1",
		"1"
	);
    my $mat_args="'".join("', '",@__args)."'";
    push(@cmds,make_matlab_command_nohf("img_transform_exec",$mat_args,$options->{"runno_base"}."_label_orient_",
					$options->{"dir_work"}
					,$ED->get_value("engine_app_matlab")
					,File::Spec->catfile($options->{"dir_work"},$options->{"runno_base"}."_label_reorient_matlab.log")
					,$ED->get_value("engine_app_matlab_opts"), 0)
	)if(! -e $options->{"labels_out"});
    
=item
    if(! execute(! -e $options->{"labels_out"}, @cmds)){
	error_out("Trouble preparing labels!");
    } else {
    
    }
=cut
    if(civm_simple_util::can_dump()){
	Data::Dump::dump(["Commands to run:",\@cmds]);
    }
    foreach(@cmds){
	run_and_watch($_);
    }
    if ( -e $options->{"labels_out"} ){
	printd(5,"Labels ready: $options->{labels_out}\n");
    } else {
	error_out("Failed to create  $options->{labels_out}\n");
    }

    #open_log($options->{"dir_work"});
}


main(@ARGV);

exit 0;
