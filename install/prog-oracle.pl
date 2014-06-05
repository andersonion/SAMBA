sub oracle () {
    my $mode = shift;
    my $do_work=0; 
    my $base_path="/Volumes/xsyros/software/oracle/";
    my $oracle_inst_dir="$WKS_HOME/../oracle"; 
    my $oracle_version="11.2";
    $oracle_inst_dir =~ s|//|/|gx;
    # $OS is package var, $os is local var
    my $os='UNKNOWN';
    if ( $OS =~ /^darwin$/ )
    {
	$os='mac';
    } else {
	$os=$OS;
	print ("oracle install not supported on non-mac systems yet. os is $os\n");
	return 0;
    }
    

    my $work_done=0;
    if ( -d "$oracle_inst_dir" && $ENV{DYLD_LIBRARY_PATH} =~ m/$oracle_inst_dir/x && $ENV{ORACLE_HOME} =~ m/$oracle_inst_dir/x ) {
	$work_done=1; 
    } else {
	if ( ! -d "$oracle_inst_dir" ){
	    print("oracle_inst_dir $oracle_inst_dir not found\n");
	}
	if ( $ENV{DYLD_LIBRARY_PATH} !~ m/$oracle_inst_dir/x ) {
	    print("oracle_inst_dir not in DYLD_LIBRARY_PATH.\n".
		  "$ENV{DYLD_LIBRARY_PATH} !~ $oracle_inst_dir\n");
	    $do_work=1;
	}
	if ( $ENV{ORACLE_HOME} !~ m/$oracle_inst_dir/x ) {
	    print("oracle_inst_dir not in ORACLE_HOME\n ".
		  "$ENV{ORACLE_HOME} !~ $oracle_inst_dir\n");
	    $do_work=1;
	}
    }


    if( $mode ){
	print ("force\t");
	$do_work=$mode;
    } elsif(!$work_done ) {
	$do_work=1;
    }
    print("oracle\n");
    #--with-oracle-lib-path
    if ( ! $IS_ADMIN && $do_work) { 
	print("Oracle install scheduled, but could not complete because not an admin\n");
	return 0 ;
    }

# % whence perl  # or whatever command returns the version of perl first in your path.   
#                 # Verify this is the version you intent to install DBD::Oracle to  
#  % gzip -dc DBD-Oracle-1.40.tar.gz | tar xf - 
#  % cd DBD-Oracle-1.17 
#  % perl Makefile.PL -V 10.2 
#  % make 
#  % make install 

    #if ( ! -d "$oracle_inst_dir" ) 
    if ( $do_work && ! -d "$oracle_inst_dir")  {
	chdir $WKS_HOME;
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
	    my $ls_cmd="ssh syros ls ${base_path}/*${os}*${ARCH}/*client*$part*${oracle_version}*${os}*${ARCH}*.zip";
	    my $oracle_zip=`$ls_cmd` or print("cmd_fail $ls_cmd\n");
	    chomp($oracle_zip);
	    #scp dmg
	    $scp_cmd="scp syros:$oracle_zip ../zip/".basename($oracle_zip);
	    if ( ! -f "../zip".basename($oracle_zip) )  {
		print ("$scp_cmd\n");
		`$scp_cmd`;
	    } else { 
		print("found zip: ".basename($oracle_zip)." found\n");
	    }
	    # 
	    chdir "../zip/";
	    my $cmd="unzip ".basename($oracle_zip)." -d $oracle_inst_dir";
	    open my $cmd_fh, "$cmd |";   # <---  | at end means to make command 
	    #         output available to the handle
	    while (<$cmd_fh>) 
	    {
		print "A line of output from the command is: $_";
	    }
	    chdir $WKS_HOME;
	}
	`mv $oracle_inst_dir/*/* $oracle_inst_dir`;
	
	###
	# Cpan requirements for oracle
	###
	my $outpath="$WKS_HOME/oracle_cpaninst.bash";
	
	print("creating oracle_cpaninst.bash for root to run\n");
	open SESAME_OUT, ">$outpath"; 
	print SESAME_OUT "#!/bin/bash\n".
	    "---\n".
	    "Running $outpath  ...... \n".
	    "---\n".
	    "declare -x ORACLE_HOME=$oracle_inst_dir\n".
	    "declare -x DYLD_LIBRARY_PATH=$oracle_inst_dir\n".
	    "cpan YAML\n".
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
    } elsif ( -e $outpath ) {
	my $cmd = "unlink $outpath";
	`cmd`;
    }
    
#     my $src_wks_settings = 'source ~/.bash_workstation_settings';
#     my $wks_settings_reg = '^[\s]*'.
# 	'source'.
# 	'[\s]+'.
# 	'[~]/[.]bash_workstation_settings'.
# 	'[\s]*(?:[#].*)?$';
#     my $wks_settings_check    = CheckFileForPattern("~/.".$rc_file,$wks_settings_reg) ;



    if ( $do_work ) {
	print("setting oracle env in ${HOME}/.${SHELL}_workstation_settings\n");
	my $outfile="${HOME}/.${SHELL}_workstation_settings";
#	if ( ! CheckFileForPattern($outfile,"ORACLE_HOME=.*") ) {
	    #open ($FILE, ">>","${HOME}/.${SHELL}_workstation_settings") || die "Could not open file: $!\n";
	    my $oracle_lib    ="export DYLD_LIBRARY_PATH=\$DYLD_LIBRARY_PATH:$oracle_inst_dir";
	    my $oracle_home   ="export ORACLE_HOME=$oracle_inst_dir";
	    my @oracle_lines=();#$oracle_lib,$oracle_home);
	    
	    if (CheckFileForPattern("${HOME}/.${SHELL}_workstation_settings",$oracle_lib) <=0 ){
		push( @oracle_lines,$oracle_lib);
	    } else {
		print("Found oracle_lib_path line\n");
	    }
	    if (CheckFileForPattern("${HOME}/.${SHELL}_workstation_settings",$oracle_home) <=0 ){
		push( @oracle_lines,$oracle_home);
		print("Found oracle_home_path line\n");
	    }
	    if ($#oracle_lines>=1) {
		FileAddText($outfile,join("\n",@oracle_lines)."\n");
		#print $FILE join("\n",@oracle_lines)."\n";
	    }
#	}
	#close $FILE;
    }
    if ( ! $do_work ) {
	print ("... done!\n");
    }
    return 1;

}
1;
