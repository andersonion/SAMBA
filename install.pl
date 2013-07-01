#!/usr/bin/perl
# simple installer to get shell settings right currently only works for bash shell.
#
# copies and edits the environment.plist from pipeline_settings/mac to ~/.MacOSX/environment.plist
# that plist calls on .bash_env_to_mac_gui run .bash_profile,
# it makes sure .bash_profile has at least one line, source .bashrc
# adds a source .bash_workstation_settings file to user's .bashrc file
# adds several symbolic links to support the legacy radish code

use strict;
use warnings;
use ENV;
use File::Basename;
use Cwd 'abs_path';
use Sys::Hostname;
#print basename($ENV{SHELL})."\n";

my $shell =  basename($ENV{SHELL});
my $wks_home=dirname(abs_path($0));
my $data_home="/Volumes/workstation_data/data";
my $hostname=hostname;
# if allowed to check.
my $name=getpwuid( $< ) ;
my @alist = split(/\./, $hostname) ;
my $arch=`uname -p`;
chomp($arch);
$hostname=$alist[0];

#check for install.pl in wks_home to make sure we're running in right dir.
# ... later
{ 
    if ( $shell !~ m/bash/x ) {
	print ("ERROR: shell is not bash, other shells un tested.");
	return(1);
    } elsif(  $shell =~ m/bash/x) {
	print ("bash match\n");
	$shell = "bash";
    } elsif ( $shell =~ m/[t]?csh/x) {
	print ("Csh match\n");
	$shell = "csh";
    }

}
###
# put source ${HOME}/.${shell}rc in .${shell}_profile
### 

{
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
	    return (0);
	} 
    }

    my $line_found=0;
    my $outpath="${HOME}/.${shell}_profile";
    my $src_rc="source ${HOME}/.${shell}rc";
    open SESAME_OUT, ">$outpath" or die "could not open $outpath for writing\n";
    foreach my $line (@all_lines) {
	if ($line =~ /source.*\.${shell}rc.*/) { # matches source<anthing>.${shell}rc<anything> could be to broad a match
	    $line_found=1;
	}
	print  SESAME_OUT $line;  # write out every line modified or not
    }
    if( $line_found==0){ 
	print ("source ${shell}rc wasnt found inserting.\n");
	print SESAME_OUT $src_rc;
    } else { 
	print("found source $src_rc\n");
    }
    close SESAME_OUT;

###
# check that user ${shell}rc is in place
###
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
	    return (0);
	} 
    }

# check that our rad env is in the ${shell}rc
    open SESAME_OUT, ">$outpath" or die "could not open $outpath for writing\n";
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
#my @export_lines;
    my @src_lines;
#push(@export_lines,$wrk_line,$rad_line,$pipe_line);
#push(@src_lines,$wrk_src,$rad_src,$pipe_src);
    my @wrk_lines=($wrk_home,$wrk_src);
    my @rad_lines=($rad_home,$rad_src);
    my @pipe_lines=($pipe_home);#,$pipe_line,$pipe_src);
