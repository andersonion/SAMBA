#!/usr/bin/env perl

# mask_warps_standalone.pl 


# Retrospectively create and apply the appropriate masks for a folder of VBM warps.
# created 2015/08/31 BJ Anderson CIVM

my $PM = "mask_warps_vbm.pm";
my $VERSION = "2014/12/23";
my $NAME = "Creates an eroded mask from MDT image for use with VBM analysis. If input images for MDT were already skull-stripped, then the raw mask will be created from the non-zero elemnts of the MDT image.";

use strict;
use warnings;
#no warnings qw(uninitialized bareword);
use Env qw(ANTSPATH PATH);
$ENV{'PATH'}=$ANTSPATH.':'.$PATH;
#use lib dirname(abs_path($0));
#use Env qw(RADISH_PERL_LIB);
#if (! defined($RADISH_PERL_LIB)) {
#    print STDERR "Cannot find good perl directories, quitting\n";
#    exit;
#}
#use lib split(':',$RADISH_PERL_LIB);

require SAMBA_pipeline_utilities;


my ($current_path,$template_contrast,$erode_radius);
my ($do_mask,$pre_masked,$mdt_skull_strip,$default_mask_threshold);
my ($incumbent_raw_mask, $incumbent_eroded_mask);
my $go=1;

my $verbose=0;
my $test=0;

