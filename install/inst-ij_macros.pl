sub ij_macros() {
    print("ij_macros\n");
    return 1;
### 
# some more linking
###
    $infile="$wks_home/analysis/james_imagejmacros";
    
    $ln_source="$infile";
    $ln_dest="/Applications/ImageJ/plugins/000_james_imagejmacros";
    if ( -r $ln_dest ) { 
	`unlink $ln_dest`;
    }    
    $ln_cmd="ln -sf $ln_source $ln_dest";
    #print ("$ln_cmd\n");
    `$ln_cmd`;
    return;
}
1;

