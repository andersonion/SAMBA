#!/usr/bin/env perl
#
# take a samba package and make it arhiveable....
# that is create 4x amend archives for the original diffusion archive
# labels, turn to match the input orientation 
#         clean up labels organzation in case it is out of spec
# transforms, notate the working orientation( in future add the original -> working transform)
# mask, capture the mask to be used in working orientation
# nhdr data, create "proper" headers to load RAS in slicer
# 
# need to create nhdr files for "good" enough inputs
#
# Will have to track the source data
# we need to know what engine to send data to.

# specimen and MDT archiving are slightly different.
# speciemn are just amending something that exists
# MDT archives dont have an existing "thing" it would be great if we could mark them derrived of all the used input runnos.
# have to check DB constraints.
# further, we dont know which specmen to use, we'll just use the first cronologically
# the group of us said use the first runno as well, but I like that significantly less. 
# Gonna use MDT_arbitraryname, with content of arbitraryname.(nii(.gz)?|.nhdr+.raw(.gz)?|nrrd) etc.
# Its samba data packagers job to handle that anyway. 
# It would be good if we were archive aware and checked for existing names.
#   -Also want a "rename" mdt function that tracked it down in a set of packages and renaamed transforms appropriately.
#
# Seems like we wanna create parallel structure for thearchiving...
# measure space may be a factor in handling here, so we wanna force pre_rigid_native_space and die if not.(give unimplemented warning)



use strict;
use warnings;
use Carp qw(carp croak cluck confess);

use Cwd qw(abs_path);
use File::Basename;

BEGIN {
    # we could import radish_perl_lib direct to an array, however that complicates the if def checking.
    my @env_vars=qw(RADISH_PERL_LIB BIGGUS_DISKUS WORKSTATION_DATA WORKSTATION_HOME);
    my @errors;
    use Env @env_vars;
    foreach (@env_vars ) {
	push(@errors,"ENV missing: $_") if (! defined(eval("\$$_")) );
    }
    die "Setup incomplete:\n\t".join("\n\t",@errors)."\n  quitting.\n" if @errors;
}
use lib split(':',$RADISH_PERL_LIB);
# my absolute fav civm_simple_util components.
use civm_simple_util qw(activity_log printd $debug_val);
# On the fence about including pipe utils every time
use pipeline_utilities;
# pipeline_utilities uses GOODEXIT and BADEXIT, but it doesnt choose for you which you want. 
$GOODEXIT = 0;
$BADEXIT  = 1;
# END BOILER PLATE
use Headfile;
use civm_simple_util qw(activity_log can_dump load_file_to_array write_array_to_file find_file_by_pattern is_writable round printd whoami whowasi debugloc sleep_with_countdown $debug_val $debug_locator);
my $can_dump = can_dump();

use lib dirname(abs_path($0));
#use SAMBA_global_variables;
use SAMBA_structure;

#module load slurm;
# test for slurm?
main(@ARGV);
exit 0;


