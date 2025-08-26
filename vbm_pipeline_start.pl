#!/usr/bin/env perl
# vbm_pipeline_start.pl
# originally created as vbm_pipeline, 2014/11/17 BJ Anderson CIVM
# vbm_pipeline_start spun off on 2017/03/14 BJ Anderson CIVM
#
# Roughly modeled after seg_pipe_mc structure. (For better or for worse.)
#


# All my includes and requires are belong to us.
# use ...

my $PM = 'vbm_pipeline_start.pl'; 

use strict;
use warnings;

use Cwd qw(abs_path cwd getcwd);
use File::Basename;
use List::MoreUtils qw(uniq);
use lib dirname(abs_path($0));
use SAMBA_pipeline_utilities;
use Headfile;
use SAMBA_global_variables;
use Env qw(ANTSPATH PATH BIGGUS_DISKUS ATLAS_FOLDER);
$ENV{'PATH'}=$ANTSPATH.':'.$PATH;
#$ENV{'SHELL'} = '/bin/bash';

$GOODEXIT = 0;
$BADEXIT  = 1;
my $ERROR_EXIT=$BADEXIT;
$permissions = 0755;
my $interval = 1;
$schedule_backup_jobs=0;

activity_log();

# a do it again variable, will allow you to pull data from another vbm_run
#my $import_data = 1;
$test_mode = 0;

### 
# simple input handling, 
# we accept a startup headfile, and/or a (number of nodes|reservation name)
# If we're doing start file, it must be first. 
use vars qw($start_file);
$start_file=shift(@ARGV);
# Only if it looks like a number to we assign it to nodes.
# this in an attempt to simplify the following handling. 
if( ! defined $start_file ){
    die "Study_variables mode deprecated! its too messy :P\nPlease create a startup headfile";
}

if ( ! -f $start_file ){
    my $current_dir= cwd;
    $start_file = "${current_dir}/${start_file}";
    print "$start_file";
}

if ( ! -f $start_file && $start_file =~ /[^0-9]/ )  {
    print "Test 2";
    $nodes = $start_file;
    $start_file = '';
} else {
    $nodes = shift(@ARGV);
}

# nodes is either a number at this point, or nothing
# startfile is either a file path or an empty string.
$reservation='';
if (! defined $nodes || $nodes eq '' ) {
    $nodes = 4 ;}
else {
    $reservation = $nodes;
    my $reservation_info = `scontrol show reservation ${reservation}`;
    if ($reservation_info =~ /NodeCnt=([0-9]*)/m) { # Unsure if I need the 'm' option)
	$nodes = $1;
    } else {
	die "\n\n\n\nINVALID RESERVATION REQUESTED: unable to find reservation \"$reservation\".\n\n\n".
	    " Maybe your start file($start_file) was not found ! Or maybe $reservation_info doesnt work. It is not equal to /NodeCnt=([0-9]*)/m after all"; 
	$nodes = 4;
	# formerly was allowed to continue with reservatoin set failure, 
	# this generates such a confusing mess that has been deprecated. 
	#print "\n\n\n\nINVALID RESERVATION REQUESTED: unable to find reservation \"$reservation\".\nProceeding with NO reservation, and assuming you want to run on ${nodes} nodes.\n\n\n"; 
	$reservation = '';
	sleep(5);
    }
}


print "Attempting to use $nodes nodes;\n\n";
if ($reservation) { 
    print "Using slurm reservation = \"$reservation\".\n\n\n";
}
umask(002);

# require ...
require study_variables_vbm;
use vbm_pipeline_workflow;
use apply_warps_to_bvecs;

#$debug_val = 35;
#my $msg =  "Your message here!";
#printd(5,$msg);

# variables, set up by the study vars script(study_variables_vbm.pm)



my $kevin_spacey='';
foreach my $entry ( keys %main:: )  { # Build a string of all initialized variables, etc, that contain only letters, numbers, or '_'.
    if ($entry =~ /^[A-Za-z0-9_]+$/) {
    	$kevin_spacey = $kevin_spacey." $entry ";
    }
}

#my $test_shit = join(' ',sort(split(' ',$kevin_spacey)))."\n\n\n";
#print $test_shit;
#die;

