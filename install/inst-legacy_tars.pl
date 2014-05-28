sub legacy_tars () {
    print("legacy_tars\n");
    return 1;
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
	my $tar_cmd="tar --keep-newer-files -xvf $tarfile 2>&1";# | cut -d " " -f3-";
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
return; 
}
1;
