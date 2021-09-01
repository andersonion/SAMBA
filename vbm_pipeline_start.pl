#!/usr/bin/env perl
# vbm_pipeline_start.pl
# originally created as vbm_pipeline, 2014/11/17 BJ Anderson CIVM
# vbm_pipeline_start spun off on 2017/03/14 BJ Anderson CIVM
#
# Roughly modeled after seg_pipe_mc structure. (For better or for worse.)
#

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

use Cwd qw(abs_path);
use File::Basename;
use POSIX qw(ceil);

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
    use Env qw(RADISH_PERL_LIB CODE_DEV_GROUP);
    if (! defined($RADISH_PERL_LIB)) {
        print STDERR "Cannot find good perl directories, quitting\n";
        exit;
    }
    use lib split(':',$RADISH_PERL_LIB);
}

use civm_simple_util qw(write_array_to_file sleep_with_countdown activity_log printd uniq can_dump $debug_val);

activity_log();
use pipeline_utilities;

use Headfile;
# New fangled ants pm from pipeline_utilities
use ants;

use lib dirname(abs_path($0));
use SAMBA_global_variables;
use SAMBA_structure;
# we share the start_file var... maybe it should be in global vars?
use vars qw($start_file);
use vbm_pipeline_workflow;

my $PM = 'vbm_pipeline_start.pl';
my $git_log=git_log_last( abs_path(__FILE__));
my $PIPELINE_VERSION = $git_log->{"date"}." ".$git_log->{"commit"};
$PIPELINE_NAME="SAMBA";

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
# Used to always schedul backup jobs, but right now wanna shut it off for more rapid failure
$schedule_backup_jobs=0;

#my $opts={};
our $opts={};
${$opts->{"only-precondition"}}=0;
#Special debug option to prepare work, but NOT schedule it, will quit right after preparation
${$opts->{"deactivate-scheduling"}}=0;
$opts=auto_opt($opts,\@ARGV);

###
# simple input handling,
# we accept a startup headfile, and/or a (number of nodes|reservation name)
# If we're doing start file, it must be first.
$start_file=shift(@ARGV);
$start_file=trim($start_file);
# Only if it looks like a number do we assign it to nodes.
# this in an attempt to simplify the following handling.
if( ! defined $start_file ){
    die "Study_variables mode DISABLED! its too messy :P\nPlease create a startup headfile";
}
if ( ! -f $start_file && $start_file =~ /^[0-9]+$/ )  {
    die("NO FILE\n");
    $nodes = $start_file;
    $start_file = '';
} else {
    $nodes = shift(@ARGV);
    $nodes=trim($nodes);
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
    # Unsure if I need the 'm' option)
    if (cluster_check()) {
        my $cmd="scontrol show reservation \"${reservation}\"";
        my ($reservation_info) = run_and_watch($cmd,0);
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
        SAMBA_global_variables::load_SAMBA_parameters($start_file);
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

