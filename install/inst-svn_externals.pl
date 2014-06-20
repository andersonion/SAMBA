use warnings;
#use strict;
use Scalar::Util qw(looks_like_number);
our %ML=(
    'rmsvn'    =>  3,
    'nosvn'    =>  2,
    'force'    =>  1,
    'normal'   =>  0,
    'quiet'    => -1,
    'silent'   => -2,
);


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
    my $proj_is_svn=! $?;
    if ( $proj_is_svn ) {
	print ("svn true\nuse command : svn update for code updates\n");
	
	return 1;
    } else {
	print("svn false, assuming git, checking on svn.externals\n");
    }

    my $do_work=0;
    my $work_done=0;

    if (! defined $mode ) {$mode=0;}
    if ( ! looks_like_number($mode) ) {
	if ( $mode =~ /:/x ){
	    print ("\tERROR: tried to have multiple values for mode in svn_externals processing\n");
	}
	if ($mode =~ /^quiet$/ix ){
	print ("$mode\t");
	    $mode=$ML{'quiet'};
	} elsif ($mode =~ /^silent$/ix ){
	print ("$mode\t");
	    $mode=$ML{'silent'};
	} elsif ($mode =~ /^no[-]?svn$/ix ){
	print ("$mode\t");
	    $mode=$ML{'nosvn'};
	} elsif ($mode =~ /^rm[-]?svn$/ix ){
	print ("$mode\t");
	    $mode=$ML{'rmsvn'};
	}
    }
    if( looks_like_number($mode) ){
	if ($mode == $ML{'force'} ) {
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
    # mode gets collapsed into an integer value, related to the verbosity of this script.
    # mode 2, git only!, do not attempt to get projects through subversion.
    # mode 1, force all parts on
    # mode 0, normal, skip finishd portions.
    # mode -1, "quit" mode, be less chatty.
    # mode -2  "silent" mode, be even less chatty.
    

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
    `chmod u+x $MAIN_DIR/*.bash`;
#    die "End of svn_externals hard stop";
    return 0;
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
	# separate svn project by path component, 
	# loop while we dont see the standard elements of an svn path(trunk/branches/tag), 
	# on finding those, set p_idx(projectname) to 1 less than that, and set the sp_idx to that point. 
	if ( 0 ) {
	    do {
		my $d_name = $svnpath[$sp_idx];
		if ($d_name =~ m/trunk/x ) {
		    $p_idx=$sp_idx-1;
		    $branch='master';	    
		} elsif ($d_name =~ m/tags/x ) {
		    $p_idx=$sp_idx-1;
		    $branch=$svnpath[$sp_idx+1] unless $sp_idx+1>$#svnpath;
		    push(@errors,"Error in svn.externals processing. Tags not supported from svn.externals\n \t$svnpath_string branch:$branch\n");
		} elsif ($d_name =~ m/branches/x ) {
		    $p_idx=$sp_idx-1;
		    $branch=$svnpath[$sp_idx+1] unless $sp_idx+1>$#svnpath;
		} elsif ($#sp_idx==$#svnpath) {# this is failover for non-standard repo layouts .
		    $p_idx=$sp_idx;
		    $branch='master';
		    print("\tNon-standard repo contidion, $d_name\n");
		}else { 
		    print("\tnomatch $d_name\n");
		}
		$sp_idx++;
	    } while ( ! defined $p_idx && $sp_idx<=$#svnpath+1);
	    if( defined ($p_idx) ) {
		$git_project=$svnpath[$p_idx];
		#$branch=
	    } else { 
		push(@errors, "Error getting the a git project name from the svn url\n");
	    }
	} else {
	    #if ($svnpath_string =~ m#^(?:.*)/(.*)/(?:trunk|branches|tags)/(.*)/?\s*$:b#x ){
	    #print ("Testing svnurplpath $svnpath_string \n");
	    if ($svnpath_string =~ m/^(?:.*)\/(.*)\/(?:trunk|branches|tags)(?:\/(.*))?\s*/x ){
		$git_project=$1;
		$branch=defined $2 ? $2 : "master";
		#print("urlparsing returned project $git_project, branch $branch\n");
	    } else {
		$git_project=$svnpath[$#svnpath];
		$branch="master";
		#print("urlparsing returned project $git_project, branch $branch\n");
	    }
	    if($git_project eq "UNKNOWN") { push(@errors, "Error getting the a git project name from the svn url\n"); }
		
	}
    }
    


    $git_url=$GITHUB_BASE.$git_project.$GITHUB_SUFFIX;
    #    my( $local_name,$url_type,$svnpath_string)
    my $svn_url=$url_type.'://'.$svnpath_string; #$git_project.$GITHUB_SUFFIX;
    if ( $mode == $ML{nosvn} ) {
	$svn_url="SVNDISABLED";
    }
    # could insert svn user here 
    my @cmd_list;
#     use Cwd 'abs_path';
#     use File::Basename;
#     use Cwd 'abs_path';
#     print (" setting svn uninst starting with ".abs_path($0)."\n");
    use File::Basename;
    my $dirname = dirname(__FILE__);
    #my $svn_uninstfile=dirname(__FILE__)."/uninstall_svn_externals.bash";
    my $svn_uninstfile=$MAIN_DIR."/uninstall_svn_externals.bash";
    my $git_uninstfile=$MAIN_DIR."/uninstall_git_projects.bash";
    if (! CheckFileForPattern($MAIN_DIR."/.gitignore","^".basename($git_uninstfile)) ) {
	FileAddText($MAIN_DIR."/.gitignore",basename($git_uninstfile)."\n"); }
    if (! CheckFileForPattern($MAIN_DIR."/.gitignore","^".basename($svn_uninstfile)) ) {
	FileAddText($MAIN_DIR."/.gitignore",basename($svn_uninstfile)."\n"); }
    my $project_rm="rm -fr $c_dir/$local_name";
    my $update_line="";
    my $status_line="";
    my $code_updatefile=$MAIN_DIR."/update_code.bash";;
    if (! CheckFileForPattern($MAIN_DIR."/.gitignore","^".basename($code_updatefile)) ) {
	FileAddText($MAIN_DIR."/.gitignore",basename($code_updatefile)."\n"); }
    my $code_statusfile=$MAIN_DIR."/find_modified_code.bash";
    if (! CheckFileForPattern($MAIN_DIR."/.gitignore","^".basename($code_statusfile)) ) {
	FileAddText($MAIN_DIR."/.gitignore",basename($code_statusfile)."\n"); }
    if ( $git_project !~ /UNKNOWN/x && $local_name !~ /UNKNOWN/x && $branch !~ /UNKNOWN/x ) {
	### 
	# download code from git or svn
	###
	if ( ! -d $local_name ){
	    my $clone_cmd="git clone $git_url $local_name";
	    print ("  \t$clone_cmd\n")unless $mode <= 0;
	    my @output=`$clone_cmd 2>&1`;
	    if ( -d $local_name ) {
		chdir $local_name;
		if ( $branch !~ /master/x ){	    
		    my $checkout_cmd="git checkout $branch";
		    my @output=`$checkout_cmd`;
		    print ("  \t$checkout_cmd\n")unless $mode <= 0;
		    if ( ! -d $local_name ) {
			push(@errors ,"\tgit FAIL!.".join("\t\t".@output)."\n");
		    }
		}
		$git_url=~ s|https://|ssh://git@|x;
		#git@github.com:jamesjcook/$git_project.$GITHUB_SUFFIX
		my $url_set_cmd="git remote set-url --push origin $git_url ";
		print ("\tchanging push url with:$url_set_cmd\n") unless $mode<0;
		my @us_out=`$url_set_cmd `;
		push(@errors ,"\tgit FAIL on remote set with message, <".join("\t\t".@us_out).">\n") if($#us_out>=0 || $? != 0);
		chdir $c_dir;
	    } elsif ( ! -d $local_name ) {
		push (@errors, "Error cloning $git_url to $local_name\nwith git cmd \n\t$clone_cmd\n message:".join("\t\t",@output)) unless $mode <= -1;
		push (@errors, "\t ATTEMPTING Subversion! for $local_name from $svn_url\n");
		my $svn_checkout_cmd="svn checkout ".$svn_url." ".$local_name ;
		print ("  \t$svn_checkout_cmd\n") unless $mode <= 0 ;
		my @output = `$svn_checkout_cmd 2>&1` unless $mode ==$ML{nosvn};
		if ( ! -d $local_name ) {
		    push(@errors ,"\tsubversion FAIL!.".join("\t\t".@output)."\n");
		}
	    }

	} 
	
	###
	# add an update line to a code udpater
	###
	# if code has been downloaded sucessfully

	if (  -d $local_name ) {
	    # dir exists, we've gotten it at least once.
	    check_add_gitignore($local_name);
	    chdir $local_name;
	    my $svnout=`svn info `;#return code is 1 for error from program output, eg, not svn. 
	    my $is_svn=! $?;
	    
	    if ( $is_svn ){ #double negative aweful condition 
		print("---WARNING---:");
		print("- SVN PROJECT -\n");
		if ( $mode == $ML{rmsvn} ){
		    print("!!!RMSVN MODE!!!\n");
		    
		    `$project_rm`;
		} else {
		    
		    if ( ! CheckFileForPattern($svn_uninstfile,"$project_rm") ) {
			print ("adding rm instructions to $svn_uninstfile\n");
			FileAddText($svn_uninstfile,"$project_rm\n");
		    }
		    $update_line="cd $c_dir/$local_name; echo -- update $local_name -- ; svn update;";
		    $status_line="cd $c_dir/$local_name; echo -- status $c_dir/$local_name -- ;echo -- $local_name --; svn status;";
		    print("  updating svn project:$local_name\n");
		    `$update_line` unless $mode ==$ML{nosvn};
		}
	    } elsif ( ! $is_svn ){
		print("- GIT project -\n");
		print("    svn false, assuming git. \n");
		@cmd_list=();
		#my $git_check_branch_cmd="git symbolic-ref --short HEAD";
		my $git_check_branch_cmd="git rev-parse --abbrev-ref HEAD|tail -n 1";
		print ("\t branch checking with : $git_check_branch_cmd\n") unless $mode <0;
		my $c_branch=`$git_check_branch_cmd`;
		my $is_git= ! $?;
		if ( $c_branch !~  /master/x) {
		    push(@errors,"ERROR: current project $git_project NOT on master !, You must be on master to update! Currently on $c_branch instead.\n");
		} elsif($is_git) {
		    #git symbolic-ref --short HEAD
		    #git rev-parse --abbrev-ref HEAD
		    my $g_abspath=`pwd`;
		    chomp($g_abspath);
		    push(@cmd_list,"cd $c_dir/$local_name");
		    push(@cmd_list,"echo \"-- update $local_name --\" ");
		    push(@cmd_list,"git stash");
		    push(@cmd_list,"git pull");
		    push(@cmd_list,"git stash pop");
		    #print ("\t\tupdate from git\n")unless $mode <= 0;
		    $update_line=join(';',@cmd_list);#."\n";
		    $status_line="cd $c_dir/$local_name; echo -- status $c_dir/$local_name -- ;echo -- $local_name --; git status";
		    if ( ! CheckFileForPattern($git_uninstfile,"$project_rm") ) {
			print ("adding rm instructions to $git_uninstfile\n");
			FileAddText($git_uninstfile,"$project_rm\n");
		    }
		    if ( $mode>=0){
			print ("  updating git project:$local_name with $update_line\n") if $mode >=0; # >> $svn_uninstfile
			`$update_line` ;
		    }
		} else {
		    print("\tWarning! Also not git\n");
		}
		print ("\tUpdate done<$local_name >\n");
	    }
	    if ( ! CheckFileForPattern($code_updatefile,"$update_line") && length($update_line) ) {
		FileAddText($code_updatefile,"$update_line\n");
	    }
	    if ( ! CheckFileForPattern($code_statusfile,"$status_line") && length($status_line) ) {
		print ("\tadding status check line $status_line\n") unless $mode <=0; # >> $svn_uninstfile
		FileAddText($code_statusfile,"$status_line\n");
	    }
	    chdir $c_dir;
	}
	
    } else {
	push (@errors, "error with git_name, local_name or branch, git_name=$git_project, Localname=$local_name, branch=$branch\n");
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
    if ( ! -f $infile ) {
	$pattern=".gitignore\n".$pattern;
    }
    if ( ! CheckFileForPattern($infile,$pattern) ) {
	FileAddText($infile,$pattern."\n");
    }
    return;
    

#     open($INPUT, $infile) || (warn "Error opening $infile : $!\n" and $gitigline=".gitignore\n");
#     #print("looking up pattern $pattern in file $infile\n");
#     #if(tell(FH) != -1)
#     if (-f $infile ){
#     while(<$INPUT>) {
# 	#if ( $_ ~ m/[\w]+[\s]+(?:svn(?:+ssh)?)|http|file:\/\//x) {
# 	chomp;
# 	if ( $_ =~m/$pattern/x) {
# 	    $found += 1;
# 	    # exit; # put the exit here, if only the first match is required
# 	} else {
# 	    #print "  nomatch ".$_;
# 	}
#     }
#     }
#     close($INPUT);
#     if ( $found <=0 ) {
# 	my $FILE;
# 	open ($FILE, ">>",$infile) || die "Could not open file: $!\n";
# 	print $FILE $gitigline."$pattern\n";
# 	close $FILE;
#     }
#     return;
}
1;
