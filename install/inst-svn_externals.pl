use warnings;
use strict;
use Scalar::Util qw(looks_like_number);


our $GITHUB_BASE='https://github.com/jamesjcook/'; 

if (getpwuid( $< ) eq "james" ){
    $GITHUB_BASE='git@github.com:jamesjcook/'; 
}

our $GITHUB_SUFFIX='.git';
#https://github.com/jamesjcook/workstation_code.git
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

    if (! defined $mode ) {$mode=0;}
    if ( ! looks_like_number($mode) ) {

	if ($mode =~ /quiet/x ){
	print ("$mode\t");
	    $mode=-1;
	} elsif ($mode =~ /silent/x ){
	print ("$mode\t");
	    $mode=-2;
	} elsif ($mode =~ /nosvn/x ){
	print ("$mode\t");
	    $mode=2;
	}
    }
    if( looks_like_number($mode) ){
	if ($mode>0 ) {
	    print ("force\t");
	    $do_work=$mode;
	} elsif(!$work_done ) {
	    $do_work=1;
	}
    } else {
	if(!$work_done ) {
	    $do_work=1;
	}

    }

###
# if we're a git project find all .svn.externals 
###
    my @svn_externals=`find . -name ".svn.externals"`; # -maxdepth 2`; while testing this was used.
    
    chomp @svn_externals;
###
# for each .svn.externals go to that folder and try to find project on jamesjcook github.
###

    print("svn_externals\n");
    #if ( $OS =~ /^darwin$/ ){
    for my $ext (@svn_externals) {
	process_external_file($ext,$mode);
    }

#    die "End of svn_externals hard stop";
    
    return 1;
}
sub process_external_file() {
    my $infile =shift;
    my $mode=shift;

    print("\tfile $infile\n")unless $mode <= -1;
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
	print("\tworking on externals in $checkout_dir\n") unless $mode <= -1;
	while(<$INPUT>) {
	    #if ( $_ ~ m/[\w]+[\s]+(?:svn(?:+ssh)?)|http|file:\/\//x) {
	    chomp;
	    if ( $_ =~m/$pattern/x) {
		process_external_deff($_,$mode);
		$found += 1;
		# exit; # put the exit here, if only the first match is required
	    } else {
		print "  nomatch ".$_  unless $mode <= 0;
	    }
	}
	close($INPUT);
	chdir $c_dir;
	print ("\tprocessed $found externals in $infile. Going back to $c_dir.\n") unless $mode <= -1;
    } else {
	print("  Bogus input file $infile.\n")unless $mode <= -1;
    }
    return;
	
}

