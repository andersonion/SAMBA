#!/usr/bin/env perl
# vbm_pipeline_start.pl
# originally created as vbm_pipeline, 2014/11/17 BJ Anderson CIVM
# vbm_pipeline_start spun off on 2017/03/14 BJ Anderson CIVM
#
# Roughly modeled after seg_pipe_mc structure. (For better or for worse.)
#

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename;
# List::MoreUtils is not part of CORE modules,
#  and is a heavy weight requirement for just
#  getting unique scalar values from an array.
# Roll your own uniq is near trivial, and is part of civm_simple_util now
# use List::MoreUtils qw(uniq);
#use JSON::Parse qw(json_file_to_perl valid_json assert_valid_json);

BEGIN {
    # Check required env vars that prove setup was done.
    # Workstation_home is not actually used, and probably should be omitted.
    my @env_vars=qw(ANTSPATH BIGGUS_DISKUS WORKSTATION_DATA WORKSTATION_HOME);
    use Env @env_vars;
    foreach (@env_vars ) {
        my $d=eval "\$$_";
        if (! -d $d ) {
            die "$_ NOT properly defined!";
        } else {
            #print("$_ got $d\n");
        }
    }
    $ENV{'PATH'}=$ANTSPATH.':'.$ENV{'PATH'};
    use Env qw(RADISH_PERL_LIB);
    if (! defined($RADISH_PERL_LIB)) {
        print STDERR "Cannot find good perl directories, quitting\n";
        exit;
    }
    use lib split(':',$RADISH_PERL_LIB);
}

use civm_simple_util qw(sleep_with_countdown activity_log printd uniq $debug_val 
write_array_to_file );

activity_log();
use pipeline_utilities;
use Headfile;

use lib dirname(abs_path($0));
use SAMBA_global_variables;
use SAMBA_structure;
use vars qw($start_file);

my $PM = 'vbm_pipeline_start.pl'; 
my $git_log=git_log_last(dirname(__FILE__));
my $PIPELINE_VERSION = $git_log->{"date"}." ".$git_log->{"commit"};
$PIPELINE_NAME="SAMBA";

use vbm_pipeline_workflow;

# Set pipeline utilities code dev group
if (exists $ENV{'CODE_DEV_GROUP'} && $ENV{'CODE_DEV_GROUP'} ne ''){
    $CODE_DEV_GROUP=$ENV{'CODE_DEV_GROUP'};
}
# pipeline_utilities uses GOODEXIT and BADEXIT, but it doesnt choose for you which you want. 
$GOODEXIT = 0;
$BADEXIT  = 1;

my $permission_mask=umask;
# Dont force permissions, this should be left up to users.
# We could specifiy an option for input if we think this is helpful at all.
if ( 0 ) {
    $permissions = 0755;
}
$permissions=0777 ^ $permission_mask;

$debug_val=45;

# a do it again variable, will allow you to pull data from another vbm_run
$test_mode = 0;

$schedule_backup_jobs=1;
### 
# simple input handling, 
# we accept a startup headfile, and/or a (number of nodes|reservation name)
# If we're doing start file, it must be first. 
$start_file=shift(@ARGV);
# Only if it looks like a number to we assign it to nodes.
# this in an attempt to simplify the following handling. 
if( ! defined $start_file ){
    die "Study_variables mode DISABLED! its too messy :P\nPlease create a startup headfile";
}
if ( ! -f $start_file && $start_file =~ /[^0-9]/ )  {
    $nodes = $start_file;
    $start_file = '';
} else {
    $nodes = shift(@ARGV);
}

# nodes is either a number at this point, nothing or a string.
# startfile is either a file path or an empty string.
# nodes and reservation are exclusive, so if nodes is > 0 len string it must be a reservation.
$reservation='';
if (! defined $nodes || $nodes eq '' ) {
    $nodes = 4 ;
} elsif( $nodes !~ /^[0-9]+$/ ) {
    # filter nodes string to only valid reservation characters
    ($reservation ) = $nodes=~ /([[:alnum:]:_-]+)/x ;
    my $cmd="scontrol show reservation \"${reservation}\"";
    my $reservation_info = qx/$cmd/;
    # Unsure if I need the 'm' option)
    if ($reservation_info =~ /NodeCnt=([0-9]*)/m) {
        $nodes = $1;
        # this slurm handling really belongs in some kinda cluter_env_cleaner function ....
        if ( cluster_scheduler() =~ /slurm/ ){
            printd(5,"Using slurm scheduler\n");
            $ENV{'SBATCH_RESERVATION'}=$reservation;
            $ENV{'SLURM_RESERVATION'}=$reservation;
        }
    } else {	
        warn "\n\n\n\nINVALID RESERVATION REQUESTED: unable to find reservation \"$reservation\".\n\n\n".
            " Maybe your start file($start_file) was not found !\n";
	#" Will start with # $nodes nodes in a few seconds."; 
	undef $reservation;
	die;
    }
}
print "Attempting to use $nodes nodes;\n\n";
if ($reservation) { 
    print "Using slurm reservation = \"$reservation\".\n\n\n";
}


{
    if ($start_file =~ /.*\.headfile$/) {
        $start_file = abs_path($start_file);
        load_SAMBA_parameters($start_file);
        #} elsif ($start_file =~ /.*\.json$/) { # BJA, 6 June 2019: temporarily killing all JSON support until a robust solution is in place ensuring the JSON package is available in arbitrary user's environment.
        #    $start_file = abs_path($start_file);
        #    load_SAMBA_json_parameters($start_file); 
    } else {
        die "Study variables is not good, so its no longer allowed";
	# Commented this ugly beast out becuase it was deprecated long enough. 
	# require study_variables_vbm;
        # study_variables_vbm();
    }
    #if (! defined $do_vba) {
    #    $do_vba = 0;
    #}
    ### DO ALL WORK in pipe workflow
    vbm_pipeline_workflow();
} #end main
exit $GOODEXIT;

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

