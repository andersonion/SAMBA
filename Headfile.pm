# Headfile.pm
#
# created 5/23/2006 Sally Gewalt
#
# read, modify, and write a civm headfile 
# 060905 slg fix space at start of written headfile lines;
#            remove \r and \n from lines, since PC generated headfiles have cr/lf
#            and chomp is insufficient to get rid of both characters
# 060906 slg add in changes from delos
# 060906b slg change time to db time  
# 070215  slg add 'pfile' mode to read Pfile header into object using provided
#                outside binary header reader app.  
# 070320 slg add 'nf' mode for no file to be written, just maintain hash 
# 070407 slg add 'nf' mode for no file to be read, just maintain hash and possibly write(tofile) 
# 071031 slg change comment included in written files
# 071107 slg remove any leading or trailing spaces from values read from (possibly user created)
#            headfiles. Add "rc" mode writability.
# 090415 slg remove comments added to headfile via COMMENT
# 090528 slg add subs that parse group format items (e.g. group_id[grouptype]=value) 
#            Sub names start with "group" or "all_group".
#            group_XXX[YYY] items are for grouping images in n-dimensions
# 120731 james Updated copy_in to allow a prefix and a post fix to be put around the key value
#              from the incoming file. Either of them can be blank or undefined. 
# 160731 james cleaned out goofy code in get_keys.
# 161121 james cleaned up new function and improved the status message additions to the check function.

package Headfile;
use strict;
## doesn't work on intel mac: use diagnostics;
###use IO::File;
use IO qw(Handle File);
my $VERSION = "181211";
my $COMMENT = 0;

use SAMBA_pipeline_utilities qw($OSNAME);
# This OS check code would be nice to place somewhere common, that has been avoided
# for now to keep this code as independent as possible.
#
# its decided that SAMBA_pipeline_utilities is a good catch all for these exceedingly simple helpers.

#our $OSNAME="$^O\n";
#our $IS_MAC=0;
#our $IS_LINUX=0;
#if ( $OSNAME =~ /^darwin$/x ) {
#    $IS_MAC=1;
#} elsif( $OSNAME =~ /^linux$/x )  { 
#    $IS_LINUX=1;
#}

BEGIN {
    use Exporter;
    our @ISA = qw(Exporter); # perl critic wants this replaced with use base; not sure why yet.
    our @EXPORT_OK = qw(
now_date_db
);
}
# now_date_db should probably be under some kind of archive support since that is when its details matter.  

