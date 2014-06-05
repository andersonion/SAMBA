use warnings;
sub shell () {
    my $mode = shift;
###
# check shell supported.
###
    my $rc_file;
    my $profile;
    { 
	if ( $SHELL !~ m/bash/x ) {
	    print ("ERROR: shell is not bash, other shells un tested and unsupported.");
	    return 0;
	} elsif(  $SHELL =~ m/bash/x) {
	    print ("Shell check match=bash\n");
	    $rc_file=${SHELL}.'rc';
	    $profile=${SHELL}.'_profile';
	    #$SHELL = "bash";
	} elsif ( $SHELL =~ m/[t]?csh/x) {
	    print ("Shell check match=Csh\n");
	    #$SHELL = "csh";
	}
	
    }

###
# check if we need to do work.
###

    my $do_work=0;
    my $work_done=0;
     
    my $src_rc="source ~/.${SHELL}rc";
    $bashrc_src_reg='^[\s]*'. # any ammount of whitespace, including none.
	'(?:source|[.])'. # source lines can start with a . or the word source
	'[\s]+'. #then followed by any ammount of whitespace
	"(?:\${HOME}|\$HOME|$HOME|[~])". # then followed by any combination of ${HOME
	"/[.]$rc_file".
	'[\s]*(?:[#].*)?$'; # any ammont of whitespace followed by end of line	
    my $profile_check=CheckFileForPattern("~/.".$profile,$bashrc_src_reg) ;

    my $src_wks_settings = 'source ~/.bash_workstation_settings';
    my $wks_settings_reg = '^[\s]*'.
	'source'.
	'[\s]+'.
	'[~]/[.]bash_workstation_settings'.
	'[\s]*(?:[#].*)?$';
    my $wks_settings_check    = CheckFileForPattern("~/.".$rc_file,$wks_settings_reg) ;

    #my $profile_check=CheckFileForPattern("~/".$profile,"[\w]?(?:source|.)[ ]+(?:${HOME}|~)$profile") ;
    if ( $wks_settings_check>=1 && $profile_check>=1 && -f "$HOME/.$profile" && -f "$HOME/.$rc_file" && -f ".${SHELL}_workstation_settings") {
	print("work done\n");
	$work_done=1;
    }
    if( $mode ){
	print ("force\t");
	$do_work=$mode;
    } elsif(!$work_done ) {
	$do_work=1;
    }
    print("shell\n");

###
# put source ${HOME}/.${SHELL}rc in .${SHELL}_profile
### 
    if ( $do_work > 0 ){
	if ( $profile_check<=0 ) {
	    print("---\n");
	    print("Setting source .${SHELL}rc in ${SHELL}_profile ...... \n");
	    print("---\n");
# 	    print("Must run this as user to install to!\n". 
# 		  "By default that is omega\n".
# 		  "This only sets up the ${SHELL} environment!\n");
	    print("adding $src_rc to ~/.$profile\n");
	    open ($FILE, ">>","${HOME}/.$profile") || die "Could not open file: $!\n";
	    print $FILE "$src_rc\n";
	    close $FILE;
	}
###
# check that user ${SHELL}rc is in place
###

#
# check that our rad env is in the bash_workstation_settings
	if ( $wks_settings_check <=0 ){
	    print("---\n");
	    print("Adding lines to ${SHELL}rc ...... \n");
	    print("---\n");
	    #$src_rc='. ~/.'."${SHELL}".'rc';
	    print("adding $src_wks_settings to ~/.$rc_file\n");
	    
	    FileAddText("${HOME}/.$rc_file","$src_wks_settings\n");
# 	    open ($FILE, ">>","${HOME}/.$rc_file") || die "Could not open file: $!\n";
# 	    print $FILE "$src_wks_settings\n";
# 	    close $FILE;
	}

	if ( ! -f ".${SHELL}_workstation_settings" ) {
	    my $wrk_home       ="export WORKSTATION_HOME=$WKS_HOME";
	    my $wrk_src        ="source \$WORKSTATION_HOME/pipeline_settings/${SHELL}/${SHELL}rc_pipeline_setup";
	    my $wrk_data     ="export WORKSTATION_DATA=$DATA_HOME";
	    my $rad_home       ="export RADISH_RECON_DIR=$WKS_HOME/recon/legacy";
	    my $rad_src        ="source \$WORKSTATION_HOME/pipeline_settings/${SHELL}/legacy_radish_${SHELL}rc";
	    my $pipe_home      ="export PIPELINE_HOME=$WKS_HOME/";
	    
#	    my @wrk_lines=($wrk_home,$wrk_src);
#	    my @rad_lines=($rad_home,$rad_src);
#	    my @pipe_lines=($pipe_home);#,$pipe_line,$pipe_src);
	    
	    
# 	    my ($src_found,$wrk_found,$rad_found,$pipe_found)=(0,0,0,0);
# 	    open SESAME_OUT, ">${HOME}/.bash_workstation_settings" or warn "Couldnt open settings file for writing!";
# 	    print SESAME_OUT join("\n",@wrk_lines)."\n";
# 	    print SESAME_OUT join("\n",@rad_lines)."\n";
# 	    print SESAME_OUT join("\n",@pipe_lines)."\n";
# 	    close SESAME_OUT;
	    FileClear("${HOME}/.bash_workstation_settings");
	    FileAddText("${HOME}/.bash_workstation_settings",
			"# \n".
			"# File automatically generated to contain paths by install.pl for worstation_code\n".
			$wrk_home."\n".
			$wrk_src."\n".
			$wrk_data."\n".
			$wrk_home."\n".
			$rad_home."\n".
			$rad_src."\n".
			$pipe_home."\n"
		);


	}
    }
    return 0;
}
1;
