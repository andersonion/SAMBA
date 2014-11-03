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
use Env qw(RADISH_PERL_LIB);
if (! defined($RADISH_PERL_LIB)) {
    print STDERR "Cannot find good perl directories, quitting\n";
    exit;
}

use lib split(':',$RADISH_PERL_LIB);


use vbm_utilities;


## Sandbox #1: remote login to host using perl.
use Net::SSH::Perl;

my $host = "deepthought";
my $ssh = Net::SSH::Perl->new($host);
$ssh->login($user, $pass);
my($stdout, $stderr, $exit) = $ssh->cmd($cmd);
