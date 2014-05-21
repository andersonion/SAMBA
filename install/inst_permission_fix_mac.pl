###
# permisison cleanup
###
if ( $isadmin && defined $opts{p}) { 
# set hostnamespace permissions on folders to omega:ipl rwsrwsr-x and files to rw-rw-r--
    print("sudo chown -R omega:ipl /Volumes/${hostname}space/ ...\n");
    `sudo chown -R omega:ipl /Volumes/${hostname}space/`;
    print("sudo find /Volumes/${hostname}space/ -not -type d -print -exec chmod 664 {} \\;  ... \n");
    `sudo find /Volumes/${hostname}space/ -not -type d -print -exec chmod 664 {} \\; `;
    print("sudo find /Volumes/${hostname}space/ -type d -exec chmod gu+s {} \\; ... \n");
    `sudo find /Volumes/${hostname}space/ -type d -exec chmod gu+s {} \\;`;
#    print("sudo find /Volumes/${hostname}space/ -type f -exec chmod gu+rw {} \\; ... \n");
#   `sudo find /Volumes/${hostname}space/ -type f -exec chmod u {} \\;`;
} else {
    if ( ! $isadmin ) {
	print("# Space drive permission commands not run because you are not an admin.\n");
    } 
    if ( ! defined $opts{p}) {
	print("# Space drive permission commands not run because -p option not used.\n");
    }
    print("# Thsese should be run at once to make sure archives do not generate permission errors\n");
    print("sudo chown -R omega:ipl /Volumes/${hostname}space/\n");
    print("sudo find /Volumes/${hostname}space/ -x -not -type d -print -exec chmod 664 {} \\; \n");
    print("sudo find /Volumes/${hostname}space/ -type d -exec chmod gu+s {} \\;\n");
#    print("sudo find /Volumes/${hostname}space/ -type f -exec chmod gu+rw {} \\;\n");
}
if (  $isrecon )
{ #$name !~ /omega/x 
    print("chgrp -R recon $wks_home ... \n"); # there doesnt have to be an ipl group
    `chgrp -R recon $wks_home`; # there doesnt have to be an ipl group
    if ( ! -d "$data_home/atlas/whs2" ) {
	`mkdir -p "$data_home/atlas/whs2"`;
	`chmod 775 "$data_home/atlas/whs2"`;
	`chgrp -R recon "$data_home/atlas/whs2"`;
    }
    
}

print("find $wks_home -type d -exec chmod ug+ws {} \\; ... \n");
`find $wks_home -type d -exec chmod ug+ws {} \\;`;
print("find $wks_home -type f -exec chmod ug+rw {} \\; ... \n");
`find $wks_home -type f -exec chmod ug+rw {} \\;`;
print("chmod 775 $wks_home/dir_param_files ... \n");
`chmod 775 $wks_home/dir_param_files`;
`chmod ug+s $wks_home/dir_param_files`;
print("chgrp -R ipl $wks_home/dir_param_files ... \n");

if ( $isipl ) 
{
    `chgrp -R ipl $wks_home/dir_param_files`;
    print("chgrp ipl $wks_home/pipeline_settings/recon_menu.txt ... \n");
    `chgrp ipl $wks_home/pipeline_settings/recon_menu.txt`;

#`chgrp $wks_home/pipeline_settings/recon_menu.txt`;
#`find . -iname "*.pl" -exec chmod a+x {} \;` # hopefully this is unnecessar and is handled by the perlexecs linking to bin section above. 
} else {
    print("permissions not altered!\n only recon users can alter permissions. If install has already been run by an admin this is not an issue!\n");
}