my $tmp_rigid_atlas_name='';
{
    use Cwd qw(abs_path);
    if ($start_file =~ /.*\.headfile$/) {
        $start_file = abs_path($start_file);
        load_SAMBA_parameters($start_file);
    #} elsif ($start_file =~ /.*\.json$/) { # BJA, 6 June 2019: temporarily killing all JSON support until a robust solution is in place ensuring the JSON package is available in arbitrary user's environment.
    #    $start_file = abs_path($start_file);
    #    load_SAMBA_json_parameters($start_file); 
    } else {
	die "Study variables is not good, so its no longer allowed";
        study_variables_vbm();
    }
    if (! defined $do_vba) {
        $do_vba = 0;
    }
    vbm_pipeline_workflow();
} #end main

# ------------------
sub load_SAMBA_parameters {
# ------------------
    my ($param_file) = (@_);
    my $tempHf = new Headfile ('rw', "${param_file}");
    if (! $tempHf->check()) {
		error_out(" Unable to open SAMBA parameter file ${param_file}.");
		return(0);
    }
    if (! $tempHf->read_headfile) {
	error_out(" Unable to read SAMBA parameter file ${param_file}."); 
	return(0);
    }
    my $is_headfile=1;  
    assign_parameters($tempHf,$is_headfile);
    }

# ------------------
sub load_SAMBA_json_parameters {
# ------------------
    my ($json_file) = (@_);
    my $tempHf = json_file_to_perl($json_file);
    if (0){
    eval {
        assert_valid_json (  $json_file);
    };
    if ($@) {
        error_out("Invalid .JSON parameter file ${json_file}: $@\n");
    #}
    #if (! valid_json($json_file)) {
    #    error_out(" Invalid .JSON parameter file ${json_file}."); 
        return(0);
    }
    }
    
    my $is_headfile=0;
    assign_parameters($tempHf,$is_headfile);

    }


