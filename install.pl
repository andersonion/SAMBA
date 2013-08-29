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
#print basename($ENV{SHELL})."\n";
my %opts;
if ( ! getopts('p',\%opts) ) { 
    print("Option error\n");
    exit;
}

my $shell =  basename($ENV{SHELL});
my $wks_home=dirname(abs_path($0));
my $oracle_inst="$wks_home/../oracle"; 
my $oracle_version="11.2";
my $data_home="/Volumes/workstation_data/data";
my $hostname=hostname;
# if allowed to check.
my $name=getpwuid( $< ) ;
my $isadmin=`id | grep -c admin`;chomp($isadmin);
my $isrecon=`id | grep -c recon`;chomp($isrecon);
my $isipl=`id | grep -c admin`;chomp($isipl);

my @alist = split(/\./, $hostname) ;
my $arch=`uname -m`;
chomp($arch);
$hostname=$alist[0];

#check for install.pl in wks_home to make sure we're running in right dir.
# ... later
{ 
    if ( $shell !~ m/bash/x ) {
	print ("ERROR: shell is not bash, other shells un tested.");
	exit(1);
    } elsif(  $shell =~ m/bash/x) {
	print ("Shell check match=bash\n");
	$shell = "bash";
    } elsif ( $shell =~ m/[t]?csh/x) {
	print ("Shell check match=Csh\n");
	$shell = "csh";
    }

}

###
# check for groups
### 
#if ( $name !~ /omega/x ) 
my @groups=qw/ipl/;
if ( $name =~ /pipeliner/x || $isadmin ) {
    push(@groups,'recon');
}
my @g_errors;
for my $group (@groups) {
#	`which dscl `;
    my $group_status=`dscl localhost list ./Local/Default/Groups | grep -c $group`;
    #grep -c $group
#	print("gs=$group_status\n");
    if ( $group_status  =~ m/0/x) { 
	push(@g_errors,"ERROR: need to create the $group group\n");
    } elsif( $group_status =~ m/1/x )  { 
	print("Found required group:$group\t");
    } elsif ( $? == -1 ) {
	push(@g_errors,"ERROR: dscl check failed on group $group.\n");
    }
    $group_status=`id | grep -c $group`; #an is member check.
    if ( $group_status  =~ m/0/x) { 
	push(@g_errors,"ERROR: current user must be part of $group group\n");
	print("... member check FAIL!\n");
    } elsif( $group_status =~ m/1/x )  { 
	print("... member check success!\n");
    } elsif ( $? == -1 ) {
	push(@g_errors,"ERROR: id check failed on group $group.\n");
	print("... member check FAIL!\n");
    }   
}


