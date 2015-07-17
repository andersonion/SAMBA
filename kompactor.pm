#!/usr/local/pipeline-link/perl
# kompactor.pm 





my $PM = "kompactor.pm";
my $VERSION = "2015/07/16";
my $NAME = "Folder compactor/dekompressor for archive or intermediate storage.";

use strict;
use warnings;
use File::stat;
no warnings qw(uninitialized);

#use vars qw($Hf $BADEXIT $GOODEXIT  $test_mode $permissions);
#require Headfile;
#require pipeline_utilities;

my $default_min_file_size = 1500; # Files smaller than this will not be gzipped.


# ------------------
sub folder_kompactor {  
# ------------------
    
    my (@folders)= @_;

    # Find all files in folder and subdirectories
    foreach my $folder (@folders) {
	my @all_files;
	my @files_to_process;

	my $kompressor_file = $folder.'/kompressor.txt';
	@all_files = `find $folder -type f`;
	foreach my $file (@all_files) {
	    chomp($file);
	     
	    # Ignore files already gzipped
	    if ($file !~ /\.gz$/) {
		# Find all files greater than 1500 bytes
		if (filesize_test($file)) {
		    push(@files_to_process,$file);
		}
	    }
	}

#	open(my $fh, '>', $kompressor_file) or die;

	foreach my $file_to_process (@files_to_process) {
	    `gzip ${file_to_process}`;
	    $file_to_process = s/${folder}//;
	   ` "${file_to_process}\n" >> ${kompressor_file}`;
	}
#	close ($fh);

	
    }
}


# ------------------
sub folder_dekompressor {
# ------------------
    



}


# ------------------
sub study_kompactor {
# ------------------
    my ($a_primary_study_folder,$target_folder) = @_;
    $a_primary_study_folder =~ /(.*)[\/]?[^\/]+[\/]?$/;
    my $parent_folder = $1;
    if ($parent_folder eq '') {
	$parent_folder = '/';
    }

    if (! defined $target_folder) {
	$target_folder = $parent_folder;
    }

    my $complete_study_prefix;
    my $return_status;  # 1 --> success, 0 --> fail

    if ($a_primary_study_folder =~ /(.*)[-]{1}(work | inputs | results)$/) {
	$complete_study_prefix = $1;
	my $new_dir = $target_folder.'/'.$complete_study_prefix.'/';
	`mkdir ${new_dir}`;
	`chmod 777 ${new_dir}`;

	`mkdir ${new_dir}inputs/`;
	`chmod 777 ${new_dir}inputs/`;
	`mv ${complete_study_prefix}-work/* ${new_dir}/inputs/`;
 
	`mkdir ${new_dir}work/`;
	`chmod 777 ${new_dir}work/`;
	`mv ${complete_study_prefix}-work/* ${new_dir}/work/`;

	`mkdir ${new_dir}results/`;
	`chmod 777 ${new_dir}results/`;
	`mv ${complete_study_prefix}-work/* ${new_dir}/results/`;

    } else {
	$return_status = 0;
    }


}


# ------------------
sub study_dekompressor {
# ------------------
    



}




# ------------------
sub filesize_test {
# ------------------
    my ($file,$min_file_size) = @_;
    my $return_status = 0;

    if (! defined $min_file_size) {
	$min_file_size = $default_min_file_size;
    }
 
    my $filesize = stat($file)->size;

    if ($filesize >= $min_file_size) {
	$return_status = 1;
    }

    return($return_status);

}

# ------------------
sub file_and_folder_sorter {
# ------------------
    my ($folder) = @_;
    my @master_list = `ls $folder`;
    my @subdirectories;
    my @files;

    foreach my $item (@master_list) {
	my $full_path = $folder.'/'.$item;
	if (-d $full_path) {
	    push(@subdirectories, $item);
	}
	if (-f $full_path) {
	    push(@files,$full_path);
	}
    }

    my $file_array_ref = \@files;
    my $folder_array_ref = \@subdirectories;


    return($file_array_ref,$folder_array_ref);

}

1;