#my $wrk_regex='('.join(')|(',@wrk_lines).')';
#my $rad_regex='('.join(')|(',@rad_lines).')';
#my $pipe_regex='('.join(')|(',@pipe_lines).')';
    my ($src_found,$wrk_found,$rad_found,$pipe_found)=(0,0,0,0);
    foreach my $line (  @user_shellrc) {
	if ( $line =~ /$src_regex/){ 
	    $src_found=1;
	    print SESAME_OUT $src_line;
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
    open SESAME_OUT, ">${HOME}/.bash_workstation_settings" or die "Couldnt open settings file for writing!";
    print SESAME_OUT "".
	"# \n".
	"# File automatically generated to contain paths by install.pl for worstation_home\n";
    print SESAME_OUT join("\n",@wrk_lines)."\n";
    print SESAME_OUT join("\n",@rad_lines)."\n";
    print SESAME_OUT join("\n",@pipe_lines)."\n";
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
    $inpath="${HOME}/.MacOSX/environment.plist";
    $outpath=$inpath."out";
    if (open SESAME, $inpath) {
	@all_lines = <SESAME>;
	close SESAME;
	print(" opened env_plist \n");
    } else {
	print STDERR "Unable to open file <$inpath> to read\n";
	return (0);
    } 

    open SESAME_OUT, ">$outpath" or die "could not open $outpath for writing\n";
    foreach my $line (@all_lines) {
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
    if ( $name !~ /omega/x ) 
    {
	if ( ! -e "../usr/bin/ANTS" ) 
	{
	    my $scp_cmd;
	    # find dmg on syros
	    my $ants_dmg=`ssh syros ls /Volumes/xsyros/Software/SegmentationSoftware/| grep ANT`;
	    chomp($ants_dmg);
	    #scp dmg
	    $scp_cmd="scp syros:/Volumes/xsyros/Software/SegmentationSoftware/$ants_dmg ../$ants_dmg";
	    if ( ! -f "../$ants_dmg" ) 
	    { 
		print ("$scp_cmd\n");
		`scp_cmd`;
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
    #get fsl script?
    my $fsl_inst_cmd="./fslinstaller.py -d $wks_home/../";
    open my $cmd_fh, "$fsl_inst_cmd |";   # <---  | at end means to make command 
    #         output available to the handle
    while (<$cmd_fh>) {
	print "A line of output from the command is: $_";
    }
    close $cmd_fh;
#    `$fsl_inst_cmd`;
    
}
}    
###
# update engine_something_pipeline_dependencis.
###
###
# copy engine_hostname_dependencis to backup and 
# cp engine_generic_dependincies to engine_hostname_depenendinceis and 
# link it to pipeline_dependencies and recon_dependencies.
###

    if ( $name !~ /omega/x )
    {
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
#    return(0);
	} else { 
	    print("Copying $default_file to $dep_file\n");
	    `cp $default_file $dep_file`;
	}
# sub hostname for hostname_radish  and hostname_pipeline
	my( $rdep, $pdep);
	($rdep = $dep_file ) =~ s/$hostname/${hostname}_radish/gx;
	($pdep = $dep_file )=~ s/$hostname/${hostname}_pipeline/gx;
	
	if( ! -e  $rdep && ! -e $pdep) {
	    `ln -s $dep_file $rdep`;
	    `ln -s $dep_file $pdep`;
	    print ("made pipeline and engine links for legacy code\n\t$rdep\n\t$pdep\n");
	} else { 
	    print("  *dependency links exist!\n");
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
	    return (0);
	} 

	my @outcommentary=();
	my $string;
	open SESAME_OUT, ">$outpath" or die "could not open $outpath for writing\n";
	foreach my $line (@all_lines) {
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
		$string="engine_work_directory=/Volumes/${hostname}space";
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
		$string="engine_radish_bin_directory=$wks_home/bin";#recon/legacy/modules/_mac_$arch
# engine_radish_contributed_bin_directory=/wks_home/recon/legacy/modules/contributed/bin_macINTEL 
	    } elsif ($line =~ /^engine_radish_contributed_bin_directory=/x ) {
		$string="engine_radish_contributed_bin_directory=$wks_home/recon/legacy/modules/contributed/bin_mac_$arch";
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
# fetch legacy binaries!
###
# should store tars of binaries and "frozen" code someplace and dump it to the recon engine when we copy this.
#scp binaries to ../tar/
my $os="$^O";
my $tarname="radish_${os}_$arch.tgz";
my $tardir="$wks_home/../tar/modules/";
my $tarfile="$tardir/$tarname";
if ( ! -f $tarfile) 
{ 
    my $scp_cmd="scp delos:$tarfile $tarfile";
    print("did not find tgz $tarname, attempting retrieval with $scp_cmd\n");
    if ( ! -d $tardir )
    {
	my $mkdir_cmd="mkdir -p $tardir";
	`$mkdir_cmd`;
    }
    `$scp_cmd`;
}

if ( -f "$tarfile" ) 
{ 
    chdir "$wks_home/bin";
    my $tar_cmd="tar -xvf $tarfile 2>&1";# | cut -d " " -f3-";
    my $output=qx($tar_cmd);
    #my ;
    open SESAME_OUT, '>', "bin_uninstall.sh" or die "couldnt open bin_uninstall.sh:$!\n";
    print(SESAME_OUT "#bin uninstall generated from installer.\n");
    print("dumping output of tar\n");
    foreach my $line (split /[\r\n]+/, $output) {
	## Regular expression magic to grab what you want
	$line =~ /x(.*)/x;
	my $out_line="$1";
	print(SESAME_OUT "rm -i $out_line\n");
	#print SESAME_OUT $output;
    }

    close SESAME_OUT;
    chdir $wks_home;
} else { 
    print("Could not find the expected tar file for this os/arch:$tarfile\n");
    sleep(4);
}
#### 
# make legacy links!
###
# ln with absolute links for source (via wks_home) and relative links for dest
#for file in `ls ../../pipeline_settings/engine_deps/* ../../pipeline_settings/scanner_deps/*
my @dependency_paths;
my $ln_cmd;
my $ln_source;
my $ln_dest;
my $infile; 
my $outname;
push(@dependency_paths,glob("$wks_home/pipeline_settings/engine_deps/*${hostname}*"));
push(@dependency_paths,glob("$wks_home/pipeline_settings/scanner_deps/*"));
# link dependency files to "recon_home" dir 
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
# link perlexecs from pipeline_utilities to bin
my @perl_execs=qw(agi_recon agi_reform agi_scale_histo dumpAgilentHeader1 dumpHeader.pl);
for $infile ( @perl_execs ) 
{
    $outname = basename($ln_source,qw(.pl .perl));
    $ln_source="$wks_home/shared/pipeline_utilities/$infile";
    $ln_dest="bin/$outname";
    if ( -r $ln_dest ) { 
	`unlink $ln_dest`;
    }    
    $ln_cmd="ln -sf $ln_source $ln_dest";
    #print ("$ln_cmd\n");
    `$ln_cmd`;
    `chmod a+x bin/$outname`;
}

#$ln_cmd="ln -sf $wks_home/shared/radish_puller recon/legacy/dir_puller";
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

#$ln_cmd="ln -sf $wks_home/shared/pipeline_utilities/startup.m $wks_home/recon/legacy/radish_core/startup.m";
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
print("use source ~/.bashrc to enabe settings now, otherwise quit terminal or restart computer\n");
# engine                         =$hostname
# engineworkdir                  = /Volumes/$hostnamespace|/$hostnamespace|/enginespace
# engine_archive_tag_directory   = /Volumes/$hostnamespace/Archive_Tags|/$hostnamespace/Archive_tags|/enginespace/Archive_Tags
# engine_app_dti_recon_param_dir = "wks_home/pipeline_settings/tensor"
# engine_recongui_menu_path      = "wks_homepipeline_settings/recon_menu.txt"
# engine_radish_bin_directory    = "wks_home/legacy/${arch}bin
# engine_radish_contributed_bin_directory = "wks_home/legacy/contrib_$(arch)/bin