# Constructor --------
sub new
{
# Constructor of object of headfile class
    my ($classname, $mode, $in_headfile_path) = @_;
    # mode = ro, new, rw, rc, pfile, nf correspond to
    #  nf   = no file: just use hash, never write a file.
    #  new  = new file,
    #  ro   = existing file/read only,    
    #  rw   = existing/update, 
    #  rc   = existing/(but write to copy, not original),
    #  pfile= read pfile header,
    #  nifti= read nifti header,
    #  nrrd
    #  
    #  in_headfile_path: input headfile to be read, for "rw" you spec output file at time of write. 
    #                   for "pfile" you spec path of pfile to read. 
    # When you call, the first argument is automatically added to the argument list
    # and contains the class name, so use no explicit $classname in call.
    # call this like: my $input_headfile = new headfile ("rw", "/analyzea/N12345T2W.headfile");
    # then to use your object, for example: $input_headfile->check; 

    my $self = {}; # an anonymous reference
    # WEOW No error checking, MY Favorite!.
    my $valid_modes="new|ro|rw|rc|pfile|nf|nii|nifti|nrrd";
    if ( $mode !~ /^$valid_modes$/ ){
	print STDERR "Unrecognized mode! $mode not in $valid_modes";
        return 0;
    }
    # convert nifti/nrrd shorthand so our check code is simpler
    if ( $mode eq "nii" ) {
	print STDERR "switching mode nii -> nifti, please update your code\n";
	$mode="nifti";
    } elsif ( $mode eq "nhdr" ) { 
	print STDERR "switching mode nhdr -> nrrd, please update your code\n";
	$mode="nrrd";
    }
    $self->{'__in_path'} = $in_headfile_path;
    $self->{'__mode'} = $mode;

    my %h = ();  # for values 
    $self->{'__hashref'} = \%h;
    my @c = (); # for comments 
    $self->{'__comment_arrayref'} = \@c;
    # $in_headfile_path= "/home/rja20/linux/test.headfile"; #DEBUGGING
    my $exists = `ls ${in_headfile_path} 2> /dev/null | wc -l`; # It's ridiculous to use this hack, but alas, this where we find ourselves...
    chomp($exists); # Because previous return had a newline at the end, and this not truly evaulating as '0'
    my $readable = 1;
    my $writeable = 1;

    #print "Does $in_headfile_path exist? = ${exists}\n"; #DEBUGGING

    # if (-e $in_file_path){
    if ( $exists ) { 
        #exist= = 1;
	#$readable = (-r $in_headfile_path); 
	#open(my $fh, "<","$in_headfile_path") or  $readable = 0; close($fh);
	$readable=`if [[ -r ${in_headfile_path} ]]; then echo 1; else echo 0;fi`;
	#$readable=`if [ -r ${in_headfile_path} ]; then echo 1; else echo 0;fi`;
	
	#print "Is $in_headfile_path readable? = ${readable}\n"; #DEBUGGING

	#$writeable = (-w $in_headfile_path);
	#open(my $fh2, ">","$in_headfile_path") or  $writeable = 0; close($fh2); # This will create a new file just by "checking"--unwanted behaviour!
	$writeable=`if [[ -w ${in_headfile_path} ]]; then echo 1; else echo 0;fi`;
	#$writeable=`if [ -w ${in_headfile_path} ]; then echo 1; else echo 0;fi`;

	#print "Is $in_headfile_path writable? = ${writeable}\n"; #DEBUGGING

    } elsif ( $mode eq 'new' ) {
	if ( open SESAME, ">$in_headfile_path") {
	    close SESAME;
	} else {
	    $readable = 0;
	    $writeable = 0;
	}
    }
    
    if ($mode eq 'rc') { $writeable = 1};  # this is a bit of a cheat cause we don't check that different file written to.
    $self->{'__exists'} = $exists;
    $self->{'__readable'} = $readable;
    $self->{'__writeable'} = $writeable;
    
    bless $self, $classname; # Tell $self it contains the address of an object of package classname
    return ($self); 
}

# Public Methods -------
#------------
sub check {
#------------
# do this after "new" to check headfile permissions
# returns sucess 0=fail, 1=good
    my ($self) = @_;
    my $mode = $self->{'__mode'};
    my $exists = $self->{'__exists'};
    my $readable = $self->{'__readable'};
    my $writeable = $self->{'__writeable'};
    my $ok = 0;

    my @msgs=();
    # if it should exist
    #
    
    if ($mode !~ /^n..?$/ && ! $exists ) { 
      # mode is something besides new or nf(nofile) then it must exist, 
      # So, throw error.
      # This is for any 2-3 length string starting with n
      # (cleverly omitting nifti/nrrd :D  because they're 4 and 5).
	push(@msgs,"because ! exist");
    } elsif ( $mode !~ /^n..?$/ ) { 
      # mode isnt new or nf(no file), and it exists.
	if ( ! $readable ) {
	  # all exising files must be readable!
	    push(@msgs,"becuase ! readable");
	} elsif ( $mode =~ /^r[wc]$/ && ! $writeable ) {
	  # select modes (rw,rc) must be writeable
	    push(@msgs,"because ! writeable");
	} else {
	    $ok=1;
	}
    } elsif ( $mode =~ /^n..?$/ && $exists ) {
      # mode new and nf(no file) shouldnt exist because 
      # that generates confusion.
	print "$mode \n\n\n";
	push(@msgs,"because exists"); 
    } elsif ($mode eq 'new' && ! $writeable ) {
	push(@msgs,"because ! writeable");
    } else {
	# success mode.
	$ok=1;
    }
    if ( ! $ok ) {
	print STDERR "check: not ok for $mode with headfile $self->{__in_path} \n".join("\n",@msgs)."\n";
	$self->{'__valid'}=0;
    } else {
	$self->{'__valid'}=1;
    }
    return ($ok);
}

