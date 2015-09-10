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
require '/home/rja20/cluster_code/workstation_code/analysis/vbm_pipe/mask_warps_standalone.pl';

my $default_min_file_size = 1500; # Files smaller than this will not be gzipped.


# ------------------
sub folder_kompactor {  
# ------------------    
    my (@folders)= @_;

    # Find all files in folder and subdirectories
    foreach my $folder (@folders) {
	my $kompressor_file = $folder.'/kompressor.txt';
	`echo "Pre-kompression size for $folder =" >> ${kompressor_file}`;
	`du -csh $folder | tail -1 >> ${kompressor_file}`;
	`echo "#+#+#+#" >> ${kompressor_file}`;
	my $pre_report = `du -csh $folder | tail -1`;
	print "Pre-kompression size for $folder=\n${pre_report}\n";

	# Help compression by masking warps
	if ($folder =~ /work/) {
	    my $warp_folders_processed = create_masked_warps($folder);
	    print "${warp_folders_processed} warp folders processed\n";
	}

	my @all_files;
	my @files_to_process;
	my $start_time = time;


	@all_files = `find $folder -type f`;
	foreach my $file (@all_files) {
	    chomp($file);
	    #print "File=$file\n";	     
	    # Ignore files already gzipped
	    if (($file !~ /\.gz$/) && ($file ne $kompressor_file)) {
		# Find all files greater than 1500 bytes
		if (filesize_test($file)) {
		    push(@files_to_process,$file);
		}
	    }
	}

#	open(my $fh, '>', $kompressor_file) or die;

	foreach my $file_to_process (@files_to_process) {
	    `gzip -f ${file_to_process}`; ##Playing with fire (-f)???
	    #print "File to process: ${file_to_process}\nFolder=$folder\n\n";
	    my @chunks=split("$folder",$file_to_process);
	    $file_to_process = '.../'.$chunks[1];
	    #if ($file_to_process = s/("$folder")//){}
	   `echo "${file_to_process}" >> ${kompressor_file}`;
	    #print "File to process: ${file_to_process}\n";
	}
	my $end_time = time;
	my $total_time = $end_time - $start_time;
#	close ($fh);
	#$study_status=study_kompactor($folder);
	`echo "#+#+#+#" >> ${kompressor_file}`;
	`echo "Post-kompression size for $folder =" >> ${kompressor_file}`;
	`du -csh $folder | tail -1 >> ${kompressor_file}`;
	`echo "Total processing time for $folder = ${total_time}" >> ${kompressor_file}`;
	my $post_report = `du -csh $folder | tail -1`;
	print "Post-kompression size for $folder=\n${post_report}\n";
	print "Total processing time for $folder = ${total_time}\n";
    }
    #print "Study status = ${study_status}.\n\n";
    return(1);
}


# ------------------
sub folder_dekompressor {
# ------------------
    



}


# ------------------
sub study_kompactor {
# ------------------
    my ($a_primary_study_folder,$target_folder) = @_;#@ARGV;#@_;
    print "${a_primary_study_folder}\n\n";
    if ($a_primary_study_folder =~ s/(\/)*$//) {}
    print "${a_primary_study_folder}\n\n";
    my @levels = split('/',$a_primary_study_folder);
    my $parent_folder='';
    my $complete_study_prefix=pop(@levels);
    $parent_folder= join('/',@levels).'/';


    print "Parent folder = ${parent_folder}\nComplete study prefix = ${complete_study_prefix}\n";
    if (! defined $target_folder) {
	$target_folder = $parent_folder;
    }
    print "Target folder = ${target_folder}\n\n";
   
    my $return_status=1;  # 1 --> success, 0 --> fail

    if ($complete_study_prefix =~ s/([-]{1}(work|inputs|results))$//) {
	#$complete_study_prefix = $1;
	my $new_dir = $target_folder.$complete_study_prefix.'/';
	my $original_inputs = $parent_folder.$complete_study_prefix.'-inputs/';
	my $original_results = $parent_folder.$complete_study_prefix.'-results/';
	my $original_work = $parent_folder.$complete_study_prefix.'-work/';
	
#	folder_kompactor($original_inputs);
#	folder_kompactor($original_results);
	folder_kompactor($original_work);

	if (! -e $new_dir) {
	    `mkdir ${new_dir}`;
	    `chmod 775 ${new_dir}`;
	}

	#`mkdir ${new_dir}inputs/`;
	`mv ${original_inputs} ${new_dir}inputs/`;
	`chmod 775 ${new_dir}inputs/`;
 
	#`mkdir ${new_dir}work/`;
	`mv ${original_work} ${new_dir}work/`;
	`chmod 775 ${new_dir}work/`;

	#`mkdir ${new_dir}results/`;
	`mv ${original_results} ${new_dir}results/`;
	`chmod 775 ${new_dir}results/`;
    } else {
	$return_status = 0;
    }
    print "Return status = ${return_status}\n";
    return($return_status);

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
sub file_and_folder_sorter { ## What was I planning on doing with this?!?
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

# ------------------
sub create_masked_warps {
# ------------------
    my ($in_folder)=@_;
    # Find MDT_pairs,MDT_diffeo,reg_diffeo
    my @all_folders = `find $in_folder -type d`;
    my $folders_processed=0;
    foreach my $folder (@all_folders) {
	chomp($folder);
	my @levels =  split('/',$folder);
	my $deepest_level = pop(@levels);
	#print "Deepest level = ${deepest_level}\n";
	if ($deepest_level =~ /^(MDT_pairs|MDT_diffeo|reg_diffeo)$/) {
	    mask_warps_standalone($folder);
	    $folders_processed++;
	}
    }

    return($folders_processed);

}

1;
