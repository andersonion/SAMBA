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

sub CraftOptionDispatchTable ()
{
    my $t_ref = shift @_;
    #my %table = %{$t_ref};
    #my $table = shift @_;
    my $dir= shift @_;
    #my $table = $_[0];
    #my $dir = $_[1];
    #Installer must be called while in the software dirctory.\n 
    opendir(D, "$dir") || die "Can't open directory $dir.\nERROR: $!\n";
    my @list = readdir(D);
    closedir(D);
    for my $file (@list) {
	if ( $file =~ m/^inst-(.*)[.]pl$/x){
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

sub CraftOptionList() {
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
	if ( $type == '' ) {
	    $type='!';
	}
	$o_string="'$key$type' => ".$o_ref->{$key}.",".$o_string;
	$o_string="'skip_$key$type' => ".'\$options{skip_'.$key.'}'.",".$o_string;
	#print("col::Adding to understood opts, $key <- ".$o_ref->{$key}." \n");
    }
    
    return $o_string;
}

1;