if ( $#g_errors>=0) { 
    #print(join("\n",@g_errors)."\n");
    print("admin check returned $isadmin\n");
    if ( ! $isadmin) 
    {
	print("Current user must be an admin and part of ipl and recon group.\nOmega should ONLY be part of ipl group.\nPipeliner should be part of ipl and recon group.\n @g_errors");
	exit 1;
    } else { 
	print("Current user must be an admin and part of ipl and recon group.\nOmega should ONLY be part of ipl group.\nPipeliner should be part of ipl and recon group.\n @g_errors");
	print("TODO createm missing groups, add basic memberships\n");
    }
}
###
# put source ${HOME}/.${shell}rc in .${shell}_profile
### 
{
    print("---\n");
    print("Setting source in ${shell}_profile in ${shell}rc...... \n");
    print("---\n");
    my $HOME=$ENV{HOME};
    my @all_lines;
    print("Must run this as user to install to!\n". 
	  "By default that is omega\n".
	  "This only sets up the ${shell} environment!\n");

### open ${shell}_profile to check for source ${shell}rc line. 
    my  $inpath="${HOME}/.${shell}_profile";
    if ( -e $inpath ) { 
	if (open SESAME, $inpath) {
	    @all_lines = <SESAME>;
	    close SESAME;
	    print(" Opened ${shell}_profile\n");
	} else {
	    print STDERR "Unable to open file <$inpath> to read\n";
	    exit (0);
	} 
    }
    my $line_found=0;
    my $outpath="${HOME}/.${shell}_profile";
    my $src_rc="source ${HOME}/.${shell}rc";
    open SESAME_OUT, ">$outpath" or warn "could not open $outpath for writing\n";
    for my $line (@all_lines) {
	if ($line =~ /source.*\.${shell}rc.*/) { # matches source<anthing>.${shell}rc<anything> could be to broad a match
	    $line_found=1;
	}
	print  SESAME_OUT $line;  # write out every line modified or not
    }
    if( $line_found==0){ 
	print ("source ${shell}rc wasnt found inserting.\n");
	print SESAME_OUT $src_rc."\n";
    } else { 
	print("found source $src_rc\n");
    }
    close SESAME_OUT;

###
# check that user ${shell}rc is in place
###
    print("---\n");
    print("Adding lines to ${shell}rc ...... \n");
    print("---\n");
    my @user_shellrc=();
    $inpath="${HOME}/.${shell}rc";
    $outpath=$inpath;

    if ( -e $inpath ) { 
	if (open SESAME, $inpath) {
	    @user_shellrc = <SESAME>;
	    close SESAME;
	    print(" opened user ${shell}rc\n");
	} else {
	    print STDERR "Unable to open file <$inpath> to read\n";
	    exit(0);
	} 
    }
#
# check that our rad env is in the ${shell}rc
    open SESAME_OUT, ">$outpath" or warn "could not open $outpath for writing\n";
    my $src_line       ="source $HOME/.bash_workstation_settings";
    my $src_regex      ="$src_line";
#my $wrk_host        ="export WORKSTATION_HOSTNAME=$hostname";
    my $wrk_home       ="export WORKSTATION_HOME=$wks_home";
    my $wrk_src        ="source \$WORKSTATION_HOME/pipeline_settings/${shell}/${shell}rc_pipeline_setup";
#my $rad_host        ="export RECON_HOSTNAME=$hostname";
    my $rad_home       ="export RADISH_RECON_DIR=$wks_home/recon/legacy";
    my $rad_src        ="source \$WORKSTATION_HOME/pipeline_settings/${shell}/legacy_radish_${shell}rc";
#my $pipe_host        ="export PIPELINE_HOSTNAME=$hostname";
    my $pipe_home      ="export PIPELINE_HOME=$wks_home/";
#my $pipe_src       ="source \$PIPELINE_HOME/pipeline_settings/${shell}/${shell}rc_pipeline_setup";
    my $oracle_lib    ="export DYLD_LIBRARY_PATH=\$DYLD_LIBRARY_PATH:$oracle_inst";
    my $oracle_home   ="export ORACLE_HOME=$oracle_inst";
#my @export_lines;
    my @src_lines;
#push(@export_lines,$wrk_line,$rad_line,$pipe_line);
#push(@src_lines,$wrk_src,$rad_src,$pipe_src);
    my @wrk_lines=($wrk_home,$wrk_src);
    my @rad_lines=($rad_home,$rad_src);
    my @pipe_lines=($pipe_home);#,$pipe_line,$pipe_src);
    my @oracle_lines=($oracle_lib,$oracle_home);
#my $wrk_regex='('.join(')|(',@wrk_lines).')';
#my $rad_regex='('.join(')|(',@rad_lines).')';
#my $pipe_regex='('.join(')|(',@pipe_lines).')';
    my ($src_found,$wrk_found,$rad_found,$pipe_found)=(0,0,0,0);
    for my $line (  @user_shellrc) {
	if ( $line =~ /$src_regex/){ 
	    $src_found=1;
	    print SESAME_OUT $src_line."\n";
	} else { 
	    print SESAME_OUT $line;
	}

#     if ( $line =~ /$wrk_regex/) { 
# 	print("found wrk lines\n");
# 	$wrk_found=1;
#     } elsif ( $line =~ /$rad_regex/) { 
# 	print("found rad lines\n");
# 	$rad_found=1;
#     } elsif ( $line =~ /$pipe_regex/ ) { 
# 	print("found pipe lines\n");
# 	$pipe_found=1;
#     } else { 

#     }
#     print SESAME_OUT $line;
    }
    if( $src_found==0){
	print ("adding src line\n");
	print SESAME_OUT "$src_line\n";
    }
# if( $wrk_found==0 ){ 
#     print ("wrk_lines not found, inserting.\n");
#     print SESAME_OUT join("\n",@wrk_lines)."\n";
# }
# if( $rad_found==0 ){ 
#     print ("rad_lines not found, inserting.\n");
#     print SESAME_OUT join("\n",@rad_lines)."\n";
# }
# if( $pipe_found==0 ){ 
#     print ("pipe_lines not found, inserting.\n");
#     print SESAME_OUT join("\n",@pipe_lines)."\n";
# }
    close SESAME_OUT;
    open SESAME_OUT, ">${HOME}/.bash_workstation_settings" or warn "Couldnt open settings file for writing!";
    print SESAME_OUT "".
	"# \n".
	"# File automatically generated to contain paths by install.pl for worstation_home\n";
    print SESAME_OUT join("\n",@wrk_lines)."\n";
    print SESAME_OUT join("\n",@rad_lines)."\n";
    print SESAME_OUT join("\n",@pipe_lines)."\n";
#    print SESAME_OUT "$oracle_lib\n";
    print SESAME_OUT join("\n",@oracle_lines)."\n";
    close SESAME_OUT;

# do an if mac check
# later...
###
# copy ${shell}_env_to_mac_gui and environment.plist
###

    if( ! -e "${HOME}/.MacOSX/environment.plist" ) { 
	if( ! -d "${HOME}/.MacOSX/" ) { 
	    `mkdir ${HOME}/.MacOSX/`;
	}
	`cp pipeline_settings/mac/environment.plist ${HOME}/.MacOSX/.`; 
	print(" Copied environment plist\n");
    } else { 
	print ("environment.plist already in place\n");
    }

    if( ! -e "${HOME}/.${shell}_env_to_mac_gui" ) {
	`cp pipeline_settings/${shell}/${shell}_env_to_mac_gui ${HOME}/.${shell}_env_to_mac_gui`;
	print (" Copied ${shell} to gui stub\n");
    }


###
# insert home dir into environment.plist
###
    print("---\n");
    print("Inserting home dir in to ~/.MacOSX/environment.plist ...... \n");
    print("---\n");
    $inpath="${HOME}/.MacOSX/environment.plist";
    $outpath=$inpath."out";
    if (open SESAME, $inpath) {
	@all_lines = <SESAME>;
	close SESAME;
	print(" opened env_plist \n");
    } else {
	print STDERR "Unable to open file <$inpath> to read\n";
	exit (0);
    } 

    open SESAME_OUT, ">$outpath" or warn "could not open $outpath for writing\n";
    for my $line (@all_lines) {
	if ( $line =~ /<string>.*(.${shell}_env_to_mac_gui)<\/string>/x ) { 
	    my $envstring="  <string>${HOME}/.${shell}_env_to_mac_gui<\/string>\n";
	    #  <string>code_location/bash_env_to_mac_gui</string>
	    print(" found ${shell}_envline: \n$line replacing with:\n$envstring\n");
	    print(SESAME_OUT "$envstring");
	} else { 
	    print( $line );
	    print SESAME_OUT $line;
	}
    }
    print("moving $outpath to $inpath\n");
    `mv $outpath $inpath`;
###
# add fsl and ants
###
    if ( $isrecon )# $name !~ /omega/x
    {
	if ( ! -e "../usr/bin/ANTS" ) 
	{
	    print("---\n");
	    print("Extracting ANTs ...... \n");
	    print("---\n");
	    my $scp_cmd;
	    # find dmg on syros
	    my $ants_dmg=`ssh syros ls -tr /Volumes/xsyros/Software/SegmentationSoftware/*dmg| grep ANT |tail -n 1`;
	    chomp($ants_dmg);
	    $ants_dmg=basename($ants_dmg);
	    #scp dmg
	    $scp_cmd="scp syros:/Volumes/xsyros/Software/SegmentationSoftware/$ants_dmg ../$ants_dmg";
	    if ( ! -f "../$ants_dmg" ) 
	    { 
		print ("$scp_cmd\n");
		`$scp_cmd`;
	    } else { 
		print("found dmg: $ants_dmg found\n");
	    }
	    #mount dmg
	    my $hdi_cmd="hdiutil attach ../$ants_dmg";
	    print("$hdi_cmd\n");
	    `$hdi_cmd`;
	    #find pkg in dmg volume
	    my $ants_pkg=`ls -d /Volumes/ANT*/*pkg`;
	    chomp($ants_pkg);
	    # install pkg
	    my $inst_cmd="sudo installer -pkg $ants_pkg -target /$wks_home/../";
	    print("$inst_cmd\n");
	    `$inst_cmd`;
	    #unmount dmg
	    $hdi_cmd="hdiutil detach $ants_pkg/../";
	    print("$hdi_cmd\n");
	    `$hdi_cmd`;
	}
	if ( ! -d "../fsl" ) 
	{
	    print("---\n");
	    print("Running FSL installer ...... \n");
	    print("---\n");
	    #get fsl script?
	    my $fsl_inst_cmd="./fslinstaller.py -d $wks_home/../";
	    open my $cmd_fh, "$fsl_inst_cmd |";   # <---  | at end means to make command 
	    #         output available to the handle
	    while (<$cmd_fh>) 
	    {
		print "A line of output from the command is: $_";
	    }
	    close $cmd_fh;
#    `$fsl_inst_cmd`;
	    
	}
	my $OS='mac';
	my $base_path="/Volumes/xsyros/software/oracle/";
	if ( ! -d "$oracle_inst" ) 
	{
	    print("---\n");
	    print("Extracting Oracle ...... \n");
	    print("---\n");
	    my @oracle_parts=qw(basic sqlplus sdk);
	    my $scp_cmd;
	    # find dmg on syros
	    if ( ! -d "../zip" ) 
	    {
		`mkdir ../zip`;
	    }
	    for my $part (@oracle_parts)  { 
		my $ls_cmd="ssh syros ls ${base_path}/*${OS}*${arch}/*client*$part*${oracle_version}*${OS}*${arch}*.zip";
		my $oracle_zip=`$ls_cmd` or print("cmd_fail $ls_cmd\n");
		chomp($oracle_zip);
		#scp dmg
		$scp_cmd="scp syros:$oracle_zip ../zip/".basename($oracle_zip);
		if ( ! -f "../zip".basename($oracle_zip) ) 
		{ 
		    print ("$scp_cmd\n");
		    `$scp_cmd`;
		} else { 
		    print("found zip: ".basename($oracle_zip)." found\n");
		}
		# 
		chdir "../zip/";
		my $cmd="unzip ".basename($oracle_zip)." -d $oracle_inst";
		open my $cmd_fh, "$cmd |";   # <---  | at end means to make command 
		#         output available to the handle
		while (<$cmd_fh>) 
		{
		    print "A line of output from the command is: $_";
		}
		chdir $wks_home;
	    }
	    `mv $oracle_inst/*/* $oracle_inst`;
	    
	    if ( 1 ) { 
		print("creating oracle_cpaninst.bash for root to run\n");
		my $outpath="$wks_home/oracle_cpaninst.bash";
		open SESAME_OUT, ">$outpath"; 
		print SESAME_OUT "#!/bin/bash\n".
		    "declare -x ORACLE_HOME=$oracle_inst\n".
		    "declare -x DYLD_LIBRARY_PATH=$oracle_inst\n".
		    "cpan DBI\n".
		    "cpan DBD::Oracle\n";
		close SESAME_OUT;
		
		my $cmd="sudo bash $outpath && unlink $outpath";
		open my $cmd_fh, "$cmd |";   # <---  | at end means to make command 
		#         output available to the handle
		while (<$cmd_fh>) 
		{
		    print "$_";
		}
	    }
	}
	#--with-oracle-lib-path
	chdir $wks_home;
# % whence perl  # or whatever command returns the version of perl first in your path.   
#                 # Verify this is the version you intent to install DBD::Oracle to  
#  % gzip -dc DBD-Oracle-1.40.tar.gz | tar xf - 
#  % cd DBD-Oracle-1.17 
#  % perl Makefile.PL -V 10.2 
#  % make 
#  % make install 
	
	
    }
#    exit();
    {
	print("---\n");
	print("Inserting FSL config to ${shell}_profile ...... \n");
	print("---\n");
	my $HOME=$ENV{HOME};
	my @all_lines;
	print("Must run this as user to install to!\n". 
	      "By default that is omega\n".
	      "This only sets up the ${shell} environment!\n");
	
### open ${shell}_profile to check for source ${shell}rc line. 
	my  $inpath="${HOME}/.${shell}_profile";
	if ( -e $inpath ) { 
	    if (open SESAME, $inpath) {
		@all_lines = <SESAME>;
		close SESAME;
		print(" Opened ${shell}_profile\n");
	    } else {
		print STDERR "Unable to open file <$inpath> to read\n";
		exit(0);
	    } 
	}
	
	my $line_found=0;
	my $outpath="${HOME}/.${shell}_profile";
	my $fsl_dir="FSLDIR=$wks_home/../fsl";
	open SESAME_OUT, ">$outpath" or warn "could not open $outpath for writing\n";
	for my $line (@all_lines) {
	    if ($line =~ /FSLDIR=.*/) { # matches source<anthing>.${shell}rc<anything> could be to broad a match
		$line_found=1;
		$line="$fsl_dir\n";
	    }
	    print  SESAME_OUT $line;  # write out every line modified or not
	}
	if( $line_found==0){ 
	    print ("FSLDIR setting not found, fsl did not install correctly, Trying to dump fsl setup into bash_profile\n"); 
# try running this again. If that fails try running the fsl installer separetly. \n");
	    my $line='# FSL Setup'."\n".
		"FSLDIR=$wks_home/../fsl"."\n".
		'PATH=${FSLDIR}/bin:${PATH}'."\n".
		'export FSLDIR PATH'."\n".
		'. ${FSLDIR}/etc/fslconf/fsl.sh'."\n";
	    print SESAME_OUT $line;
	}
	close SESAME_OUT;
    }

###
# update engine_something_pipeline_dependencis.
###
###
# copy engine_hostname_dependencis to backup and 
# cp engine_generic_dependincies to engine_hostname_depenendinceis and 
# link it to pipeline_dependencies and recon_dependencies.
###

    if ( $isrecon ) #$name !~ /omega/x
    {
	print("---\n");
	print("Setting engine dependencies ...... \n");
	print("---\n");
	print("setting engine dependencies\n");
	my $dep_file="${wks_home}/pipeline_settings/engine_deps/engine_${hostname}_dependencies";
	my $default_file="${wks_home}/pipeline_settings/engine_deps/engine_generic_dependencies";
	if( -e $dep_file && ! -e "${dep_file}.bak") { 
	    `mv $dep_file ${dep_file}.bak`; 
	    `cp $default_file $dep_file`;
	    print(" Backed up previous settings to ${dep_file}.bak\n");
	    print(" DONT FORGET TO REMOVE IF THIS WORKED\n");
	} elsif ( -e "${dep_file}.bak") {  #-e $dep_file && 
	    print( "old backup ${dep_file}.bak was not cleared\n");
#    exit(0);
	} else { 
	    print("Copying $default_file to $dep_file\n");
	    `cp $default_file $dep_file`;
	}
# sub hostname for hostname_radish  and hostname_pipeline
	my( $rdep, $pdep);
	($rdep = $dep_file ) =~ s/$hostname/${hostname}_radish/gx;
	($pdep = $dep_file )=~ s/$hostname/${hostname}_pipeline/gx;
	for my $file ($rdep, $pdep) {
#	    if( ! -e  $file) {
	    
	    chdir dirname($dep_file);
	    my $ln_cmd="ln -fs ".basename($dep_file)." ".basename($file);
	    `$ln_cmd`;
	    chdir $wks_home;
		#`ln -s $dep_file $pdep`;
		print ("made link for legacy code\n\t$file");
#	    } else { 
#		print("  *dependency links exist!\n");
#	    }
	}
###
# fix setting 
	$inpath="$dep_file";
	$outpath=$inpath."out";
	if (open SESAME, $inpath) {
	    @all_lines = <SESAME>;
	    close SESAME;
	    print(" opened dependency \n");
	} else {
	    print STDERR "Unable to open file <$inpath> to read\n";
	    exit(0);
	} 

	my @outcommentary=();
	my $string;
	open SESAME_OUT, ">$outpath" or warn "could not open $outpath for writing\n";
	for my $line (@all_lines) {
# # warkstation workflow settings file
# # format like headfile
	    if ( $line =~ /^engine=hostname/x ) { 
		$string="engine=$hostname";
# engine=hostname
# engine_endian=little
# ###
# # data_locations
# engine_work_directory=/Volumes/enginespace
	    } elsif ($line =~ /^engine_work_directory=/x ) {
		$string="engine_work_directory=/${hostname}space";
# engine_recongui_paramfile_directory=/wks_home/dir_param_files
	    } elsif ($line =~ /^engine_recongui_paramfile_directory=/x ) {
		$string="engine_recongui_paramfile_directory=$wks_home/dir_param_files";
		
# engine_recongui_menu_path=/wks_home/pipe_settings/recon_menu.txt
	    } elsif ($line =~ /^engine_recongui_menu_path=/x ) {
		$string="engine_recongui_menu_path=$wks_home/pipeline_settings/recon_menu.txt";
		
# engine_archive_tag_directory=/engine_work_directory/Archive_Tags
	    } elsif ($line =~ /^engine_archive_tag_directory=/x ) {
		$string="engine_archive_tag_directory=/Volumes/${hostname}space/Archive_Tags";
# engine_waxholm_canonical_images_dir=/wks_home/whs_references/whs_canonical_images/alx_can_101103
	    } elsif ($line =~ /^engine_waxholm_canonical_images_dir=/x ) {
		$string="engine_waxholm_canonical_images_dir=$data_home/atlas/whs/whs_canonical_images/alx_can_101103";
# engine_waxholm_labels_dir=/wks_home/whs_references/whs_labels/canon_labels_101103
	    } elsif ($line =~ /^engine_waxholm_labels_dir=/x ) {
		$string="engine_waxholm_labels_dir=$data_home/atlas/whs/whs_labels/cannon_labels_101103";
# engine_app_dti_recon_param_dir=/wks_home/dti_references
	    } elsif ($line =~ /^engine_app_dti_recon_param_dir=/x ) {
		$string="engine_app_dti_recon_param_dir=$wks_home/pipeline_settings/tensor";
# #
		
# ###
# # program names
# engine_3dpr_fast_prog_name=nuray05_v5_toff
# engine_3dgrid_prog_name=grid3d01
# engine_3dthreadgrid_prog_name=grid_thread
# #
		
# ###
# # program locations
# engine_radish_bin_directory=/wks_home/recon/legacy/modules/bin_macINTEL
	    } elsif ($line =~ /^engine_radish_bin_directory=/x ) {
		$string="engine_radish_bin_directory=$wks_home/bin";#recon/legacy/modules/_mac_${arch}
# engine_radish_contributed_bin_directory=/wks_home/recon/legacy/modules/contributed/bin_macINTEL 
	    } elsif ($line =~ /^engine_radish_contributed_bin_directory=/x ) {
		$string="engine_radish_contributed_bin_directory=$wks_home/recon/legacy/modules/contributed/bin_mac_${arch}";
# engine_app_matlab=/usr/bin/matlab
 	    } elsif ($line =~ /^engine_app_matlab=/x ) { 
 		$string="engine_app_matlab=/usr/bin/matlab";# -nosplash -nodisplay -nodesktop ";
# engine_app_matlab_opts=-nosplash -nodisplay -nodesktop
 	    } elsif ($line =~ /^engine_app_matlab_opts=/x ) { 
 		$string="engine_app_matlab_opts=-nosplash -nodisplay -nodesktop";
# engine_app_ants_dir=/Applications/SegmentationSoftware/ANTS/
	    } elsif ($line =~ /^engine_app_ants_dir=/x ) { 
		$string="engine_app_ants_dir=/$wks_home/../usr/bin/";
# engine_app_fsl_dir=/Applications/SegmentationSoftware/fsl/bin
	    } elsif ($line =~ /^engine_app_fsl_dir=/x ) {
		$string="engine_app_fsl_dir=$wks_home/../fsl/bin";
# engine_app_dti_recon=/Applications/Diffusion\ Toolkit.app/Contents/MacOS/dti_recon
# engine_app_dti_tracker=/Applications/Diffusion\ Toolkit.app/Contents/MacOS/dti_tracker
# engine_app_dti_spline_filter=/Applications/Diffusion\ Toolkit.app/Contents/MacOS/spline_filter
# ###
	    } else { 
		$string=$line;
		chomp($string);
	    }
	    my @temp=split(/\=/,$string);
	    while ( $#temp < 1 ) {
		push( @temp, ' ');
	    }
	    if ( -e $temp[1]  && $string !~ /^#/ ) {
		push (@outcommentary,"$string <- $line");
	    } else {
		if ( $string !~ /(^#)|(\s)/  ){
#	    print("$temp[0]:::$temp[1]\n"); 
		    push (@outcommentary,"WARNING: newlocation $temp[1] did not exist yet!"); 
		}
	    }
	    print(SESAME_OUT "$string\n");
	}
	print(join("\n",@outcommentary));
	print("moving $outpath to $inpath\n");
	`mv $outpath $inpath`;
#`mv  ${dep_file}.bak $dep_file`
    }
}

###
# get legacy tar files
###
print("---\n");
print("Extracting Tar's ...... \n");
print("---\n");
my $os="$^O";
my @legacy_tars;
my @output_dirs;
if ( $isrecon ) {
push(@legacy_tars, "radish_${os}_${arch}.tgz");
push(@output_dirs, "$wks_home/bin");
push(@legacy_tars, "t2w_slg_dir.tgz");
push(@output_dirs, "$wks_home/recon/legacy/");
push(@legacy_tars, "contrib_active.tgz");
push(@output_dirs, "$wks_home/recon/legacy/");
push(@legacy_tars, "contributed.tgz");
push(@output_dirs, "$wks_home/recon/legacy/");
#push(@legacy_tars, "DCE.tgz");
#push(@output_dirs, "$wks_home/recon/");
push(@legacy_tars, "DCE_test_data.tgz");
push(@output_dirs, "$wks_home/recon/");
push(@legacy_tars, "DCE_examples.tgz");
push(@output_dirs, "$wks_home/recon/DCE");
}
my $tardir="$wks_home/../tar/"; # modules/
if ( ! -d $tardir ) { 
    `mkdir -p $tardir`;
}
for( my $idx=0;$idx<=$#legacy_tars;$idx++) 
{
    my $tarname=$legacy_tars[$idx];
    print("finding tar:$tarname\n");
###
# fetch legacy binaries!
###
# should store tars of binaries and "frozen" code someplace and dump it to the recon engine when we copy this.
#scp binaries to ../tar/
    my %files;
    find( sub { ${files{$File::Find::name}} = 1 if ($_ =~  m/^$tarname$/x ); },$tardir);
    my @fnames=sort(keys(%files));    
    
    my $tarfile;
    if ( defined( $fnames[0]) ) { 
	$tarfile="$fnames[0]";
    } else { 
	print("tar $tarname not found locally\n");# $tardir\n");
	$tarfile="$tardir/$tarname";
    }
    ### check for functional host here, if not function try again. 
    my $hostname="delos";
    
    if ( ! -f "$tarfile")
    {
	my $ssh_find="ssh $hostname find $tardir -iname \"*.tgz\" | grep $tarname";
	print("finding tgz path with $ssh_find\n");
	$tarfile=`$ssh_find`;
	chomp($tarfile);
	my $tar_loc=dirname($tarfile); #$tardir=
	if ( ! -d $tar_loc )
	{
	    my $mkdir_cmd="mkdir -p $tar_loc";
	    print("$mkdir_cmd\n");
	    `$mkdir_cmd`;
	} else { 
#	    print("found $tar_loc for scp, ");
	}
#	exit();
	if ( $tarfile =~ /.*$tarname.*/x) 
	{
	    my $scp_cmd="scp delos:$tarfile $tarfile";
	    print("\ttgz $tarname, attempting retrieval via $scp_cmd\n");# $scp_cmd\n");
	    `$scp_cmd`;
	}
    }
    find( sub { ${files{$File::Find::name}} = 1 if ($_ =~  m/^$tarname$/x ); },$tardir);
    @fnames=sort(keys(%files));    
    if ( defined( $fnames[0]) ) { 
	$tarfile="$fnames[0]";
    } else { 
	print("tar $tarname not found locally\n");# $tardir\n");
	$tarfile="$tardir/$tarname";
    }
    if ( -f "$tarfile" ) 
    { 
	chdir "$output_dirs[$idx]";
	my $tar_cmd="tar -xvf $tarfile 2>&1";# | cut -d " " -f3-";
	#print("Attempting tar cmd $tar_cmd\n");
	my $output=qx($tar_cmd);
	open SESAME_OUT, '>', "bin_uninstall.sh" or warn "couldnt open bin_uninstall.sh:$!\n";
	print(SESAME_OUT "#bin uninstall generated from installer.\n");
	print("dumping tar: $tarfile\n");
	for my $line (split /[\r\n]+/, $output) {
	    ## Regular expression magic to grab what you want
	    $line =~ /x(.*)/x;
	    my $out_line="$1";
	    print(SESAME_OUT "rm -i $out_line\n");
	    #print SESAME_OUT $output;
	}
	
	close SESAME_OUT;
	chdir $wks_home;
    } else { 
	print("tar os/arch:$tarfile\n");
	sleep(4);
    }
}
#### 
# make legacy links!
###
# ln with absolute links for source (via wks_home) and relative links for dest
#for file in `ls ../../pipeline_settings/engine_deps/* ../../pipeline_settings/scanner_deps/*
print("---\n");
print("Making legacy links ...... \n");
print("---\n");
my @dependency_paths;
my $ln_cmd;
my $ln_source;
my $ln_dest;
my $infile; 
my $outname;
my $in_dir="$wks_home/";
push(@dependency_paths,glob("$wks_home/pipeline_settings/engine_deps/*${hostname}*"));
push(@dependency_paths,glob("$wks_home/pipeline_settings/scanner_deps/*"));
# link dependency files to "recon_home" dir 
if ( $isrecon) { 
for $infile ( @dependency_paths ) 
{
    $outname = basename($infile);
    $ln_source=$infile;
    $ln_dest="recon/legacy/$outname";
    if ( -r $ln_dest ) { 
	`unlink $ln_dest`;
    }
    $ln_cmd="ln -sf $ln_source $ln_dest";
    #print ("$ln_cmd\n");
    `$ln_cmd`;
}
}
open SESAME_OUT, '>>', "bin/bin_uninstall.sh" or warn "couldnt open bin_uninstall.sh:$!\n";
# 	print(SESAME_OUT "#bin uninstall generated from installer.\n");
# 	print("dumping output of tar$tarfile to $output_dirs[$idx]\n");
# 	for my $line (split /[\r\n]+/, $output) {
# 	    ## Regular expression magic to grab what you want
# 	    $line =~ /x(.*)/x;
# 	    my $out_line="$1";
# 	    print(SESAME_OUT "rm -i $out_line\n");
# 	    #print SESAME_OUT $output;
# 	}
	
# 	close SESAME_OUT;
### 
# link perlexecs from pipeline_utilities and other  to bin
###
my @perl_execs=();
if ( $isrecon ) { 
    push(@perl_execs,qw(agi_recon agi_reform agi_scale_histo dumpAgilentHeader1 dumpHeader.pl rollerRAW:roller_radish lxrestack:restack_radish validate_headfile_for_db.pl:validate_header puller.pl puller_simple.pl radish.pl display_bruker_header.perl radish_agilentextract.pl display_agilent_header.perl sigextract_series_to_images.pl k_from_rp.perl:kimages retrieve_archive_dir.perl:imgs_from_archive pinwheel_combine.pl:pinwheel keyhole_3drad_KH20_replacer:keyreplacer re-rp.pl main_tensor.pl:tensor_create recon_group.perl group_recon_scale_gui.perl:radish_scale_bunch radish_brukerextract/main.perl:brukerextract main_seg_pipe_mc.pl:seg_pipe_mc archiveme_now.perl:archiveme t2w_pipe_slg.perl:fic mri_calc reform_group.perl reformer_radish.perl getbruker.bash));
}
#dumpEXGE12xheader:header
for $infile ( @perl_execs )
{
    if ($infile =~ /:/x ) 
    {
	my @temp=split(':',$infile);
	$infile=$temp[0];
	$outname=$temp[1];
    } else { 
       $outname = basename($infile,qw(.pl .perl));
    }
    my %files;
    print("Finding $infile in $in_dir ...");
    find( sub { ${files{$File::Find::name}} = 1 if ($_ =~  m/^$infile$/x ) ; },"$in_dir");
    my @temp=sort(keys(%files));
    my @fnames;
    # clean out anything with junk in path
    #$wks_home/shared/
    if(defined ( $#temp ) ) { 
	#print ( "ERROR: find function found too many files (@fnames) \n");
	my $found = 0;
        foreach (@temp)
	{
	    if ( $_ !~ /.*(:?\/_junk|\/bin).*/x ) 
	    {
		if ( ! -d $_ ) 
		{
		    $found=$found+1;
		    push( @fnames,$_);
		}
	    }
	    
	}
	if ( $found)
	{
	    print("  found! ...");
	} else {
	    print("  NOT_FOUND.");
	}
    }
    if ( defined ( $fnames[0]) && $#fnames<1) 
    { 
	$ln_source="$fnames[0]";#$in_dir/$infile";
	$ln_dest="bin/$outname";
	if ( -l $ln_dest ) { 
	    `unlink $ln_dest`;
	}
	if ( ! -e $ln_dest )
	{
	    $ln_cmd="ln -sf $ln_source $ln_dest";
	    #print ("$ln_cmd\n");
	    `$ln_cmd`;
	    print(SESAME_OUT "unlink ".basename($ln_dest)."\n");	
	    `chmod a+x bin/$outname`;
	    `chmod a+x $ln_source`;
	    print( " linked.\n");
	} else { 
	    print (" NOT A LINK, NOT OVERWRITING!\n");
	}
    } else {
	print (" NOT_LINKED!\n");
#	print ("$infile  in $in_dir\n");
    }
}
close SESAME_OUT;
### some legacy linking
# Legacy Link puller
if ( $isrecon ) { 
$infile="$wks_home/shared/radish_puller";
{
    $ln_source="$infile";
    $ln_dest="$wks_home/recon/legacy/dir_puller";
    if ( -r $ln_dest ) { 
	`unlink $ln_dest`;
    }    
    $ln_cmd="ln -sf $ln_source $ln_dest";
    #print ("$ln_cmd\n");
    `$ln_cmd`;
}
# legacy link startup
{
    $ln_source="$wks_home/shared/pipeline_utilities/startup.m";
    $ln_dest="$wks_home/recon/legacy/radish_core/startup.m";
    if ( -r $ln_dest ) { 
	`unlink $ln_dest`;
    }    
    $ln_cmd="ln -sf $ln_source $ln_dest";
    #print ("$ln_cmd\n");
    `$ln_cmd`;
}
# legacy link perl
{
    if ( ! -e "/usr/local/pipeline-link/perl" )
    {
	`sudo ln -s /usr/bin/perl /usr/local/pipeline-link/perl`;
    }
}

### 
# some more linking
###
$infile="$wks_home/analysis/james_imagejmacros";
{
    $ln_source="$infile";
    $ln_dest="/Applications/ImageJ/plugins/000_james_imagejmacros";
    if ( -r $ln_dest ) { 
	`unlink $ln_dest`;
    }    
    $ln_cmd="ln -sf $ln_source $ln_dest";
    #print ("$ln_cmd\n");
    `$ln_cmd`;
}
}
###
# permisison cleanup
###
if ( $isadmin && defined $opts{p}) { 
    `sudo chown -R omega:ipl /Volumes/${hostname}space/`;
`sudo find /Volumes/${hostname}space/ -not -type d -print -exec chmod a-x {} \\; `;
`sudo chmod -R gu+rws /Volumes/${hostname}space/`;
} else {
    print("# Space drive permission commands not run because you are not an admin.\n");
print("# Thsese should be run at once to make sure archives do not generate permission errors\n");
print("sudo chown -R omega:ipl /Volumes/${hostname}space/\n");
print("sudo find /Volumes/${hostname}space/ -x -not -type d -print -exec chmod a-x {} \\; \n");
print("sudo chmod -R gu+rws /Volumes/${hostname}space/\n");


}
if (  $isrecon )
{ #$name !~ /omega/x 
    `chgrp -R recon $wks_home`; # there doesnt have to be an ipl group
    `chmod -R ug+s $wks_home`;
    `chmod a+rwx $wks_home/dir_param_files`;
#`chmod ug+s $wks_home/dir_param_files`;
    `chgrp ipl $wks_home/pipeline_settings/recon_menu.txt`;
    `chgrp -R ipl $wks_home/dir_param_files`;
#`chgrp $wks_home/pipeline_settings/recon_menu.txt`;
#`find . -iname "*.pl" -exec chmod a+x {} \;` # hopefully this is unnecessar and is handled by the perlexecs linking to bin section above. 
} else {
    print("permissions not altered!\n only recon users can alter permissions. If install has already been run by an admin this is not an issue!\n");
}
print("use source ~/.bashrc to enable settings now, otherwise quit terminal or restart computer\n");