my $folder;
#---------------------
sub mask_warps_standalone {
#---------------------


#$folder = shift(@ARGV); #For use as STANDALONE script?
($folder)=@_; #For use as subroutine?

# get warps in folder 

my $start_time = time;

my $mask_dir = $folder.'/warp_masks';
if (! -e $mask_dir) {
    mkdir ($mask_dir,0777);
}
my $log = open_log($mask_dir);
log_info("Folder = $folder\n\n",$verbose);

my @warp_list=`ls $folder/*to*warp.nii*`;
my $ratio = 0.4;
my $largest_warp=0;
my $thresh_size;
#for (my $warp_no=0;$warp_no<=$#warp_list;$warp_no++) {
#    $warp_list[$warp_no]=$folder.'/'.$warp_list[$warp_no];
#}

## test for need to compress
#  use first file
log_info("Calculating minimum file size to work on, assuming minimum compression of $ratio.",$verbose);
if ($test) {
    log_info(".\n",1);
    $thresh_size = 168157000;
} else {
for (my $ii=0;((($largest_warp == 0) || ($ii < 3)) && ($ii<=$#warp_list));$ii++) {
    log_info(".",1);
    my $delete_me = 0;
    my $full_size=0;
    my $test_file = $warp_list[$ii];
    chomp($test_file);
   # print "Test file = ${test_file}\n\n";
    if (-e $test_file) {
	my $compressed_size = -s $test_file;
	#print "compressed size = ${compressed_size}\n\n";
	my $t_file = $test_file;
	my $suffix='';
	if ($compressed_size > 1110000) {
	    if ($t_file =~ s/\.nii\.gz$/_TEST\.nii/) {
		$suffix=".gz";
	    } elsif ($t_file =~ s/\.nii$/_TEST\.nii/) {
		$suffix="";
	    }
#  copy + unzip
	    if (! -e $t_file) {
		`cp ${test_file} ${t_file}${suffix}`;
		$delete_me = 1;
		log_info(".",1);
		if ($suffix eq '.gz') {
		    `gunzip ${t_file}${suffix}`;
		}	    		
		log_info(".",1);
	    }
#  get size
	    $full_size = -s $t_file;
	    if ($delete_me) {
		if (-e $t_file) {
		    `rm ${t_file}`;
		}
		if (-e $t_file.'.gz') {
		    `rm ${t_file}.gz`;
		}
	    }
	} else {
	    $full_size = 0;
	} 
    } else {
	$full_size = 0;
    }    

    if ($full_size > $largest_warp) {
	$largest_warp = $full_size;
    }
}
log_info("...\n",1);
#print "largest warp = ${largest_warp}\n\n";

#  calculate threshold ratio (~40% compression ratio is considered good?)
$thresh_size = int($ratio*$largest_warp);
}

my $readable_thresh_size = int($thresh_size/(1024*1024));
my $size_before_masking=0;
my $size_after_masking=0;
log_info("Thresh size = ${readable_thresh_size}MB\n\n",1);

#  compile list of files over this threshold

my @work_list;
foreach my $file (@warp_list) {
    chomp($file);
    my $size = -s $file;
    #print "Size = $size\n\n";
    if ($size > $thresh_size) {
	push(@work_list,$file);
	$size_before_masking = $size_before_masking + $size;
    } else {
	my $h_size = int($size/(1024*1024))+1;
	log_info("Compressed file size does not exceed threshold; no work done on file:\n\t $file;\n\t${h_size}MB is less than threshold ${readable_thresh_size}MB\n",1);
    }
}

my $number_of_work_warps = $#work_list + 1;

my $h_size_before_masking = int($size_before_masking/1024)+1;
my $before_units = "kB";
if ($h_size_before_masking > 1024) {
    $h_size_before_masking = int($h_size_before_masking/1024)+1;
    $before_units = "MB";
}
if ($h_size_before_masking > 1024) {
    $h_size_before_masking = int($h_size_before_masking/1024)+1;
    $before_units = "GB";
}
log_info("Number of warps on which to work = ${number_of_work_warps}\n\n",1);
log_info("Size of compressed warps before masking = ${h_size_before_masking}${before_units}\n\n",1);


## make list of masks needed
my %mask_hash;
my %dilated_mask_hash;
my %warp_mask_hash;
my %initializing_warps_hash;
my %registered_image_hash;
my @relevant_runnos=();
my %runno_pairs;
my %bash_hash;

my $MDT_folder=$folder;
my $alt_folder;

my @folder_tree = split('/',$folder);
if ($folder_tree[$#folder_tree] eq '') {pop(@folder_tree);}
my $level='';
my $flag=1;

for ($level = pop(@folder_tree);$flag;$level = pop(@folder_tree)) {
    $alt_folder=join('/',(@folder_tree,'MDT_pairs'));
    if (-d $alt_folder) {
	$flag=0;
    }
}
my $MDT_contrast=pop(@folder_tree);
my @dummy = split('_',$MDT_contrast);
$MDT_contrast = $dummy[0];


my $case;
if ($MDT_folder =~ s/MDT_diffeo/median_images/) {
    $case = 1;
} elsif ($MDT_folder =~ s/reg_diffeo/median_images/) {
    $case = 2;
} else {
    $MDT_folder = '';
    $case = 0
}





my $sbatch_path;
my @bash_list;
if (($case == 0) || ($case == 2)){
    $sbatch_path = $folder.'/sbatch/';
    @bash_list=`ls ${sbatch_path}/*.bash`;
} else {    
    $sbatch_path = $alt_folder.'/sbatch/';
}
#print "Case = $case\nAlt_folder2=${alt_folder2}\nsbatch path = ${sbatch_path}\n\n";

@bash_list=`ls ${sbatch_path}/*.bash`;

#  for each file
foreach my $in_warp (@work_list) {
#    harvest relevant runnos
    my ($path,$name,$ext)= fileparts($in_warp,2);
    my @name_parts = split('_to_',$name);
    my $runno_1 = shift(@name_parts);
    #print "Runno 1 = ${runno_1}\n";
    my @better_half = split('_warp',$name_parts[0]);
    my $runno_2 = shift(@better_half);
    #print "Runno 2 = ${runno_2}\n";
    $runno_pairs{$in_warp}=$runno_1.','.$runno_2;
    foreach my $runno ($runno_1,$runno_2) {
	my $rev_runnos = join('|',@relevant_runnos);
	#print "Runno = ${runno}\nRev_runnos =${rev_runnos}\n";
	if ($rev_runnos eq '') {
	    push(@relevant_runnos,$runno);
	} else {
	    if ($runno =~ /(${rev_runnos})/) {
		# Do nothing
	    } else {
		push(@relevant_runnos,$runno);
	    }	   
	}
    }
  
}
#print "$#relevant_runnos\n\n";
#   find matching bash (MDT_pairs and reg_diffeo)

foreach my $runno (@relevant_runnos) {
    if ((! defined $bash_hash{$runno}) || ($bash_hash{$runno} eq '')) {
	if ($runno eq "MDT") {
	    $bash_hash{$runno}="NULL";
	} else {
	    foreach my $bash_file (@bash_list) {
		my $test_bash_file = $bash_file;
		if ($test_bash_file =~ s/${runno}_//) {
		    if ($test_bash_file =~ /${runno}_/) {
		    # Don't want self warps!
		    } else {
			#print "Bash_file = ${bash_file}\n\n";
			$bash_hash{$runno} = $bash_file;
		    }
		}
	    }
	}
	#print "\$bash_hash{${runno}} = $bash_hash{${runno}}\n\n";
    }
}


#    harvest images + initializing warp (store in hash)
#   (using hash will handle redundancies mindlessly)

foreach my $runno (@relevant_runnos) {
    chomp($runno);
    log_info("Working on runno: ${runno}\n",1);
    $dilated_mask_hash{$runno} = "${mask_dir}/${runno}_warp_mask.nii.gz";
    my $MDT_skip=1;
    if (! -e $dilated_mask_hash{$runno}) {
	if ($runno eq "MDT") {
	    my $MDT_mask = "${MDT_folder}/MDT_mask.nii";
	    if (data_double_check($MDT_mask)) {
		$MDT_mask=$MDT_mask.'.gz';
		if (data_double_check($MDT_mask)) {
		    my $MDT_contrast_image ="${MDT_folder}/MDT_${MDT_contrast}.nii";
		    if (data_double_check($MDT_contrast_image)) {
			$MDT_contrast_image=$MDT_contrast_image.'.gz';
		    }
		    $registered_image_hash{$runno}=$MDT_contrast_image;
		    $initializing_warps_hash{$runno}='';
		    $MDT_skip=0;
		} else {
		    $warp_mask_hash{$runno}=$MDT_mask;
		}
	    } else {
		$warp_mask_hash{$runno}=$MDT_mask;
	    }
	} else {
	    my $bash_out = `more $bash_hash{$runno}`;
	    my @bash_parse = split(';',$bash_out);
	    my $reg_line='';
	    foreach my $command (@bash_parse) {
		if ($command =~ s/antsRegistration//) {
		    $reg_line = $command;
		}
	    }
	    my @line_parse=split(' -',$reg_line);
	    my $transform_option = 'babadoobiedoobiedoo';
	    $initializing_warps_hash{$runno}='';
	    foreach my $parsed_bit (@line_parse) {
		#print "Parsed bit = ${parsed_bit}\nTransform_option = ${transform_option}\n\n";
		
		if ($parsed_bit =~ s/^(m[\s]*)//){
		    if ($parsed_bit =~ s/^(.*\[[\s]*)//) {}
		    
		    my @option_parse = split(',',$parsed_bit);
		    for (my $ii=0;$ii<2;$ii++) {
			my $parsnip = $option_parse[$ii];
			if ($parsnip =~ /$runno/) {
			    $registered_image_hash{$runno}=$parsnip;
			    if ($ii) {
				$transform_option = "r";
			    } else {
				$transform_option = "q";
			    }
			}
		    }
		} elsif ($parsed_bit =~ s/^(${transform_option}[\s]*)//) {
		    $initializing_warps_hash{$runno} = $parsed_bit;
		}
	    }
	}
	
#  make mask by thresholding input image
#  apply affine and rigid warps
#  dilate mask and save

	#$dilated_mask_hash{$runno} = "${mask_dir}/${runno}_warp_mask.nii.gz";
	my $delete = 1;
	my $radius = 5;
	my $ref_space = $work_list[0];
	if (($runno eq "MDT") && ($MDT_skip)) {
	    print"\n";
	    $delete = 0;
	} else {
	    print "\n";
	    $mask_hash{$runno} = "${mask_dir}/${runno}_temp_mask.nii.gz";
	    $warp_mask_hash{$runno}="${mask_dir}/${runno}_warped_temp_mask.nii.gz";
	    my $make_mask_command = "fslmaths \"${registered_image_hash{${runno}}}\" -thr 0.00000001 -bin \"${mask_hash{$runno}}\"";
	    `${make_mask_command}`;
	    log_info("Make mask command=\n${make_mask_command}\n",$verbose);

	    if ($MDT_skip) {
		my $xform_command = "antsApplyTransforms --float -d 3 -i ${mask_hash{$runno}} -o ${warp_mask_hash{$runno}} -t ${initializing_warps_hash{$runno}} -r ${ref_space}  -n Linear";
		`${xform_command}`;
		log_info("Apply transform command=\n${xform_command}\n",$verbose);	    
	    } else {
		my $copy_MDT_mask_command = "cp ${mask_hash{$runno}} ${warp_mask_hash{$runno}}";
		`${copy_MDT_mask_command}`;
		log_info("Copy MDT mask command=\n${copy_MDT_mask_command}\n",$verbose);	

	    }

	    my $remove_temp_mask_command = "rm ${mask_hash{$runno}}";
	    `${remove_temp_mask_command}`;
	    log_info("Remove temp mask command =\n${remove_temp_mask_command}\n",$verbose);
	}
	my $dilate_command = "ImageMath 3 ${dilated_mask_hash{$runno}} MD ${warp_mask_hash{$runno}} $radius";
	`${dilate_command}`;
	log_info("Dilate command=\n${dilate_command}\n",$verbose);
	
	if ($delete) {
	    my $remove_warped_temp_mask_command = "rm ${warp_mask_hash{$runno}}";
	    `${remove_warped_temp_mask_command}`;
	   log_info("Remove warped temp mask command=\n${remove_warped_temp_mask_command}\n",$verbose);
	}
	
    }
}


## for each warp
my $index = 0;
my $countdown = $#work_list;
foreach my $in_warp (@work_list) {
    log_info("Process warp: ${in_warp}\n",2);
    $index++;
    my $suffix='';
    my $ph_test_before = `PrintHeader ${in_warp} | head -8`;

    if ($in_warp =~ s/.gz$//) {$suffix='.gz';}
    my ($path,$name,$ext)= fileparts($in_warp,2);
    #print "Name = $name\n\n";
    my $masked_warp = "${folder}/${name}_masked.nii.gz"; 
    if (! -e $masked_warp) {
# intersect masks
	my ($runno_1,$runno_2) = split(',',$runno_pairs{$in_warp.$suffix});
	my $mask_1 = $dilated_mask_hash{$runno_1};
	my $mask_2 = $dilated_mask_hash{$runno_2};
	my $intersected_mask = "${mask_dir}/temp_intersected_mask_${index}.nii";

	if (! data_double_check($mask_1,$mask_2)) { 
	    my $intersect_command = "ImageMath 3 ${intersected_mask} addtozero ${mask_1} ${mask_2}";
	    `${intersect_command}`;
	    log_info("Intersect command =\n${intersect_command}\n",$verbose);
	}
#  apply intersected mask
	if (! data_double_check($intersected_mask)) { 
	    my $apply_mask_command = "fslmaths \"${in_warp}${suffix}\" -mas \"${intersected_mask}\" \"${masked_warp}\"";
	    `${apply_mask_command}`;
	    log_info("Apply mask command =\n${apply_mask_command}\n",$verbose);
	}
#  mv masked warp over unmasked warp
	if (! data_double_check($intersected_mask)) { 
	    my $remove_intersected_mask_command="rm ${intersected_mask}";
	    `${remove_intersected_mask_command}`;
	    log_info( "Remove intersected mask command =\n${remove_intersected_mask_command}\n",$verbose);
	}
    }

    my $ph_test_after = `PrintHeader ${masked_warp} | head -8`;

    if ($ph_test_before eq $ph_test_after) {
	my $size = -s $masked_warp;
	$size_after_masking = $size_after_masking + $size;
	if (! data_double_check($in_warp.$suffix)) { 
	    my $remove_old_warp_command = "rm ${in_warp}${suffix}";
	    `${remove_old_warp_command}`;
	    log_info("Remove old warp command =\n${remove_old_warp_command}\n",$verbose);
	}
	if (! data_double_check($masked_warp)) { 
	    my $rename_warp_command = "mv ${masked_warp} ${in_warp}.gz";
	    `${rename_warp_command}`;
	    log_info("Rename warp command =\n${rename_warp_command}\n",$verbose);
	}
    } else {
	if (! data_double_check($masked_warp)) {
	    my $remove_new_warp_command = "rm ${masked_warp}";
	    `${remove_new_warp_command}`;
	    log_info("PrintHeader revealed error in masking process.  Unmasked warp will stay in place.\nRemove new warp command =\n${remove_new_warp_command}\n",$verbose);
	}
    }
    print "$countdown warp(s) remaining...\n";
    $countdown--;    
}

my $h_size_after_masking = int($size_after_masking/1024)+1;
my $after_units = "kB";
if ($h_size_after_masking > 1024) {
    $h_size_after_masking = int($h_size_after_masking/1024)+1;
    $after_units = "MB";
}
if ($h_size_after_masking > 1024) {
    $h_size_after_masking = int($h_size_after_masking/1024)+1;
    $after_units = "GB";
}

if ($size_before_masking ==0) {$size_before_masking=1;}
my $effective_compression_ratio = int(100*$size_after_masking/$size_before_masking+1);

my $end_time = time;

my $total_time = $end_time - $start_time;

log_info("Size before masking = ${h_size_before_masking}${before_units}\n\n",1); 

log_info( "Size after masking = ${h_size_after_masking}${after_units}\n\n",1);

log_info("Effective compression ratio = ${effective_compression_ratio}%\n\n",1);

log_info("Total time for warp folder compression = ${total_time} seconds.\n\n",1);

log_info("Perl script: mask_warps_standalone has finished.  Great job.\n\n",1);
}
1;
