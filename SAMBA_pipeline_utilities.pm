#SAMBA_pipeline_utilites.pm
#
# created 09/10/15  Sally Gewalt CIVM
#                   based on t2w pipemline  
# modifications by James J. Cook and B.J. Anderson

package SAMBA_pipeline_utilities;
use strict;
use warnings;

use Getopt::Long qw(HelpMessage GetOptionsFromArray);
Getopt::Long::Configure qw(bundling ignorecase_always auto_abbrev);

use English;
use File::Basename;
use File::Glob qw(:globally :nocase);
use File::Path;
use File::stat;
use File::Find;
use POSIX qw(strftime :sys_wait_h);
use Carp qw(carp croak cluck confess);
use File::Temp qw(tempfile);
use Scalar::Util qw(looks_like_number);
use Fcntl qw(O_RDONLY);


## Multiple cluster type support, 27 June 2019, BJ Anderson
# Hope to make this automatic!
# Cluster type codes:
# 0: Local machine with no job management
# 1: Slurm
# 2: SGE
our $cluster_type = 1;


my $HAVE_GUNZIP;
sub _have_gunzip {
    return $HAVE_GUNZIP if defined $HAVE_GUNZIP;
    $HAVE_GUNZIP = eval { require IO::Uncompress::Gunzip; 1 } ? 1 : 0;
}

my $PM="SAMBA_pipeline_utilities";
my $VERSION = "250213";
our $PIPELINE_NAME;
our $PIPELINE_INFO;
#$VERSION=get_git_commit($0); # wouldnt this be fun! ;)
# MAYBE a git_info fuction would be better? returning a hash of git log -1 strings? 
# from which we could pull the date, or version etc. Maybe we would handle uncommit changes reasonably using a post notation?

# log vars.
my $log_open = 0;
my $pipeline_info_log_path = "UNSET";
# outheadfile_comments added to by log_pipeline_info 
my @outheadfile_comments = ();  

# 16 January 2019: Moving from 'use vars' convention to 'our' & 'Export', with clear (i.e. singular) ownership of variables.
our ($HfResult, $BADEXIT, $GOODEXIT);
$HfResult='unset';

our ($debug_val,$debug_locator);
# we're going to defacto debug_val to 5, that way we can go quieter than 5.
$debug_val=5;# unless defined $debug_val;
$debug_locator=80;# unless defined $debug_locator;

# slurm queue handling.
my $custom_q = 0; # Default is to assume that the cluster queue is not specified.
my $my_queue = '';
$my_queue = $ENV{'PIPELINE_QUEUE'} or $my_queue= '';
if ((defined $ENV{'PIPELINE_QUEUE'}) && ($my_queue ne '') ) {
    $custom_q = 1;
}
# global var required for slurm things, caused by SAMBA pipeline. 
our $schedule_backup_jobs;

# positive or negative floating point or integer number in scientific notation.
#our $num_ex="[-]?[0-9]+(?:[.][0-9]+)?(?:[Ee][-]?[0-9]+)?"; 
#our $plain_num="[-]?[0-9]+(?:[.][0-9]+)?"; # positive or negative number 
# this should be composit based buiding on smaller parts for other functions to better use.
our $n_ex     ="[-]?";
our $int_ex   ="[0-9]+";
our $float_ex ="$n_ex$int_ex(?:[.]$int_ex)?";
our $plain_num=$float_ex;
our $full_nex ="$float_ex(?:[E]$n_ex$int_ex)?";
our $num_ex=$full_nex;


our $OSNAME="$^O\n";
our $IS_MAC=0;
our $IS_LINUX=0;
if ( $OSNAME =~ /^darwin$/x ) {
    $IS_MAC=1;
} elsif( $OSNAME =~ /^linux$/x )  { 
    $IS_LINUX=1;
}


BEGIN {
    use Exporter;
    our @ISA = qw(Exporter); # perl critic wants this replaced with use base; not sure why yet.
    #@EXPORT_OK is prefered, as it markes okay to export, HOWEVER our code is dumb and wants all the pipe utils!
    our @EXPORT = qw(
    
activity_log
close_log_on_error
cluster_check
cluster_exec
cluster_wait_for_jobs
compare_headfiles
compare_two_reference_spaces
convert_time_to_seconds
create_explicit_inverse_of_ants_affine_transform
data_double_check
debugloc
error_out
execute
execute_heart
execute_log
fileparts
find_file_by_pattern
find_temp_headfile_pointer
format_transforms_for_command_line
get_bounding_box_and_spacing_from_header
get_nii_from_inputs
get_slurm_job_stats
get_spacing_from_header
hash_summation
headfile_list_handler
load_file_to_array
log_info
make_process_dirs
mask_volume_mm3
memory_estimator
memory_estimator_2
nifti_dim4
nifti1_bb_spacing
nifti_max_label
nifti_max_value
open_log
printd
read_refspace_txt
round
run_and_watch
sleep_with_countdown
symbolic_link_cleanup
timestamp_from_epoc 
whoami
whowasi
wrap_in_container
write_array_to_file
write_refspace_txt

$schedule_backup_jobs
$HfResult
$debug_val
$debug_locator 
$BADEXIT
$GOODEXIT
$PIPELINE_NAME
$IS_MAC
$IS_LINUX
$OSNAME
); 
}
########
# Helpful common variables
########

# scale_lookup for disk/memory size postfixes
# These are sticking to the old convention of 2^10.
our %scale_lookup = (
        G => 1024**3,
        GB => 1024**3,
        GiB => 1024**3,
        g => 1024**3,
        M => 1024**2,
        MB => 1024**2,
        MiB => 1024**2,
        m => 1024**2,
        K => 1024,
        KB => 1024,
        KiB => 1024,
        k => 1024,
    );

# -------------
sub activity_log {
# -------------
    #use POSIX;
    my $log_file="$ENV{BIGGUS_DISKUS}/activity_log.txt";
    my $time = scalar localtime;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
    my $nice_timestamp = sprintf ( "%04d-%02d-%02d_%02d:%02d:%02d",
                                   $year+1900,$mon+1,$mday,$hour,$min,$sec);
    # this works because ARGV is preserved, what a great piece of magic that is :D !
    # that makes us very robust against any fiddly commandline processing.
    my $args=join(' ',@ARGV);
    my $log_txt=join("\t",("$nice_timestamp","$ENV{USER}","$0","$args"));
    open(my $fd, ">>$log_file");
    print $fd "$log_txt\n";
    # perpetually resets file permissions to friendly, becuase thats the purpose
    # of this function. 
    my $mode = 0666;   chmod $mode, $log_file;
    return;
}

# -------------
sub close_log_on_error  {
# -------------
  my ($msg,$verbose) = @_;

  if (! defined $verbose) {$verbose = 1;}

  # possible you may call this before the log is open
  if ($log_open) {
      my $exit_time = scalar localtime;
      log_info("Error cause: $msg",$verbose);
      log_info("Log close at $exit_time.");

      # emergency close log (w/o log dumping to headfile)
      close($PIPELINE_INFO);
      $log_open = 0;
      warn("  Log is: $pipeline_info_log_path\n");
      return (1);
  } else {
      warn( "NOTE: log file was not open at time of error.\n");
      return (0);     
  }
}

# ------------------
sub cluster_check {
# ------------------
# Primitive and silly check if our code is on a cluster.
# Initally just checked hostname, but our code uses slurm to schedule,
# so updated to check if slurm is available by looking for srun/sbatch.
	

	if ( `which sbatch 2>/dev/null | wc -l | tr -d [:space:]` ) {
		$cluster_type=1;
	#return(1);
	} elsif ( `which qsub  2> /dev/null | wc -l | tr -d [:space:]` ) {
	  $cluster_type=2;
	  #return(2);
	} else {
	  #$cluster_type=1;
	  $cluster_type=0;
	}
	return($cluster_type);
	#return(0);
}