sub process_external_deff(){
    my $ext_def=shift;
    my $mode=shift;
  
    #svn_external_regex
    my( $local_name,$url_type,$svnpath_string)= $ext_def =~ /^([\w]+)[\s]+
    ((?:svn(?:\+ssh)?)|http|file):\/\/
    ((?:[\w.-]+[\/\\]?)+)/gx;
    #print("\t\tname:$local_name type:$url_type repo_path:$svnpath_string\n");
    my @svnpath=split ('/',$svnpath_string);
    my $git_project='UNKNOWN';
    my $git_url='UNKNOWN';
    my $branch='UNKNOWN';
    my $c_dir=`pwd`;chomp $c_dir;
    my @errors=();

    ### get standard parts of repository name.
    if( 0 ) {
	# this is our first pass at getting the stuff. 
	if ( $svnpath[$#svnpath] =~ m/trunk/x ) {
	    $git_project=$svnpath[$#svnpath-1];
	    $branch='master';
	} elsif ( $svnpath[$#svnpath-1] =~ m/tags|branches/x ) {
	$git_project=$svnpath[$#svnpath-2];
	if ( $svnpath[$#svnpath-1] =~ m/branches/x ) {
	    push(@errors,"Error in svn.externals processing. Branches not supported from svn.externals\n \t$svnpath_string\n");
	} else {
	    $branch = $svnpath[$#svnpath-1];
	}
	} else {
	    $branch='';
	}
    } else {
	my $p_idx;
	my $sp_idx=0;
	do {
	    my $d_name = $svnpath[$sp_idx];
	    if ($d_name =~ m/trunk/x ) {
		$p_idx=$sp_idx-1;
		$branch='master';	    
	    }elsif ($d_name =~ m/tags/x ) {
		$p_idx=$sp_idx-1;
		$branch=$svnpath[$sp_idx+1] unless $p_idx+1>$#svnpath;
		push(@errors,"Error in svn.externals processing. Branches not supported from svn.externals\n \t$svnpath_string branch:$branch\n");
	    }elsif ($d_name =~ m/branches/x ) {
		$p_idx=$sp_idx-1;
		$branch=$svnpath[$sp_idx+1] unless $p_idx+1>$#svnpath;
	    } else { 
#		print("\tnomatch $d_name\n");
	    }
	    $sp_idx++;
	} while ( ! defined $p_idx && $sp_idx<=$#svnpath);
	if( defined ($p_idx) ) {
	    $git_project=$svnpath[$p_idx];
	    #$branch=
	} else { 
	    push(@errors, "Error getting the get project from the svn url\n");
	}
    }

    $git_url=$GITHUB_BASE.$git_project.$GITHUB_SUFFIX;
    #    my( $local_name,$url_type,$svnpath_string)
    my $svn_url=$url_type.'://'.$svnpath_string; #$git_project.$GITHUB_SUFFIX;
    # could insert svn user here 
    my @cmd_list;
    if ( $git_project !~ /UNKNOWN/x && $local_name !~ /UNKNOWN/x && $branch !~ /UNKNOWN/x ) {
	if ( ! -d $local_name ){
	    my $clone_cmd="git clone $git_url $local_name";
	    print ("  \t$clone_cmd\n")unless $mode <= 0;
	    my @output=`$clone_cmd 2>&1`;
	    if ( ! -d $local_name && $branch !~ /master/x ){	    
		chdir $local_name;
		my $checkout_cmd="git checkout $branch";
		`$checkout_cmd`;
		print ("  \t$checkout_cmd\n")unless $mode <= 0;
		chdir $c_dir;
	    } else {
		push (@errors, "Error cloning $git_url to $local_name\n".join("\t\t",@output)) unless $mode <= -1;
		push (@errors, "\t ATTEMPTING Subversion! for $local_name from $svn_url\n");
		my $svn_checkout_cmd="svn checkout ".$svn_url." ".$local_name unless $mode >=2;
		print ("  \t$svn_checkout_cmd\n")unless $mode <= 0;
		my @output = `$svn_checkout_cmd 2>&1`;
		if ( ! -d $local_name ) {
		    push(@errors ,"\tsubversion FAIL!.".join("\t\t".@output)."\n");
		}
	    }
	} else {

	    chdir $local_name;
	    my $svnout=`svn info `;
	    if ( ! $? ) {
		#return 1;
		print ("svn update\n");
		`svn update` unless $mode >=2;
	    } else {
		print("svn false, assuming git. \n");
	    }
	    
	    @cmd_list=();
	    my $c_branch=`git symbolic-ref --short HEAD`;
	    if ( $c_branch !~  /master/x) {
		push(@errors,"ERROR: current project $git_project NOT on master !, You must be on master to update! Currently on $c_branch instead.\n");
	    } else {
		#git symbolic-ref --short HEAD
		#git rev-parse --abbrev-ref HEAD
		push(@cmd_list,"git stash");
		push(@cmd_list,"git pull");
		push(@cmd_list,"git stash pop");

		print ("\t\tupdate from git\n")unless $mode <= 0;
		for my $cmd (@cmd_list ) {
		    `$cmd`;
		}
	    }
	    chdir $c_dir;
	}
	if (-d $local_name ) {
	    check_add_gitignore($local_name);
	}
    } else {
	push (@errors, "error with git_name, local_name or branch.git_name=$git_project, Localname=$local_name, branch=$branch\n");
    }
#     $ext_def =~ /^([\w]+)[\s]+
#     ((?:svn(?:\+ssh)?)|http|file):\/\/
#     ([\w.-]+[\/\\]?)+$/x;
#     my $local_name2 = $1;
#     my $url_type2 = $2;
#     my @svnpath = $3;


#    print("name:$local_name2 type:$url_type2 repo_path:".join("::",@svnpath)."\n");    
    if ( $#errors>=0) {
	print @errors unless $mode <= -2;
    }
    return;
}

sub check_add_gitignore () {
    my $pattern=shift;

    my $INPUT;
    my $found=0;
    
    my $infile='.gitignore';
    my $gitigline='';
    open($INPUT, $infile) || (warn "Error opening $infile : $!\n" and $gitigline=".gitignore\n");
    #print("looking up pattern $pattern in file $infile\n");
    #if(tell(FH) != -1)
    if (-f $infile ){
    while(<$INPUT>) {
	#if ( $_ ~ m/[\w]+[\s]+(?:svn(?:+ssh)?)|http|file:\/\//x) {
	chomp;
	if ( $_ =~m/$pattern/x) {
	    $found += 1;
	    # exit; # put the exit here, if only the first match is required
	} else {
	    #print "  nomatch ".$_;
	}
    }
    }
    close($INPUT);
    if ( $found <=0 ) {
	my $FILE;
	open ($FILE, ">>",$infile) || die "Could not open file: $!\n";
	print $FILE $gitigline."$pattern\n";
	close $FILE;
    }
    return;
}
1;
