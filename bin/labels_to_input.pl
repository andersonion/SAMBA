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
use civm_simple_util qw(file_mod_extreme find_file_by_pattern trim);

# needs to take pre_rigid refspace labels and transform them back through the translator to input space.
# We may need to re-create our ref image becuase we're running someplace else.
# Args then are translation tform, "pristine input" ref_image label file

# First pass was coded for img_transform_exec case of half/way okay nii inputs
# Need to now accomidate NHDR resamply inputs which have an additional step, and don't use img_transform_exec


sub main {

    my (@input_things)=@_;
    my $options ={};

    # An original dwi
    #dwi from diffusion directorye exactly OR from appropriate point in samba data handling, generally preprocess.
    ${$options->{"dwi_path=s"}}="";
    ${$options->{"translator=s"}}="";
    # translator use inv
    ${$options->{"translator_inv"}}=1;
    # In the off chance our dwi is already a good reference
    ${$options->{"dwi_is_ref"}}=0;
    #
    ${$options->{"runno_base=s"}}="";
    ${$options->{"dir_work=s"}}="";
    ${$options->{"labels_in=s"}}="";
    ${$options->{"labels_out=s"}}="";
    ${$options->{"labels_lookup=s"}}="";
    # labels_filename in the output labels_subdir ?
    # re-orient labels from currentorientation,neworientation
    ${$options->{"label_reorient=s"}}="";
    # Only used some times, currently, when we used custom NHDR files as our input.
    ${$options->{"samba_inputs=s"}}="";
    ${$options->{"samba_work=s"}}="";


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

    # if newest file is not input, we're done.
    #  We cant check if newest file is output, becuase it wont exist yet for new work.
    if(file_mod_extreme([$options->{"labels_in"},$options->{"labels_out"}],"new") ne $options->{"labels_in"}) {
        printd(5,"Work complete, quiting\n");
        exit(0);
    }

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

        $ref_dwi=File::Spec->catfile($options->{"dir_work"},"preproces_ref_dwi.nii");
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
    my $labels_preprocess=File::Spec->catfile($options->{"dir_work"},"preprocess_labels.nii");
    my $label=$labels_preprocess;
    if($o_code[0] eq $o_code[1]){
    #    $label=$options->{"labels_out"};
    }
    my $cmd=File::Spec->catfile($ED->get_value('engine_app_ants_dir'),"antsApplyTransforms")
        ." -v -d 3 -e 0 -o $label -i $options->{labels_in} -r $ref_dwi -t [ $options->{translator} ,$options->{translator_inv} ] --interpolation NearestNeighbor";
    push(@cmds,$cmd) if (! -e $label);

##
# labels_tmp is now in preprocess space.
##
# Depending on samba inputs, this maybe a simple img_transform_exec run,
# OR it maybe more complicated using, however, the more complicated behavior failed!
# 1) copy_header preprocess->inputs(conv)
# 2) resampleiamgebyref inputs(conv)->inputs

# this is only used if we've got the same orientation code forward and backward.
my $conv_dir=File::Spec->catdir($options->{"samba_inputs"},"conv_nhdr");
=item bash code to move from preprocess to inputs
        tform='R:\19.gaj.43\200316-1_1\slicer\SAMBA_temp\VBM_19gaj43_'"${RIGID_ATLAS}"''"${SUFFIX}"'-inputs\PREPROCESS_to_INPUTS.mat';
    echo "Run ants apply to reorient back to input";
    antsApplyTransforms  -d 3 -e 0 -o $labels_input -i $labels_pre -r $input_refspace --interpolation NearestNeighbor -t $tform
=cut
    if($o_code[0] ne $o_code[1] && ! -e $options->{"labels_out"}){
        #% function niiout=img_transform_exec(img,current_vorder,desired_vorder,output_path,write_transform,recenter)
        my @__args=($labels_preprocess,
                    trim($o_code[0]),
                    trim($o_code[1]),
                    $options->{"labels_out"},
                    "1",
                    "1"
            );
        my $mat_args="'".join("', '",@__args)."'";
        push(@cmds,make_matlab_command_nohf("img_transform_exec",$mat_args,$options->{"runno_base"}."_labels_orient_",
                                            $options->{"dir_work"}
                                            ,$ED->get_value("engine_app_matlab")
                                            ,File::Spec->catfile($options->{"dir_work"},$options->{"runno_base"}."_label_reorient_matlab.log")
                                            ,$ED->get_value("engine_app_matlab_opts"), 0)
            )if(! -e $options->{"labels_out"});
    }elsif( -e $options->{"samba_inputs"} && -e $options->{"samba_work"}
            && -d $conv_dir ) {
        my $labels_conv=File::Spec->catfile($options->{"dir_work"},"conv_labels.nii");
        # else it should
        #  $options->{"samba_inputs"}
        #  $options->{"samba_work"}) {
        #Usage:  CopyImageHeaderInformation refimage.ext imagetocopyrefimageinfoto.ext imageout.ext   boolcopydirection  boolcopyorigin boolcopyspacing  {bool-Image2-IsTensor}
        my ($ref) = find_file_by_pattern($conv_dir,$options->{"runno_base"}.".*dwi[.]n.*",1);
        push(@cmds,"CopyImageHeaderInformation $ref $labels_preprocess $labels_conv 0 1") if ! -e $labels_conv;
        #error this didnt work!!! we have a1,1 voxel discrepancy from preprocess to conv(when respecting headers!)
        # To track down error, loaded data headerless, and found.
        #     label preprocess->conv identical(ImageJSubtraction)
        #       dwi preproces->>conv identcial(ImageJSubtraction)
        # IT seems the problem was a missing "copy origin" flag Added that and this process now works as expected!
        #push(@cmds,"antsApplyTransforms -v -d 3 -e 0 -i $labels_preprocess -o $labels_conv -r $ref --interpolation NearestNeighbor") if ! -e $labels_conv;
        # a dwi input.
        ($ref) = find_file_by_pattern($options->{"samba_inputs"},$options->{"runno_base"}.".*dwi[.]n.*",1);
        push(@cmds,"antsApplyTransforms -v -d 3 -e 0 -i $labels_conv -o $options->{labels_out} -r $ref --interpolation NearestNeighbor") if ! -e $options->{"labels_out"};
    }
    #die "TESTING\n\n".join("\n\n",@cmds);
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
