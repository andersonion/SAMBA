#use lib split(':',$RADISH_PERL_LIB);
#require subroutines;
#require order;
sub handle_prereqs () {
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
	print("handle_prereqs\n");
	my @programs=qw(ImageJ MATLAB xcode(gcc) SeverAdmin ANTS FSL);
	print("Mac checks\n\t".join("\n\t",@programs)."\n");
	$work_done=1;
    }

my %dispatch_table=(); # look up of option function names to function refer3ences
my %dispatch_status=();# look up to hold if we've run a function or not.
my %option_list=();    # list of options recognized, built from the dispatch table.
my %options=();        # the options specified on the command line.

CraftOptionDispatchTable(\%dispatch_table,$ENV{PWD}.'/install','prog');
my @order = OptionOrder("prog");
#my $opt_eval_string=CraftOptionList( \%dispatch_table, \%option_list);


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
ProcessStages(\%dispatch_table,\%dispatch_status,\%options,\@order);


    if( $work_done) {
	return 1; 
    } else{
	return 0 ;
    }

    
}
1;
