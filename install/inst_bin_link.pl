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
    push(@perl_execs,qw(agi_recon agi_reform agi_scale_histo dumpAgilentHeader1 dumpHeader.pl rollerRAW:roller_radish lxrestack:restack_radish validate_headfile_for_db.pl:validate_header puller.pl puller_simple.pl radish.pl display_bruker_header.perl radish_agilentextract.pl display_agilent_header.perl sigextract_series_to_images.pl k_from_rp.perl:kimages retrieve_archive_dir.perl:imgs_from_archive pinwheel_combine.pl:pinwheel keyhole_3drad_KH20_replacer:keyreplacer re-rp.pl main_tensor.pl:tensor_create recon_group.perl group_recon_scale_gui.perl:radish_scale_bunch radish_brukerextract/main.perl:brukerextract main_seg_pipe_mc.pl:seg_pipe_mc archiveme_now.perl:archiveme t2w_pipe_slg.perl:fic mri_calc reform_group.perl reformer_radish.perl getbruker.bash roll_3d.pl));
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
    $link_text="Finding $infile in $in_dir ...";
    #print("Finding $infile in $in_dir ...");
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
	    $link_text="  found! ...";
	    #print("  found! ...");
	} else {
	    $link_text="$link_text  NOT_FOUND.";
	    #print("  NOT_FOUND.");
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
	    `chmod 775 bin/$outname`;
	    `chmod 775 $ln_source`;
	    $link_text="$link_text linked.\n";
	    #print( " linked.\n");
	} else { 
	    print (" NOT A LINK, NOT OVERWRITING!\n");
	}
    } else {
	$link_text="$link_text NOT_LINKED!\n";
        #print (" NOT_LINKED!\n");
#	print ("$infile  in $in_dir\n");
    }
    if ( $link_text =~ m/.*NOT.*/x ) {
	push(@link_summary,"$link_text");
    } else {
	print(".");
    }
}
print("\n");
close SESAME_OUT;
print(@link_summary);
