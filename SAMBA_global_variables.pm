#!/usr/bin/false
# SAMBA_global_variables.pm
# Originally written by James Cook & BJ Anderson, CIVM
# A messy but singluar place to globalize all the globals.
# When you "use" this file, you get all these globals.
# INSTEAD YOU CAN "require" this,
# then pluck out individuals with ${SAMBA_global_variables::variable_name}
# (Maybe that highlights a path away from 100 globals to concise limited scoping?)
# This is done for very select functions in pipeline utilities so that these
# variables don't destroy the current namespace.
#
# It should be evident that Any code using a SAMBA_global_variable IS SAMBA CODE,
# and therefore shouldn't be separate.
#
# Broadly these are variables from our input headfile we want to share,
# with some additions.
#
# Adding limited support functions, but really want to keep this pm
# ultra minimal.
# Derrived vars will be functions operating on the existing vars.
#
# SUBROUTINES:
# populate  -  taking a hf object populate our vars.
# all_runnos - combine the relevant vars to create an array of all runnos.
#
package SAMBA_global_variables;
use strict;
use warnings;

my $PM = "SAMBA_global_variables.pm";
my $VERSION = "2019/01/16";
my $DESC = "Master list of all global variables to be used by SAMBA, to be called in MAIN.";
my $NAME = $PM =~ s/\.pm//;

use civm_simple_util qw( uniq printd $debug_val);

BEGIN {
    use Exporter;
    our @ISA = qw(Exporter); # perl critic wants this replaced with use base; not sure why yet.
    #@EXPORT_OK is preferred, as it markes okay to export, HOWEVER our code is dumb and needs to force import all them things...
    # (requires too much brainpower for the time being to implement correctly).

    our @EXPORT = qw(
$project_name
@control_group
$control_comma_list
@compare_group
$compare_comma_list

$complete_comma_list

@group_1
$group_1_runnos
@group_2
$group_2_runnos
$all_groups_comma_list

@channel_array
$channel_comma_list

$custom_predictor_string
$template_predictor
$template_name

$flip_x
$flip_z
$optional_suffix
$rigid_atlas_name
$label_atlas_name
$label_transform_chain
$label_input_file
$label_atlas_nickname
$make_individual_ROIs

$skull_strip_contrast
$threshold_code
$do_mask
$pre_masked
$port_atlas_mask
$port_atlas_mask_path
$thresh_ref

$rigid_contrast

$affine_contrast
$affine_metric
$affine_radius
$affine_shrink_factors
$affine_iterations
$affine_gradient_step
$affine_convergence_thresh
$affine_convergence_window
$affine_smoothing_sigmas
$affine_sampling_options
$affine_target

$mdt_contrast
$mdt_creation_strategy
$mdt_iterations
$mdt_convergence_threshold
$initial_template
$stop_after_mdt_creation

$compare_contrast

$diffeo_metric
$diffeo_radius
$diffeo_shrink_factors
$diffeo_iterations
$diffeo_transform_parameters
$diffeo_convergence_thresh
$diffeo_convergence_window
$diffeo_smoothing_sigmas
$diffeo_sampling_options

$vbm_reference_space
$reference_path
$resample_images
$resample_factor

$register_MDT_to_atlas
$create_labels
$label_space
$label_reference_space

$do_vba
$fdr_masks
$tfce_extent
$tfce_height
$fsl_cluster_size

$nonparametric_permutations

$convert_labels_to_RAS
$tabulate_statistics
$eddy_current_correction
$do_connectivity
$recon_machine

$original_study_orientation
$working_image_orientation

$fixed_image_for_mdt_to_atlas_registratation

$vba_contrast_comma_list
$vba_analysis_software
$smoothing_comma_list

$U_specid
$U_species_m00
$U_code

$image_dimensions

$participants

@comparisons
@predictors

$civm_ecosystem
$ref_runno

$dims
$ants_verbosity
$broken
$permissions
$test_mode
$nodes
$reservation
$Hf
$mdt_to_reg_start_time

$samba_label_types
$valid_formats_string
 );
    # looks like we dont need to export if we call direct, and i'd rather call direct.
    #Non-default export of the functions
#    our @EXPORT_OK = qw(
#populate
#);

    # make all of these vars "SAMBA_global_variables" package variables "properly"
    # using our, in a nasty eval one liner
    my $dirty_eval_string = 'our '.join('; our ',@EXPORT).';';
    eval($dirty_eval_string);
}

