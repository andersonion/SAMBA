# package install::subroutines;
# use strict;
# use warnings;
# BEGIN { #require Exporter;
#     use Exporter(); #
#     our @ISA = qw(Exporter);
# #    our @Export = qw();
#     our @EXPORT_OK = qw(
# CraftOptionDispatchTable
# CraftOptionList
# );
# }
use warnings;
#use strict;
sub CheckFileForPattern {
    my $infile  = shift @_;
    my $pattern = shift @_; 
    my $INPUT;
    my $found=0;
    $infile =~ s/~/${HOME}/gx;
    $pattern =~ s|(/\|[ ])|\\$1|gx;
    if (-f $infile && open($INPUT, $infile) ){
	#print("looking up pattern $pattern in file $infile\n");
	while(<$INPUT>) {
	    if (m/$pattern/x) {
#	if ( $_=~/$pattern/) {
#		print;
		$found += 1;
		# exit; # put the exit here, if only the first match is required
	    } else {
		#print "nomatch ".$_;
	    }
	} 
# 	else {
# 	    warn "Error opening $infile : $!\n" ;
# 	    $found =0;
# 	}
	close($INPUT);
	#print ("CheckFile out $found\n");
    } else {
	#$found=-1;
    }
    return $found;
}

sub CraftOptionDispatchTable  {
    my $t_ref = shift @_;
    #my %table = %{$t_ref};
    #my $table = shift @_;
    my $dir= shift @_;
    my $prefix = shift @_;
    if ( ! defined $prefix ) {
	$prefix="inst";
    }
    #my $table = $_[0];
    #my $dir = $_[1];
    #Installer must be called while in the software dirctory.\n 
    opendir(D, "$dir") || die "Can't open directory $dir.\nERROR: $!\n";
    my @list = readdir(D);
    closedir(D);
    for my $file (@list) {
	if ( $file =~ m/^$prefix-(.*)[.]pl$/x){
#	if ( $file =~ m/^$prefix-(.*)(?:-(.*))?[.]pl$/x){
	    my $name=$1;
#	    my $type=$2;
	    my $first_letter=substr($name,0,1);
#	    print("inserting funct reference for $name\n");	    
	    require $file;
	    #eval $name;
	    $t_ref->{$name}= eval '\&$name';
	    
	    # check for colliding names on first letter.
	    my $l_num=0;
	    my $l_txt='';
	    while( defined($t_ref->{$first_letter.$l_txt} ) ) {
		$l_num++;
		$l_txt=$l_num;
		#print ("lbump$l_num\n");
	    }
	    #### all in one... 
	    #$t_ref->{"$name".'|'."$first_letter.$l_txt"}= eval '\&$name';
	    if( !defined($t_ref->{$first_letter.$l_txt} ) ) {
		#print("and $first_letter$l_txt\n");
		#$t_ref->{$first_letter.$l_txt}= eval '\&$name';
	    } else {
		print ( "couldnt get a letter to use for simplified optioning, only assigned by name $name\n");
	    }
	}
    }
#     for my $key ( keys(%{$t_ref}) ){
# 	print("codt::Opt inserted! ( $key )\n");
#     }
#    print("Done craftingoption dispatch\n");
    return;
}

sub CraftOptionList {
# o_ref isnt really used for this, this should be updated to make it optional
    #my %table = %{shift @_};
    #my %opt_list = %{shift @_};
    my $t_ref = shift @_;
    #my %table = %{$t_ref};
    my $o_ref = shift @_;
#    my %opt_list = %{$o_ref};
    #print ("OptionList setup\n");
    my $o_string='';
    for my $key ( keys(%{$t_ref}) ){
	#if(
	
	$o_ref->{$key}='\$options{'.$key.'}';
	#$o_ref->{$key}="$key";
	
	#$o_ref->{$key}='\$options{$key}';
	#$o_ref->{$key}='\\$options{$key}';
	#$o_ref->{$key}='\\\$options{$key}';
	#$o_ref->{$key}='\$key';
	my $type='';
	if ( $type eq '' ) {
	    $type=':s';
	} 
	#$o_string="'$key' => ".$o_ref->{$key}.",".$o_string;
	$o_string="'$key$type' => ".$o_ref->{$key}.",".$o_string;
	$o_string="'skip_$key' => ".'\$options{skip_'.$key.'}'.",".$o_string;
	#print("col::Adding to understood opts, $key <- ".$o_ref->{$key}." \n");
    }
    
    return $o_string;
}

sub ProcessStages {
    print("Begin real work of $0\n");
    # dispatch_ref,output_status_ref, Stage_enableflags_ref,stage_order_arrrayref
    my( $d_ref,$s_ref,$s_flags,$o_ref)= @_;

    die print("No dispatch found, cannot continue\n") unless( defined $d_ref ); 

    $debug_mode=$s_flags->{"debug"};
#    print ("\n\ntest\n\n");

    if ( ! defined $debug_mode ) {
	print("Debug not set, proceding in quiet mode\n");
	$debug_mode=0;
    } else {
	print ("debug level ".$debug_mode."\n");
    }
    my @order=();
#    print ref( $o_ref) ."\n";
    #pprint  (join(':',@{$o_ref})."\n");
    if ( defined $o_ref ) {
	@order=@{$o_ref};
	print("defined order ".join(':',@order)."\n") unless $debug_mode < 15;
    } else {
	@order=keys %{$t_ref};
	print("undefined order ".join(':',@order)."\n") unless $debug_mode < 15;
    }
    my $first_stage=shift @_;
    my $prefix = shift @_;
    if ( ! defined $prefix ) {
	$prefix="inst";
    }
    
    my $found_first=0;
    for my $opt ( @order ) {
	if ( ! $s_flags->{'skip_'.$opt} ) {
	    # for default behavior optinos{opt} is undefined, for force on it is is 1, for force off it is 0.
	    my $status=$d_ref->{$opt}->($s_flags->{$opt} #put params in here.
		);
	    $s_ref->{$opt}=$status;
	    if (! $status ) {
		print("Stage exit clean:$opt\n");
	    } else {
		print("Stage error:$opt\n");
	    } 
	}
    }
    
    return;   
}

sub FileAddText { 
    my $file=shift @_;
    my $text=shift @_;
    my $FB;
#    print("Writing to $file\n");
    # could add optional $before_pattern $after_pattern to insert before or after some pattern found
    open($FB, '>>', $file) || die "Error opening $file : $!\n";
    print $FB ($text);
    close $FB;
    return;
}

sub FileClear {
    my $file=shift @_;
    my $FB;
    # could add optional $before_pattern $after_pattern to insert before or after some pattern found
    open($FB, '>', $file) || die "Error opening $file : $!\n";
    print $FB ('');
    close $FB;
    return;
}
1;