#------------
sub read_headfile {
#------------
# returns 1 when good, else returns 0 for errors.
    my ($self) = @_;
    if ( ($self->{'__mode'} eq "ro") 
	 || ($self->{'__mode'} eq "rw") 
	 || ($self->{'__mode'} eq "rc")
	) {
	my @all_lines;
	# stream to list, open ro
	if (open SESAME, $self->{'__in_path'}) {
	    @all_lines = <SESAME>; 
	    close SESAME;
	}
	else {
	    print STDERR "Unable to open headfile to read\n"; 
	    return (0);
	}

	#--- convert list form to hash
	my $l;
	my @header_comments = ();
	my %header_hash = (); # local 
	foreach $l (@all_lines) {

	    #print STDERR "parsing $l\n";
	    my ($is_empty, $field, $value, $is_comment, $the_comment, $error) =
		private_parse_line($l);

	    if ($error) { 
		print STDERR "Unable to parse headfile $self->{'__in_path'}\n problem line: $l\n"; 
		return 0;
	    }

	    if (! $is_empty) {
		if ($is_comment) {
		    private_set_comment($self, $the_comment);
		}
		else {
		    my $temp = $value; # remove any spaces at beginning or end of value before saving
		    $temp =~ s/^\s+//; 
		    $temp =~ s/\s+$//; 
		    $value = $temp;
		    private_set_value($self, $field, $value);
		}
	    }
	}
    }
    else {
	# insert other read types here?
	#if ($self{'__mode'} !~ /^n..?/ && ! $exists ) { 
	# mode is something besides new or nf(nofile) then it must exist, 
	# So, throw error.
	print STDERR "Attempt to read new or non headfile! ".
	    "Use specific loaders ?!\n"; 
	return (0);
    }
    return (1);
}

#------------
sub get_value {
#------------
# Error return values may be EMPTY_VALUE, UNDEFINED_VALUE, NO_KEY
    my ($self, $item_name) = @_;
    my ($ok, $value) = private_get_value($self, $item_name);
    return $value;
}

#------------
sub get_value_check {
#------------
# Error return values may be EMPTY_VALUE, UNDEFINED_VALUE, NO_KEY
    my ($self, $item_name,$bool_mode) = @_;
    my ($ok, $value) = private_get_value($self, $item_name);
    if( ! defined $bool_mode || $bool_mode==1 ) {
# converts get_value_check output to bool, 0 -fail 1 -sucess
	$ok = $ok eq 'OK' ? 1 : 0 ;
    }
    return ($ok, $value);
}


#------------
sub get_value_abort {
#------------
    my ($self, $item_name) = @_;
    my ($ok, $value) = private_get_value($self, $item_name);
    if ($ok eq "ERROR") {
	print STDERR "get_value_abort: found $value looking for $item_name in headfile\n";
	exit 0;
    }
}

#------------
sub get_value_like {
#------------
    my ($ok,$value)=get_value_like_check(@_);
    return $value;
}

#------------
sub get_value_like_check {
#------------
# would have to find key which matched then get that value. 
    my ($self, $item_name) = @_;
    my @keys = ();
    my $item_like='__TRASH_KEY';
    my @sk = sort (keys %{$self->{'__hashref'}});
    foreach my $k (@sk) {
	if ( $k =~ /.*${item_name}.*/ ) {
	    $item_like=$k;
	    push(@keys,$k);
	}
    }
    #my ($ok, $value) = private_get_value($self, $item_like);
    my ($ok, $value) = get_value_check($self, $item_like);
    return ($ok,$value);
}

