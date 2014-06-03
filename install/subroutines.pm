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
	    my $name=$1;
	    my $first_letter=substr($name,0,1);
	    #print("inserting funct reference for $name\n");	    
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
    return;
}

sub CraftOptionList {
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
	    $type='=s';
	} 
	$o_string="'$key$type' => ".$o_ref->{$key}.",".$o_string;
	$o_string="'skip_$key' => ".'\$options{skip_'.$key.'}'.",".$o_string;
	#print("col::Adding to understood opts, $key <- ".$o_ref->{$key}." \n");
    }
    
    return $o_string;
}

sub CheckFileForPattern {
    my $infile  = shift @_;
    my $pattern = shift @_; 
    my $INPUT;
    my $found=0;
    $infile =~ s/~/${HOME}/gx;
    if (-f $infile ){
    open($INPUT, $infile) || warn "Error opening $infile : $!\n";
    #print("looking up pattern $pattern in file $infile\n");
    while(<$INPUT>) {
	if (m/$pattern/x) {
#	if ( $_=~/$pattern/) {
	    #print;
	    $found += 1;
	    # exit; # put the exit here, if only the first match is required
	} else {
	    #print "nomatch ".$_;
	}
    }
    close($INPUT);
    #print ("CheckFile out $found\n");
    } else {
	$found=-1;
    }
    return $found;
}
sub ProcessStages {
#table, status, order

    my $first_stage=shift @_;
    my $prefix = shift @_;
    if ( ! defined $prefix ) {
	$prefix="inst";
    }
    
    my $found_first=0;
    for my $opt ( @order ) {
#    print ("Run $opt\n");
	if ( ! $options{'skip_'.$opt} ) {
	    if ( $opt =~ /$first_stage/ ) {
		print ("Found Starting point\n");
		$found_first=1;
	    } else {
		#found is not it.... 
	    }
	    if ( $found_first || ! length $first_stage) { 
		# for default behavior optinos{opt} is undefined, for force on it is is 1, for force off it is 0.
		my $status=$dispatch_table{$opt}->($options{$opt} #put params in here.
		    );
		$dispatch_status{$opt}=$status;
		if ( !$status ){
		    print ("ERROR: $opt failed!\n");
		} 
	    } else {
		print ("$opt not desired first file<$first_stage>\n");
	    }
	}
    }
    
    return;   
}


1;
