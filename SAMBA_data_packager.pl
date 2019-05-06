#!/usr/bin/perl
# This was created as to help organize warp chains.

# This only creates links, and will only work for the person running the study!
# Labels were initally faked out, but that has been disabled becuase we dont think we need them.
#    # The labels are intentionally just a blank here to prevent trash propagation,
#    # labels are expected by the code and it chokes if they're missing. 
# 
# this is one part of the larger idea of "promote" to atlas for an MDT, which we'll 
# use as the targetatlas of future SAMBA runs.


# sys level include
use strict;
use warnings;
use Carp qw(carp croak cluck confess);

use File::Basename;
use File::Path qw(make_path);
use Getopt::Std;
use Scalar::Util qw(looks_like_number);

use Env qw(RADISH_PERL_LIB WORKSTATION_DATA BIGGUS_DISKUS);
die "Cannot find good perl directories, quiting" unless defined($RADISH_PERL_LIB);
use lib split(':',$RADISH_PERL_LIB);

use pipeline_utilities;
use civm_simple_util qw(activity_log can_dump load_file_to_array write_array_to_file find_file_by_pattern is_writable round printd whoami whowasi debugloc sleep_with_countdown $debug_val $debug_locator);
use Headfile;

# ex of use lib a module (called MyModule) in current dir
# use lib dirname(__FILE__) . "MyModule";

exit main();