sub main {
    # Prepare's one samba work folder for archive 
    # (ON THE SAME DISK) 
    # uses samba_data_packager to arrange data
    # then does hard linkity and convert to data as archived.
    # Lets put our packaged data into -results/paks
    # Then we'll put our archival bits into -results/amend_archive
    # What does this script need to know to do its job?
    # Samba inputs folder maybe?
    # Samba startup headfile maybe?
    # NO NO NO, Take the results(or in progress maybe) headfile ONLY! 
    # If strange things occured like, we ran over the same directory multiple times THATS ON THEM.
    # 
    #Kinda Screaming for a samba::datastructure
    
    my $opts={};
    # Options of the data_packager, some of which we'll need to pass in.
    ${$opts->{"output_base=s"}}="";
    ${$opts->{"hf_path=s"}}="";
    ${$opts->{"mdtname=s"}}="";
    # mdtdir prefixes for the mdt dir.
    ${$opts->{"mdtdir_prefix=s"}}="MDT_";
    ${$opts->{"mdt_out_path=s"}}="";
    # this disables that behavior, alternatively you could specify --mdtdir_prefix=""
    ${$opts->{"disable_mdtdir_prefix"}}=0;
    ${$opts->{"template_predictor=s"}}="";
    ${$opts->{"label_atlas_nickname=s"}}="";

    ${$opts->{"rsync_location=s"}}="";
    ${$opts->{"instant_feedback!"}}=1;
    
    
    # Options of the data_packager we first thought of... check vs list above, some of which we'll need to pass in.
    #${$opts->{"mdt_iterations:i"}}=0;
    #${$opts->{"link_individuals!"}}=1;
    #${$opts->{"link_images!"}}=1;
    #${$opts->{"template_predictor=s"}}="";
    #${$opts->{"label_atlas_nickname=s"}}="";
    #${$opts->{"rsync_location=s"}}="";
    # Alternative orientation to archive(as opposed to just like previously archived data)
    ${$opts->{"orientation=s"}}="";
    # Shall we create nhdr files for loading the data in RAS orientation?
    # This may be overly abitious, but we've got the idea
    ${$opts->{"create_nhdr!"}}=1;
    # Maybe we'll allow people to do the nasty thing of making a redundant archive.
    #${$opts->{"UgLyReDUNdaNTarCHIvE!"}}=0;
    $opts=auto_opt($opts,\@ARGV);
    
    ###
    # Figure out implied things given the headfile.
    ###
    my @input_errors;
    my $v_ok;
    my $hf=new Headfile ('ro', ${$opts->{"hf_path"}});
    $hf->check() or push(@input_errors,"Unable to open ${$opts->{hf_path}}\n");
    $hf->read_headfile or push(@input_errors,"Unable to read ${$opts->{hf_path}}\n");
    ($v_ok,my $main_results)=$hf->get_value_check("results_dir");

    #die("v_ok:$v_ok, ($main_results)\n");
    if ( ! $v_ok ) { 
	printd(5,"WARNING: Input headfiles not well supported\n");

	require SAMBA_global_variables;
	my @unused_vars=SAMBA_global_variables::populate($hf);
	my @individuals=SAMBA_global_variables::all_runnos();
	my $pc="CODE_NOT_FOUND";
	$pc=${SAMBA_global_variables::project_name} or push(@input_errors,'Global project_name not found');
	my $ran="RIGID_ATLAS_NOT_FOUND";
	$ran=${SAMBA_global_variables::rigid_atlas_name} or push(@input_errors,'Global rigid_atlas_name not found');
	my $opt_s="OPTIONAL_SUFFIX_NOT_FOUND";
	$opt_s=${SAMBA_global_variables::optional_suffix} or push(@input_errors,'Global optional_suffix not found');
	my $mdir=SAMBA_structure::main_dir($pc, scalar(@individuals),$ran,$opt_s);
	
	my $r_hfp=File::Spec->catfile($ENV{"BIGGUS_DISKUS"},$mdir."-results","$mdir.headfile");
	$hf=new Headfile ('ro', $r_hfp );
	$hf->check() or push(@input_errors,"Unable to open ${$opts->{hf_path}}\n");
	$hf->read_headfile or push(@input_errors,"Unable to read ${$opts->{hf_path}}\n");
	($v_ok,$main_results)=$hf->get_value_check("results_dir");
    }
    push(@input_errors,"results_dir missing in headfile, Please use SAMBA results headfile (internal checkpoint headfile may also work).") if ! $v_ok;
    
    # from here need mdtname, samba pak dir, archive dir

    # Set the samba pak,archivable dirs
    my $paks;
    my $archivable;
    
    
    push(@input_errors,"mdtname input option required") if ${$opts->{"mdtname"}} eq "";
    
    #if("STRING"}} ne "" ) { } 
    #if( ${$opts->{"FLAG"}} ) { }
    
    if ( scalar(@input_errors)>0 ){
	die join('',@input_errors)."\n";
    }
    $paks=File::Spec->catdir($main_results,"paks");
    $archivable=File::Spec->catdir($main_results,"archivable");
    

    my $cmd=sprintf("SAMBA_data_packager --mdtname=\"%s\" --hf_path=\"%s\" --output_base=\"%s\"",
		    ${$opts->{"mdtname"}} ,
		    ${$opts->{"hf_path"}} ,
		    $paks
	);
    
    if( ${$opts->{"instant_feedback"}} ){
	Data::Dump::dump($opts) if can_dump();
	#$hf->print();
	printf("will build packages into: $paks\n"
	       ."archive data assebeled at: $archivable\n");
	print($cmd."\n");
	
    }
}
