sub permission_fix_mac () {
    print("permission_fix_mac\n");
    return 1;
###
# permisison cleanup
###
#    && defined $opts{p}

    if ( $IS_ADMIN ) { 
# set hostnamespace permissions on folders to omega:$USER_GROUP rwsrwsr-x and files to rw-rw-r--
	print("sudo chown -R omega:$USER_GROUP /Volumes/${hostname}space/ ...\n");
	`sudo chown -R omega:$USER_GROUP /Volumes/${hostname}space/`;
	print("sudo find /Volumes/${hostname}space/ -not -type d -print -exec chmod 664 {} \\;  ... \n");
	`sudo find /Volumes/${hostname}space/ -not -type d -print -exec chmod 664 {} \\; `;
	print("sudo find /Volumes/${hostname}space/ -type d -exec chmod gu+s {} \\; ... \n");
	`sudo find /Volumes/${hostname}space/ -type d -exec chmod gu+s {} \\;`;
#    print("sudo find /Volumes/${hostname}space/ -type f -exec chmod gu+rw {} \\; ... \n");
#   `sudo find /Volumes/${hostname}space/ -type f -exec chmod u {} \\;`;
    } else {
	if ( ! $IS_ADMIN ) {
	    print("# Space drive permission commands not run because you are not an admin.\n");
	} 
	#if ( ! defined $opts{p}) {
	#    print("# Space drive permission commands not run because -p option not used.\n");
	#}
	print("# Thsese should be run at once to make sure archives do not generate permission errors\n");
	print("sudo chown -R omega:$USER_GROUP /Volumes/${hostname}space/\n");
	print("sudo find /Volumes/${hostname}space/ -x -not -type d -print -exec chmod 664 {} \\; \n");
	print("sudo find /Volumes/${hostname}space/ -type d -exec chmod gu+s {} \\;\n");
#    print("sudo find /Volumes/${hostname}space/ -type f -exec chmod gu+rw {} \\;\n");
    }
    if (  $IS_CODER )
    { #$name !~ /omega/x 
	print("chgrp -R recon $WKS_HOME ... \n"); # there doesnt have to be an $USER_GROUP group
	`chgrp -R recon $WKS_HOME`; # there doesnt have to be an $USER_GROUP group
	if ( ! -d "$data_home/atlas/whs2" ) {
	    `mkdir -p "$data_home/atlas/whs2"`;
	    `chmod 775 "$data_home/atlas/whs2"`;
	    `chgrp -R recon "$data_home/atlas/whs2"`;
	}
	
    }
    
    print("find $WKS_HOME -type d -exec chmod ug+ws {} \\; ... \n");
    `find $WKS_HOME -type d -exec chmod ug+ws {} \\;`;
    print("find $WKS_HOME -type f -exec chmod ug+rw {} \\; ... \n");
    `find $WKS_HOME -type f -exec chmod ug+rw {} \\;`;
    print("chmod 775 $WKS_HOME/dir_param_files ... \n");
    `chmod 775 $WKS_HOME/dir_param_files`;
    `chmod ug+s $WKS_HOME/dir_param_files`;
    print("chgrp -R $USER_GROUP $WKS_HOME/dir_param_files ... \n");
    
    if ( $IS_USER ) 
    {
	`chgrp -R $USER_GROUP $WKS_HOME/dir_param_files`;
	print("chgrp $USER_GROUP $WKS_HOME/pipeline_settings/recon_menu.txt ... \n");
	`chgrp $USER_GROUP $WKS_HOME/pipeline_settings/recon_menu.txt`;
	
#`chgrp $WKS_HOME/pipeline_settings/recon_menu.txt`;
#`find . -iname "*.pl" -exec chmod a+x {} \;` # hopefully this is unnecessar and is handled by the perlexecs linking to bin section above. 
    } else {
	print("permissions not altered!\n only recon users can alter permissions. If install has already been run by an admin this is not an issue!\n");
    }
    return;
}
1;