sub main {
    activity_log();
    #getopts? 
    # must define the options hashref before referincing inside it...of course. 
    my $opts={};
    #${$opts->{"label_nick:s"}}="";
    #${$opts->{"label_dir:s"}}="";
    #${$opts->{"image_dir:s"}}="";
    #${$opts->{"stat_dir:s"}}="";
    ${$opts->{"mdt_iterations:i"}}=0;
    ${$opts->{"link_mdt"}}=1;
    $opts=auto_opt($opts,\@ARGV);

#inputs headfile 
    #mdtname is still required, it may be the optional suffix. (maybenot)
    #want to add output path, 
#and target atlas is part of headpile
    my $output_path=$ARGV[0];
    my $hf_path=$ARGV[1];
    my @hf_errors;
    my $mdtname=$ARGV[2];

    if (! defined $output_path) {
	print( "Not enough input arguments, please specify your output_path, SAMBA startup file, and optionally the MDT name\n");
    }
    
    # This whole startup segment belongs in some "samba_helper.pm" file.
    # something like "samba pathing" ...
    my $hf=new Headfile ('ro', $hf_path);
    $hf->check() or push(@hf_errors,"Unable to open $hf_path\n");
    $hf->read_headfile or push(@hf_errors,"Unable to read $hf_path\n");
    if ( scalar(@hf_errors)>0 ){
	#print("Error_dump$#hf_errors\n");
	die(join('',@hf_errors));
    }
    # group runs, a hash ref of arrays of group runnos.
    # we're expecting 1 group with 4 in this code,
    # more than 1 group is an error, more than 4 per group is also an error. 
    #
    my $g_r;
    # group number, declaring outside so we can error check the loop code.
    # Groups start counting at 1 for human infterface.
    # (but group 0 as control would be sooo satisfying! oh well.)
    my $gn=1;
    my $v_ok;
    for(;$gn<100;$gn++) {
	($v_ok,$g_r->{$gn})=$hf->get_value_check("group_${gn}_runnos");
	if (! $v_ok ) {
	    delete $g_r->{$gn};
	    last;
	}
    }
    if($gn>5){
	cluck("group check code appears to have gone off the rails and over checked, final group number is $gn\n");
    }
    ($v_ok,my $c_list)=$hf->get_value_check("control_comma_list");
    my @controls=split(",",$c_list);
    my $MDT_n=scalar(@controls);
    # in mdt land, the group runnos arnt used :p
    #my @runnos=split(",",$g_r->{1});
    #if ( scalar(@runnos) < 1 ) {
    #croak "group_1_runnos undefined! (Dont know how to proceed.)";
    #}

    # headfile lookups, getting a bunch of implied vars in a lookup hash to make use of.
    # uses bunch of short varnams
    # generaly in decreasing specificity
    # project_name -> name_project -> n_p
    # rigid_atlas_name -> name_atlas_rigid -> n_a_r
    # label_atlas_name -> name_atlas_label -> n_a_l
    # label_atlas_nickname -> name_atlas_label_nick -> n_a_l_n
    # rigid_contrast -> contrast_rigid -> c_r
    # affine_contrast -> contrast_affine -> c_a
    # mdt_contrast -> contrast_mdt -> c_mdt
    # out_suffix -> o_s
    # diffeo_transform_parameters -> parameters_diffeo -> p_d
    # mdt_iterations -> iterations_mdt -> i_mdt
    # template_predictor -> ..? ->mdt_p 
    my $l;
    # With samba input headfiles project_name is synonamouse with project_code 
    ($v_ok,my $n_p)=$hf->get_value_check("project_name");
    if (!$v_ok) {
	$n_p='';
    }
    $n_p=~ s/[.]//gx;
    ($v_ok,my $n_a_l_n)=$hf->get_value_check("label_atlas_nickname");
    if (!$v_ok) { $n_a_l_n='';}
    # rigid_contrast=dwi
    # affine_contrast
    # mdt_contrast=fa
    ($v_ok,my $c_r)=$hf->get_value_check("rigid_contrast");
    #($v_ok,my $c_a)=$hf->get_value_check("affine_contrast");
    ($v_ok,my $c_mdt)=$hf->get_value_check("mdt_contrast");
    ($v_ok,my $n_a_r)=$hf->get_value_check("rigid_atlas_name");
    if (!$v_ok) { $n_a_r=''; }
    ($v_ok,my $o_s)=$hf->get_value_check("optional_suffix");
    if (!$v_ok) { $o_s=''; }
    ($v_ok,my $n_a_l)=$hf->get_value_check("label_atlas_name");
    if(! $v_ok) { $n_a_l=$n_a_r; }

    ($v_ok,my $mdt_p)=$hf->get_value_check("template_predictor");
    if(! $v_ok) { die "required var (template_predictor) not found"; }
    # old data has no template predictor, which comes out as NoName. 
    # Could add support for that later. 
    # Shame is isnt, None, or something meaning unspecified, like, Unspec, or just straight up omitted...

    if ($mdt_p =~ /,/ ){ 
	die "multi-predictor is a work in progress :P ";
    }

    ($v_ok,my $p_d)=$hf->get_value_check("diffeo_transform_parameters");
    if(! $v_ok) { die "required var not found"; }
    my $i_mdt;
    if( ${$opts->{"mdt_iterations"}} ) {
	print "found mdt_iterations on command line:${$opts->{mdt_iterations}}\n";
	$i_mdt=${$opts->{"mdt_iterations"}};
    } else {
	($v_ok,$i_mdt)=$hf->get_value_check("mdt_iterations");
	if(! $v_ok) { die "required var (mdt_iterations) not found"; }
    }
    
    ##
    # adjust vars and derrive paths
    ## 
    $p_d=~s/,/_/g;
    $p_d=~s/[.]/p/g;

    my @vbmname_parts=("VBM");
    push(@vbmname_parts,$n_p,$n_a_r);
    if ($o_s ne ''){
	push(@vbmname_parts,$o_s);  }
    # name of vbm folder there will be three sibling direcrories with this prefix, that is -inputs, -work, and -results.
    #my $n_vbm=sprintf("VBM_%s_%s%s",$n_p,$n_a_r,$o_s);
    my $n_vbm=join("_",@vbmname_parts);
    # if given a results headfile, the vbm name is explicitly specified, under a strange key "project_id"
    # alternate names might make sense, like 
    # process_name, VBM_name, working_name, SAMBA_process, SAMBA_data, local_name, local_storage etc. 
    # The thing wrong with project_id, is that sounds like project_code, and thats confusing.
    ($v_ok,my $n_vbm_r)=$hf->get_value_check("project_id");
    if($v_ok ){
	$n_vbm=$n_vbm_r;
    }

    #diffeo_transform_parameters=0.25,3,0.5
    #mdt_iterations=6
    # mdtpath ... VBM_PROJECT_TARGETATLAS(_SUFFIX)?-work/rigidcontrast/SYNSETTINGS/DIFFEOCONTRASTMDT_PREDICTOR_n*_i*";
    # mdtpath="${BIGGUS_DISKUS}/VBM_18gaj42_chass_symmetric3_${mdtname}-work/dwi/SyN_0p25_3_0p5_fa/faMDT_all_n*_i6";
    my $mdtpath=File::Spec->catfile($BIGGUS_DISKUS,
				    sprintf("%s-work",$n_vbm),
				    $c_r,
				    sprintf("SyN_%s_%s",$p_d,$c_mdt),
				    sprintf("%sMDT_%s_n%i_i%i",$c_mdt,$mdt_p,$MDT_n,$i_mdt)  );
    if ( ! defined $mdtname ) { 
	# if mdtname not set, and we had an o_s assume the o_s is mdname, else error
	if ( $o_s ne '' ) {
	    $mdtname=$o_s; 
	} else {
	    die "Need mdtname, optional suffix not available!";
	}
    }
# didnt convert this bash code becuase its not really the important work right now. 
#for fp in $(ls -d $mdtpath/median_images/* |grep -E '(dwi|fa)\.');
#do 
#    f=$(basename $fp);
#    c_nii=${f##*_};
#    echo -n "    $f:";
#    if [ ! -L "${mdtname}_$c_nii" ]; then
#	ln -s $fp ${mdtname}_$c_nii;
#    fi;
#    echo "done";
#done;
    my @files;
    if ( -e File::Spec->catfile($mdtpath,"median_images")  ) {
	@files=qx(find $mdtpath/median_images/ -maxdepth 1 -type f );
	chomp(@files);
    }
    print("MDT images from $mdtpath/median_images\n");
    if( -d $output_path) {
	carp("output ($output_path) already exists! attempting validation");
    }  elsif(! -e $output_path ) {
	make_path($output_path) or die $!;
    }
    my $mdt_lookup={};
    #foreach (@files) {print $_."\n\n";} # works as expected
    #foreach (@files) {basename$_;print $_."\n\n";}# didnt work..., basename not performed, or not captured
    #foreach (@files) {print(${basename$_}."\n\n");}
    #print(basename $_) for @files;
    #foreach (@files) {my $n=basename$_;print $n."\n\n";} # works as expected
    foreach (@files) {
	if( $_ !~ /^.*(txt)|(nhdr)|(nii([.]gz)?)$/ ) {
	    next;
	}
	my $n=basename$_;
	my $o=$n;
	$o=~s/MDT/$mdtname/;
	print "\t".$n."->".$o."\n";
	$o=File::Spec->catfile($output_path,$o);
	if (! -e $o ) {
	    $mdt_lookup->{$_}=$o;
	}
    }
    if (${$opts->{"link_mdt"}} ) {
	print("\t Linking up images\n");
	while (my ($key, $value) = each %$mdt_lookup ) {
	    qx(ln -vs $key $value);
	}
	# check for a labels folder in median images we'd want to capture. 
	my $lp=File::Spec->catfile($mdtpath,"median_images","labels_MDT");
	# annoying uncertainty in what labels structure will be available, so we'll try to do an either or.
	my $lp_a=File::Spec->catfile($mdtpath,"median_images","labels");
	if ( ! -e $lp && -e $lp_a  ) { 
	    $lp=$lp_a;
	}
	# first pass of labels out.
	my $lo_o=File::Spec->catfile($output_path,"labels_${mdtname}");
	my $lo=File::Spec->catfile($output_path,"labels");
	if ( -e $lp  ) { 
	    # handle move former spec
	    if ( ! -e $lo && -e $lo_o  ) { 
		qx(mv $lo_o $lo);
	    }
	    if(! -e $lo) {
		qx(mkdir $lo;lndir $lp $lo);
	    }
	    @files=qx(find $lo);
	    chomp(@files);
	    foreach (@files) {
		#if( $_ !~ /^.*(txt)|(nhdr)|(nii([.]gz)?)$/ ) {
		#    next;
		#}
		#my $n=basename$_;
		my ($t_p,$t_n,$t_e)=fileparts($_);
		my $o=$t_n;
		$o=~s/MDT/$mdtname/;
		print "\t".$t_n."->".$o."\n";
		$o=File::Spec->catfile($lo,$o.$t_e);
		qx(mv $_ $o);
	    }	    
	}
    } else {
	print("\tNot linked today, just getting the transforms together.\n");
    }
# transcribe the name of the atlas for labels into targetatlas for code clarity. 
    my $TargetAtlas=$n_a_l;
###
# Get the affine
###
# do this first so we dont leave a mess if it fails.
    my $aff=qx(ls $mdtpath/stats_by_region/labels/transforms/MDT_*_to_${TargetAtlas}_affine.*) || die "affine find fail";
    chomp($aff);
###
# make TARGETATLAS/foward and reverse  directories!
###
# add simple annotation readme of what this is.
    # name of old road
    my $n_r_o="transforms_$TargetAtlas";
    my $old_road=File::Spec->catfile($output_path,$n_r_o);
    # name of road
    my $n_r="transforms";
    my $road=File::Spec->catfile($output_path,$n_r);
    my $road_forward="$road/${TargetAtlas}_to_${mdtname}";
    my $road_backward="$road/${mdtname}_to_${TargetAtlas}";
    if ( ! -e $road && -e $old_road ){
	qx(mv $old_road $road);
    }
    if ( ! -e $road ){
	mkdir($road); } 
    if ( ! -e ${road_backward} ) {
	mkdir(${road_backward}); }
    if ( ! -e $road_forward ) {
	mkdir($road_forward); }
    my @dir_s=qw(from to);
    my @derp=($road_forward,$road_backward);
    for( my $i_d=0;$i_d<2;$i_d++){
	my $direction=$dir_s[$i_d];
	my $d_p=$derp[$i_d];
	my $p_r_txt="$d_p/README.txt";
	if ( ! -e $p_r_txt ) { 
	    open(my $f_id,'>',$p_r_txt);
	    print($f_id "This folder holds the transforms from this data $direction TargetAtlas:$TargetAtlas.\n");
	    print($f_id "This was collected from the depths of $n_vbm in \$BIGGUS_DISKUS \n");
	    print($f_id "\t($mdtpath)\n");
	    print($f_id "numbered warps to be used in order as reported by ls _*.\n");
	    print($f_id "WARNING: for ants apply, these have to be reverse ordered you can use ls -r _*.\n");
	    print($f_id "The numbered warps should just be just be links in the hopes of reducing re-organization\n");
	    print($f_id "transcription headaches. Affines may be an explicit inverse of a transform from the other direction\n");
	    close($f_id);
	}
    }

###
# link the affine
###
    my $mdt_TargetAtlas_affine=File::Spec->catfile(${road_backward},basename($aff));
    if ( ! -e $mdt_TargetAtlas_affine ) {
	qx(ln -vs $aff $mdt_TargetAtlas_affine);
    }
###
# get the warp
###
    my $warp=File::Spec->catfile("$mdtpath","stats_by_region","labels","transforms","MDT_to_${TargetAtlas}_warp.nii.gz");
    my $mdt_TargetAtlas_warp=File::Spec->catfile(${road_backward},basename( $warp));
    if ( ! -e $mdt_TargetAtlas_warp ) {
	die "EXPCTED warp missing !($warp)" unless -e $warp ;
	qx(ln -s $warp $mdt_TargetAtlas_warp);
    }
###
# get the "inverse" warp.
###
    $warp=File::Spec->catfile("$mdtpath","stats_by_region","labels","transforms","${TargetAtlas}_to_MDT_warp.nii.gz");
    my $TargetAtlas_mdt_warp=File::Spec->catfile($road_forward,basename( $warp));
    if (  ! -e $TargetAtlas_mdt_warp ) {
	qx(ln -s $warp $TargetAtlas_mdt_warp);
    }
### 
# kajigger the "inverse" affine"
###
# this file doesent exist yet, we have to create it, we do this to simply the usage syntax so 
# we have an explict transform instead of implict.
    my $n_mdt_t_a=basename($mdt_TargetAtlas_affine);
    $n_mdt_t_a=~ s/MDT_(.+)_to_${TargetAtlas}_(.*)$/${TargetAtlas}_to_MDT_$1_$2/;
    my $TargetAtlas_mdt_affine="$road_forward/".$n_mdt_t_a;
    my $antsCreateInverse="ComposeMultiTransform 3 ${TargetAtlas_mdt_affine} -i ${mdt_TargetAtlas_affine} && ConvertTransformFile 3 ${TargetAtlas_mdt_affine} ${TargetAtlas_mdt_affine} --convertToAffineType";
    my($p,$n,$e)=fileparts(${TargetAtlas_mdt_affine},3);
    my $p_i_t_c=File::Spec->catfile($p,$n.".sh");
    if (  ! -e $p_i_t_c ) {
	open(my $f_id,'>',$p_i_t_c);
	print($f_id "#!/bin/bash\ncd $p;$antsCreateInverse;\n");
	close($f_id);
    }
    if (  ! -z "$mdt_TargetAtlas_affine" && ! -e $TargetAtlas_mdt_affine ) {
	print("have $mdt_TargetAtlas_affine create $TargetAtlas_mdt_affine\n");
	qx(bash $p_i_t_c);
    } elsif (  -z "$mdt_TargetAtlas_affine" || ! -e "$mdt_TargetAtlas_affine" ) {
	die("Missing(or bad file) $mdt_TargetAtlas_affine");
	
    }
###
# Create ordered links ( relative links to files in same folder just for our future selve's book keeping.
###
# WARNING: These are the not in ants specification order(which is backwards). 
# Backward path
    my ($t,$p_t);
    $t="_2_${mdtname}_to_${TargetAtlas}_warp.nii.gz";
    $p_t=File::Spec->catfile(${road_backward},$t);
    if (  ! -e $p_t ) {
	$t=basename $mdt_TargetAtlas_warp;
	qx(ln -sv $t $p_t);
    }
    $t="_1_${mdtname}_to_${TargetAtlas}_affine.mat";
    $p_t=File::Spec->catfile(${road_backward},$t);
    if (  ! -e $p_t ) {
	$t=basename $mdt_TargetAtlas_affine;
	qx(ln -sv $t $p_t);
    }
# Forward path
    $t="_2_${TargetAtlas}_to_${mdtname}_affine.mat";
    $p_t=File::Spec->catfile(${road_forward},$t);
    if (  ! -e $p_t ) {
	$t=basename $TargetAtlas_mdt_affine;
	qx(ln -sv $t $p_t);
    }
    $t="_1_${TargetAtlas}_to_${mdtname}_warp.nii.gz";
    $p_t=File::Spec->catfile(${road_forward},$t);
    if (  ! -e $p_t ) {
	$t=basename $TargetAtlas_mdt_warp;
	qx(ln -sv $t $p_t);
    }
# END arranging
    
    #print("#You may want to copy this output to $WORKSTATION_DATA/atlas, you could also just use symbolic links :D !\n");
    my $atlased_dir="$WORKSTATION_DATA/atlas/$mdtname";
    if (  -e $atlased_dir && 0 ) {
	my @empties;
	my @files=run_and_watch("find $atlased_dir/ -maxdepth 1 -type f -print");
	chomp @files;
	for my $f ( @files  ) {
	    if (  -z "$(head $f)" ) { push(@empties,$f);} 
	}
	if (  scalar(@empties)>0 ) {
	    print("# You may need to remove empty files in $atlased_dir \n");
	    print("#DO THIS WITH CAUTION!!!!");
	    print("#Here are the existing empty files (LOOK at the output of ls!)\n");
	    for my $f (@empties){ print("# ".`ls -l $f`);}
	    print("  rm ".join(" ",@empties)."\n"  );
	    print("# WARNING: there is probably a readme in that folder which is now invalid!\n");
	}
    }
    print("To use this MDT for your next SAMBA run, use $output_path as an element of your transform chain\n");
    #print("  cp -RPpn $output_path $WORKSTATION_DATA/atlas/".basename( $output_path)."\n");
    #print("#Or at least the linky stack,");
    #print("  cp -RPpn $road $WORKSTATION_DATA/atlas/".basename( $output_path)."/$n_r\n");
    
    #print(" To convert to a proper archiveable use unit, use rsync -a --copy-unsafe-links $output_path/ NEW_PATH/ \n");
    #print("WARNING!!!! WITH RSYNC TRAILING SLASHES ARE IMPORTANT AND BOTH MUST BE PRESENT FOR CORRECT BEHAIVOR\n");
}
