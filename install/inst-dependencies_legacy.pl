

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
# link dependency files to "recon_home" dir for legacy processes
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