#------------
sub delete_key {
#------------
    my ($self, $item_name) = @_;
    delete $self->{'__hashref'}->{$item_name};
}

#------------
sub set_value {
#------------
    my ($self, $item_name, $value) = @_;
    if ($self->{'__mode'} ne "ro") {
	private_set_value ($self, $item_name, $value);
    }
    else {
	print STDERR "Refusing to set_value in \"ro\" headfile!!!\n";
	print STDERR "Run headfile object->check to head off this exit!\n";
	exit 0;
    }
}

#------------
sub set_comment {
#------------
    my ($self, $comment) = @_;
    if ($self->{'__mode'} ne "ro") {
	private_set_comment ($self, $comment);
    }
    else {
	print STDERR "Refusing to set_comment in \"ro\" headfile!!!\n";
	print STDERR "Run headfile object->check to head off this exit\n";
	exit 0;
    }
}

#------------
sub write_headfile {
#------------
    my ($self, $out_path) = @_;
    #if (($self->{'__mode'} eq "new") || ($self->{'__mode'} eq "rw") || ($self->{'__mode'} eq "rc")) 
    if ($self->{'__writeable'}) { 
	# check that file name ends in .headfile
	#return 0 unless private_check_headfile_name($self,$out_path); # THAT SEEMS AN UNNECESSARY LIMITATION
	
	# from delos: 
	# note on below: running check creates the "new" file, so -e becomes true
	# if (($self->{'__mode'} eq "new") && (-e $out_path)) {
	#   print STDERR "write_headfile ERROR: $outpath already exists but you specified mode=new\n"; 
	#   return 0;
	#}
	if ($self->{'__mode'} eq "rc") {
	    if ((-e $out_path)) {
		print STDERR "write_headfile ERROR: $out_path already exists but you specified mode=rc (write to new file)\n"; 
		return 0;
	    }
	    if ($out_path eq $self->{'__in_path'}) {
		print STDERR "write_headfile ERROR: outpath $out_path is same as in_path but you specified mode=rc (write to new file)\n"; 
		return 0;
	    }
	}
	my $SESAME;
	#my SESAME;
	#if (open $SESAME, ">$out_path") {
	if ($SESAME = IO::File->new("$out_path", ">")) { # use IO so we can pass $SESAME 
	    # add information about headfile history
	    # source headfile
	    my $infile = "new headfile";
	    if (defined $self->{'__in_path'}) {
		$infile = "input headfile " . $self->{'__in_path'}; 
	    }
	    #my ($s,$m,$h,$mday,$mon,$year,$wd,$yd,$is) = localtime(time);
	    #my $date = "$year/$mon/$mday $h:$m";
	    my $date = now_date_db();
	    set_comment($self, "# Headfile.pm version $VERSION; run $date") if $COMMENT; 
	    set_comment($self, "# Headfile.pm input headfile $infile")      if $COMMENT; 
	    set_comment($self, "# Headfile.pm this headfile $out_path")     if $COMMENT; 
	    set_value($self,"version_pm_Headfile", $VERSION);  # instead of comment
	    # increment some counter
	    my $count = get_value($self, "hfpmcnt"); 
	    if ($count eq "NO_KEY") {
		set_value($self,"hfpmcnt", 1);
	    } 
	    else {
		set_value($self, "hfpmcnt", $count+1);
	    }
	    private_write_headfile($self, $SESAME, ""); 
	    #private_write_headfile($self, SESAME, ""); 
	    close $SESAME;
	}
	else {
	    print STDERR "write_headfile ERROR: Unable to open $out_path\n"; 
	    return 0;
	}
    }
    else {
	print STDERR "Attempt to write a read only headfile\n"; 
	return 0;
    }
    print STDOUT "    write_headfile: wrote $out_path\n"; 
    return 1;
}

