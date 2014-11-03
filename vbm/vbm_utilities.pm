#vbm_utilities.pm
# Version 0.1, written by BJ Anderson
# created 14/10/28
#
# Wishlist of utilities:
#   connect_to_remote_host
#   get_project_name
#   archive_vbm_data

my $VERSION = "141028";
my $debug_val = 5;
use File::Path;
use POSIX;
use strict;
use warnings;
use English;

#use Net::SSH::Perl;


BEGIN {
    use Exporter;
    our @ISA = qw(Exporter); # perl cricit wants this replaced with use base; not sure why yet.
    our @EXPORT_OK = qw(
create_fake_tensor_headfile
); 
}

##  Temporarily hardcoded inputs
my $project_code = ; # Will be replaced by function to get from command line.
my $spec_id = ; # Will be replaced by function that looks at tensor archive.
my $starting_folder = '/Volumes/cretespace/hess/'; # Will be replaced by function to get from command line.
my $control_runnos = ; # Will be replaced by function to get from command line.

# -------------
sub DTI_MDT_through_seg_pipe_mc {
# -------------
   my ($log_me) = @_;

#   create_headfile;
#   parse_inputs;
#   create_tensor_directory
#   rename_MDT_master_channel; # ...and move to tensor directory
#   transform_other_channels;
#   average_other_channels;
#   create_fake_tensor_headfile;

}


# -------------
sub create_fake_tensor_headfile {
# -------------
   my ($log_me) = @_;

}

1;
