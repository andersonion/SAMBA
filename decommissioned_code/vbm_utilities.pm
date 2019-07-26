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
#my $project_code = "13.colton.01"; # Will be replaced by function to get from command line.
#my $spec_id = 213; # Will be replaced by function that looks at tensor archive.
#my $starting_folder ="/Volumes/atlas2/13.colton.01/research" ; # Will be replaced by function to get from command line.
#my $control_runnos = ; # Will be replaced by function to get from command line.

# -------------
sub DTI_MDT_through_seg_pipe_mc {
# -------------
   my ($average_volume_folder,$channel,$fake_runno,$spec_id) = @_; #$project_code
  
   my ($local_input_dir,$local_work_dir,$local_result_dir,$result_headfile) = make_process_dirs("${fake_runno}Labels");
   my $average_name = "final_average.nii";

   my $main_channel_volume_name = "${fake_runno}_DTI_${channel}.nii";
   my $folder_2 = "${local_input_dir}/${fake_runno}";
   if (! -d $folder_2){
	    mkdir($folder_2 ) or die("couldnt create dir $folder_2");
   }

   my $tensor_hf_name = "${folder_2}/tensor${fake_runno}.headfile";
   my $tensor_string = "U_specid=${spec_id}-100:1";
   my $cmd_1 = "touch ${tensor_hf_name}";
   my $cmd_2 = "${tensor_string} > ${tensor_hf_name}";   
   my $cmd_3 = "cp ${average_volume_folder}/${average_name} ${folder_2}/${main_channel_volume_name}";

   system($cmd_1);
   system($cmd_2);
   if (! system($cmd_3)){
   print STDOUT "final_average_for_segpipe:   ${main_channel_volume_name} has been placed in ${folder_2} along with a headfile containing the line ${tensor_string}. \n   Now ready for use with seg_pipe_mc using option \"-e\" and RUNNO = ${fake_runno}. \n ";    
   } else {
       print STDOUT "final_average_for_segpipe:  FAIL: Unable to create all directories and files needed for use with seg_pipe_mc.\n";
   }

#   create_headfile;
#   parse_inputs;
#   create_tensor_directory
#   rename_MDT_master_channel; # ...and move to tensor directory
#   transform_other_channels;
#   average_other_channels;
#   create_fake_tensor_headfile;

}
# -------------
sub create_headfile {
# -------------
   my ($log_me) = @_;

}

# -------------
sub parse_inputs {
# -------------
   my ($study_name) = @_;

   my  @study = split('.',$study_name);
   if ($study[0] < 12) {
      my $atlas_name = "bobara-ann"; # WTF is this code?
   }

}

# -------------
sub rename_MDT_master_channel {
# -------------
   my ($log_me) = @_;

}

# -------------
sub transform_other_channels {
# -------------
   my ($log_me) = @_;

}

# -------------
sub average_other_channels {
# -------------
   my ($log_me) = @_;

}

# -------------
sub create_fake_tensor_headfile {
# -------------
   my ($log_me) = @_;

}


1;
