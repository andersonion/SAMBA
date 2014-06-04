sub matlab (){
    
    my $output=`which matlab`;
    if ( ! $? ) {
	#when true matlab found.
	print("\tMatlab found, at $output\n");
    } elsif ( $IS_MAC ) {
	print("ERROR: Matlab not found, it should be linked into place on the path. path <$ENV{PATH}>\n");
	my @matlabs=`find /Applications -iname "MATLAB*" -type d -maxdepth 1`;
	chomp @matlabs;
	my $mat_path=`find $matlabs[$#matlabs] -name matlab -type f -maxdepth 3`;
	chomp $mat_path;
	my $sudo_ln="sudo ln -sf $mat_path /usr/bin/matlab";
	if ( $IS_ADMIN ) {
	    print("\t$sudo_ln\n");
	    `$sudo_ln`;
	    return $?;
	} else {
	    print("tell your administator you cant access matlab on the command line, and they should run the following command. \n\t$sudo_ln\n");
	    return 1;
	}
    } else {
	# didtn find matlab, but not mac
	print("Didnt find required software, matlab\n");
	return 1;
    }

}
1;