# ------------------
sub assign_parameters {
# ------------------

    my ($tempHf,$is_headfile) = (@_); # Current headfile implementation only supports strings/scalars

    if ($is_headfile) {
        foreach ($tempHf->get_keys) {
            my $val = $tempHf->get_value($_);
            #if ($val eq '') { # Don't know what this code was doing; commenting out 31 May 2018.
            #    print "$val\n";
            #}

            if ($kevin_spacey =~ /$_/) {
                if (defined $val) {
					$val =~ s/(?<!\\)([\s]+)//g; # 20 February 2020, BJA: First kill any unprotected spaces.
					$val =~ s/(\\([\s]){1})/$2/g; # 20 February 2020, BJA: Now make protected spaces literal and hope things don't blow up elsewhere.
                    eval("\$$_=\'$val\'");
                    print $_." = $val\n";
   
                    if ($_ eq 'rigid_atlas_name'){
                        eval("\$tmp_rigid_atlas_name=\'$val\'");
                    }
                }
            }
        }
    } else {
        foreach (keys %{ $tempHf }) {
            if ($kevin_spacey =~ /\b$_\b/) {

				#my $val = %{ $tempHf }->{($_)};
				#print "\n\n$_\n\n"; 
				die "json mode requires revalidation!!!";
				my $val;
				$val = %{ $tempHf ->{$_}}; # Option A: take hash in tempHf and store as scalar
				$val = $tempHf->{$_};  # Option B (more likely to be right): Store reference (scalar array hash) as val.
				#my $val = %{ $tempHf }->{$_}; # This is as originally formulated, but not quite right.
				if ($val ne '') {
					#print "LOOK HERE TO SEE NOTHING\$val = ${val}\n";
					if ($val =~ /^ARRAY\(0x[0-9,a-f]{5,}/){
						eval("\@$_=\'@$val\'");
						print "$_ = @{$_}\n"; 
					} elsif ($val =~ /^HASH\(0x[0-9,a-f]{5,}/){
						eval("\%$_=\'%$val\'");
						print "$_ = %{$_}\n"; 
	
					} else { # It's just a normal scalar.
						eval("\$$_=\'$val\'");
						print "$_ = ${$_}\n";   
						if ($_ eq 'rigid_atlas_name') {
							eval("\$tmp_rigid_atlas_name=\'$val\'");
						}
					}
				}
			}
		}
    }
    my @ps_array;

    if (! defined $project_name) {
        my $project_string;
        if ($is_headfile) {
            $project_string = $tempHf->get_value('project_id');
         } else {
            die "json mode requires revalidation!!!";
            $project_string = %{ $tempHf ->{"project_id"}}; # Option A: take hash in tempHf and store as scalar
            $project_string = $tempHf->{"project_id"};  # Option B (more likely to be right): Store reference (scalar array hash) as val.
            # $project_string = %{ $tempHf }->{"project_id"}; # This is as originally formulated, but not quite right.
         }

        @ps_array = split('_',$project_string);
        shift(@ps_array);
        my $ps2 = shift(@ps_array);
        if ($ps2  =~ /^([0-9]+)([a-zA-Z]+)([0-9]+)$/) {
            $project_name = "$1.$2.$3";
        }

        if (! defined $optional_suffix) {
            $optional_suffix = join('_',@ps_array);
            if ($tmp_rigid_atlas_name ne ''){
                if ($optional_suffix =~ s/^(${tmp_rigid_atlas_name}[_]?)//) {}
            }
        }

    }

    if ((! defined ($pre_masked)) && (defined ($do_mask))) {
		if ($do_mask) {
			$pre_masked = 0;
		} else {
			$pre_masked=1;
		}
    }

    if ((defined ($pre_masked)) && (! defined ($do_mask))) {
		if ($pre_masked) {
			$do_mask = 0;
		} else {
			$do_mask=1;
		}
    }

    if (! defined $port_atlas_mask) { $port_atlas_mask = 0;}

    if (($test_mode) && ($test_mode eq 'off')) { $test_mode = 0;}

    if (defined $channel_comma_list) {
		my @CCL = split(',',$channel_comma_list);
		foreach (@CCL) {
			if ($_ !~ /(jac|ajax|nii4D)/) {
			push (@channel_array,$_);
			}
		}
	
		@channel_array = uniq(@channel_array);
		$channel_comma_list = join(',',@channel_array);
    }

if (0) { # We want to retire the confusing concept of $atlas_name, when we really mean $rigid_atlas_name
    my $atlas_name; # Only used here so perl won't throw up trying to check this code.
    if (! defined  $atlas_name){
        my ($r_atlas_name,$l_atlas_name);
        if ($is_headfile) {
            $r_atlas_name = $tempHf->get_value('rigid_atlas_name');
            $l_atlas_name = $tempHf->get_value('label_atlas_name');
            if ($r_atlas_name ne 'NO_KEY') {
                $atlas_name = $r_atlas_name;
            } elsif ($l_atlas_name ne 'NO_KEY') {
                $atlas_name = $l_atlas_name;
            } else {
                $atlas_name = 'chass_symmetric2'; # Will soon point this to the default dir, or let init module handle this.
            }
        } else {
            die "json mode requires revalidation!!!";
            $r_atlas_name = %{ $tempHf ->{'rigid_atlas_name'}}; # Option A: take hash in tempHf and store as scalar
            $r_atlas_name = $tempHf->{'rigid_atlas_name'};  # Option B (more likely to be right): Store reference (scalar array hash) as val.
            #$r_atlas_name = %{ $tempHf }->{'rigid_atlas_name'}; # This is as originally formulated, but not quite right.

            $l_atlas_name = %{ $tempHf ->{'label_atlas_name'}}; # Option A: take hash in tempHf and store as scalar
            $l_atlas_name = $tempHf->{'label_atlas_name'};  # Option B (more likely to be right): Store reference (scalar array hash) as val.
            # $l_atlas_name = %{ $tempHf }->{'label_atlas_name'};

            if ($r_atlas_name ne '') {
                $atlas_name = $r_atlas_name;
            } elsif ($l_atlas_name ne '') {
                $atlas_name = $l_atlas_name;
            } else {
                $atlas_name = 'chass_symmetric2'; # Will soon point this to the default dir, or let init module handle this.
            }
        }
    }
}
	if (! defined $optional_suffix) {
	    $optional_suffix = join('_',@ps_array);
        if ($optional_suffix =~ s/^(${rigid_atlas_name}[_]?)//) {}
	}

}

