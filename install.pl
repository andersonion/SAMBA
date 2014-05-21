#!/usr/bin/perl
# unfortunately involved installer to get shell settings right currently only works for bash shell.
#
# copies and edits the environment.plist from pipeline_settings/mac to ~/.MacOSX/environment.plist
# that plist calls on .bash_env_to_mac_gui run .bash_profile,
# it makes sure .bash_profile has at least one line, source .bashrc
# adds a source .bash_workstation_settings file to user's .bashrc file
# adds several symbolic links to support the legacy radish code
# extracts tar files for oracle and legacy radish code to reasonable places
# 
# requirements! and assumptions!
#    a working directory, it assumes the current directory is where you started from and 
# that you've run the svn co svn+ssh://pathtorepository/workstation_code/trunk software
# HAS NOT BEEN TESTED IN LOCATIONS OTHER THAN /Volumes/workstation_home/software. That could use work!.
# the user running the script has administrative access, IF NOT, will still update shell settings.
# 
use strict;
use warnings;
use ENV;
use File::Basename;
use Cwd 'abs_path';
use Sys::Hostname;
use File::Find;
use Getopt::Std;
#print basename($ENV{SHELL})."\n";
my %opts;
if ( ! getopts('p',\%opts) ) { 
    print("Option error\n");
    exit;
}

my $shell =  basename($ENV{SHELL});
my $wks_home=dirname(abs_path($0));
my $data_home="/Volumes/workstation_data/data";
#wks_home= /volumes/workstation_home/software
#if hostname is cluster
if ( 0 ) 
{

$data_home="$wks_home/../data"
}
my $oracle_inst="$wks_home/../oracle"; 
my $oracle_version="11.2";
my $hostname=hostname;
# if allowed to check.
my $name=getpwuid( $< ) ;
my $isadmin=`id | grep -c admin`;chomp($isadmin);
my $isrecon=`id | grep -c recon`;chomp($isrecon);
my $isipl=`id | grep -c ipl`;chomp($isipl);

my @alist = split(/\./, $hostname) ;
my $arch=`uname -m`;
chomp($arch);
$hostname=$alist[0];

#check for install.pl in wks_home to make sure we're running in right dir.
# ... later
# svn info to check installpl location.

exit;
quit;
stop();
error();



print("use source ~/.bashrc to enable settings now, otherwise quit terminal or restart computer\n");


