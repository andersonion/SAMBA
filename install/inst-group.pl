sub group () {
    my $mode = shift;
    my $do_work=0;
    my $work_done=0;
    if( $mode ){
	print ("force\t");
	$do_work=$mode;
    } elsif(!$work_done ) {
	$do_work=1;
    }

    my @g_errors;    
    if ( $do_work > 0) {
###
# check for groups
### 
	print("group\n");
	my @groups=($ADMIN_GROUP, $EDIT_GROUP, $USER_GROUP);
	# group check code changes for mac vs linux vs windows this is the mac check,
	# dscl localhost list ./Local/Default/Groups | grep -c $group
	# for linux this is a listing of users and the groups they belong to
	# getent passwd | awk -F: '{print $1}' | while read name; do groups $name; done
	# this is a a listing of groups
	# getent group 
	# this is the linux check 
	# getent group | grep -c $group
	#grep -c $group
	my $group_check='echo 0';
	if ($OS =~/^darwin$/ ){
	    $group_list='dscl localhost list ./Local/Default/Groups ';
	} elsif($OS =~ /^linux$/ ) {
	    $group_list='getent group ';
	}
	for my $group (@groups) {
	    my $cmd="$group_list "."| grep -c $group";
	    #print $cmd;
	    my $group_status=`$cmd`;
	    #print("gs=$group_status\n");
	    if ( $group_status  =~ m/0/x) { 
		push(@g_errors,"ERROR: need to create the $group group\n");
	    } elsif( $group_status =~ m/1/x )  { 
		print("Found required group:$group\n");
	    } elsif ( $? == -1 ) {
		push(@g_errors,"ERROR: check failed on group $group.\n");
	    }
	}
###
# check group membership
###
	$IS_ADMIN=`id | grep -Hc $ADMIN_GROUP`;chomp($IS_ADMIN);
	$IS_CODER=`id | grep -Hc $EDIT_GROUP`;chomp($IS_CODER);
	$IS_USER=`id | grep -Hc $USER_GROUP`;chomp($IS_USER);
	
	@groups=();
	if ( $IS_ADMIN) {
	    push @groups,$ADMIN_GROUP;
	} else {
	    print("Edit Group $group ... member check no member!\n");
	}
	if ( $IS_CODER) {
	    push @groups,$EDIT_GROUP;
	} else {
	    print("Edit Group $group ... member check no member!\n");
	}
	
	if ( $IS_USER ) {
	    push @groups,$USER_GROUP;
	} else {
	    push(@g_errors,"ERROR: current user must be part of $group group\n");
	    print("Required Group $group ... member check FAIL!\n");
	}
	print("Group Memberhsips,".join(", ",@groups).".\n");
    }

    if ( $#g_errors>=0) { 
	#print(join("\n",@g_errors)."\n");
	print("admin check returned $IS_ADMIN\n");
	if ( ! $IS_ADMIN) 
	{
	    print("Current user must be an admin and part of ipl and recon group.\nOmega should ONLY be part of ipl group.\nPipeliner should be part of ipl and recon group.\n @g_errors");
	} else { 
	    print("Current user must be an admin and part of ipl and recon group.\nOmega should ONLY be part of ipl group.\nPipeliner should be part of ipl and recon group.\n @g_errors");
	    print("TODO createm missing groups, add basic memberships\n");
	}
	return 1;
    } else {
	return 0;
    }
}
1;
