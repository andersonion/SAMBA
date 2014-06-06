sub bin_link ()
{
    print("bin_links\n");
    #return 1;
    my $bin_uninstfile=$MAIN_DIR."/uninstall_bin_links.sh";

### 
# link perlexecs from pipeline_utilities and other  to bin
###
    #
    #
    # handle code deps some how? this cant run witohut the group check module running.
    group();
    #
    #
    #
    my @perl_execs=();
    if ( $IS_USER ) { 
	push(@perl_execs,qw(agi_recon agi_reform agi_scale_histo dumpAgilentHeader1 dumpHeader.pl rollerRAW:roller_radish lxrestack:restack_radish validate_headfile_for_db.pl:validate_header puller.pl puller_simple.pl radish.pl display_bruker_header.perl radish_agilentextract.pl display_agilent_header.perl sigextract_series_to_images.pl k_from_rp.perl:kimages retrieve_archive_dir.perl:imgs_from_archive pinwheel_combine.pl:pinwheel keyhole_3drad_KH20_replacer:keyreplacer re-rp.pl main_tensor.pl:tensor_create recon_group.perl group_recon_scale_gui.perl:radish_scale_bunch radish_brukerextract/main.perl:brukerextract main_seg_pipe_mc.pl:seg_pipe_mc archiveme_now.perl:archiveme t2w_pipe_slg.perl:fic mri_calc reform_group.perl reformer_radish.perl getbruker.bash roll_3d.pl));
    } else {
	print ("Not part of user group, not bothering to link\n");
    }
    
    if ( ! CheckFileForPattern("$MAIN_DIR/.gitignore","^".basename($bin_uninstfile)) ) {
	FileAddText("$MAIN_DIR/.gitignore",basename($bin_uninstfile)."\n");
    } else {
	print ("$MAIN_DIR/.gitignore set up.(binuninst)\n");
    }
    if ( ! CheckFileForPattern("$MAIN_DIR/.gitignore","^bin/\\*") ) {
	FileAddText("$MAIN_DIR/.gitignore","bin/\*\n");
	print("Adding bin ignore line to gitignore\n");
    } else {
	print ("$MAIN_DIR/.gitignore set up.(folder)");
    }
#dumpEXGE12xheader:header
    my @link_summary=();
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
	my $link_text="";
	$link_text="Finding $infile in $WKS_HOME ...";
	#print("Finding $infile in $WKS_HOME ...");
	find( sub { ${files{$File::Find::name}} = 1 if ($_ =~  m/^$infile$/x ) ; },"$WKS_HOME");
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
		$link_text="  found! ...";
		#print("  found! ...");
	    } else {
		$link_text="$link_text  NOT_FOUND.";
		#print("  NOT_FOUND.");
	    }
	}
	if ( defined ( $fnames[0]) && $#fnames<1) 
	{ 
	    $ln_source="$fnames[0]";#$WKS_HOME/$infile";
	    $ln_dest="bin/$outname";
	    if ( -l $ln_dest ) { 
		`unlink $ln_dest`;
	    }
	    if ( ! -e $ln_dest )
	    {
		$ln_cmd="ln -sf $ln_source $ln_dest";
		#print ("$ln_cmd\n");
		`$ln_cmd`;
#	    print(SESAME_OUT "unlink ".basename($ln_dest)."\n");	
		`chmod 775 bin/$outname`;
		`chmod 775 $ln_source`;
		$link_text="$link_text linked.\n";
		my $rm_cmd="unlink $WKS_HOME/$ln_dest";
		if ( ! CheckFileForPattern($bin_uninstfile,"$rm_cmd") ) {
		    print ("adding bin removal instructions to $bin_uninstfile:$rm_cmd\n");
		    FileAddText($bin_uninstfile,"$rm_cmd\n");
		}
		#print( " linked.\n");
	    } else { 
		print (" NOT A LINK, NOT OVERWRITING!\n");
	    }
	} else {
	    $link_text="$link_text NOT_LINKED!\n";
	    #print (" NOT_LINKED!\n");
#	print ("$infile  in $WKS_HOME\n");
	}
	if ( $link_text =~ m/.*NOT.*/x ) {
	    push(@link_summary,"$link_text");
	} else {
	    print(".");
	}
    }
    print("\n");
#close SESAME_OUT;
    if ( $#link_summary>0 ) {
	print(@link_summary);

	return 1;
    } else {
	return 0;
    }
}
1;
