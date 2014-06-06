sub student_matlab () {
    print("student_matlab\n");
    
###
# add student matlab
###	
    if ( $IS_MAC) {
	print("STudent matlab grab is attrocious, should not be used anywhere but civm\n");
	if ( ! -e "../student_matlab/evan" ) {
	    print("Studnet matlab not found, Required for some DCE code.");
	    `mkdir -p "../student_matlab"`;
	    my $scp_cmd="scp -r panorama:$WKS_HOME/student_matlab/evan/evan_matlab ../student_matlab/evan";
	    print ("$scp_cmd\n");
	    `$scp_cmd`;
	}
    }
    return 1; 
}
1;