# ------------------
sub cluster_exec {
# ------------------
    # James says: This function interface is ugly, Count the number of inputs here! thats too much!.
    # BJ says: suck it.
    my ($do_it,$annotation,$cmd,$work_dir,$Id,$verbose,$memory,$test,$node,$dependency) = @_;
    # my $memory=25600;
	# Not sure what the function of $test is, but will leave it in place for now.
    use Env qw(NOTIFICATION_EMAIL);
	$cmd = wrap_in_container($cmd);
    my @sbatch_commands;
    my @qsub_commands;

    my $node_command=''; # Was a one-off ---> now turned on for handling diffeo identity warps.
 
    my $queue_command='';
    my $memory_command='';
    my $time_command = '';
    my $dependency_command='';

    my $default_memory = 24870;#int(154000);
    if (! defined $verbose) {$verbose = 1;}
    #if ($test) {
    #    #$queue_command = "-p overload";#"-p matlab";#Not sure why switched from overload to matlab...have now switched back.
    #    #$time_command = "-t 15"; # -t 180
    #    #push(@sbatch_commands,$time_command); 
    #    #$queue_command = "-p high_priority";
    #    $queue_command = "-p slow_master"; # Trying this for now...otherwise, gets stuck behind CSrecon singleton jobs.
    #} els
    if ($custom_q == 1) {
        $queue_command = "-p $my_queue";
    	push(@sbatch_commands,$queue_command);
	}
	
   # push(@sbatch_commands,"-m cyclic");    
    my $local_reservation;
    my $reservation_command='';
    if (defined $node) {
        my $r = $ENV{'SLURM_RESERVATION'};
        if ($node =~ /,/) {
            ($node,$local_reservation) = split(',',$node);
            $node_command = "-w $node";
            push(@sbatch_commands,$node_command);
            ###
            # Enforced reservation for users who have their ENV var set.
            ###
            if ( defined $r ) { $local_reservation=$r;} # james did this
            ###
            $reservation_command = "--reservation=${local_reservation}";
            push(@sbatch_commands,$reservation_command);
        } else {
			$local_reservation = $node;
			###
			# Enforced reservation for users who have their ENV var set.
			###
			if ( defined $r ) { $local_reservation=$r;} # james did this
			###
			$reservation_command = "--reservation=${local_reservation}";
			push(@sbatch_commands,$reservation_command);
        }
    }

    if ((! defined $memory) ||($memory eq ''))  { #12 December 2016: Added memory eq '' so we can more easily trigger the default.
        $memory ="${default_memory}";
    } else {
		if ($memory =~ /(\d+(?:\.\d+)?)\s*([a-zA-Z]*)/i) {
			#my $raw_mem = $1;
			if ($2) {
				my $raw_mem = $1;
				my $unit = $2; 
				my $multiplier = $scale_lookup{$unit} / 1024 /1024 ;
				$memory = $raw_mem * $multiplier;
			}
		}
        if ($memory >= 239000) {$memory = 239000;}
    }	
    $memory_command = " --mem=$memory ";

    push(@sbatch_commands,$memory_command);

    if ( $memory =~ s/(\d+(?:\.\d+)?)$/${1}M/) {}
    $memory_command =" -l h_vmem=${memory},vf=${memory} ";
    push(@qsub_commands,$memory_command);
 
	# For most SAMBA jobs we would want multithreading
	my $multi_command = " --hint=multithread ";
	push(@sbatch_commands,$multi_command);
	
    #my $verbose_command = " -v 1"; # Oops! Inserted during the week of 24-28 Oct 2016 
    my $verbose_command = " -v"; # However, this fixes an issue with antsRegistration calls, NOT sbatch calls!
    push(@sbatch_commands,$verbose_command);  # It would have been fine without the "1", dammit

    my $sharing_is_caring =  ' -s ';  # Not sure if this is still needed.
    push(@sbatch_commands,$sharing_is_caring);

    my $dependency_type='';
    my $master_jobs;
    if (defined $dependency) {
        ($dependency_type,$master_jobs) = split(':',$dependency);
        if ($master_jobs) { 
            $master_jobs = join(':',split(',',$master_jobs));
        }
        $dependency_command = " --dependency=${dependency_type}${master_jobs} ";
    }
   # push(@sbatch_commands,$dependency_command); # will explicitly call this from the command line, as to avoid potential confusion if recalled or repurposed for backup call.

    # SGE doesn't like names that start with numbers (28 August 2019):
    my $qsub_id=$Id;
    if ( $qsub_id =~ s/^([0-9]{1})/Subject$1/){}
    my $name_command = " -N ${qsub_id} ";
    push (@qsub_commands,$name_command);

    if ( defined $NOTIFICATION_EMAIL ){
    	my $email_address_command='';
    	my $email_options_command='';
    	if ( $cluster_type == 1 ) {
			$email_address_command=" --mail-user=${NOTIFICATION_EMAIL} ";
			$email_options_command=" --mail-type=END,FAIL ";    	
    	} elsif ( $cluster_type == 2 ){
			$email_address_command=" -M ${NOTIFICATION_EMAIL} ";
			$email_options_command=" -m ea ";
		}
		push (@qsub_commands,$email_address_command);
		push (@qsub_commands,$email_options_command);
    }

    if ( $qsub_id =~ /create.*warp/ ) {
		#my $extra_juice_1 = " -pe cores 2:24 ";
		#my $extra_juice_1 = " -pe cores 12 ";
		#my $extra_juice_2 = " -binding linear:48 ";
		my $extra_juice_1 = " -pe cores 4 ";
		my $extra_juice_2 = " -binding linear:8 ";
		push (@qsub_commands,$extra_juice_1);
		push (@qsub_commands,$extra_juice_2);

    }


    my ($batch_path,$batch_file,$b_file_name);
    my $msg = '';
    my $jid=0;
    my $jid2;
    my $other_name='';

    if ((! $test) && ($verbose != 3))  {
        execute_log($do_it,$annotation,$cmd,$verbose);
    }
    if ($do_it) {
        $batch_path = "${work_dir}/sbatch/";
        $b_file_name = $Id.'.bash';
        $batch_file = $batch_path.$b_file_name;

        if (! -e $batch_path) {
            mkdir($batch_path,0777);
        }
        my $slurm_out_command = " --output=${batch_path}".'/slurm-%j.out ';
        push(@sbatch_commands,$slurm_out_command);

	my $sge_out_command = " -o ${batch_path}".'/slurm-$JOB_ID.out ';
	push(@qsub_commands,$sge_out_command);

	my $sge_err_command = " -e ${batch_path}".'/slurm-$JOB_ID.out ';
	push(@qsub_commands,$sge_err_command);

#       my $open_jobs_path = "${batch_path}/open_jobs.txt";

        # Added a confession on this file open command in attempt to track
        # repeated failures to write batch file.
        open(my $file_Id,'>',$batch_file) or confess "PROBLEM SETTING UP BATCH FILE err:$! \nfile:$batch_file";
        print($file_Id "#!/bin/bash\n");
        #print($file_Id 'echo \#'."\n");
	my $explicit_sbatch_options='';
        foreach my $sbatch_option (@sbatch_commands) {
            print($file_Id "#SBATCH ${sbatch_option}\n");
	    $explicit_sbatch_options="${explicit_sbatch_options} ${sbatch_option}";
       }
 
	my $explicit_qsub_options='';
        foreach my $qsub_option (@qsub_commands) {
            print($file_Id '#$'."${qsub_option}\n");
	    $explicit_qsub_options="${explicit_qsub_options} ${qsub_option}";
        }

        print($file_Id "$cmd \n");
        close($file_Id);

	#
	# SLOW EVERYTHING CHECK
	# 
	# while this loop appears crazy, it is here because 
	# we had a number of issues with "slow" disks and network devices.
	# This kludges those by giving them 2 seconds to try and finish 
	# writing the sbatch file from above.
        my $test_size = -s $batch_file;
        my $no_escape = 1;
        my $num_checks = 0;
        my $flag = 0;
        while (($test_size < 30) && $no_escape) {
            $num_checks++;
            sleep(0.1);
            $test_size = -s $batch_file;
            if ($num_checks > 20) {
                $no_escape=0;
                $flag =1;
            }
        }
        if ($flag) {
            log_info("batch file: ${batch_file} does not appear to have been created. Expect sbatch failure.")
        }
        
        # this works, but alternate call might be nicer.
	my $bash_call_with_visible_options ='';
	my $bash_call = '';

	if (${cluster_type} == 1){
	    #$bash_call_with_visible_options = "sbatch ${slurm_out_command} ${sharing_is_caring} ${verbose_command} ${node_command} ${reservation_command} ${queue_command} ${memory_command} ${time_command} ${dependency_command} ${batch_file}";
	    $bash_call_with_visible_options = "sbatch ${explicit_sbatch_options} ${dependency_command} ${batch_file}";
	    $bash_call = "sbatch ${dependency_command} ${batch_file}";
	    if ($verbose != 3) {
			print "sbatch command is: ${bash_call_with_visible_options}\n";
	    }
	    ($msg,$jid)=`$bash_call 2>&1` =~  /([^0-9]+)([0-9]+)/x;
	    my $extra_message='';
	    
	    if ((! defined $msg ) || ($msg !~  /.*(Submitted batch job).*/) ) {
			$extra_message="Slurm failure encountered while try to submit job; Waited 30 seconds to try again once.\n";
			sleep(30);
			if ( defined $msg && $msg ne "" ) {
				$extra_message=$extra_message."output1: ".$msg."\n";
			}
			($msg,$jid)=`$bash_call 2>&1` =~  /([^0-9]+)([0-9]+)/x;
			if ((! defined $msg) || ($msg !~  /.*(Submitted batch job).*/) ) {
				$jid = 0;
				error_out("${extra_message}Bad batch submit to slurm with output2: $msg\n");
				exit;
			}
	    } elsif ($schedule_backup_jobs) {
			if ($dependency_type eq 'singleton') {
				$other_name = $batch_path.'/backup_'.$b_file_name;
				`cp ${batch_file} ${other_name}`;
			} else {
				$other_name = $batch_file;
			}
			
			my $backup_bash_call = "sbatch --dependency=afternotok:${jid} ${other_name}";
			($msg,$jid2)=`$backup_bash_call` =~  /([^0-9]+)([0-9]+)/x;
			$extra_message="Slurm failure encountered while try to submit job; will wait 30 seconds and try again once.\n";
			
			if ((! defined $msg) || ($msg !~  /.*(Submitted batch job).*/) ) {
				$jid2 = 0;
				error_out("${extra_message}Bad batch submit to slurm with output: .$msg\n");
				exit;
			}
	    }
	} elsif (${cluster_type} == 2) {
	    $bash_call_with_visible_options = "qsub -V ${explicit_qsub_options} ${batch_file}";
	    $bash_call = "qsub -V ${batch_file}";
	    if ($verbose != 3) {
			print "qsub command is: ${bash_call_with_visible_options}\n";
	    }

	    ($msg,$jid)=`$bash_call 2>&1` =~  /([^0-9]+)([0-9]+)/x;
	    
	    my $extra_message='';
	    if ((! defined $msg ) || ($msg !~  /.*(Your job).*/) ) {
			$extra_message="SGE failure encountered while try to submit job; Waited 30 seconds to try again once.\n";
			sleep(30);
			if ( defined $msg && $msg ne "" ) {
				$extra_message=$extra_message."output1: ".$msg."\n";
			}
			($msg,$jid)=`$bash_call 2>&1` =~  /([^0-9]+)([0-9]+)/x;
			if ((! defined $msg) || ($msg !~  /.*(Your job).*/) ) {
				$jid = 0;
				error_out("${extra_message}Bad batch submit to SGE with output2: $msg\n");
				exit;
			}
	    } 
	}
    }
    if (not $jid) {
        warn("  Problem:  system() returned: $msg\n".
             "  * Command was: $cmd\n".
             "  * Execution of command failed.\n");
        return 0;
    } else {
        my $job2_string = '';
        if ($verbose != 3) {
            my $plural='';
            if (($schedule_backup_jobs) && ( ${cluster_type} == 1) ) {
		$plural='s';
		$job2_string=",$jid2";
            }
            print STDOUT " Job Id = ${jid}${job2_string}.\n";
        } else {
            print STDOUT "$jid${job2_string}";
        }
        if ($batch_file ne '') {
            my $new_name = $batch_path.'/'.$jid."_".$b_file_name;
            if ($verbose != 3) {           
                print "batch_file = ${batch_file}\nnew_name = ${new_name};\n\n";
            }
            rename($batch_file, $new_name);     
            if ((${cluster_type} == 1 ) && $schedule_backup_jobs) {
                my $backup_name = $batch_path.'/'.$jid2."_backup_".$b_file_name;
                if ($verbose != 3) {       
                    print "backup_batch_file = ${backup_name};\n\n";
                }
                if ($dependency_type eq 'singleton') {
                    rename($other_name,$backup_name); 
                } else {
                    `cp ${new_name} ${backup_name}`; 
                }
            }   
        }
    }

    if ($jid2) {
        $jid = join(',',($jid,$jid2));
    }
    return($jid);
}

# ------------------
sub cluster_wait_for_jobs {
# ------------------
# interval, verbose, [sbatch folder], @job_ids.
# sbatch_folder is optional.
    require List::MoreUtils;
    List::MoreUtils->import(qw(uniq));
    require Scalar::Util;
    Scalar::Util->import(qw(looks_like_number));
    my ($interval,$verbose,$sbatch_location,@job_ids)=@_;
    my $check_for_slurm_out = 1;
    # sort out if we were given the sbatch location
    if ((defined $sbatch_location) && (! -d $sbatch_location)  ) {
        # we cant just check for number because we may have been fed compound job_ids instead of simple ones, bleh... 
        if( $sbatch_location =~ /.+[,:].+/x || looks_like_number($sbatch_location)  ) {
            unshift(@job_ids,$sbatch_location);
        } else {
            carp("sbatch location ($sbatch_location) not available to check for slurm outs");
        }
        undef $sbatch_location;
        $check_for_slurm_out = 0;
    }
    # return early if we have no jobs to check.
    if (! scalar @job_ids) {
        return 1;
    }
    # convert any stringy compound job_ids to numbers
    my @bad_ids;
    my @good_ids;
    foreach (@job_ids ) {
        push(@good_ids,split(/[:,]/,$_));
    }
    @job_ids=@good_ids;@good_ids=();
    # Added uniq to ensure accurate job counting, moved uniq to the whole array early.
    @job_ids=uniq(@job_ids);
    # make sure all job ids are at least numeric.
    foreach (@job_ids ) {
        if ( looks_like_number($_)  ){
            push(@good_ids,$_);
        } else {
            carp("$_ doesnt look like a number");
            push(@bad_ids,$_);
        }
    }
    @job_ids=@good_ids; @good_ids=();
    if(scalar(@bad_ids) ){
        carp("Bad jobs were given to me :( ".join("  ",@bad_ids)." ): ");
        sleep_with_countdown(3);
    }
    my $jobs='';
    $jobs = join(",",@job_ids);

    my $number_of_jobs = scalar(@job_ids); 
    print " Number of independent jobs = ${number_of_jobs}\n";
    my $completed = 0;
    if ($number_of_jobs) {
        #print STDOUT "SLURM: Waiting for multiple jobs to complete";
        print STDOUT "SLURM: Waiting for jobs $jobs to complete...";    
		while ($completed == 0) {
                my $j_o;
				my $sacct_ended_jobs;
				my @job_states;
				if (${cluster_type} == 1){
					my $simple_way = 1;
					# Not all slurm clusters have sacct db setup.
					if ($simple_way) {
					 	$j_o=`squeue -o "%i,%50j,%T" -h -j $jobs`;
					 	chomp($j_o);
					 	@job_states=split("\n",$j_o);
						my $j_o_num = `squeue -h -j $jobs | wc -l`;
						$sacct_ended_jobs=$number_of_jobs - $j_o_num;
					} else {
						$j_o = `sacct -nj $jobs -o JobID,JobName%50,State|grep -v '.batch'`;
							#| grep -v '.batch' | grep -cE 'FAIL|CANCEL|COMPLETED|DEADLINE|PREEMPTED|TIMEOUT'`;
						chomp($j_o);
						@job_states=split("\n",$j_o);
						my @ended=grep /FAIL|CANCEL|COMPLETED|DEADLINE|PREEMPTED|TIMEOUT/ ,@job_states;
						$sacct_ended_jobs=scalar(@ended);
					}
				} elsif (${cluster_type} == 2) {
					$j_o = `qstat -j $jobs 2>&1| grep '==='  | wc -l`;
					$sacct_ended_jobs=$number_of_jobs - $j_o;
					#print $j_o;
				}   
                if ($sacct_ended_jobs < $number_of_jobs) {
                    if ($verbose) {print STDOUT ".";}
                    my $throw_error=0;
                    if (($check_for_slurm_out) && (${cluster_type} == 1) ) {
                        my $waited_time=0;
                        my $recheck_interval=10;
                        my $max_check_time=300;
                        my %job_checkup; # a hash of jobids->number of checks
                        my @running=grep /RUNNING/ ,@job_states;
                        # initalize job checks to 0 
                        for my $job_info (@running) {
							$job_info=~s/,/ /g;# replace commas with one space
                            $job_info=~s/\s+/ /g;# collapse all spaces to one space
                            my ($job,$jobname,$state)=split(" ",$job_info);
                            $job_checkup{$job}=0;
                        }
                        while ($waited_time<$max_check_time && scalar(keys %job_checkup)) {
                            # check each job exactly once before we wait.
                            for my $job ( keys(%job_checkup) ) {
                                my $slurm_out_file = File::Spec->catfile(${sbatch_location},"slurm-${job}.out");
                                if (! -e $slurm_out_file) {
                                    $job_checkup{$job}=$job_checkup{$job}+1;
                                } else {
                                    if ($job_checkup{$job} > 0 ) {
                                        print STDOUT "$job took $waited_time seconds to be found running normally\n" if $verbose;
                                    }
                                    delete $job_checkup{$job};
                                }
                            }
                            if ($verbose) {print STDOUT "s";}# lets get messy! 
                            sleep($recheck_interval);
                            $waited_time=$waited_time+$recheck_interval;
                        }
                        # now that we've wasted up to max_check_time(5 minutes right now) lets throw an error for anyone still not running.
                        my @bad_jobs=keys(%job_checkup);                        
                        my @missing_files;
                        if (scalar(@bad_jobs) ) {
                            $throw_error = 1;
                            foreach (@bad_jobs) {
                                push(@missing_files,File::Spec->catfile(${sbatch_location},"slurm-$_.out"));
                            }
                        } else {
                            # Now that we've checked for slurm_out once we dont need to do it again. 
                            $check_for_slurm_out=0;
                        }
                        if ($throw_error) {
                            my $bad_jobs=join(' ',@bad_jobs);
                            my $missing_file_s=join("\n",@missing_files);
                            require SAMBA_pipeline_utilities;
                            SAMBA_pipeline_utilities->import(qw(whowasi));
                            my $process = whowasi();
                            my @split = split('::',$process);
                            $process = pop(@split);
                            log_info("sbatch existence error generated by process: $process\n");
                            my $error_message ="UNRESOLVED ERROR! No slurm-out file created for job(s): ${bad_jobs}. Job will run but will not save output!\n".
                                "It is suspected that this is due to unhealthy nodes or a morbidly obese glusterspace.\n".
                                "Expected file(s):\n${missing_file_s} does not exist.\nCancelling bad jobs ${bad_jobs}.\n\n\n";
                            my $time = time;                    
                            my $email_file="${sbatch_location}/Error_email_for_${time}.txt";

                            my $time_stamp = "Failure time stamp = ${time} seconds since January 1, 1970 (or some equally asinine date).\n";
                            my $subject_line = "Subject: cluster slurm out error.\n";
							my $NE=$ENV{NOTIFICATION_EMAIL};
							if ( ! defined $NE || $NE == '') {
								my $cluster_user=$ENV{USER} || $ENV{USERNAME};
								$NE="$cluster_user\@duke.edu"
							}
                            my $email_content = $subject_line.$error_message.$time_stamp;
                            `echo "${email_content}" > ${email_file}`;
                            `sendmail -f $process.kea\@dhe.duke.edu $NE < ${email_file}`;
                            `scancel ${bad_jobs}`; #29 Nov 2016: commented out because of delayed slurm-out files causing unwarrented cancellations #9 Dec 2016, trying to mitigate witha 10 second wait, and the cancelling if still no slurm out file
                            log_info($error_message);
                        }
                    }
                    sleep($interval);
                } else { 
                    $completed = 1;
                    print STDOUT "\n";
                }
            }
    } else {
        $completed = 1;
    }
    #sleep(25);  #James, don't reduce this unless tested and shown to not fail on checking too quickly for files to exist (10 seconds failed)
    sleep(10);
    return($completed);
}

