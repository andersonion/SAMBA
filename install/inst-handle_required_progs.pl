#use lib split(':',$RADISH_PERL_LIB);
#require subroutines;
#require order;
use warnings;
use strict;
my $PROGRAM_NAME="handle_required_progs";
sub handle_required_progs  {
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
	print("handle_required_progs\n");
	#my @programs=qw(ImageJ MATLAB xcode(gcc) SeverAdmin ANTS FSL);
	#print("required_programs\n\t".join("\n\t",@programs)."\n");
	$work_done=1;
    }

#
    my %dispatch_table=(); # look up of option function names to function refer3ences
    my %dispatch_status=();# look up to hold if we've run a function or not.
    my %option_list=();    # list of options recognized, built from the dispatch table.
    my %options=();        # the options specified on the command line.
    my $p_sub_path=$ENV{PWD}."/"."install";
    print("Finding required progs in $p_sub_path\n");
    CraftOptionDispatchTable(\%dispatch_table,$p_sub_path,'prog');
    #my @order = OptionOrder("prog");
    my @order=keys( %dispatch_table);

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
#    print("Call opt dispatch\n");
#    $options{'debug'}=45;
 #   print("processing in order ".join(" ",@order)."\n");
    ProcessStages(\%dispatch_table,\%dispatch_status,\%options,\@order);
    
#    print("done with required_progs\n");
    if( $work_done) {
	return 0; 
    } else{
	return 1 ;
    }
}


sub main {
#    print("required_progs_main");
    print("Checking on required programs and installing a limited selection of them:$0\n");
    my $yucky_eval_cmd="$PROGRAM_NAME($@)";
    eval $yucky_eval_cmd;
    return ;
}

if ( $0 =~ /$PROGRAM_NAME/x){
    
    use Cwd 'abs_path';
    use File::Basename;
    use lib dirname(abs_path($0));
    require subroutines;
    use Scalar::Util qw(looks_like_number);
    main($@);
}
1;
