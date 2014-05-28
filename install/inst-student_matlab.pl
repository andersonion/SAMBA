###
# add student matlab
###	
	if ( ! -e "../student_matlab/evan" ) {
	    print("Studnet matlab not found, Required for some DCE code.");
	    `mkdir -p "../student_matlab"`;
	    my $scp_cmd="scp -r panorama:$wks_home/student_matlab/evan/evan_matlab ../student_matlab/evan";
	    print ("$scp_cmd\n");
	    `$scp_cmd`;
	}
