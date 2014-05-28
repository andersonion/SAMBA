sub check_prereqs () {
    my $mode = shift;
    my $do_work=0;
    my $work_done=0;
    if( $mode ){
	print ("force\t");
	$do_work=$mode;
    } elsif(!$work_done ) {
	$do_work=1;
    }
    if ( $do_work > 0) {
	print("check_prereqs\n");
	my @programs=qw(ImageJ MATLAB xcode(gcc) SeverAdmin);
	print("Mac checks\n\t".join("\n\t",@programs)."\n");
	$work_done=1;
    }
    if( $work_done) {
	return 1; 
    } else{
	return 0 ;
    }
### 
# check for required programs
###
# sohuld fail loudly if not found? or do as much as possible first?
# 
# need xcode 
#   need command line tools, checkable using the make command.
# need matlab2013b or newer
# need image j
# 
}
1;