use SAMBA_global_variables;
sub populate {
    my ($tempHf)=@_;
    my @unused_vars;
    die if ! defined $tempHf;
    printd(5,"Transcribing input headfile to variables\n");
    # For all variables in the given headfile, populate a samba global named the same.
    foreach ($tempHf->get_keys) {
        my ($v_ok,$val) = $tempHf->get_value_check($_);
        if ( exists $SAMBA_global_variables::{$_}
             && $v_ok && defined $val) {
            eval("\$$_=\'$val\'");
            printd(5,"\t".$_." = $val\n");
        } else {
            push(@unused_vars,$_);
        }
    }
    return @unused_vars;
}

#
# Subroutine definintions below.
#
# it occurs to me that these subroutines really belong to samba_globals or pipeline_workflow as exported functions.
# that'd let other pipelines open up samba input files in more meaningful ways.

# ------------------
sub load_SAMBA_parameters {
# ------------------
    my ($param_file) = (@_);
    my $tempHf = new Headfile ('ro', "${param_file}");
    if (! $tempHf->check()) {
        error_out(" Unable to open SAMBA parameter file ${param_file}.");
        return(0);
    }
    if (! $tempHf->read_headfile) {
        error_out(" Unable to read SAMBA parameter file ${param_file}.");
        return(0);
    }
    my $is_headfile=1;
    assign_parameters($tempHf,$is_headfile);
}

# ------------------
sub load_SAMBA_json_parameters {
# ------------------
    my ($json_file) = (@_);
    my $tempHf = json_file_to_perl($json_file);
    if (0){
        eval {
            assert_valid_json (  $json_file);
        };
        if ($@) {
            error_out("Invalid .JSON parameter file ${json_file}: $@\n");
            #}
            #if (! valid_json($json_file)) {
            #    error_out(" Invalid .JSON parameter file ${json_file}.");
            return(0);
        }
    }

    my $is_headfile=0;
    assign_parameters($tempHf,$is_headfile);
}

