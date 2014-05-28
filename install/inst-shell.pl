sub shell () {
    print("shell\n");
    return 1;
###
# check shell supported.
###
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
    my $wrk_data     ="export WORKSTATION_DATA=$data_home";
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
}
return;
}
1;
