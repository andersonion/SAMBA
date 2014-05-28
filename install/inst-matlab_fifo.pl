sub matlab_fifo () {
    print("matlab_fifo\n");
    return 1;
if ( ! -d $wks_home."/matlab_fifos" ) 
{
    my $fifo_dir="$wks_home/../matlab_fifos";
    my $mkdir_cmd = "mkdir -p $fifo_dir" ;
    print("$mkdir_cmd\n");
    `$mkdir_cmd` or warn "could not make the fifo dir $fifo_dir";
    
    print("chmod 775 $fifo_dir\n");
    `chmod 775 $fifo_dir`;
    `chmod ug+s $fifo_dir`;
    print("chgrp -R ipl $fifo_dir\n");
    `chgrp -R ipl $fifo_dir`;
}
return;
}
1;
