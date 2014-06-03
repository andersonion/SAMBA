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
use Getopt::Long;
use Scalar::Util qw(looks_like_number);

use lib $ENV{PWD}.'/install';
#use lib split(':',$RADISH_PERL_LIB);
require install::subroutines;
require install::order;



Getopt::Long::Configure ("bundling", "ignorecase_always");


my %dispatch_table=(); # look up of option function names to function refer3ences
my %dispatch_status=();# look up to hold if we've run a function or not.
my %option_list=();    # list of options recognized, built from the dispatch table.
my %options=();        # the options specified on the command line.
#CraftOptionDispatchTable(\%dispatch_table,$ENV{PWD}.'/install');
CraftOptionDispatchTable(\%dispatch_table,$ENV{PWD}."/install","inst");

my $opt_eval_string=CraftOptionList( \%dispatch_table, \%option_list);


### debug check to seee we got functions for each option
# print ("Option_list is:\n");
# foreach ( keys %option_list ) {
#     #print "option:".$_."-> ".$option_list{$_}."\n";
#     print "option:".$_."\t\n";
# }

##################
## work directly on the dispatch table, but this doesnt suit our use case
## we want a default of do all options
## this is equiavalent to  GetOptions ('opt=i' => \&handler);
# if ( !GetOptions(%dispatch_table ) ) { 
#     print("Option error\n");
#     exit;
# }
##################


###
# get system information.
###
our $HOSTNAME=hostname;
our $ARCH=`uname -m`; chomp($ARCH);
my @alist = split(/\./, $HOSTNAME) ;
$HOSTNAME=$alist[0];
our $IS_MAC=0;#true always for now, should fix this to find linux
our $OS="$^O\n";
if ( $OS =~ /^darwin$/x ) {
    $IS_MAC=1;
} else { 
    
}
###
# get user information
###
our $DATA_HOME;
our $SHELL    = basename($ENV{SHELL});
our $WKS_HOME = dirname(abs_path($0));
our $HOME=$ENV{HOME};
#wks_home= /volumes/workstation_home/software
#if hostname is cluster
if ( !$IS_MAC ) {
   $DATA_HOME="$WKS_HOME/../data"
} else {
    print("Mac system, perhaps the old install.mac.pl would be more appropriate\n");
   $DATA_HOME="/Volumes/workstation_data/data";
}
# admin_group is allowed to modifiy any files and permissions, 
# edit_group is allowed to edit code and run recon/workstation code.
# user_group is allowed to run recon/workstation code. 
our $ADMIN_GROUP="admin";
our $EDIT_GROUP;
our $USER_GROUP="ipl";
if ( $IS_MAC ) {
    $EDIT_GROUP="recon" 
}else {
    $EDIT_GROUP="coders" 
}
our $IS_ADMIN=0;
our $IS_CODER=0;
our $IS_USER=0;
###
# process options
###
#print ("option specs are $opt_eval_string\n");
#if ( !GetOptions(\%option_list ) ) { 
#if ( !GetOptionsFromArray(\@ARGV,\%option_list ) ) { 
my $first_stage='';
if ( !GetOptions( eval $opt_eval_string,"admin_group=s" => \$ADMIN_GROUP, "WKS_HOME=s" => \$WKS_HOME,  "start_at=s" => \$first_stage) ) { 
    print("Option error\n");
    exit;
}

###
# get the options to be forced on or off.
###
my @force_on=();  # list of options which are forced on
my @force_off=(); # list of options which are forced off. forced off over rides forced on.
for my $opt ( keys %options)  {
    print ("force_processing for $opt") unless ($opt =~ m/^skip_(.*)$/x ) ;
    if( ($options{$opt} ) && ($opt =~ m/^skip_(.*)$/x ) ){
	push @force_off,$1;
	print (" off: $1\n");
    }elsif( ($options{$opt} ) ){
	push @force_on,$opt;
	print (" on: $1\n");
    } else {
	print("\n") unless ($opt =~ m/^skip_(.*)$/x ) ;
    }
}
#for my $opt(@force_on) { $options{$opt}=$opt; }
for my $opt(@force_off){ $options{$opt}=0; print("skip $opt\n"); }
for my $opt ( keys %options)  {
    if ($opt =~ m/^skip_(.*)$/x ) {}
    elsif($options{$opt}) {
	print ("$opt on!\n");
	if ( defined $dispatch_table{$opt} ) {
	    print("\tFUNCT_CALL:$dispatch_table{$opt}\n");
	}
    }
}

###
# run the installer stages
###
# if allowed to check.
my $name=getpwuid( $< ) ;
# using the id field, check for groups, $ADMIN_GROUP, $EDIT_GROUP, and $USER_GROUP.



#check for install.pl in wks_home to make sure we're running in right dir.
# ... later
# svn info to check installpl location.

# run all.
#for my $opt ( keys %dispatch_table)  {
### run in order
# could add a start from option as wel, with something like until we are the starting option remove options
my $found_first=0;

my @order_new = OptionOrder("inst");
my @order = OptionOrder("install/inst-order.txt");# could make this an option later....
if ($#order_new != $#order ) {
    print("error with optionorder function, it doesnt produce expected results when called with both possiblilites\n");
}
for ( my $i=0;$i<=$#order;$i++){
    my $opt=$order[$i];
    my $opt_n=$order_new[$i];
    if ( $opt ne $opt_n) {
	print("$opt!=$opt_n\n");
    }
# my $opt ( @order ) {
    
    $dispatch_status{$opt}=1;
}
for my $key (keys %dispatch_table ) {
    print ("finding $key in order\n");
    if ( ! defined $dispatch_status{$key} ){
	push @order, $key;
	print("\t missing, now added.\n");
    }
    $dispatch_status{$key}=0;
}
if ( 0 ) {
for my $opt ( @order ) {
#    print ("Run $opt\n");
    if ( ! $options{'skip_'.$opt} ) {
	if ( $opt =~ /$first_stage/ ) {
	    print ("Found Starting point\n");
	    $found_first=1;
	} else {
	    #found is not it.... 
	}
	if ( ( defined $dispatch_table{$opt})&& ( $found_first || ! length $first_stage ) ) { 
	    # for default behavior optinos{opt} is undefined, for force on it is is 1, for force off it is 0.
	    my $status=$dispatch_table{$opt}->($options{$opt} #put params in here.
		);
	    $dispatch_status{$opt}=$status;
	    if ( !$status ){
		print ("ERROR: $opt failed!\n");
	    } 
	} elsif ( ! defined $dispatch_table{$opt} ) { 
	    print ("$opt specified in order but no function found for it\n");
	} else {
	    print ("$opt not desired first file<$first_stage>\n");
	}
    }
}
} else {

    ProcessStages(\%dispatch_table,\%dispatch_status,\@order);
}
exit;
#quit;
stop();
error();



print("use source ~/.bashrc to enable settings now, otherwise quit terminal or restart computer\n");