# ------------------
sub assign_parameters {
# ------------------
# Replicate input parameter variable values into globals WHERE they're named the same.
# Handles some implied options
    my ($tempHf,$is_headfile) = (@_); # Current headfile implementation only supports strings/scalars
    my @unused_vars;
    if ($is_headfile) {
        @unused_vars=SAMBA_global_variables::populate($tempHf);
    } else {
        # Life would be easier if we loaded json to a headfile, then this segment wouldn't need exist.
        foreach (keys %{ $tempHf }) {
            #if ($kevin_spacey =~ /\b$_\b/) {
            if ( exists $SAMBA_global_variables::{$_} ) {
                #my $val = %{ $tempHf }->{($_)};
                #print "\n\n$_\n\n";
                die "json mode requires revalidation!!!";
                my $val;
                $val = %{ $tempHf ->{$_}}; # Option A: take hash in tempHf and store as scalar
                $val = $tempHf->{$_};  # Option B (more likely to be right): Store reference (scalar array hash) as val.
                #my $val = %{ $tempHf }->{$_}; # This is as originally formulated, but not quite right.
                if ($val ne '') {
                    #print "LOOK HERE TO SEE NOTHING\$val = ${val}\n";
                    if ($val =~ /^ARRAY\(0x[0-9,a-f]{5,}/){
                        eval("\@$_=\'@$val\'");
                        print "$_ = @{$_}\n";
                    } elsif ($val =~ /^HASH\(0x[0-9,a-f]{5,}/){
                        eval("\%$_=\'%$val\'");
                        print "$_ = %{$_}\n";

                    } else { # It's just a normal scalar.
                        eval("\$$_=\'$val\'");
                        print "$_ = ${$_}\n";
                        if ($_ eq 'rigid_atlas_name') {
                            # tmp_rigid is assigned direct later straight from the global,
                            # that should give identical behavior for undefined's
                            #eval("\$tmp_rigid_atlas_name=\'$val\'");
                        }
                    }
                }
            } else {
                push(@unused_vars,$_);
            }
        }
    }

    if(scalar(@unused_vars) ) {
        Data::Dump::dump(["Some headfile vars were not used, That is probably an error.",
                          "Feeding a result headfile back in is not currnetly supported.",
                          \@unused_vars,
                          "Press ctrl+c to cancel"]) if can_dump();
        sleep_with_countdown(15);
    }
    # do some default assignment
    my @ps_array;

    if ( defined $project_name) {
        printd(40,"project_name:$project_name\n");
    } else {
        printd(5,"UNTESTED CODE PATH: Watch carefully, and yell at programmer.\n");
        sleep_with_countdown(4);
        my $project_string;
        if ($is_headfile) {
            $project_string = $tempHf->get_value('project_id');
        } else {
            die "json mode requires revalidation!!!";
            $project_string = %{ $tempHf ->{"project_id"}}; # Option A: take hash in tempHf and store as scalar
            $project_string = $tempHf->{"project_id"};  # Option B (more likely to be right): Store reference (scalar array hash) as val.
            # $project_string = %{ $tempHf }->{"project_id"}; # This is as originally formulated, but not quite right.
        }
        @ps_array = split('_',$project_string);
        shift(@ps_array);
        my $ps2 = shift(@ps_array);
        if ($ps2  =~ /^([0-9]+)([a-zA-Z]+)([0-9]+)$/) {
            $project_name = "$1.$2.$3";
        }

        # If opt suffix undefined, make it the ps_array
        # making this the empty string most of the time.
        if (! defined $optional_suffix) {
            $optional_suffix = join('_',@ps_array);
            # tmp var was localized here because it's looks suspiciously like old garbage.
            my $tmp_rigid_atlas_name=$rigid_atlas_name;
            if ($tmp_rigid_atlas_name ne ''){
                $optional_suffix =~ s/^(${tmp_rigid_atlas_name}[_]?)//;
            }
            warn("No optional sufix, auto-guessing set to ($optional_suffix)\n");
        }
    }

    # pre_masked and do_masked are exclusive options, if one is true the other shouldn't be.
    # They can both be set which will probably work, and is likely a waste of time.
    # Originally this code didn't handle the case where neither was set.
    # Now adjusting that to the expected default of do_mask on, but we'll give a warning.
    if (! defined $pre_masked && ! defined $do_mask ) {
        printd(5,"mask choices not specified, forcing do_mask on.\n");
        sleep_with_countdown(3);
        $do_mask=1;
    }
    $pre_masked = ! $do_mask unless defined $pre_masked;
    $do_mask = ! $pre_masked unless defined $do_mask;

    ### shortended version of original code
    #if ((! defined ($pre_masked)) && (defined ($do_mask))) {
    #  $pre_masked = ! $do_mask; }
    # if ((defined ($pre_masked)) && (! defined ($do_mask))) {
    #  $do_mask = !$pre_masked; }

    $port_atlas_mask = 0 unless defined $port_atlas_mask;
    if (($test_mode) && ($test_mode eq 'off')) { $test_mode = 0;}

    if (defined $channel_comma_list) {
        # Filter vbm and non 3d channels from our channel list.
        my @CCL = split(',',$channel_comma_list);
        foreach (@CCL) {
            if ($_ !~ /(jac|ajax|nii4D)/) {
                push (@channel_array,$_);
            } else {
                warn("channel $_ is a special channel, and should not be part of the channel_comma_list, filtering it out.\n"
                    ."\t(Don't worry it'll be used appropriately later.)\n");
            }
        }
        @channel_array = uniq(@channel_array);
        $channel_comma_list = join(',',@channel_array);
    }
    # Formerly did an auto assign of optional suffix, but it was form the json only code path,
    # so that was moved into that if condition.
}



sub all_runnos {
    # After the globals have been loaded, and populate has been run we can see the derived var
    # all_runnos

    # While very tempting to create a function for group1, 2 compare and control in addition
    # to this one, it will be resisted for now because those are all bad groups for different reasons.

    # only group1 and group2 are expected to be exclusive, and that is not controlled here.
    # Group names are somewhat misleading here,
    # Control really means "mdt" group, and compare means "Not-mdt" group.
    # For the forseeable use cases what we really need is, MDT group, and Complete group.

    # The group management code takes advantage of the behaviorof push with empty arrays.
    @group_1 = split(',',$group_1_runnos) if defined $group_1_runnos;
    @group_2 = split(',',$group_2_runnos) if defined $group_2_runnos;

    if ( defined $control_comma_list ) {
        @control_group = split(',',$control_comma_list) ;
    } else {
        push(@control_group,@group_1);
        push(@control_group,@group_2);
    }
    if (defined $compare_comma_list) {
        @compare_group = split(',',$compare_comma_list);
    } else {
        @compare_group = @control_group;
    }
    push(@compare_group,@group_1);
    push(@compare_group,@group_2);

    # becuase we make no attempt to be clean about replication or runnos earlier, we need to uniq now.
    @control_group=uniq(@control_group);
    @compare_group=uniq(@compare_group);

    return uniq(@control_group,@compare_group);
}

1;