#------------
sub print {
    #------------
    my $self=shift;
    $self->print_headfile(@_);
}
#------------
sub print_headfile {
#------------
    #my ($self, $name) = @_;
    my $self = shift;
    my $name = shift;
    $name = defined $name ? $name : "unspecified headfile"; 
    my $fancy = " | ";
    print STDOUT "$fancy----- Print current --- $name -------------\n";;
    my $output = \*STDOUT;
    private_write_headfile($self, $output, $fancy);
    print STDOUT "$fancy----- End --- $name -----------\n";;
}

#------------
sub read_pfile_header {
#------------
    my ($self, $pfile_header_reader_app, $pfile_version) = @_;
# read pfile header into hash using streaming reader app you specify

    if ($self->{'__mode'} eq "pfile") {
	if (! -e $pfile_header_reader_app) {
	    # the headfile reader lookup in pfile_header.pm prefixes error results as shown above 
	    print STDERR "Headfile::read_pfile_header Problem finding pfile header app supplied:  $pfile_header_reader_app\n"; 
	    return 0;
	}

	my @all_lines;
	# assume this reader app program dumps to standard output
	# stream to list
	if (open SESAME, "$pfile_header_reader_app $self->{'__in_path'} |") {
	    @all_lines = <SESAME>;
	    close SESAME;
	} else {
	    print STDERR "Unable to open pfile to read\n";
	    return (0);
	}

	#--- convert list form to hash

	my $l;
	my @header_comments = ();
	my %header_hash = (); # local
	foreach $l (@all_lines) {
	    #print STDERR "parsing $l\n";
	    my ($is_empty, $field, $value, $is_comment, $the_comment, $error) =
		private_parse_line($l);
	    if ($error) {
		print STDERR "Unable to parse headfile $self->{'__in_path'}\n problem line: $l\n";
		return 0;
	    }
	    if (! $is_empty) {
		if ($is_comment) {
		    private_set_comment($self, $the_comment);
		}
		else {
		    private_set_value($self, $field, $value);
		}
	    }
	}
    }
    else {
	print STDERR "Attempt to read headfile as a pfile\n";
	return (0);
    }

    private_set_value($self, "S_header_source", $pfile_version);

    return (1);

}
#------------
sub read_nii_header {
#------------
    my ($self, $nii_header_reader_app, $nii_version) = @_;
# read nii header into hash using streaming reader app you specify
    if ($self->{'__mode'} =~ /nii|nifti/x ) {
	if (! -e $nii_header_reader_app) {
	    # the headfile reader lookup in nii_header.pm prefixes error results as shown above 
	    print STDERR "Headfile::read_nii_header Problem finding nii header app supplied:  $nii_header_reader_app\n"; 
	    return 0;
	}
	my @all_lines=`$nii_header_reader_app $self->{'__in_path'}  | sed -e's/  */ /g' | sed -e's/ /=/'`;
	# assume this reader app program dumps to standard output
	# stream to list
	#--- convert list form to hash
	my $l;
	my @header_comments = ();
	my %header_hash = (); # local
	foreach $l (@all_lines) {
	    #print STDERR "parsing $l\n";
	    my ($is_empty, $field, $value, $is_comment, $the_comment, $error) =
		private_parse_line($l);
	    if ($error) {
		print STDERR "Unable to parse headfile $self->{'__in_path'}\n problem line: $l\n";
		return 0;
	    }
	    if (! $is_empty) {
		if ($is_comment) {
		    private_set_comment($self, $the_comment);
		}
		else {
		    private_set_value($self, $field, $value);
		}
	    }
	}
    }
    else {
	print STDERR "Attempt inapropriate to read as a nifti\n";
	return (0);
    }
    private_set_value($self, "S_header_source", $nii_version);
    return (1);
}
#------------
sub read_nrrd_header {
#------------
    my ($self, $header_reader_app, $reader_version) = @_;
# read nrrd header into hash using streaming reader app you specify
    if ($self->{'__mode'} =~ /nrrd|nhdr/x ) {
	if (! -e $header_reader_app) {
	    # the headfile reader lookup in header.pm prefixes error results as shown above 
	    print STDERR "Headfile::read_nrrd_header Problem finding header app supplied:  $header_reader_app\n"; 
	    return 0;
	}
	
	my $OS_OPTS="-r";
	if ($OSNAME =~ /^darwin$/x ){
	    $OS_OPTS="-E";
	}
	# Sed line -r not okay for mac os need to slip in -E
	my @all_lines=`$header_reader_app head $self->{'__in_path'}  | sed -e's/  */ /g' | sed $OS_OPTS -e's/:=?/=/'`;
	# assume this reader app program dumps to standard output
	# stream to list
	#--- convert list form to hash
	my $l;
	my @header_comments = ();
	my %header_hash = (); # local
	foreach $l (@all_lines) {
	    #print STDERR "parsing $l\n";
	    my ($is_empty, $field, $value, $is_comment, $the_comment, $error) =
		private_parse_line($l);
	    if ($error) {
		print STDERR "Unable to parse headfile $self->{'__in_path'}\n problem line: $l\n";
		return 0;
	    }
	    if (! $is_empty) {
		if ($is_comment) {
		    private_set_comment($self, $the_comment);
		}
		else {
		    private_set_value($self, $field, $value);
		}
	    }
	}
    }
    else {
	print STDERR "Attempt inapropriate to read as a nrrd\n";
	return (0);
    }
    private_set_value($self, "S_header_source", $reader_version);
    return (1);
}

