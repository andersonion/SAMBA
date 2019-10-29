#!/usr/bin/false
# SAMBA_structure
# Originally written by James Cook 
# To better enable extension of the SAMBA bits this characterizes where
# different parts of data live. 
# Its value became clear as the semi-extenral data-packager was created.
# Primary use in the data-packger and archive prep.

package SAMBA_structure;
use strict;
use warnings;

my $PM = "SAMBA_structure.pm";
my $VERSION = "2019/10/29";
my $DESC = "Simple helper functions to defined the data layout so it's shareable with other code";
my $NAME = $PM =~ s/\.pm//;

BEGIN {
    use Exporter;
    our @ISA = qw(Exporter); # perl critic wants this replaced with use base; not sure why yet.
    #@EXPORT_OK is preferred, as it markes okay to export, HOWEVER our code is dumb and needs to force import all them things...
    # (requires too much brainpower for the time being to implement correctly).

    our @EXPORT_OK = qw(
main_dir
);
}


sub main_dir {
    my ($project_name,$count,$rigid_target,$optional_suffix)=@_;
    if ($optional_suffix ne '') {
        $optional_suffix = "_${optional_suffix}";
    }
    my $main_folder_prefix;
    if ($count==1) {
        $main_folder_prefix = 'SingleSegmentation_';
    } else  {
        $main_folder_prefix = 'VBM_';  ## Want to switch these all to 'SAMBA'
    }
    my @project_components = split(/[.]/,$project_name); # $project_name =~ s/[.]//g;
    my $main_dir =  join('',@project_components);
    ###create_identifer($project_name); ?
    $main_dir = $main_folder_prefix.$main_dir.'_'.$rigid_target.$optional_suffix; 
    return $main_dir;
}

1;
