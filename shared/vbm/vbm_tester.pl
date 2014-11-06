#!/usr/local/pipeline-link/perl

use warnings;
use strict;

#use Posix; # Not sure why, but it seems like a good idea.
use English; # "America! Heck, yeah!"
use File::Path qw(make_path remove_tree);
require pipeline_utilities;

# generic includes
use Cwd qw(abs_path);
use File::Basename;
use lib dirname(abs_path($0));
use Env qw(RADISH_PERL_LIB WORKSTATION_HOME);
if (! defined($RADISH_PERL_LIB)) {
    print STDERR "Cannot find good perl directories, quitting\n";
    exit;
}

use lib split(':',$RADISH_PERL_LIB);

use lib ("${WORKSTATION_HOME}/shared/vbm");
use vbm_utilities;


## Sandbox #1: remote login to host using perl.
#use Net::SSH::Perl;

#my $host = "deepthought";
#my $ssh = Net::SSH::Perl->new($host);
#$ssh->login($user, $pass);
#my($stdout, $stderr, $exit) = $ssh->cmd($cmd);

## Start testing stuff 

my $project_code = "13.colton.01"; # Will be replaced by function to get from command line.
my $spec_id = "120413"; # Will be replaced by function that looks at tensor archive.
my $average_volume_folder="/glusterspace/BJ_test_fake_archive/" ; # Will be replaced by function to get from command line.
my $control_runnos = "N50122"; # Will be replaced by function to get from command line.
my $fake_runno = "MD12345";


DTI_MDT_through_seg_pipe_mc($average_volume_folder,'fa',$project_code,$fake_runno,$spec_id);