#------------
sub get_keys {
#------------
    my ($self) = @_; 

    my @sk = sort (keys %{$self->{'__hashref'}});
    return ( @sk);

    # seriously.... this shit.....
    if ( 0 ) {
	my @keys = ();    
    foreach my $k (@sk) {
	push @keys, $k;
    }
    return @keys;
    }
}

# private subroutines -----------

sub private_write_headfile {
    my ($self, $file_handle, $fancy) = @_;
    # comments
    foreach my $comment (@{$self->{'__comment_arrayref'}}) {
	print $file_handle "$fancy$comment\n";  # add nl back
    }
    # items 
    my @sk = sort (keys %{$self->{'__hashref'}});
    foreach my $k (@sk) {
	my $value=$self->{'__hashref'}->{$k};
	print $file_handle "$fancy$k=$value\n";
    }
}

sub private_parse_line {
    my ($ln) = @_;  
    my $is_empty = 0;
    my $field ="";
    my $value="";
    my $is_comment=0;
    my $comment="";
    my $error=0;
    my $debug = 0;
    print "\nparse line:$ln" if $debug;
    $ln =~ s/\r//;
    $ln =~ s/\n//;
    print "\n chomped line:$ln   \n" if $debug;

    if ($ln =~ /^#/) {
	# comment
	$is_comment = 1;
	## don't leave returns on comment lines
	##print "BEFORE: $ln|||";
	# get rid of cr
	chomp ($ln);
	# get rid of any remaining white space at end of $ln
	$ln =~ s/\s*$//;
	##print "AFTER: $ln|||";
	$comment=$ln;
	print " sub line is comment: $ln" if $debug;
    } elsif ($ln =~ /\w/) {
	chomp ($ln);
	($field, $value) = split /=/, $ln, 2 ;
	# get rid of any white space at end of $field
	$field =~ s/\s*$//;
	# convert whitespace in fieldname to underscores
	$field =~ s/(.+)\s+(.+)/$1_$2/gx;
	# get rid of any white space at start of $value
	$value =~ s/^\s*//;
	print " sub line is field: $ln : $field, $value" if $debug;
    } else {
	# skip whitespace
	print " sub line is whitespace: $ln" if $debug;
	$is_empty = 1;
    }

    # so far catches no errors...
    return ($is_empty, $field, $value, $is_comment, $comment, $error);
}

#------------
sub private_set_value {
#------------
    my ($self, $item_name, $value) = @_;
    $self->{'__hashref'}->{$item_name} = $value;
}

