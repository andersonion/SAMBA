use warnings;
#use strict;
sub dependencies (){
    print("dependencies\n");
    my $os='UNKNOWN';
    if ( $OS =~ /^darwin$/ )
    {
	$os='mac';
    } else {
	$os=$OS;
    }
###
# update engine_something_dependencies.
###
###
# copy engine_hostname_dependencis to backup and 
# cp engine_generic_dependincies to engine_hostname_depenendinceis and 
# link it to pipeline_dependencies and recon_dependencies.
###
    
	print("---\n");
	print("Setting engine dependencies ...... \n");
	print("---\n");
	print("setting engine dependencies\n");
	my $dep_file="${WKS_HOME}/pipeline_settings/engine_deps/engine_${HOSTNAME}_dependencies";
	my $default_file="${WKS_HOME}/pipeline_settings/engine_deps/engine_generic_dependencies";
	if( -e $dep_file && ! -e "${dep_file}.bak") { 
	    `mv $dep_file ${dep_file}.bak`; 
	    `cp $default_file $dep_file`;
	    print(" Backed up previous settings to ${dep_file}.bak\n");
	    print(" DONT FORGET TO REMOVE IF THIS WORKED\n");
	} elsif ( -e "${dep_file}.bak") {  #-e $dep_file && 
	    print( "old backup ${dep_file}.bak was not cleared\n");
#    exit(0);
	} else { 
	    print("Copying $default_file to $dep_file\n");
	    `cp $default_file $dep_file`;
	}
# sub hostname for hostname_radish  and hostname_pipeline
	my( $rdep, $pdep);
	($rdep = $dep_file ) =~ s/$HOSTNAME/${HOSTNAME}_radish/gx;
	($pdep = $dep_file )=~ s/$HOSTNAME/${HOSTNAME}_pipeline/gx;
	for my $file ($rdep, $pdep) {
#	    if( ! -e  $file) {
	    chdir dirname($dep_file);
	    my $ln_cmd="ln -fs ".basename($dep_file)." ".basename($file);
	    `$ln_cmd`;
	    chdir $WKS_HOME;
		#`ln -s $dep_file $pdep`;
		print ("made link for legacy code\n\t$file");
#	    } else { 
#		print("  *dependency links exist!\n");
#	    }
	}
###
# fix setting 
	$inpath="$dep_file";
	$outpath=$inpath."out";
	if (open SESAME, $inpath) {
	    @all_lines = <SESAME>;
	    close SESAME;
	    print(" opened dependency \n");
	} else {
	    print STDERR "Unable to open file <$inpath> to read\n";
	    exit(0);
	} 

	my @outcommentary=();
	my $string;
	open SESAME_OUT, ">$outpath" or warn "could not open $outpath for writing\n";
	for my $line (@all_lines) {
# # wrkstation workflow settings file
# # format like headfile
	    if ( $line =~ /^engine=hostname/x ) { 
		$string="engine=$HOSTNAME";
# engine=hostname
# engine_endian=little
# ###
# # data_locations
# engine_work_directory=/Volumes/enginespace
	    } elsif ($line =~ /^engine_work_directory=/x ) {
		$string="engine_work_directory=/${HOSTNAME}space";
# engine_data_directory=/Volumes/worktation_data/data
	    } elsif ($line =~ /^engine_data_directory=/x ) {
		$string="engine_data_directory=$DATA_HOME";
# engine_recongui_paramfile_directory=/wks_home/dir_param_files
	    } elsif ($line =~ /^engine_recongui_paramfile_directory=/x ) {
		$string="engine_recongui_paramfile_directory=$WKS_HOME/dir_param_files";
		
# engine_recongui_menu_path=/wks_home/pipe_settings/recon_menu.txt
	    } elsif ($line =~ /^engine_recongui_menu_path=/x ) {
		$string="engine_recongui_menu_path=$WKS_HOME/pipeline_settings/recon_menu.txt";
		
# engine_archive_tag_directory=/engine_work_directory/Archive_Tags
	    } elsif ($line =~ /^engine_archive_tag_directory=/x ) {
		$string="engine_archive_tag_directory=/Volumes/${HOSTNAME}space/Archive_Tags";
		if ( ! -d "/Volumes/${HOSTNAME}space/Archive_Tags") {
		    `mkdir "/Volumes/${HOSTNAME}space/Archive_Tags"`;
		    }
# engine_waxholm_canonical_images_dir=/wks_home/whs_references/whs_canonical_images/alx_can_101103
	    } elsif ($line =~ /^engine_waxholm_canonical_images_dir=/x ) {
		$string="engine_waxholm_canonical_images_dir=$DATA_HOME/atlas/whs2";
# engine_waxholm_labels_dir=/wks_home/whs_references/whs_labels/canon_labels_101103
	    } elsif ($line =~ /^engine_waxholm_labels_dir=/x ) {
		$string="engine_waxholm_labels_dir=$DATA_HOME/atlas/whs2";
# engine_app_dti_recon_param_dir=/wks_home/dti_references
	    } elsif ($line =~ /^engine_app_dti_recon_param_dir=/x ) {
		$string="engine_app_dti_recon_param_dir=$WKS_HOME/pipeline_settings/tensor";
# #
		
# ###
# # program names
# engine_3dpr_fast_prog_name=nuray05_v5_toff
# engine_3dgrid_prog_name=grid3d01
# engine_3dthreadgrid_prog_name=grid_thread
# #
		
# ###
# # program locations
# engine_radish_bin_directory=/wks_home/recon/legacy/modules/bin_macINTEL
	    } elsif ($line =~ /^engine_radish_bin_directory=/x ) {
		$string="engine_radish_bin_directory=$WKS_HOME/bin";#recon/legacy/modules/_mac_${ARCH}
# engine_radish_contributed_bin_directory=/wks_home/recon/legacy/modules/contributed/bin_macINTEL 
	    } elsif ($line =~ /^engine_radish_contributed_bin_directory=/x ) {
		$string="engine_radish_contributed_bin_directory=$WKS_HOME/recon/legacy/modules/contributed/bin_${os}_${ARCH}";
# engine_app_matlab=/usr/bin/matlab
 	    } elsif ($line =~ /^engine_app_matlab=/x ) { 
 		$string="engine_app_matlab=/usr/bin/matlab";# -nosplash -nodisplay -nodesktop ";
# engine_app_matlab_opts=-nosplash -nodisplay -nodesktop
 	    } elsif ($line =~ /^engine_app_matlab_opts=/x ) { 
 		$string="engine_app_matlab_opts=-nosplash -nodisplay -nodesktop";
# engine_app_ants_dir=/Applications/SegmentationSoftware/ANTS/
	    } elsif ($line =~ /^engine_app_ants_dir=/x ) { 
		$string="engine_app_ants_dir=/$WKS_HOME/../usr/bin/";
# engine_app_fsl_dir=/Applications/SegmentationSoftware/fsl/bin
	    } elsif ($line =~ /^engine_app_fsl_dir=/x ) {
		$string="engine_app_fsl_dir=$WKS_HOME/../fsl/bin";
# engine_app_dti_recon=/Applications/Diffusion\ Toolkit.app/Contents/MacOS/dti_recon
# engine_app_dti_tracker=/Applications/Diffusion\ Toolkit.app/Contents/MacOS/dti_tracker
# engine_app_dti_spline_filter=/Applications/Diffusion\ Toolkit.app/Contents/MacOS/spline_filter
# ###
	    } else { 
		$string=$line;
		chomp($string);
	    }
	    my @temp=split(/\=/,$string);
	    while ( $#temp < 1 ) {
		push( @temp, ' ');
	    }
	    if ( -e $temp[1]  && $string !~ /^#/ ) {
		push (@outcommentary,"$string <- $line");
	    } else {
		if ( $string !~ /(^#)|(\s)/  ){
#	    print("$temp[0]:::$temp[1]\n"); 
		    push (@outcommentary,"WARNING: newlocation $temp[1] did not exist yet!"); 
		}
	    }
	    print(SESAME_OUT "$string\n");
	}
	print(join("\n",@outcommentary));
	print("moving $outpath to $inpath\n");
	`mv $outpath $inpath`;
#`mv  ${dep_file}.bak $dep_file`
	return 1;
}
1;