# ------------------
sub compare_headfiles {
# ------------------
    my ($Hf_A, $Hf_B, $include_or_exclude, @keys_of_note) = @_;
    my @errors=();
    my $error_msg = '';
    my $include = $include_or_exclude;
 


    foreach my $testHf ($Hf_A,$Hf_B) {  
        if (! $testHf->check()) { # It seems that it should be assumed that the headfile is coming checked already. If not, that aint on us!
           confess("Unable to open headfile referenced by ${testHf}"); 
        }
        if ( 0 ) {  # this causes errors for a reason which is un clear. Both headfiles have already been checked and read external to this call.
            if (! $testHf->read_headfile) {
                push(@errors, "Unable to read contents from headfile referenced by ${testHf}\n");
            }
        }
        if ( @errors ) {
            $error_msg = join('\n',@errors);
            return($error_msg);
        }
    }
        
    my @key_array = ();
    if ($include) {
        @key_array = @keys_of_note;
    } else {
        my @A_keys = $Hf_A->get_keys;
        my @B_keys = $Hf_B->get_keys;;
        my @all_keys = keys %{{map {($_ => undef)} (@A_keys,@B_keys)}}; # This trick is from http://www.perlmonks.org/?node_id=383950.
        foreach my $this_key (@all_keys) {
            my $pattern = '('.join('|',@keys_of_note).')';
            if ($this_key !~ m/$pattern/) {
                push(@key_array,$this_key) unless (($this_key eq 'hfpmcnt') || ($this_key eq 'version_pm_Headfile'));
            }
        }
    }

    if ($key_array[0] ne '') {
        foreach my $Key (@key_array) {
            # 10 April 2017, BJA: trying to add wildcard support. Wildcards are only allowed at the beginning and/or end of $Key.
            my $use_get_value_like = 0;
            if ($Key =~ s/^\*//) {
                $use_get_value_like = 1;
            }

            if ($Key =~ s/\*$//) {
                $use_get_value_like = 1;
            }
            my ($A_val,$B_val);
            if ( $use_get_value_like ) {
                $A_val = $Hf_A->get_value_like($Key);
                $B_val = $Hf_B->get_value_like($Key);
            } else {
                $A_val = $Hf_A->get_value($Key);
                $B_val = $Hf_B->get_value($Key);
            }
            
            $A_val='' if($A_val =~ /^EMPTY_VALUE|UNDEFINED_VALUE$/ );
            $B_val='' if($B_val =~ /^EMPTY_VALUE|UNDEFINED_VALUE$/ );
            
            my $robust_A_val = $A_val; # 15 January 2016: added functionality such that gzipped/ungzipped difference doesn't throw a flag.
            my $robust_B_val = $B_val;

            if ($robust_A_val =~ s/\.gz//) {}
            if ($robust_B_val =~ s/\.gz//) {}
            
            # 30 April 2019: Ignore extra slashes in path names...can't think of a non-path case where a single slash 
            # couldn't replace multiple consecutive slashes and compromise behavior.

            if ($robust_A_val =~ s/[\/]{2,}/\//) {}
            if ($robust_B_val =~ s/[\/]{2,}/\//) {}

            if ($robust_A_val ne $robust_B_val) {
                my $msg = "Non-matching values for key \"$Key\":\n\tValue 1 = ${A_val}\n\tValue 2 = ${B_val}\n";
                push (@errors,$msg);
            }
        }
    }
  
    if ( @errors) {
        $error_msg = join("\n",@errors);
        $error_msg = "Headfile comparison complete, headfiles are not considered identical in this context.\n".$error_msg."\n";
    }
    
    return($error_msg); # Returns '' if the headfiles are found to be "equal", otherwise returns message with unequal values.
}

#---------------------
sub compare_two_reference_spaces {
#---------------------
    my ($file_1,$file_2) = @_; #Refspace may be entered instead of file path and name.
    my ($bb_and_sp_1,$bb_and_sp_2);
 #   my ($sp_1,$sp_2);
    
    my $file_1_is_a_ref_space = 0;
    if ($file_1 =~ s/(\.gz)$//) {}
    
    if (! data_double_check($file_1)){
        $bb_and_sp_1 = get_bounding_box_and_spacing_from_header($file_1);  # Attempted to make this impervious to the presence or absence of .gz 14 October 2016
    } elsif (! data_double_check($file_1.'.gz')) {
    	$file_1 = $file_1.'.gz';
        $bb_and_sp_1 = get_bounding_box_and_spacing_from_header($file_1);
    }  else {
        $bb_and_sp_1 = $file_1;
        $file_1_is_a_ref_space = 1;
    }
	my $file_2_is_a_ref_space = 0;
	if ($file_2 =~ s/(\.gz)$//) {}
	if (! data_double_check($file_2)){
	   $bb_and_sp_2 = get_bounding_box_and_spacing_from_header($file_2);
	} elsif (! data_double_check($file_2.'.gz')) {
		$file_2 = $file_2.'.gz';
		$bb_and_sp_2 = get_bounding_box_and_spacing_from_header($file_2);
	} else {
	   $bb_and_sp_2 = $file_2;
	   $file_2_is_a_ref_space = 1;
	}

    my $result=0;
	
	#if ($bb_and_sp_1 eq $bb_and_sp_2) {
    if (ref_space_equal($bb_and_sp_1 eq $bb_and_sp_2)) {
        $result = 1;
    } else {
    	if (( $file_1_is_a_ref_space && ! $file_2_is_a_ref_space ) || ($file_2_is_a_ref_space && ! $file_1_is_a_ref_space)){
    		if ( $file_1_is_a_ref_space ){
    			# Legacy check on $file_2:
    			$bb_and_sp_2 = get_bounding_box_and_spacing_from_header($file_2,1);
    		} else {
				# Legacy check on $file_1:
    			$bb_and_sp_1 = get_bounding_box_and_spacing_from_header($file_1,1);
    		}
    		#$bb_and_sp_1 = _canon_ref_space_str($bb_and_sp_1);
    		#$bb_and_sp_2 = _canon_ref_space_str($bb_and_sp_2);
			
			#if ($bb_and_sp_1 eq $bb_and_sp_2) {
			if (ref_space_equal($bb_and_sp_1, $bb_and_sp_2)) {
				$result = 1;
			} else {
				print visualize_ws($bb_and_sp_1)."\n";
				print "Is not equal to\n";
				print visualize_ws($bb_and_sp_2)."\n";
			}
			
    	}
    }

    return($result);
}

# Helper subs
# Canonicalize the string form (drop prefixes/suffixes, normalize spaces)
sub _canon_ref_space_str {
    my ($s) = @_;
	return '' unless defined $s;          # guard: avoid s/// on undef
	
    $s =~ s/\p{Z}/ /g;                 # Unicode spaces -> ASCII space
    $s =~ s/\x{200B}//g;               # remove zero-width space
    $s =~ s/^\s+|\s+$//g;              # trim ends
    $s =~ s/[ \t]+/ /g;                # collapse internal spaces
    $s;
}

# Pull out all numbers in order from the canonicalized string
sub _nums_from_ref_space {
    my ($s) = @_;
    $s = _canon_ref_space_str($s);
    my @nums = ($s =~ /-?\d+(?:\.\d+)?/g);   # 9 numbers: 3 bb0 + 3 bb1 + 3 spacings
    @nums;
}

# Numeric compare with tolerance (<= eps)
sub ref_space_equal {
    my ($a, $b, $eps) = @_;
    $eps //= 1e-6;  # fits your diffs
    my @A = _nums_from_ref_space($a);
    my @B = _nums_from_ref_space($b);
    return 0 unless @A == 9 && @B == 9;
    for my $i (0..8) {
        my ($x, $y) = ($A[$i]+0.0, $B[$i]+0.0);
        return 0 if abs($x - $y) > $eps;     # use > (not >=) so Δ=1e-6 passes
    }
    return 1;
}


#---------------------
sub convert_time_to_seconds {
#---------------------
# a more complete solution exists in SAMBA_pipeline_utilities
    my ($time_and_date_string) = @_;
    my ($days,$hours,$minutes,$seconds);
    my $time_in_seconds = 0;
    
    
    my @colon_split = split(':',$time_and_date_string);
    my $categories = $#colon_split; 
 
    $seconds = $colon_split[$categories];
    chomp($seconds);
    if ($seconds =~ s/s$//){}
    $seconds = int($seconds + 0.9999999);
    $time_in_seconds = $time_in_seconds + $seconds;
    
    if ($categories > 0) {
        $minutes = $colon_split[($categories-1)];
	if ($minutes =~ s/m$//){}
        $time_in_seconds = $time_in_seconds + ($minutes*60);
    }
    
    if ($categories > 1) {
        my $hours_and_days = $colon_split[($categories-2)];
        if ($hours_and_days =~ /-/) {
            ($days,$hours) = split('-',$hours_and_days);
           
        } else {
            $days = 0;
            $hours = $hours_and_days;
        }
        
	if ($hours =~ s/h$//){}
	if ($days =~ s/d$//){}

        $time_in_seconds = $time_in_seconds + ($hours*60*60);
        $time_in_seconds = $time_in_seconds + ($days*24*60*60);
        
    }
        
   # print "For ${time_and_date_string}, time in seconds is ${time_in_seconds}\n";

    return($time_in_seconds);

}

#---------------------
sub create_explicit_inverse_of_ants_affine_transform {
#---------------------
    my $return_msg;
    my ($transform_to_invert,$outfile) = @_;
    if (! defined $outfile) {
        my ($p,$n,$e) = fileparts($transform_to_invert,3);
        $outfile = "${p}/${n}_inverse${e}";
    }
    my ($invert_cmd,$convert_cmd);
    if ($transform_to_invert =~ /\.(txt|mat)$/ ) {
        my $dim = 3;
        $invert_cmd = "ComposeMultiTransform ${dim} ${outfile} -i ${transform_to_invert}";
        $convert_cmd = "ConvertTransformFile ${dim} ${outfile} ${outfile} --convertToAffineType";
        ##### WILL PROBABLY FAIL WITH SINGULARITY!!!!! ######
        $return_msg =`${invert_cmd}; ${convert_cmd}`;
    } else {
        my $error_msg = "File does not appear to be a valid ants affine matrix, and therefore cannot be properly inverted here.\nOffending file: ${transform_to_invert}\n";
        error_out($error_msg);
    }  

    return($return_msg,$invert_cmd.'&&'.$convert_cmd); 

}

#---------------------
sub data_double_check { # Checks a list of files; if a file is a link, double checks to make sure that it eventually lands on a real file.
# ------------------    # Subroutine returns number of files which point to null data; "0" is a successful test.

    my (@file_list)=@_;
    require Scalar::Util;
    Scalar::Util->import(qw(looks_like_number));
    my $unused_dummy=0;
    my $number_of_bad_files = 0;
    if (looks_like_number($file_list[$#file_list])) {
       $unused_dummy=pop @file_list;
    }

    for my $file_to_check (@file_list) {

      my ($path,$name,$ext) = fileparts($file_to_check,2);
#  The following is based on: http://snipplr.com/view/67842/perl-recursive-loop-symbolic-link-final-destination-using-unix-readlink-command/
      if ($file_to_check =~/[\n]+/) {
          $number_of_bad_files++;
      } else {
        my $waited=0;
        if (! -e $file_to_check) {
            #my $msg = `ls -l $file_to_check`;
            #print "$msg\n";
            $number_of_bad_files++;
        }
      }
    }
    return($number_of_bad_files);
}

#---------------------
sub debugloc { if ($debug_val>=$debug_locator ) { print "->", whowasi(), "\n"; } return; }

# -------------
sub error_out {
# -------------
  my ($msg,$verbose) = @_;

  if (! defined $verbose) {$verbose = 1;}

  warn("\n<~Pipeline failed.\n");
  my @callstack=(caller(1));
  my $pm;
#  $pm=$callstack[1] || $pm="UNDEFINED"; #||die "caller failure in error_out for message $msg";
  $pm=$callstack[1] || die "caller failure in error_out with message: $msg";
  my $sn;
#  $sn=$callstack[3] || $sn="UNDEFINED";#||die "caller failure in error_out for message $msg";
  $sn=$callstack[3] || die "caller failure in error_out with message: $msg";
  warn("  Failure cause: ".$msg." at ".$pm.'|'.$sn."\n".
       "  Please note the cause.\n");
  
  if (! $verbose) {
      print "Errors have been logged\n";
  }
  close_log_on_error($msg,$verbose);

  my $hf_path='';
  if (defined $HfResult && $HfResult ne "unset") {
      #$hf_path = $HfResult->get_value('headfile_dest_path');
      (my $v_ok,$hf_path) = $HfResult->get_value_like_check('headfile[_-]dest[_-]path');
      #if($hf_path eq "NO_KEY"){ $hf_path = $HfResult->get_value('headfile-dest-path'); }
      #if($hf_path eq "NO_KEY"){ $hf_path = $HfResult->get_value('result-headfile-path'); }
      if(! $v_ok){ ($v_ok,$hf_path) = $HfResult->get_value_like_check('result[_-]headfile[_-]path'); }
      #my ($n,$p,$e) = fileparts($hf_path);
      my ($p,$n,$e) = fileparts($hf_path,2);
      my $hf_path = $p.$n.'.err'.$e;
      if ($v_ok ) {
          $HfResult->write_headfile($hf_path);
          $HfResult = "unset";
      }
  }
  exit $BADEXIT;
}

# -------------
sub execute {
# -------------
# returns 0 if error, or 1 for success
# execute command or list of commands sequentially
#
	my ($do_it, $annotation, @commands) = @_;
	my $succeeded=0;
	my $cmd_prefix="";
	
	printd(45,"Execute non-cluster or matlab\n");
	my $exec_verbose=1;
	if ($debug_val<15){ 
		$exec_verbose=0;
	}
	#######################
	foreach my $c (@commands) {
		$succeeded = $succeeded + execute_heart($do_it, $annotation, $cmd_prefix.$c,$exec_verbose);
	}
	#######################
	printd(45," $succeeded of ".scalar(@commands)." commands succeeded.\n");
	# if n success is n commands, return 1, else, 0
	return $succeeded == scalar(@commands) ? 1 : 0;
}

# -------------
sub execute_heart {
# -------------
# returns 0 if error, or 1 for success
    my ($do_it, $annotation, $single_command,$exec_verbose) = @_;
    my $shell_return;
    # -- log the info and the specific command on separate lines.
    execute_log($do_it,$annotation,$single_command,$exec_verbose);

    # This could use improvement as it doesnt capture command output
    if ($do_it) {

		$shell_return = system ($single_command);
    }
    else {
        $shell_return = 0; # fake ok
    }
    #print "------ system returned: $shell_return -------\n";
    if ($shell_return != 0) {
        warn("  Problem:  system() returned: $shell_return\n".
             "  * Command was: $single_command\n".
             "  * Execution of command failed.\n");
        return 0;
    }
    return 1;
}

# ------------------
sub execute_log {
# ------------------
# execute_log
# logger for execute function. Uses log_info functions. 
# do_it,notation,cmd,display_bool
    my ($do_it,$annotation,$command,$verbose)=@_;
    if (! defined $verbose) {$verbose = 1;}
    my $skip = $do_it ? "" : "Skipped ";
    my $info = $annotation eq '' ? ": " : " $annotation: "; 
    my $time = scalar localtime;
    my $msg = join '', $skip, "EXECUTING",$info, "--", $time , "--";
    my $cmsg = "   $command";
    if (($verbose == 2)) {
        if (! $do_it) {
            $verbose = 0;
        } else {
            $verbose = 1;
        }
    }
    log_info($msg,$verbose);
    log_info($cmsg,$verbose);
}

# ------------------
sub fileparts { 
# ------------------
# ala matlab file parts, take filepath, return path name ext
# operates in 2 modes.
# mode 2: all extension behavior, path, name, all.ext
# mode 3: last extension behavior, path, name, finalext
    my ($fullname,$ver) = @_;
    if( ! defined $ver){
        $ver=2;
    }

    if ( ! defined $fullname || $fullname eq "") { 
        return("","","");
    }
    my ($name,$path,$suffix) = fileparse($fullname,qr/\.([^.].*)+$/);#qr/\.[^.]*$/)
    if ($ver ==3){
        ($name,$path,$suffix) = fileparse($fullname,qr/\.[^.]*$/);
    }

    return($path,$name,$suffix);

}

# ------------------
sub find_file_by_pattern {
# ------------------
    my ($search_base,$pattern,$recursion_limit)=@_;
    my %files;
    #Data::Dump::dump($search_base,$pattern);
    # crunch all trailing slashes
    #$search_base=~ s:/*$::x;#simplistic method
    # two line method
    #my @sb_dirs = grep { $_ ne '' } File::Spec->splitdir($search_base);
    #$search_base=File::Spec->catdir(@sb_dirs);
    # oneliner
    $search_base = File::Spec->catdir('', grep { $_ ne '' } File::Spec->splitdir($search_base) );
    my $inital_depth = grep { length } File::Spec->splitdir($search_base);
    #confess "starting depth for $search_base is $inital_depth\n";
    my $preprocess_ref=sub {# preprocess
        #my $depth=$File::Find::dir =~ tr[/][];
        my $depth=scalar File::Spec->splitdir($File::Find::dir) - $inital_depth;
        return @_ if $depth < $recursion_limit;
        return grep { not -d } @_ if $depth == $recursion_limit;
        return;
    };
    my $wanted_ref=sub { # wanted  
        # pretty sure this doenst help us any.
        #if( $recursion_limit && -d $_ ) {
        #    $File::Fine::prune = 1;
        #    return;
        #}
        ${files{$File::Find::name}} = 1 if ($_ =~  m/$pattern/x && -f $_ );
    };
    #my $wanted_ref=\&wanted;
    #my $preprocess_ref=\&preprocess;
    if( ! defined $recursion_limit || $recursion_limit == 0 ){
        $preprocess_ref=undef;
    }
    #printd(40,"finding files in $search_base matching $pattern\n");
    #$IS_LINUX
    #find( sub { ${files{$File::Find::name}} = 1 if ($_ =~  m/$pattern/x ) ; },$search_base."/");
    #$IS_MAC
    find(
        { 
            #wanted => sub { ${files{$File::Find::name}} = 1 if ($_ =~  m/$pattern/x && -f $_) ; },
            preprocess=>$preprocess_ref,
            wanted=>$wanted_ref,
            # preprocess is incompatible with follow for some reason. 
            #follow => 1, 
        },
        $search_base."/");
    my @fnames=sort(keys(%files));
    return(@fnames);
}

# ------------------
sub find_temp_headfile_pointer {
# ------------------
   # In a given a directory, checks to see if there is ONE AND ONLY ONE headfile. If so, returnsT pointer to this file. ELSE returns undefined.
    
    my ($location) = @_;

    if (! -e  $location) {
        return();
    } else {
        opendir(DIR,$location);
        my @headfile_list = grep(/.*\.headfile$/ ,readdir(DIR));
        if ($#headfile_list > 0) {
            error_out(" $PM: more than one temporary headfile found in folder: ${location}.  Unsure of which one accurately reflects previous work done.\n"); 
        }
        if ($#headfile_list < 0) {
            print " $PM: No temporary headfile found in folder ${location}.  Any existing data will be removed and regenerated.\n";
            return();
        } else {
            my $tempHf = new Headfile ('rw', "${location}/${headfile_list[0]}");
            if (! $tempHf->check()) {
                print " Unable to open temporary headfile ${headfile_list[0]}. Any existing data in ${location} will be removed and regenerated.\n";
                return();
            }
            if (! $tempHf->read_headfile) {
                print " Unable to read temporary headfile ${headfile_list[0]}. Any existing data in ${location} will be removed and regenerated.\n";
                return();
            }
    
            return($tempHf); 
        }
    }
}

# ------------------
sub format_transforms_for_command_line {
# ------------------    
    my ($comma_string,$option_letter,$start,$stop) = @_;
    my $command_line_string='';
    my @transforms = split(',',$comma_string);
    my $total = $#transforms + 1;
  
    if ((defined $option_letter) && ($option_letter ne '')) {
        $command_line_string = "-${option_letter} ";
    }

    if (! defined $start) {
        $start = 1;
        #$stop = $total;
    }

    if (! defined $stop) {
        $stop = $total;
    }

    my $count = 0;
#for(count=start;cont<stop&&count<maxn;count++)
#trans=transforms[count]
    foreach my $transform (@transforms) {
        $count++;
        if (($count >= $start) && ($count <= $stop)) {
            if (($transform =~ /\.nii$/) || ($transform =~ /\.nii\.gz$/)) { # We assume diffeos are in the format of .nii or .nii.gz
                $command_line_string = $command_line_string." $transform ";     
            } elsif (($transform =~ /\.mat$/) || ($transform =~ /\.txt$/)) { # We assume affines are in .mat or .txt formats
                if ($transform =~ m/-i[\s]+(.+)/) {
                    $command_line_string = $command_line_string." [$1,1] "; 
                } else {
                    $command_line_string = $command_line_string." [$transform,0] ";
                }
            }
        }
    }
    return($command_line_string);
}



## Note: the following code wouldn't be so verbose, but ChatterBoxGPT doesn't know how to keep things succint.

#---------------------
sub nifti1_bb_spacing {
#---------------------
    my ($path, $try_legacy) = @_;
    $try_legacy //= 0;

    my $hdr = _read348($path);
    my $r   = _unpack_hdr($hdr);

    my ($ndim, @shape) = ($r->{dim}[0]||0, @{$r->{dim}}[1..7]);
    @shape = @shape[0..$ndim-1] if $ndim && $ndim <= @shape;

    my ($qfac, @pd) = @{$r->{pixdim}};
    my ($dx,$dy,$dz,$dt) = (@pd,0,0,0,0)[0..3];

    # pick offsets
    my ($ox,$oy,$oz) = (0.0,0.0,0.0);
    if (($r->{sform_code}||0) > 0) {
        ($ox,$oy,$oz) = ($r->{srow_x}[3], $r->{srow_y}[3], $r->{srow_z}[3]);
        if ($try_legacy && ($r->{qform_code}||0) > 0) {
            $ox = $r->{qoffset_x} if $ox == 0;
            $oy = $r->{qoffset_y} if $oy == 0;
            $oz = $r->{qoffset_z} if $oz == 0;
        }
    } elsif (($r->{qform_code}||0) > 0) {
        ($ox,$oy,$oz) = ($r->{qoffset_x}, $r->{qoffset_y}, $r->{qoffset_z});
    }

    my $dim = $ndim; $dim = 3 if $dim > 3; $dim = 1 if $dim < 1;

    my @sizes    = (@shape, (0,0,0))[0..2];
    my @spacings = (($dx||0), ($dy||0), ($dz||0));
    my @bb0      = ($ox, $oy, $oz);
    my @bb1      = (
        $bb0[0] + $sizes[0]*$spacings[0],
        $bb0[1] + $sizes[1]*$spacings[1],
        $bb0[2] + $sizes[2]*$spacings[2],
    );

    my ($fmt_bb0, $fmt_bb1, $fmt_sp);
    if ($try_legacy) {
        $fmt_bb0 = \&_fmt_legacy_from_fsl;   # like fslhd tokens
        $fmt_bb1 = \&_fmt_legacy_from_calc;  # like legacy computed path
        $fmt_sp  = \&_fmt_legacy_from_fsl;   # like fslhd tokens
    } else {
        $fmt_bb0 = $fmt_bb1 = $fmt_sp = \&_fmt_new;
    }

    my $bb_0   = join(' ', map { $fmt_bb0->($_) } @bb0[0..$dim-1]);
    my $bb_1   = join(' ', map { $fmt_bb1->($_) } @bb1[0..$dim-1]);
    my $spacing= join('x', map { $fmt_sp ->($_) } @spacings[0..$dim-1]);
	
	my $temp_debug = 0;
	if ($try_legacy && $temp_debug) {
		my $print_line = "\{\[${bb_0}\], \[${bb_1}\]\} $spacing";
		print  "Legacy result: ${print_line}\n";
		$print_line = visualize_ws(${print_line}) ;
		print  "Legacy result: ${print_line}\n";
	}
    # Return exactly what your caller expects
    return ($bb_0, $bb_1, $spacing, $dim);

}

# ---------- Begin nifti1_bb_spacing internals ----------

sub visualize_ws {
    my ($s) = @_;
    # Make invisibles visible
    $s =~ s/ /␠/g;        # space
    $s =~ s/\t/␉/g;       # tab
    $s =~ s/\r/␍/g;       # CR
    $s =~ s/\n/␊/g;       # LF
    $s =~ s/\x{A0}/⍽/g;   # NBSP
    return $s;
}

sub _read348 {
    my ($path) = @_;
    sysopen(my $fh, $path, O_RDONLY) or die "open $path: $!";
    binmode($fh);
    my $sig = '';
    my $got = read($fh, $sig, 2);
    die "short read($path)" unless defined $got && $got == 2;

    if ($sig eq "\x1f\x8b") {   # gzip
        close $fh;
        if (_have_gunzip()) {
            my $z = IO::Uncompress::Gunzip->new($path)
              or die "gunzip($path): $IO::Uncompress::Gunzip::GunzipError";
            my $buf = ''; my $need = 348;
            while ($need > 0) {
                my $chunk = '';
                my $n = $z->read($chunk, $need);
                die "gunzip read error on $path" unless defined $n;
                last if $n == 0;
                $buf  .= $chunk;
                $need -= $n;
            }
            $z->close();
            die "decompressed header too short in $path" unless length($buf) == 348;
            return $buf;
        } else {
            open my $z, "-|", "gzip", "-dc", "--", $path
              or die "spawn gzip -dc $path: $!";
            binmode($z);
            my $buf = ''; my $need = 348;
            while ($need > 0) {
                my $chunk = '';
                my $n = read($z, $chunk, $need);
                die "gzip pipe read error on $path" unless defined $n;
                last if $n == 0;
                $buf  .= $chunk;
                $need -= $n;
            }
            close $z;
            die "decompressed header too short in $path" unless length($buf) == 348;
            return $buf;
        }
    } else {
        sysseek($fh, 0, 0) or die "seek $path: $!";
        my $hdr = ''; my $n = read($fh, $hdr, 348);
        close($fh);
        die "short header ($n bytes) in $path" unless defined $n && $n == 348;
        return $hdr;
    }
}

sub _unpack_hdr {
	my ($hdr) = @_;
	my $sz_le = unpack('V', substr($hdr,0,4));
	my $sz_be = unpack('N', substr($hdr,0,4));
	my $little = $sz_le == 348 ? 1 : $sz_be == 348 ? 0 : die "Not a NIfTI-1 header";
	my $s = $little ? 's<' : 's>';   my $l = $little ? 'l<' : 'l>';   my $f = $little ? 'f<' : 'f>';
	my $tpl = join(' ',
		$l,'Z10','Z18',$l,$s,'a1','C',
		$s.'8',($f)x3,$s,$s,$s, $s,
		$f.'8', $f,$f,$f, $s,'C','C',
		$f,$f,$f,$f, $l,$l, 'Z80','Z24',
		$s,$s, ($f)x6, $f.'4',$f.'4',$f.'4', 'Z16','Z4'
	);
	my @v = unpack($tpl, $hdr);
	my %r; my $i=0;
	$r{sizeof_hdr}=$v[$i++]; $r{data_type}=$v[$i++]; $r{db_name}=$v[$i++];
	$r{extents}=$v[$i++]; $r{session_error}=$v[$i++]; $r{regular}=$v[$i++]; $r{dim_info}=$v[$i++];
	$r{dim}=[ @v[$i..$i+7] ]; $i+=8;
	@r{qw(intent_p1 intent_p2 intent_p3)} = @v[$i..$i+2]; $i+=3;
	@r{qw(intent_code datatype bitpix slice_start)} = @v[$i..$i+3]; $i+=4;
	$r{pixdim}=[ @v[$i..$i+7] ]; $i+=8;
	@r{qw(vox_offset scl_slope scl_inter)} = @v[$i..$i+2]; $i+=3;
	@r{qw(slice_end slice_code xyzt_units)} = @v[$i..$i+2]; $i+=3;
	@r{qw(cal_max cal_min slice_duration toffset)} = @v[$i..$i+3]; $i+=4;
	@r{qw(glmax glmin)} = @v[$i..$i+1]; $i+=2; @r{qw(descrip aux_file)} = @v[$i..$i+1]; $i+=2;
	@r{qw(qform_code sform_code)} = @v[$i..$i+1]; $i+=2;
	@r{qw(quatern_b quatern_c quatern_d qoffset_x qoffset_y qoffset_z)} = @v[$i..$i+5]; $i+=6;
	$r{srow_x}=[ @v[$i..$i+3] ]; $i+=4; $r{srow_y}=[ @v[$i..$i+3] ]; $i+=4; $r{srow_z}=[ @v[$i..$i+3] ]; $i+=4;
	@r{qw(int}ent_name magic)} = @v[$i..$i+1];
		return \%r;
}

sub _fmt {
	my ($x)=@_;
	my $s = sprintf("%.10f", $x // 0);
	$s =~ s/0+$//; $s =~ s/\.$/.0/;
	return $s;
}

# New, sane formatter (retain if you still want the modern behavior)
sub _fmt_new {
    my ($x) = @_;
    my $s = sprintf("%.10f", $x // 0);
    $s =~ s/0+$//;      # drop fractional trailing zeros
    $s =~ s/\.$/.0/;    # ensure trailing .0
    return $s;
}

# Legacy: emulate fslhd-style tokens *before* applying the old trims.
# Use this for values that originally came from fslhd text: bb0 and pixdims.
sub _fmt_legacy_from_fsl {
    my ($x) = @_;
    my $s = sprintf("%.6f", $x // 0);  # fslhd typically shows 6 decimals
    $s =~ s/0+$//;                     # legacy bug: drop all trailing zeros
    $s =~ s/\.$/.0/;                   # fix bare trailing dot
    return $s eq '' ? '0' : $s;
}

# Legacy: for computed numbers (bb1), legacy code stringified the perl number
# and then applied the same buggy trims -> 110 becomes 11.
sub _fmt_legacy_from_calc {
    my ($x) = @_;
    my $s = "$x";                      # Perl's default stringification

    # If it has >6 decimals, TRUNCATE (not round) to 6 places
    if ($s =~ /^(-?\d+)\.(\d{6})(\d+)/) {
        $s = "$1.$2";
    }

    # Legacy cleanup steps (buggy on integers, by design):
    $s =~ s/0+$//;                     # drop *all* trailing zeros
    $s =~ s/\.$/.0/;                   # fix bare trailing dot
    $s =~ s/^\s+//;                    # trim leading ws
    return $s eq '' ? '0' : $s;
}

# ---------- End nifti1_bb_spacing internals ----------


# Returns dim[k] from a NIfTI header (default k=4).
# - k must be 0..7
# - If k>0 and the file reports fewer than k dimensions, returns 1.
# - Uses your _read348() helper; no external tools required.
sub nifti_dim4 {
    my ($path, $k) = @_;
    $k = 4 if !defined $k;
    die "dim index k must be an integer 0..7" if $k !~ /^\d+$/ or $k > 7;

    my $hdr = _read348($path);

    # Endianness via sizeof_hdr (bytes 0..3 must be 348)
    my $sz_le = unpack('V', substr($hdr, 0, 4));
    my $sz_be = unpack('N', substr($hdr, 0, 4));
    my $little;
    if    ($sz_le == 348) { $little = 1 }
    elsif ($sz_be == 348) { $little = 0 }
    else { die "Not a valid NIfTI-1 header in $path (sizeof_hdr != 348)" }

    # dim[8] lives at offset 40..55 (8 * int16)
    my @dim = $little ? unpack('v8', substr($hdr, 40, 16))
                      : unpack('n8', substr($hdr, 40, 16));
    my $ndim = $dim[0] // 0;

    # k==0: report ndim as-is; otherwise honor NIfTI convention of 1's beyond ndim
    return $k == 0 ? ($ndim || 0)
                   : (($ndim >= $k && ($dim[$k] // 0)) ? $dim[$k] : 1);
}


# Fast header parse (dim[], pixdim[]) then stream data and count > 0
sub mask_volume_mm3 {
    my ($path) = @_;
    my $hdr = _read348($path);

    my $sz_le = unpack('V', substr($hdr,0,4));
    my $little = $sz_le == 348 ? 1 : 0;
    my @dim    = $little ? unpack('v8', substr($hdr, 40, 16))
                         : unpack('n8', substr($hdr, 40, 16));
    my @pix    = unpack(($little?'f<8':'f>8'), substr($hdr, 76, 32));

    my ($nx,$ny,$nz) = @dim[1..3];
    my $voxel_mm3 = abs($pix[1] * $pix[2] * $pix[3]) || 0;

    # datatype/bitpix/scl for proper thresholding
    my ($datatype,$bitpix,$slope,$inter) = (
        ($little?unpack('v',substr($hdr,70,2)):unpack('n',substr($hdr,70,2))),
        ($little?unpack('v',substr($hdr,72,2)):unpack('n',substr($hdr,72,2))),
        unpack(($little?'f<':'f>'), substr($hdr,112,4)),
        unpack(($little?'f<':'f>'), substr($hdr,116,4)),
    );
    $slope ||= 1; $inter ||= 0;

    # Determine where image data starts (vox_offset)
    my $vox_offset = unpack(($little?'f<':'f>'), substr($hdr,108,4));
    $vox_offset = 352 if $vox_offset < 352;  # typical for .nii

    # Open the file (gunzip transparently if needed)
    my ($fh, $is_gz);
    if ($path =~ /\.gz$/i) {
        require IO::Uncompress::Gunzip;
        $fh = IO::Uncompress::Gunzip->new($path) or die "gunzip($path): $IO::Uncompress::Gunzip::GunzipError";
        $is_gz = 1;
    } else {
        open($fh, '<:raw', $path) or die "open $path: $!";
    }

    # Skip to vox_offset
    if ($is_gz) {
        my $skip = $vox_offset; my $buf;
        while ($skip > 0) { my $n = $fh->read($buf, ($skip > 1<<20 ? 1<<20 : $skip)) or last; $skip -= $n; }
    } else {
        seek($fh, $vox_offset, 0) or die "seek $path: $!";
    }

    my $type_tpl = do {
        # Handle most common types: 2=uint8, 4=int16, 8=int32, 16=float32
        $datatype == 2  ? 'C*' :
        $datatype == 4  ? ($little?'s<*':'s>*') :
        $datatype == 8  ? ($little?'l<*':'l>*') :
        $datatype == 16 ? ($little?'f<*':'f>*') :
        die "datatype $datatype not implemented";
    };
    my $bytes_per = $bitpix/8;

    my $nvox = $nx*$ny*$nz;
    my $chunk = 1_000_000;  # elements per chunk
    my $buf; my $nonzero = 0; my $left = $nvox;

    while ($left > 0) {
        my $take = $left > $chunk ? $chunk : $left;
        my $need = $take * $bytes_per;
        my $read = read($fh, $buf, $need);
        die "short read image data" unless defined $read && $read == $need;

        my @vals = unpack($type_tpl, $buf);
        if ($slope != 1 || $inter != 0) {
            $nonzero += grep { ($slope*$_ + $inter) != 0 } @vals;
        } else {
            $nonzero += grep { $_ != 0 } @vals;
        }

        $left -= $take;
    }
    close $fh unless $is_gz;

    return $nonzero * $voxel_mm3;
}

# Returns the maximum voxel value in a NIfTI image (good for label maps).
# - Works for .nii / .nii.gz, and .hdr/.img (and gzipped pair).
# - Applies scl_slope/scl_inter if present.
# - For label maps, you'll usually want int(...) of this.
sub nifti_max_value {
    my ($path) = @_;

    my $hdr = _read348($path);  # your helper

    # --- endian + key header fields ---
    my $is_le = (unpack('V', substr($hdr,0,4)) == 348) ? 1
             : (unpack('N', substr($hdr,0,4)) == 348) ? 0
             : die "Not a valid NIfTI-1 header in $path";

    my $u16 = sub { $is_le ? unpack('v', $_[0]) : unpack('n', $_[0]) };
    my $f32 = sub { $is_le ? unpack('f<', $_[0]) : unpack('f>', $_[0]) };

    my $datatype  = $u16->(substr($hdr, 70, 2));
    my $bitpix    = $u16->(substr($hdr, 72, 2));
    my $vox_offset = $f32->(substr($hdr,108, 4));
    my $scl_slope  = $f32->(substr($hdr,112, 4)) || 1.0;
    my $scl_inter  = $f32->(substr($hdr,116, 4)) || 0.0;

    # dims
    my @dim = $is_le ? unpack('v8', substr($hdr, 40, 16))
                     : unpack('n8', substr($hdr, 40, 16));
    my ($nx,$ny,$nz) = @dim[1..3];
    my $nvox = ($nx||0) * ($ny||0) * ($nz||0);
    die "Zero-dimension image in $path" unless $nvox;

    # Some NIfTI writers set small vox_offset; enforce minimum for .nii
    $vox_offset = 352 if $vox_offset < 352 && $path =~ /\.nii(\.gz)?$/i;

    # Determine data file (nii vs hdr/img pair)
    my ($data_path, $prefix_is_gz, $is_pair) = ($path, ($path =~ /\.gz$/i)?1:0, 0);
    if ($path =~ /\.hdr(\.gz)?$/i) {
        $is_pair = 1;
        (my $img = $path) =~ s/\.hdr(\.gz)?$/.img$1/i;
        $data_path = $img;
        $vox_offset = 0;  # Analyze/NIfTI pair starts at 0
    }

    # Open data stream (gz or raw)
    my ($fh, $is_gz);
    if ($data_path =~ /\.gz$/i) {
        require IO::Uncompress::Gunzip;
        $fh = IO::Uncompress::Gunzip->new($data_path)
          or die "gunzip($data_path): $IO::Uncompress::Gunzip::GunzipError";
        $is_gz = 1;
    } else {
        open($fh, '<:raw', $data_path) or die "open $data_path: $!";
        seek($fh, $vox_offset, 0) or die "seek $data_path: $!" if $vox_offset;
    }

    # For gz streams, skip vox_offset manually
    if ($is_gz && $vox_offset) {
        my $to_skip = $vox_offset; my $tmp;
        while ($to_skip > 0) {
            my $chunk = $to_skip > 1<<20 ? 1<<20 : $to_skip;
            my $n = $fh->read($tmp, $chunk);
            die "short skip in $data_path" unless defined $n && $n == $chunk;
            $to_skip -= $n;
        }
    }

    # Map datatype -> unpack template & element size
    my ($tpl, $bytes);
    if    ($datatype == 2)   { $tpl = 'C*';                    $bytes = 1; }         # uint8
    elsif ($datatype == 4)   { $tpl = $is_le ? 's<*' : 's>*';  $bytes = 2; }         # int16
    elsif ($datatype == 8)   { $tpl = $is_le ? 'l<*' : 'l>*';  $bytes = 4; }         # int32
    elsif ($datatype == 16)  { $tpl = $is_le ? 'f<*' : 'f>*';  $bytes = 4; }         # float32
    elsif ($datatype == 64)  { $tpl = $is_le ? 'd<*' : 'd>*';  $bytes = 8; }         # float64
    elsif ($datatype == 512) { $tpl = $is_le ? 'S<*' : 'S>*';  $bytes = 2; }         # uint16
    elsif ($datatype == 768) { $tpl = $is_le ? 'L<*' : 'L>*';  $bytes = 4; }         # uint32
    else { die "datatype $datatype not implemented in nifti_max_value()" }

    my $left   = $nvox;
    my $chunkN = 1_000_000;                      # elements per chunk
    my $buf; my $max = undef;

    while ($left > 0) {
        my $take = $left > $chunkN ? $chunkN : $left;
        my $need = $take * $bytes;
        my $read = read($fh, $buf, $need);
        die "short read image data from $data_path" unless defined $read && $read == $need;

        my @vals = unpack($tpl, $buf);

        if ($datatype == 16 || $datatype == 64 || $scl_slope != 1.0 || $scl_inter != 0.0) {
            # apply scaling for real types or when slope/inter set
            for my $v (@vals) {
                my $x = $scl_slope * $v + $scl_inter;
                $max = defined $max ? ($x > $max ? $x : $max) : $x;
            }
        } else {
            # integer types, no scaling
            for my $x (@vals) {
                $max = defined $max ? ($x > $max ? $x : $max) : $x;
            }
        }

        $left -= $take;
    }
    close($fh) unless $is_gz;

    return $max // 0;
}

# Convenience wrapper for label maps: returns an integer max label
sub nifti_max_label {
    my ($path) = @_;
    my $mx = nifti_max_value($path);
    # For labels, force to nearest non-negative integer
    $mx = 0 if !defined $mx;
    $mx = int($mx + 0.5) if $mx >= 0;
    return $mx;
}


#---------------------
sub get_bounding_box_and_spacing_from_header {
#---------------------
	# Old method of invoking fslhd has been permanently deprecated as of 2 September 2025
	# Using custom perl code avoids system call, and has been shown to speed things up ~20x
    my ($file,$try_legacy) = @_;
    my $bb_and_spacing;
    #my ($spacing,$bb_0,$bb_1);
    
    if (! defined $try_legacy) {
        $try_legacy = 0;
    }

	my ($bb_0, $bb_1, $spacing, $dim) = nifti1_bb_spacing($file,$try_legacy);
	$bb_and_spacing = "{[$bb_0], [$bb_1]} $spacing";

    return($bb_and_spacing);
}

# ------------------
sub get_nii_from_inputs {
# ------------------
    #### :D #### 
    #### :D #### 
    #funct_obsolete('get_nii_from_inputs','SAMBA_pipeline_utilities::find_file_by_pattern("dir","regex"');
    #### :D #### 
    #### :D #### 
# Update to only return hdr/img/nii/nii.gz formats.
# Case insensitivity added.
# Order of selection (using contrast = 'T2' and 'nii' as an example):
#        1)  ..._contrast_masked.nii   S12345_T2_masked.nii    but not...   S12345_T2star.nii or S12345_T2star.nii
#        2)  ..._contrast.nii          S12345_T2.nii           but not...   S12345_T2star.nii
#        3)  ..._contrast_*.nii        S12345_T2_unmasked.nii  but not...   S12345_T2star.nii or S12345_T2star.nii
#        4)  ..._contrast*.nii         S12345_T2star.nii  or S12345_T2star_masked.nii, etc
#        5)  Returns error if nothing matches any of those formats
#
#        Note that on 17 July 2017, the first two cases were swapped, thus giving '_masked' preference.  It appears that sometimes an unmasked version of an image may not get removed from a folder, and will be selected when it is, in general, the masked version which is wanted.
#
# Need to add exception for fa/color_fa--> requesting fa can inadvertently return color_fa, which can be problematic for finding atlas fa's
    require SAMBA_global_variables;
    #SAMBA_global_variables->import(qw($valid_formats_string));
    #require vars qw($valid_formats_string);
    #use SAMBA_global_variables qw($valid_formats_string);
    # the OR didnt work... Investigate!
    #or my $valid_formats_string="GLOBALS_MISSING";
    #die("format_string:${SAMBA_global_variables::valid_formats_string}");
    my $valid_formats_string="GLOBALS_MISSING";
    $valid_formats_string=${SAMBA_global_variables::valid_formats_string} or die $valid_formats_string;
    my ($inputs_dir,$runno,$contrast) = @_;
    my $error_msg='';
    #pattern to rule them alls :D 
    # Missing from this is the selection order behavior, or protection from substring constrats that include name demarkations.
    # Name demarkations in use are . _ and -, it is expected that contrast is framed by those.
    # TODO: modify both instances of '.*' in the line below to explicitly exclude "color" (this should break as soon as we try to pull tensor_create results--30 April 2019 
    my $pattern=$runno.".*[\.\_\-]{1}(".$contrast.'|'.uc($contrast).")[\.\_\-]{1}.*(".$valid_formats_string.")\$";

# 29 July 2023 --BJA: Turning of James' code since it is behaving poorly
if (0) {
    my @found=SAMBA_pipeline_utilities::find_file_by_pattern($inputs_dir,$pattern,1);
    $error_msg="SAMBA_pipeline_utilities function get_nii_from_inputs: Unable to locate file using the input criteria:\n\t\$inputs_dir: ${inputs_dir}\n\t\$runno: $runno\n\t\$contrast: $contrast\n";
    # filter found to masked if(and only if) there are extra
    @found=grep /_masked/ ,@found if (scalar(@found) > 1);

    if ($inputs_dir =~ /inputs/){
#	Data::Dump::dump($inputs_dir,$pattern,@found);die;
    }
    if ( scalar(@found) ) {
        if (scalar(@found) > 1) { 
            Data::Dump::dump("Found too many in $inputs_dir, this is scary to proceed!",@found);
            confess "Found too many in $inputs_dir, dont dare proceed!".join("\n\t".@found);  # Turned on 24 March 2023 -- turn off if switching back
        }
        return $found[0];  # Turned on 24 March 2023 -- turn off if switching back
    } else {
        #confess "failed to find data in $inputs_dir with $runno $contrast $valid_formats_string";
        return $error_msg; # Turned on 24 March 2023 -- turn off if switching back
    }
} # PAirs with if ((0)) above
    
   # 24 March 2023 (Fri) --BJA: Turning off this code, as file-checking is taking excruciatingly long on BIAC cluster for large studies.
    # 29 July 2023 (Sat) --BJA: Turning this code back on, since the other option couldn't tell the difference between mask and masked.
   #if (0) {

    my $test_contrast;
    if ((defined $contrast) && ($contrast ne '')) {
        if ($contrast =~ /^fa$/i) {
            $contrast='(?<!color_)fa(?!_color)'; # 7 July 2017: use negative look behind assertion to avoid finding 'color_fa' when looking for just 'fa'.  
        }

        if ($contrast =~ /^nqa$/i) {
            $contrast='(?<!color_)nqa(?!_color)'; # 7 July 2017: use negative look behind assertion to avoid finding 'color_fa' when looking for just 'fa'.  
        }
        $test_contrast = "_${contrast}";
    } else {
        $test_contrast = "";
    }
    
    my $input_file='';
    if (-d $inputs_dir) {
        opendir(DIR, $inputs_dir);
        my @input_files_0= grep(/^($runno).*(${test_contrast})_masked\.($valid_formats_string){1}(\.gz)?$/i ,readdir(DIR));
        #my @input_files_0= grep(/^($runno).*(${test_contrast})_masked\.($valid_formats_string){1}(\.gz)?$/i ,glob ("${inputs_dir}/*"));

        $input_file = $input_files_0[0];

        if ((! defined $input_file) || ($input_file eq '') ) {
			opendir(DIR, $inputs_dir);
            #my @input_files_1= grep(/\/${runno}.*${test_contrast}\.($valid_formats_string)$/i ,glob ("${inputs_dir}/*")); #27 Dec 2016, added "^" because new phantom naming method of prepending (NOT substituting) "P" "Q" etc to beginning of runno results in ambiguous selection of files. Runno "S64944" might return "PS64944" "QS64944" or "S64944".
            my @input_files_1= grep(/^($runno).*(${test_contrast})\.($valid_formats_string){1}(\.gz)?$/i ,readdir(DIR));
            $input_file = $input_files_1[0];
 
            if ((! defined $input_file) || ($input_file eq '')) {
				
                opendir(DIR, $inputs_dir);
                #my @input_files_2= grep(/\/($runno).*(${test_contrast})_.*\.($valid_formats_string){1}(\.gz)?$/i ,glob ("${inputs_dir}/*")); #28 Dec 2016, added "^" like above.
                my @input_files_2=grep(/^($runno).*(${test_contrast})_.*\.($valid_formats_string){1}(\.gz)?$/i ,readdir(DIR));
                $input_file = $input_files_2[0];
  
                if ((! defined $input_file) || ($input_file eq '') ) {
                    opendir(DIR, $inputs_dir);
                    #my @input_files_3= grep(/\/($runno).*(${test_contrast}).*\.($valid_formats_string){1}(\.gz)?$/i ,glob ("${inputs_dir}/*"));  #28 Dec 2016, added "^" like above.
                     my @input_files_3= grep(/^($runno).*(${test_contrast}).*\.($valid_formats_string){1}(\.gz)?$/i ,readdir(DIR)); 
                    $input_file = $input_files_3[0];

                }
            }
        }
        
        if ((defined $input_file) && ($input_file ne '') ) {
            my $path= $inputs_dir.'/'.$input_file;
            return($path);
            #return($input_file);
        } else {
            $error_msg="SAMBA_pipeline_utilities function get_nii_from_inputs: Unable to locate file using the input criteria:\n\t\$inputs_dir: ${inputs_dir}\n\t\$runno: $runno\n\t\$contrast: $contrast\n";
            return($error_msg);
        }
    } else {
        $error_msg="SAMBA_pipeline_utilities function get_nii_from_inputs: The input directory $inputs_dir does not exist.\n";
        return($error_msg);
    }
    # } # Comment out  if reactivating codeblock above (pairs with if (0) )
}

#---------------------
sub get_slurm_job_stats {
#---------------------
    my ($PM_code,@jobs) = @_;
  
    my $stats_string='';
    my $requested_stats = 'Node%25,TotalCPU%25,CPUTimeRaw%25,MaxRSS%25';
    my ($node,$Node_string, $TotalCPU_string,$CPURaw_string,$MaxRSS_string);
    foreach my $job (@jobs) {
        my $out_string='';
	my $inverted_sacct_test=`sacct 2>&1 | grep 'is disabled' | wc -l`;
	if ( $inverted_sacct_test ) {
		return('No_Stats_Accounting_Available');
	}
	if ($cluster_type == 1) {
	    my  $current_stat_string = `sacct -Pan  -j $job.batch -o ${requested_stats}`;
	    #print "Current_stat_string = ${current_stat_string}\n\n";
	    my @raw_stats = split('\|',$current_stat_string);
	    $Node_string = $raw_stats[0];
	    $TotalCPU_string = $raw_stats[1];
	    $CPURaw_string = $raw_stats[2];
	    $MaxRSS_string = $raw_stats[3];

	    if ($Node_string =~ /civmcluster1-0([1-6]{1})G?/) {
			$node = $1;
	    } else {
			$node = 0;
	    }
        
	} elsif ($cluster_type = 2) {
	    my $jid=$job;
	    $node=`qacct -j $jid | tr -s [:space:] "\n" | grep -A1 hostname | tail -1| cut -d '.' -f1`;
	    $TotalCPU_string =`qacct -j $jid | tr -s [:space:] "\n" | grep -A1 ru_utime | tail -1`;
	    $CPURaw_string =`qacct -j $jid | tr -s [:space:] "\n" | grep -A1 cpu | tail -1`;
	    $MaxRSS_string =`qacct -j $jid | tr -s [:space:] "\n" | grep -A1 ru_maxrss | tail -1`;
	}

	my $total_cpu_raw = convert_time_to_seconds($TotalCPU_string);
	my $memory_in_kb = 0;
	chomp($MaxRSS_string);
	if ($MaxRSS_string =~ s/K[B]?$//) {
		$memory_in_kb = $MaxRSS_string; 
	} 
	
	$out_string = "${PM_code},${job},${node},${total_cpu_raw},${CPURaw_string},${memory_in_kb}\n";
	$stats_string=$stats_string.$out_string;
    }
    #print "Stats string:\n${stats_string}\n";
    return($stats_string);
}

#---------------------
sub get_spacing_from_header { ## Easier to just call bb_and_spacing code and then take what we need.
#---------------------
    my ($in_file) = @_;
    my $spacing;
    my $bb_and_spacing = get_bounding_box_and_spacing_from_header($in_file);
    my @array = split(' ',$bb_and_spacing);
    $spacing = pop(@array);
   
    return($spacing);
}

#---------------------
sub hash_summation {
#---------------------

    # This is very VBM pipeline (SAMBA) specific dealing with a do_work calls
    my ($hash_pointer)=@_;
    my %hashish = %$hash_pointer;
    my $sum = 0;
    my $errors = 0;
    foreach my $k (keys %hashish) {
        if (ref($hashish{$k}) eq "HASH") {
            foreach my $j (keys %{$hashish{$k}}) {
                my $string = $hashish{$k}{$j};
                if ($string =~ /^[0-9]*$/) {
                    $sum = $sum + $string;
                } else {
                    $errors++;
                }
            }
        } else {
            my $string = $hashish{$k};
            if ($string =~ /^[0-9]*$/) {
                $sum = $sum + $string;
            } else {
                $errors++;
            }
        }
    }
    return($sum,$errors);
}

# ------------------
sub headfile_list_handler {
# ------------------
    my ($current_Hf,$key,$new_value,$invert,$replace) = @_; # 17 November 2016: Added replace to support iterative capabilities, where we only want to track the latest diffeo warp.
    if (! defined $invert) { $invert = 0;}
    if (! defined $replace) { $replace = 0;}

    my $list_string = $current_Hf->get_value($key);
    if ($list_string eq 'NO_KEY') {
        $list_string = '';
    }

    my @list_array = split(',',$list_string);
    my $trash;

    if ($invert) {
        if ($replace) {
            $trash = pop(@list_array);
        }
        push(@list_array,$new_value);
        #$list_string=$list_string.",".$new_value;
    } else {
        if ($replace) {
            $trash = shift(@list_array);
        }
        unshift(@list_array,$new_value);
        #$list_string=$new_value.",".$list_string;
    }

    $list_string = join(',',@list_array);
    $current_Hf->set_value($key,$list_string);
}

# ------------------
sub load_file_to_array { # (path,array_ref[,debug_val]) loads text to array ref, returns number of lines loaded.
# ------------------
    my (@input)=@_;
#    my ($file,$array_ref)=@_;
    my $file=shift @input;
    my $array_ref=shift @input; 
    my $old_debug=$debug_val;
    $debug_val = shift @input or $debug_val=$old_debug;
    SAMBA_pipeline_utilities::debugloc();
    my @all_lines =();
    SAMBA_pipeline_utilities::whoami();
    SAMBA_pipeline_utilities::printd(30,"Opening file $file.\n");
    open my $text_fid, "<", "$file" or confess "could not open $file";
    croak "file <$file> not Text\n" unless -T $text_fid ;
    @all_lines =  <$text_fid> ;
    close  $text_fid;
    push (@{$array_ref}, @all_lines);
    return scalar(@all_lines);
}

# -------------
sub log_info {
# -------------
   my ($log_me,$verbose) = @_;
   if (! defined $verbose) {
       $verbose = 1;
   }
   if( $log_me=~/\n/) {
       # If we're multil line, separate and runourselves per each.
       my @m=split("\n",$log_me);
       #print "\n".$msg."\n\n";
       foreach (@m) {
           log_info($_);
       }
       return;
   }
   
   # add to packagewide array to be used later
   my $to_headfile = "# PIPELINE: " . $log_me;
   push @outheadfile_comments, "$to_headfile";  
   if ($log_open) {

     # send to pipeline file: 
     print( $PIPELINE_INFO "$log_me\n");
   }
   else {
       warn ("LOG NOT OPEN!\n".
             "  You tried to send info for logging, but the log file is not available:\n");
   }
   # show to user:
   if ($verbose) {
       print( "#LOG: $log_me\n");
   }
}

sub make_process_dirs {
# ------------------
# make_process_dirs (Thing, no_change_dir_bool)
# makes our standard triplicate of processing directories,
#  Thing-inputs, Thing-work, Thing-results, and figures out our result headfile path.
# NEW: switches working directory into our work path so garbage files end up there.
# can be turned off with the no_change_dir_bool.
    my ( $identifier,$nocd) =@_;
    use Env qw(BIGGUS_DISKUS);
    my @errors;
    if (! defined($BIGGUS_DISKUS))       { push(@errors, "Environment variable BIGGUS_DISKUS must be set."); }
    if (! -d $BIGGUS_DISKUS)             { push(@errors, "unable to find disk location: $BIGGUS_DISKUS"); }
    #if (! -w $BIGGUS_DISKUS)             { push(@errors, "unable to write to disk location: $BIGGUS_DISKUS notify IT support!"); }
    error_out(join(", ",@errors)) if ( scalar(@errors) > 0 );
    my @dirs;
    foreach ( qw/inputs work results/ ){
        push(@dirs,"$BIGGUS_DISKUS/$identifier\-$_"); }
    foreach (@dirs ){
        if (! -d ){
            mkdir( $_,0777) or push(@errors,"couldnt create dir $_");}}
    error_out(join(", ",@errors)) if ( scalar(@errors) > 0 );
    # switch to the working dir. This is hidden behavior, so its optional, and on by default.
    chdir ($dirs[1]) unless $nocd; 
    return(@dirs,File::Spec->catdir($dirs[2],$identifier.".headfile"));
}

#---------------------
sub memory_estimator {
#---------------------

    my ($jobs,$nodes) = @_;
    if ((! defined $nodes) || ($nodes eq '') || ($nodes == 0)) { $nodes = 1;}

    my $node_mem = 244000;
    if ($cluster_type == 2 ) {$node_mem=124000;} # Added 1 October 2020
    my $memory;
    my $max_jobs_per_node;

    if ($jobs && $nodes) {
        $max_jobs_per_node=int($jobs/$nodes + 0.99999);

        $memory =int($node_mem/$max_jobs_per_node);


        my $limit = 0.9*$node_mem;
        if ($memory > $limit) {
            $memory = $limit;
        } 

            print "Memory requested per job: $memory MB\n";
        
    } else {
        $memory = 2440; # This number is not expected to be used so it can be arbitrary.

    }
    return($memory);
}

#---------------------
sub memory_estimator_2 {
#---------------------

    my ($jobs,$nodes) = @_;
    if ((! defined $nodes) || ($nodes eq '') || ($nodes == 0)) { $nodes = 1;}

    my $node_mem = 240000;
    if ($cluster_type == 2 ) {$node_mem=120000;} #Added 1 October 2020
    my $memory_1;
    my $memory_2;
    my $jobs_requesting_memory_1;
    my $holes;
    my $max_jobs_per_node;
    if ($jobs && $nodes) {
        $max_jobs_per_node=int($jobs/$nodes + 0.99999);
        $holes = $nodes*$max_jobs_per_node-$jobs;

        $jobs_requesting_memory_1 = ($nodes-$holes)*$max_jobs_per_node;

        $memory_1 =int($node_mem/$max_jobs_per_node);
        if ($max_jobs_per_node > 1) {
            $memory_2 =int($node_mem/($max_jobs_per_node-1));
        } else {
            $memory_2 = $memory_1;
        }
        my $limit = 0.9*$node_mem;
        if ($memory_1 > $limit) {
            $memory_1 = $limit;
        } 

        if ($memory_2 > $limit) {
            $memory_2 = $limit;
        } 
        if ($holes) {
            print "[Variable] Memory requested per job: ${memory_1} MB or ${memory_2} MB\n";
        } else {
            print "Memory requested per job: $memory_1 MB\n";
        }
    } else {
        $memory_1 = 2440; # This number is not expected to be used so it can be arbitrary.
        $memory_2 = 2440;
    }
    return($memory_1,$memory_2,$jobs_requesting_memory_1);
}

# -------------
sub open_log {
# -------------
   my ($result_dir) = @_;
   printd(35,"open_log: $result_dir\n");
   if (! -d $result_dir) {
       print ("no such dir for log: $result_dir");
       exit $BADEXIT;
   }
   
   #if (! -w $result_dir) { # Checking write permissions in perl is fraught...
   if (0) {
       print("\n\ndir for log: $result_dir not writeable\n\n\n");
       exit $BADEXIT;
   }
   #$pipeline_info_log_path = "$result_dir/pipeline_info_$PID.txt";
   $pipeline_info_log_path = "$result_dir/pipeline_info_".timestamp_from_epoc(time).".txt";
   open $PIPELINE_INFO, ">$pipeline_info_log_path" or die "Can't open pipeline_info file $pipeline_info_log_path, error $!\n";
   print("# Logfile is: $pipeline_info_log_path\n");
   $log_open = 1;
   my $time = scalar localtime;
   log_info(" Log opened at $time");
   return($pipeline_info_log_path);
}

# -------------
sub printd {
# -------------
    my ($verbosity_threshold,$msg,@remainder)=@_;
    if ($debug_val>=$verbosity_threshold) {
        my $it=ref($msg);
        if( $it ne '' ){
            cluck "badly formed msg passed to printd! in type was a ref of $it! should not be ref!";
            Data::Dump::dump($msg);die;
            return;
        }
        # Had to split the functionality so that errant %'s wouldnt throw issues.
        if(scalar(@remainder)>1  ) {
            $msg=sprintf "$msg",@remainder;
        }
        if ($debug_val >=200 || $debug_val < 85 ) {
            print "$msg";
        } else {
            cluck $msg;
        }
    }
    return;    
}


#---------------------
sub read_refspace_txt {
#---------------------
    my ($refspace_folder,$split_string,$custom_filename)=@_;
    my $refspace_file;
    my ($existing_refspace,$existing_refname);

    if (defined $custom_filename) {
        $refspace_file = "${refspace_folder}/${custom_filename}";
    } else { 
        $refspace_file = "${refspace_folder}/refspace.txt";
    }
   # print "$refspace_file\n\n";
    if (! data_double_check($refspace_file)) {
        my @existing_refspace_and_name =();
        my $array_ref = load_file_to_array($refspace_file, \@existing_refspace_and_name);

        ($existing_refspace,$existing_refname) = split("$split_string",$existing_refspace_and_name[0]); 
    } else {
        $existing_refspace=0;
        $existing_refname=0;
    }
    return($existing_refspace,$existing_refname);
}

#---------------------
sub round {
#---------------------
    my( $val,$digs) = @_;
    if ( ! defined $digs){ 
        $digs=0
    }
    #printf "round $val => to $digs";
    my $result=sprintf("%.".$digs."f",$val);
    #$result=sprintf("%.1f",$val);
#    printf "$result\n";
    return $result;
}

# -------------
sub run_and_watch {
# -------------
# Like execute, run a command, 
# Unlike execute, watch that command and fill our terminal with its spam,
# also return said spam as an array of lines. 
# Testing minimal. 
    require Scalar::Util;
    Scalar::Util->import( qw(openhandle));
    my($c,$indent,$fail_on_return,@a)=@_;
    # indent should be whitespace... of course we might want some char string also... 
    if (scalar(@a)>0){
        die "EXTRA COMMANDS THROWN AT ME!";
    }
    if ( ! defined $indent ){
        $indent="";
    }
    if (! defined $fail_on_return){
        $fail_on_return=1;
    }
    my @out;
    # ... what are my redirects doing! These look terribly shell dependent, eg bash 3+ only.
    # 3 to 1, 1 into t2 2 into 3, and 3 to console? is that whats going on?
    # bashifying all our commands is seen as poor form.... and this is meant for limited use cases,
    # So i guess its okay. 
    #my $pid = open(my $PH, "$c 3>&1 1>&2 2>&3 3>&-|") or die "Couldnt start command $c";
    #my $pid = open(my $PH, "$c 3>&1 1>&2 2>&3 3>& -|") or die "Couldnt start command $c";
    my $pid = open(my $PH, "-|",$c ) or die "Couldnt start command $c";
    # alternative line
    while ( openhandle($PH) && (my $line = <$PH>)) {
    #while (<$PH>) {
        print $indent.$line;
        push(@out,$indent.$line);
    }
    if ( ! close $PH ) {
        if ($fail_on_return){
            Carp::croak ("FAILED: $c \n\twith exit $?");
        } else {
            cluck ("FAILED: $c \n\twith exit $?");
        }
    }
    return @out;
}

# -------------
sub sleep_with_countdown {
# -------------
    my ($sleep_length)=@_;
    print("continuing in ") unless $debug_val==0;
    my $previous_default=select(STDOUT);
    $| ++;
    for(my $t=$sleep_length;$t>0;$t--) {
        print(" $t") unless $debug_val==0; 
        sleep 1 unless $debug_val==0;
        
    }   
    print(" 0.\n");
    select($previous_default);
    return;
}

# ------------------
sub symbolic_link_cleanup {
# ------------------
   # my ($folder,$log) = @_;
   # if (! defined $log) {$log=0;}
    my ($folder,$PM) = @_;
    if (! defined $PM) {$PM = 'Unknown_module';}

    if ($folder !~ /\/$/) {
        $folder=$folder.'/';
    }

    my $link_path;
    my $temp_path = "$folder/temp_file";
    if (! -d $folder) {
        print " Folder $folder does not exist.  No work was done to cleanup symbolic links in non-existent folder.\n";
        return;
    }
    opendir(DIR,$folder);
    my @files = grep(/.*/,readdir(DIR));
    my $log_msg_prefix = "${PM}: Attempting symbolic link cleanup...\n";
    my $log_msg = '';    
   
    foreach my $file (@files) {
        my $file_path = "$folder/$file";
        if (-l $file_path) {
            $link_path = readlink($file_path);
            my ($link_folder,$dummy1,$dummy2)=fileparts($link_path,2);
            my $action;
            if ($link_folder ne $folder) {
                $action = "cp";
                # print "\$link_folder ${link_folder}  ne \$folder ${folder}\n";
            } else {
                # print "\$link_folder ${link_folder}  eq \$folder ${folder}\n";
                $action = "mv";
            }
            my $command = "rm ${file_path}; ${action} ${link_path} ${file_path};";
            my $echo = `$command`;
            $log_msg = $log_msg."Bash command: ${command}\n";
            if ($echo ne '') {
                $log_msg = $log_msg."\tBash echo: $echo\n";
            }
            #my $echo = `rm ${file_path}; ${action} ${link_path} ${file_path};`;
            # if ($log) {
            #   my $annotation = "Cleaning up symbolic links.";
            #   my $command =  "${action} ${link_path} ${file_path}";
            #   $command = $command.$echo;
            #   execute(1,$annotation,$command,$verbose);
            #}
        }
    }
    if ($log_msg ne '') {
        log_info($log_msg_prefix.$log_msg);
    }
}

# -------------
sub timestamp_from_epoc {
# -------------
    my($time)=@_;
    my ($sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst) = localtime($time);$year+=1900;
    my $df="%04i%02i%02i%02i%02i.%02i";
    my $t=sprintf("$df",$year,$month+1,$day,$hour,$min,$sec);
    #print("Convert sec:$time -> $t\n");
    return $t;
}

# ------------------
sub whoami {  return ( caller(1) )[3]; }

# ------------------
sub whowasi { return ( caller(2) )[3]; }


# ------------------
sub wrap_in_container {
# ------------------
    my ($cmd) = @_;

    # Only wrap if CONTAINER_CMD_PREFIX is defined
    return $cmd unless $ENV{CONTAINER_CMD_PREFIX};

    # Safely quote the command for use inside bash -c
    $cmd =~ s/'/'\\''/g;                    # Escape single quotes
    my $quoted_cmd = "'$cmd'";             # Wrap the entire command in single quotes

    # Construct the full container command
    my $container_cmd = "$ENV{CONTAINER_CMD_PREFIX} bash -c $quoted_cmd";

    return $container_cmd;
}

{
    no warnings 'redefine';
    *CORE::GLOBAL::readpipe = sub {
        my ($cmd) = @_;
        return CORE::readpipe($cmd) if $ENV{SAMBA_WRAP_DISABLE};
        my $wrapped = wrap_in_container($cmd);
        return CORE::readpipe($wrapped);
    };
}

{
    no warnings 'redefine';

    my $original_system = \&CORE::system;

    *CORE::GLOBAL::system = sub {
        my @args = @_;

        # Optional disable-switch for debugging
        if ($ENV{SAMBA_WRAP_DISABLE}) {
            return $original_system->(@args);
        }

        my $cmd = @args > 1 ? join(' ', @args) : $args[0];
        $cmd = wrap_in_container($cmd);

        return $original_system->($cmd);
    };
}

sub _shell_quote {
    my (@a) = @_;
    for (@a) { s/'/'\\''/g; $_ = "'$_'"; }
    return join(' ', @a);
}

# ---- override CORE::GLOBAL::open for piped opens only ----
{
    no warnings 'redefine';

    *CORE::GLOBAL::open = sub {
        # Kill-switch (do nothing special)
        if ($ENV{SAMBA_WRAP_DISABLE}) {
            return CORE::open(@_);
        }

        # Expect at least a filehandle and one more arg
        return CORE::open(@_) if @_ < 2;

        my ($fh, @rest) = @_;

        # String-form pipe opens:
        #   open $fh, "cmd |";
        #   open $fh, "| cmd";
        if (@rest == 1 && !ref($rest[0])) {
            my $expr = $rest[0];

            # Read from command ( ... | )
            if ($expr =~ /\|\s*$/) {
                (my $cmd = $expr) =~ s/\|\s*$//;           # strip trailing pipe
                $cmd =~ s/^\s+|\s+$//g;
                my $wrapped = wrap_in_container($cmd);
                my $new = "$wrapped |";
                return CORE::open($fh, $new);
            }

            # Write to command ( | ... )
            if ($expr =~ /^\s*\|/) {
                (my $cmd = $expr) =~ s/^\s*\|\s*//;        # strip leading pipe
                $cmd =~ s/^\s+|\s+$//g;
                my $wrapped = wrap_in_container($cmd);
                my $new = "| $wrapped";
                return CORE::open($fh, $new);
            }

            # Not a pipe open → pass through
            return CORE::open($fh, @rest);
        }

        # List-form pipe opens:
        #   open $fh, "-|", "cmd", @args     # read from command
        #   open $fh, "|-", "cmd", @args     # write to command
        if ($rest[0] eq "-|" || $rest[0] eq "|-") {
            my $mode = shift @rest;          # "-|" or "|-"
            my $cmd_str = _shell_quote(@rest);
            my $wrapped = wrap_in_container($cmd_str);

            # Re-express as string-form pipe open via the shell
            if ($mode eq "-|") {
                return CORE::open($fh, "$wrapped |");
            } else { # "|-"
                return CORE::open($fh, "| $wrapped");
            }
        }

        # Anything else (regular file opens, modes, layers) → pass through
        {
            no strict 'refs';
            return CORE::open(@_);
        }

    };
}


# ------------------
# write_array_to_file
# (path, array_ref[, debug_val]) writes text from array ref to file.
# ------------------
sub write_array_to_file {
    my (@input) = @_;

    my $file      = shift @input;
    my $array_ref = shift @input;

    my $old_debug = $debug_val;
    my $maybe_dbg = shift @input;
    if (defined $maybe_dbg) {
        $debug_val = $maybe_dbg;
    }

    SAMBA_pipeline_utilities::debugloc();
    SAMBA_pipeline_utilities::whoami();
    SAMBA_pipeline_utilities::printd(30, "Opening file $file.\n");

    # Open file for writing using a lexical filehandle
    open my $text_fid, '>', $file
      or croak "could not open $file, $!";

    # Sanity check: ensure it's treated as text
    croak "file <$file> not Text\n"
      unless -T $text_fid;

    # Write each line explicitly to this filehandle
    foreach my $line (@{$array_ref}) {
        print {$text_fid} $line
          or croak "ERROR on write to $file: $!";
    }

    close $text_fid
      or croak "ERROR closing $file: $!";

    # restore previous debug value
    $debug_val = $old_debug;

    return 1;
}


#---------------------
sub write_refspace_txt {
#---------------------
    my ($refspace,$refname,$refspace_folder,$split_string,$custom_filename)=@_;
    my $refspace_file;
    my $contents;

    my $array = join("$split_string",($refspace,$refname));

    
    if (defined $custom_filename) {
        $refspace_file = "${refspace_folder}/${custom_filename}";
    } else { 
        $refspace_file = "${refspace_folder}/refspace.txt";
    }
    #my @array = ($array);
    $contents = [$array];
    write_array_to_file($refspace_file,$contents);
    return(0);
}


{
    no warnings 'redefine';

    my $original_system = \&CORE::system;

    sub system {
        my @args = @_;
        my $cmd = @args > 1 ? join(' ', @args) : $args[0];
        $cmd = wrap_in_container($cmd);
        return $original_system->($cmd);
    }
}

1;
