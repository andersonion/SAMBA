use warnings;
use strict;
our $GITHUB_BASE='git@github.com:jamesjcook/'; 
our $GITHUB_SUFFIX='.git';
sub svn_externals () {
    my $mode = shift;
###
# check if we're an svn or git project.
###
    my $svnout=`svn info`;
    if ( ! $? ) {
	print ("svn true\nuse command : svn update for code updates\n");
	
	return 1;
    } else {
	print("svn false, assuming git, checking on svn.externals\n");
    }

    my $do_work=0;
    my $work_done=0;
    if( $mode ){
	print ("force\t");
	$do_work=$mode;
    } elsif(!$work_done ) {
	$do_work=1;
    }

###
# if we're a git project find all .svn.externals 
###
    my @svn_externals=`find . -name ".svn.externals" -maxdepth 1`;
    chomp @svn_externals;
###
# for each .svn.externals go to that folder and try to find project on jamesjcook github.
###

    print("svn_externals\n");
    #if ( $OS =~ /^darwin$/ ){
    for my $ext (@svn_externals) {
	process_external_file($ext);
    }


    die "End of svn_externals hard stop";
    
    return 1;
}
sub process_external_file() {
    my $infile =shift;
    print("\tfile $infile\n");
    my $INPUT;
    my $found=0;
    my $pattern='[\w]+[\s]+'.
	'(?:svn(?:\+ssh)?)|http|file'.
	':\/\//x'; #svn_external_regex
    my $c_dir=`pwd`; chomp $c_dir;
    my $checkout_dir=dirname($infile);
    if (-f $infile ){
	open($INPUT, $infile) || warn "Error opening $infile : $!\n";
	#print("looking up pattern $pattern in file $infile\n");
	chdir $checkout_dir;
	print("working on externals in $checkout_dir\n");
	while(<$INPUT>) {
	    #if ( $_ ~ m/[\w]+[\s]+(?:svn(?:+ssh)?)|http|file:\/\//x) {
	    chomp;
	    if ( $_ =~m/$pattern/x) {
		process_external_deff($_);
		$found += 1;
		# exit; # put the exit here, if only the first match is required
	    } else {
		print "nomatch ".$_;
	    }
	}
	close($INPUT);
	chdir $c_dir;
	print ("processed $found externals in $infile. Going back to $c_dir.\n");
    } else {
	print("Bogus input file $infile.\n");
    }
    return;
	
}
sub process_external_deff(){
    my $ext_def=shift;
    
  
    #svn_external_regex
    my( $local_name,$url_type,$svnpath_string)= $ext_def =~ /^([\w]+)[\s]+
    ((?:svn(?:\+ssh)?)|http|file):\/\/
    ((?:[\w.-]+[\/\\]?)+)/gx;
    print("name:$local_name type:$url_type repo_path:$svnpath_string\n");
    my @svnpath=split ('/',$svnpath_string);
    my $git_project='UNKNOWN';
    my $git_url='UNKNOWN';
    if ( $svnpath[$#svnpath] =~ m/trunk/x ) {
	$git_project=$svnpath[$#svnpath-1];
    }
    $git_url=$GITHUB_BASE.$git_project.$GITHUB_SUFFIX;
    if ( ! -d $local_name ){
	print ( "git fetch $git_url $local_name\n");
    } else {
	print ("update from git\n");
    }
   
#     $ext_def =~ /^([\w]+)[\s]+
#     ((?:svn(?:\+ssh)?)|http|file):\/\/
#     ([\w.-]+[\/\\]?)+$/x;
#     my $local_name2 = $1;
#     my $url_type2 = $2;
#     my @svnpath = $3;


#    print("name:$local_name2 type:$url_type2 repo_path:".join("::",@svnpath)."\n");    
    
    return;
}

1;