#------------
sub private_set_comment {
#------------
    my ($self, $comment) = @_;
    # this may be a new comment not read from file
    # check that comment starts with a # sign
    if (defined $comment) {
	if ($comment !~ /^#/) {
	    print STDERR "WARNING set_comment: comment added to headfile did not have leading #; leading # was added!!!\n";
	    print STDERR "BAD comment was: $comment\n";
	    $comment = "# " . $comment;
	}
	push @{$self->{'__comment_arrayref'}}, $comment;
    }
    else { print STDERR "WARNING set_comment: undefined comment\n";}
}

#------------
sub private_check_headfile_name {
#------------
    my ($self, $headfile_path) = @_;
    if (($headfile_path !~ /\.headfile$/)) { # doesnt end in .headfile...
	print STDERR "  PROBLEM: headfile name must end in .headfile\n";
	return 0;
    }
    return 1;
}

#------------
sub private_get_value {
#------------
    my ($self, $item_name) = @_;
    my $ri;
    if (exists $self->{'__hashref'}->{$item_name}) { 
	if (defined $self->{'__hashref'}->{$item_name}) { 
	    $ri = $self->{'__hashref'}->{$item_name};
	}
	else {
	    return ("ERROR","UNDEFINED_VALUE"); 
	}
	# should this be an error?
	if ($ri eq "") {
	    return ("ERROR", "EMPTY_VALUE");
	}
    }
    else {
	return ("ERROR", "NO_KEY");
    }
    return ("OK", $ri);
}

#------------
sub now_date_db {
#------------
#  this function should probablypi be part of archive support. 
#  this will now be replicated into pipeline utilities?
    ##my $DATE_FORMAT = "\'YY-MM-DD HH24:MI:SS\'";
    my ($s,$m,$h,$mday,$mon,$year,$w,$y,$isdst) = localtime(time);
    if ( 1 ) {
	return sprintf('%02i-%02i-%02i %02i:%02i:%02i',
		       $year - 100,$mon+1,$mday,
		       $h,$m,$s);
    } else {
	# old unduely complicated code.
	$year = private_padder($year - 100, 2);
	$mon  = private_padder($mon+1, 2);
	$mday = private_padder($mday, 2);
	$h = private_padder($h, 2);
	$m = private_padder($m, 2);
	$s = private_padder($s, 2);
	my $date = "$year-$mon-$mday $h\:$m\:$s";
	#return ("TO_DATE(\'$date\',$DATE_FORMAT)");
	return ($date);
    }
}

