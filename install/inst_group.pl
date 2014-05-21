
###
# check for groups
### 
#if ( $name !~ /omega/x ) 
my @groups=qw/ipl/;
if ( $name =~ /pipeliner/x || $isadmin ) {
    push(@groups,'recon');
}
my @g_errors;
## mac group check
for my $group (@groups) {
#	`which dscl `;
    my $group_status=`dscl localhost list ./Local/Default/Groups | grep -c $group`;
    #grep -c $group
#	print("gs=$group_status\n");
    if ( $group_status  =~ m/0/x) { 
	push(@g_errors,"ERROR: need to create the $group group\n");
    } elsif( $group_status =~ m/1/x )  { 
	print("Found required group:$group\t");
    } elsif ( $? == -1 ) {
	push(@g_errors,"ERROR: dscl check failed on group $group.\n");
    }
    $group_status=`id | grep -c $group`; #an is member check.
    if ( $group_status  =~ m/0/x) { 
	push(@g_errors,"ERROR: current user must be part of $group group\n");
	print("... member check FAIL!\n");
    } elsif( $group_status =~ m/1/x )  { 
	print("... member check success!\n");
    } elsif ( $? == -1 ) {
	push(@g_errors,"ERROR: id check failed on group $group.\n");
	print("... member check FAIL!\n");
    }   
}


if ( $#g_errors>=0) { 
    #print(join("\n",@g_errors)."\n");
    print("admin check returned $isadmin\n");
    if ( ! $isadmin) 
    {
	print("Current user must be an admin and part of ipl and recon group.\nOmega should ONLY be part of ipl group.\nPipeliner should be part of ipl and recon group.\n @g_errors");
	exit 1;
    } else { 
	print("Current user must be an admin and part of ipl and recon group.\nOmega should ONLY be part of ipl group.\nPipeliner should be part of ipl and recon group.\n @g_errors");
	print("TODO createm missing groups, add basic memberships\n");
    }
}