#------------
sub private_padder
#------------
{
    require Carp;
    Carp->import(qw(cluck));
    cluck("OBSOLETE FUNCTION DETECTED private_padder !!! ");
### This appears to replicate the ability of sprintf #
# to print constant length number strings with leading zeros's
# It appears to Only be used in the now_data_db function.
    my ($n, $npad) = @_;
    my $start = 10 ** $npad;
    if ($n >= $start)  {
	return (0, "Cannot pad $n with $npad digits");
    }
    my $zeros = ("0" x $npad);  # at least enough even for 0
    my @backwards = split (//,$zeros);  # at least enough even for 0
    my @digits = split (//,$n);
    my $max = $#digits;
    #print "given digit max = $max\n";
    for my $i (0 .. $max) {
	my $c =  shift(@digits);
	unshift (@backwards, $c);
	#print "nabbed $c, @backwards\n";
    }

    my @result = ();
    for my $i (0..($npad-1)) {
	my $c =  shift(@backwards);
	unshift (@result, $c);
	#print "taking $c, @result\n";
    }

    my $p = join ('',@result);
    #print "padded = $p\n";

    return (1, $p);
}

#------------
sub copy_in {
#------------
# copy the fields of provided hf into this hf
# this will overwrite shared fields in this hf
# prefix and postfix can be used to control that behavior
    my ($self, $other_hf,$prefix, $postfix) = @_;
    my @keys = $other_hf->get_keys();
    if ( ! defined ($prefix)) {
	$prefix='';
    }
    if ( ! defined ($postfix)) {
	$postfix='';
    }
    foreach my $k (@keys) {
	private_set_value($self, $prefix.$k.$postfix, $other_hf->get_value($k));
    }
    # also copy the comments from other_hf to self
    #foreach my $comment (@{$other_hf->{'__comment_arrayref'}}) {
    #  $comment =~ s/\s*$//; # remove newline
    #  private_set_comment($self, "$comment");
    #}
}

#------------
sub copy_in_comments {
#------------
# copy the comments of provided hf into this hf
# this could duplicate comments if they are already in this hf....
    my ($self, $other_hf) = @_;
    # copy the comments from other_hf to self
    foreach my $comment (@{$other_hf->{'__comment_arrayref'}}) {
	$comment =~ s/\s*$//; # remove newline
	private_set_comment($self, "$comment");
	#print STDERR "COPIED IN COMMENT: $comment\n";
    }
}

#------------
sub all_group_types {
#------------
# return list of all types by looking at all items like group_id[a_group_type]=idvalue.
# a particular run/headfile may be in several groups
    my ($self) = @_;
    my @keys = $self->get_keys();
    my @group_types = ();
    foreach my $item (@keys) {
	if ($item =~ /^group_id/) {
	    $item =~ /\[(\w+)\]/;
	    push @group_types, $1;
	}
	#my $value=$self->{'__hashref'}->{$item};
    }
    return (@group_types);
    
}

#------------
sub all_group_ids {
#------------
# return list of all groupids from items like group_id[all_types]=groupid.
# a particular run/headfile may be in several groups
    my ($self) = @_;
    my @group_types = $self->all_group_types;
    my @group_ids = ();
    foreach my $type (@group_types) {
	my $item_name = "group_id[$type]";
	my ($ok, $idvalue) = private_get_value($self, $item_name);
	push @group_ids, $idvalue;
    }
    return(@group_ids);
}

#------------
sub group_type {
#------------
# return the grouptype for a particular groupid from the item like group_id[grouptype]=provided_group_id.
# a particular run/headfile may be in several groups
    my ($self,$provided_group_id) = @_;
    my @keys = $self->get_keys();
    foreach my $item (@keys) {
	if ($item =~ /^group_id/) {
	    my ($ok, $idvalue) = private_get_value($self, $item);
	    if ($idvalue eq $provided_group_id) { 
		$item =~ /\[(\w+)\]/;
		return ($1);
	    }
	}
    }
    return (undef);
}

#------------
sub group_runno {
#------------
# return the runno for a particular grouptype from the item like group_runno[provided_group_type]=runno.
    my ($self,$group_type) = @_;
    my $item = "group_runno[$group_type]";
    my ($ok, $runno) = private_get_value($self, $item);
    if ($ok) { return ($runno) }
    else { return (undef); }
}

#------------
sub group_value {
#------------
# get the value in the group's dimension, if any
    # check both storage methods.  If both (kind of an error) return the group_dim_value[] setting
    my ($self,$group_type) = @_;
    # try direct setting
    my $item = "group_dim_value[$group_type]";
    my $ok = "NOT";
    my $direct_value;
    ($ok, $direct_value) = private_get_value($self, $item);
    ##print STDERR "group type $group_type\n   direct_value = $direct_value, $ok, item= $item\n";
    if ($ok eq "ERROR") {
	# try indirect setting, via group_dim_hf_param
	$item = "group_dim_hf_param[$group_type]";
	my ($ok2, $hf_parameter) = private_get_value($self, $item);
	my ($ok3, $indirect_value) = private_get_value($self, $hf_parameter);
	##print STDERR "   indirect_value = param: $hf_parameter, $ok2, value: $indirect_value, $ok3\n";
	if ($ok3 ne "ERROR") {
	    return ($indirect_value)
	}
	else {
	    return (undef)
	}
    }
    else { return ($direct_value) }
}




1;
