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
use List::MoreUtils qw(uniq);

use Env qw(RADISH_PERL_LIB WORKSTATION_DATA BIGGUS_DISKUS);
die "Cannot find good perl directories, quiting" unless defined($RADISH_PERL_LIB);
use lib split(':',$RADISH_PERL_LIB);

use pipeline_utilities;
use civm_simple_util qw(activity_log can_dump file_trim load_file_to_array write_array_to_file find_file_by_pattern file_mod_extreme is_writable round printd whoami whowasi debugloc sleep_with_countdown $debug_val $debug_locator);
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
    ${$opts->{"link_individuals!"}}=1;
    ${$opts->{"link_images!"}}=1;
    ${$opts->{"template_predictor=s"}}="";
    ${$opts->{"label_atlas_nickname=s"}}="";
    ${$opts->{"rsync_location=s"}}="";
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
    $output_path=file_trim($output_path);
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
    # there is also the compare group to account for.... 
    # The compare is probably the only real group we care about, however
    # it might be implied in a start headfile. So, we should gather both 
    # and the numbered groups, and run unique on them, to get a the full list. 
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
    # The control group controls the mdt N.
    ($v_ok,my $c_list)=$hf->get_value_check("control_comma_list");
    my @controls=split(",",$c_list);
    my $MDT_n=scalar(@controls);
    # using individuals instead of runnos, because that is the real intent.
    # "In the future" we may work out using specimen identifiers instead of runnos.
    # Individuals also fits the idea of data packages which aught to align.
    my @individuals=@controls;
    ($v_ok,$c_list)=$hf->get_value_check("compare_comma_list");
    if($v_ok) {
        push(@individuals,split(",",$c_list));
    }
    @individuals=uniq(@individuals);
    # when handling the MDT, the group runnos arnt used, so is non-fatal
    if ( scalar(@individuals) < 1 ) {
        cluck "input runnos undefined!";
    }
    if( ! ${$opts->{"link_individuals"}} ) {
	# if we're skipping the individuals.
	@individuals=();
    }

    #sleep_with_countdown(1);
    # Our options hash is a bit cantankerous, have to use the odd ${$opts->{"option_name"}} 
    # syntax to get the value. 
    #printf("\tlink_ind=%i\n\tlink_im=%i",${$opts->{"link_individuals"}},${$opts->{"link_images"}});
    #printf("\tlink_ind=%i\n\tlink_im=%i",$opts->{"link_individuals"},$opts->{"link_images"});
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
    if (!$v_ok) { 
        $n_a_l_n='';
    }
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
    if(! $v_ok) { 
        $n_a_l=$n_a_r; 
    }
    if( $n_a_l_n eq '' ) {
        $n_a_l_n=$n_a_l;
        if( ${$opts->{"label_atlas_nickname"}} ne "" ) {
            $n_a_l_n=${$opts->{"label_atlas_nickname"}};
        } else {
            cluck "lighlty TESTED CONDITION, no label_atlas_nickname specified, would have used $n_a_l as nick (that is label_atlas_name, or rigid_atlas_name)";
            sleep_with_countdown(3) if ($debug_val>0 && $debug_val<100);
        }
    }
    ($v_ok,my $mdt_p)=$hf->get_value_check("template_predictor");
    if(! $v_ok) { 
        if( ${$opts->{"template_predictor"}} ne "" ) {
            $mdt_p=${$opts->{"template_predictor"}};
        } else {
            die "required var (template_predictor) not found"; }
    }
    # old data has no template predictor, which comes out as NoName. 
    # Could add support for that later. 
    # Shame is isnt, None, or something meaning unspecified, like, Unspec, or just straight up omitted...
    if ($mdt_p =~ /,/ ){ 
        # multi-predictor isnt really implemented in samba yet anyway. so this is a placeholder.
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
    # parms-diffeo
    $p_d=~s/,/_/g;
    $p_d=~s/[.]/p/g;
    my @vbmname_parts=("VBM");
    push(@vbmname_parts,$n_p,$n_a_r);
    if ($o_s ne ''){
        push(@vbmname_parts,$o_s);  }
    # name of vbm folder, there will be three sibling direcrories with this prefix, that is -inputs, -work, and -results.
    #my $n_vbm=sprintf("VBM_%s_%s%s",$n_p,$n_a_r,$o_s);
    my $n_vbm=join("_",@vbmname_parts);
    # if given a results headfile, the vbm name is explicitly specified, under a strange key "project_id"
    # That is more reliable than making it up in place, so if its available we'll use it.
    # alternate names might make sense, like 
    # analysis_name, analysis_id, process_name, VBM_name, working_name, SAMBA_process, SAMBA_data, local_name, local_storage etc. 
    # The thing wrong with project_id, is that sounds like project_code, and thats confusing.
    ($v_ok,my $n_vbm_r)=$hf->get_value_check("project_id");
    if($v_ok ){
        $n_vbm=$n_vbm_r;
    }
    # get affine path which is sitting outside("above") the mdt folder.
    # Its a constant up two, so we're gonna switch to just that now.
    #my $affpath=File::Spec->catfile($BIGGUS_DISKUS,
    #                                sprintf("%s-work",$n_vbm),
    #                                $c_r );

    my $mdtpath=File::Spec->catfile($BIGGUS_DISKUS,
                                    sprintf("%s-work",$n_vbm),
                                    $c_r,
                                    sprintf("SyN_%s_%s",$p_d,$c_mdt),
                                    sprintf("%sMDT_%s_n%i_i%i",$c_mdt,$mdt_p,$MDT_n,$i_mdt)  );
    if ( ! defined $mdtname ) { 
        # if mdtname not set, and we had an o_s assume the o_s is mdname, else error
        if ( $o_s ne '' ) {
            printd(5,"no mdtname specified, but we found an optional suffix $o_s, this is what we're going to call the mdt, it will be in all your transform names for this set of packaged data.\n IF YOU DON'T LIKE THAT CANCEL NOW AND SPECIFY AN MDTNAME on the command line\n");
            sleep_with_countdown(8);
            $mdtname=$o_s; 
        } else {
            die "Need mdtname, optional suffix not available!";
        }
    }

    if ($debug_val==100 ) {
	Data::Dump::dump(($output_path));
	die "db:100 stop";
    }

    #### 
    # handle MDT median_images
    ###
    if( -d $output_path) {
        carp("output ($output_path) already exists! attempting validation");
    }  elsif(! -e $output_path ) {
        make_path($output_path) or die $!;
    }
    ###
    # discover images to link
    ###
    ###
    # do the linking of images
    ###
    if ( $opts->{"link_images"} ) {
        my $in_im_dir=File::Spec->catfile($mdtpath,"median_images");
        print("MDT images from $in_im_dir\n");
        my $mdt_lookup={};
        $mdt_lookup=transmogrify_folder($in_im_dir,$output_path,'MDT',$mdtname);
        if ( scalar(keys(%$mdt_lookup)) ) {
            print("\t Linking up images\n");
            while (my ($key, $value) = each %$mdt_lookup ) {
                qx(ln -vs $key $value);
            }
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
        # "accepted standard" labels out
        my $lo=File::Spec->catfile($output_path,"labels");
        # if labels available for linkage
        if ( -e $lp  ) {
            # handle move former spec
            if ( ! -e $lo && -e $lo_o  ) { 
                qx(mv $lo_o $lo);
            }
            # If we havnt got them yet, make sybolic link stack for labels folder
            # This is only done the first time. If we have need to repeat this(due to pipeline additions) 
            # best practice would be to remove the existing labels package.
            if(! -e $lo) {
                mkdir($lo);
                qx(lndir $lp $lo);
            }
            # run through link stack setting up the name.
            my $sub_lookup=transmogrify_folder($lo,$lo,'MDT',$mdtname);
            while (my ($key, $value) = each %$sub_lookup ) {
                qx(mv $key $value);
            }
            # handle label nicks
            my $ln=File::Spec->catfile($lo,$n_a_l_n);
            if(! -e $ln) {
                mkdir($ln);
            }
            $sub_lookup=transmogrify_folder($lo,$ln,$n_a_l_n,$n_a_l_n);
            while (my ($key, $value) = each %$sub_lookup ) {
                qx(mv $key $value);
            }
        }
    } else {
        print("\tNot linked today, just getting the transforms together.\n");
    }
    
# transcribe the name of the atlas for labels into targetatlas for code clarity. 
    my $TargetDataPackage=$n_a_l;
    package_transforms_MDT($mdtpath,$output_path,$mdtname,$TargetDataPackage,$n_vbm);
    #fix_ts_new($output_path,'README.txt');
    record_metadata($output_path);
# END arranging
    
    ###
    # Handle per specimen images as measured. 
    ###
    # There are other specimen images available, but this seems like the bet choice.
    my $output_base=dirname($output_path);
    # While we say specimen here, we may actually have runnos's... You were warned. 
    for my $Specimen (@individuals) {
        my $output_path=File::Spec->catfile($output_base,$Specimen);
        if( -d $output_path) {
            carp("output ($output_path) already exists! attempting validation");
        }  elsif(! -e $output_path ) {
            make_path($output_path) or die $!;
        }
        # pre_rigid_native_space should actually be the measure space.... 
        # Best science comes from untouched voxels, (we think)
        # so hard coding this isn't the worst idea.
        my $in_im_dir=File::Spec->catfile($mdtpath,"stats_by_region","labels","pre_rigid_native_space","images");
        my $sub_lookup=transmogrify_folder($in_im_dir,$output_path,$Specimen,$Specimen);
        if ( scalar(keys(%$sub_lookup)) ) {
            print("\t Linking up images\n");
            while (my ($key, $value) = each %$sub_lookup ) {
                qx(ln -vs $key $value);
            }
        }
        package_transforms_SPEC($mdtpath,$output_path,$Specimen,$mdtname,$n_vbm);
        # n_a_l_n - the nickname for the labelset.
        package_labels_SPEC($mdtpath,$output_path,$Specimen,$n_a_l_n,$n_vbm);
	record_metadata($output_path);
	
    }

    ###
    # MDT feedback
    ###
    # out of use.
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
    
    my $bd_name=basename($BIGGUS_DISKUS);
    my $o_name=basename($output_base);
    if ($bd_name =~ /$o_name/) {
	# if we packaged straight into biggus_diskus, then add our project_code to our samba_packages_folder on remote
	$o_name=$n_p;
    }
    my $rsync_location="piper.dhe.duke.edu:/Volumes/piperspace/samba_packages/$o_name/";
    if ( ${$opts->{"rsync_location"}} ne "" ) {
	# force slash on.
	$rsync_location=${$opts->{"rsync_location"}}."/";
	# collapse any multi slashing to single
	$rsync_location=~s|/+|//|g;
    }
    print(" Data \"packaged\" sucessfully! THIS IS A PRESENTATION SET, NOT what we would archive.\n");
    print(" To get archive ready please use the SAMBA_archive_prep\n");
    print("\n");
    print(" You can send all your data to one of our workstations (piper) for continuting work with the following:\n");
    print("   rsync -a --copy-unsafe-links $output_base/ $rsync_location \n");
    print(" To archive you will need to dereference the linkages, with the following command:\n");
    print("   rsync -a --copy-unsafe-links $output_base/ NEW_PATH/ \n");
    print(" You can ask Lucy or James to help you with that step.\n\n");
    print("To use this MDT for your next SAMBA run, add its path to your transform chain:\n");
    print("\t$output_path \n");
    #print("  cp -RPpn $output_path $WORKSTATION_DATA/atlas/".basename( $output_path)."\n");
    #print("#Or at least the linky stack,");
    #print("  cp -RPpn $road $WORKSTATION_DATA/atlas/".basename( $output_path)."/$n_r\n");
    
    #print("WARNING!!!! WITH RSYNC TRAILING SLASHES ARE IMPORTANT AND BOTH MUST BE PRESENT FOR CORRECT BEHAIVOR\n");
    return 0;
}

sub transmogrify_folder {
    # File name transmogrifier ... 
    # A messy idea, and as such is nearly impossible to name reasonably.
    # 
    # Give an input and output folders and input and output keywords, 
    # look at all files in input folder, resolve an output file path replacing 
    # input keyword   with  output keyword.
    # eg, get ready to rename on the fly from the inputfolder to the output folder.
    # returns hash(ref) of in path to outpath
    my ($in_path,$out_path,$in_key,$out_key)=@_;
    my %transfer_setup;

    my @files = find_file_by_pattern($in_path,".*$in_key.*",1);
    foreach (@files) {
        if( $_ !~ /^.*(txt|csv|xlsx?|headfile)|(nhdr|nrrd|raw.gz)|(nii([.]gz)?)$/ ) {
            next;
        }
        my $n=basename$_;
        my $o=$n;
        $o=~s/$in_key/$out_key/;
        printd(5, "\t".$n."   ..   ".$o."\n");
        $o=File::Spec->catfile($out_path,$o);
        if (! -e $o ) {
            $transfer_setup{$_}=$o;
        }
    }
    return \%transfer_setup;
}

sub transform_dir_setup {
    my ($ThisPackageInRoot,$ThisPackageOutLocation,$ThisPackageName,$TargetDataPackage,$CollectionSource)=@_;
###
# make Package foward and reverse directories
###
# and add simple annotation readme of what this is.
    # name of old road
    my $n_r_o="transforms_$TargetDataPackage";
    my $old_road=File::Spec->catfile($ThisPackageOutLocation,$n_r_o);
    # name of road
    my $n_r="transforms";
    my $road=File::Spec->catfile($ThisPackageOutLocation,$n_r);
    my $road_forward="$road/${TargetDataPackage}_to_${ThisPackageName}";
    my $road_backward="$road/${ThisPackageName}_to_${TargetDataPackage}";
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
            print($f_id "This folder holds the transforms for this data $direction Target:$TargetDataPackage.\n");
            print($f_id "This was collected from the depths of $CollectionSource in \$BIGGUS_DISKUS \n");
            print($f_id "\t($ThisPackageInRoot)\n");
            print($f_id "numbered warps to be used in order as reported by ls _*.\n");
            print($f_id "WARNING: for ants apply, these have to be reverse ordered you can use ls -r _*.\n");
            print($f_id "The numbered warps should just be just be links in the hopes of reducing re-organization\n");
            print($f_id "transcription headaches. Affines may be an explicit inverse of a transform from the other direction\n");
            close($f_id);
        }
    }

    return($road_backward,$road_forward);
}
sub package_transforms_MDT {
    # Collects transforms of "ThisPackage/MDT" from the input location, to the output location. 
    # annotates the TargetDataPackage and CollectionSource with the transforms, making the transforms 
    # an independent unit(in case we want that).
    # The work between specimen and mdt is very subtly different, its not clear they could be merged.
    my($ThisPackageInRoot,$ThisPackageOutLocation,$ThisPackageName,$TargetDataPackage,$CollectionSource)=@_;
    #my($inpath,$ThisPackageOutLocation,$DataPackage,$TargetDataPackage,$source_ident)=@_;
###
# Get the affine
###
# do this first so we dont leave a mess if it fails.
    my $aff=qx(ls $ThisPackageInRoot/stats_by_region/labels/transforms/MDT_*_to_${TargetDataPackage}_affine.*) 
        || die "affine find fail";
    chomp($aff);
###
# make Package foward and reverse directories
###
    my($road_backward,$road_forward)=transform_dir_setup($ThisPackageInRoot,$ThisPackageOutLocation,$ThisPackageName,
                                                         $TargetDataPackage,$CollectionSource);
###
# link the affine
###
    my $ThisPackage_TargetDataPackage_affine=File::Spec->catfile(${road_backward},basename($aff));
    if ( ! -e $ThisPackage_TargetDataPackage_affine ) {
        qx(ln -vs $aff $ThisPackage_TargetDataPackage_affine);
    }
###
# get the warp
###
    my $warp=File::Spec->catfile("$ThisPackageInRoot","stats_by_region","labels","transforms","MDT_to_${TargetDataPackage}_warp.nii.gz");
    my $ThisPackage_TargetDataPackage_warp=File::Spec->catfile(${road_backward},basename( $warp));
    if ( ! -e $ThisPackage_TargetDataPackage_warp ) {
        die "EXPCTED warp missing !($warp)" unless -e $warp ;
        qx(ln -s $warp $ThisPackage_TargetDataPackage_warp);
    }
###
# get the "inverse" warp.
###
    $warp=File::Spec->catfile("$ThisPackageInRoot","stats_by_region","labels","transforms","${TargetDataPackage}_to_MDT_warp.nii.gz");
    my $TargetDataPackage_ThisPackage_warp=File::Spec->catfile($road_forward,basename( $warp));
    if (  ! -e $TargetDataPackage_ThisPackage_warp ) {
        qx(ln -s $warp $TargetDataPackage_ThisPackage_warp);
    }
### 
# kajigger the "inverse" affine"
###
# this file doesent exist yet, we have to create it, we do this to simply the usage syntax so 
# we have an explict transform instead of implict.
    my $n_ThisPackage_t_a=basename($ThisPackage_TargetDataPackage_affine);
    $n_ThisPackage_t_a=~ s/MDT_(.+)_to_${TargetDataPackage}_(.*)$/${TargetDataPackage}_to_MDT_$1_$2/;
    my $TargetDataPackage_ThisPackage_affine="$road_forward/".$n_ThisPackage_t_a;
    #my $antsCreateInverse="ComposeMultiTransform 3 ${TargetDataPackage_ThisPackage_affine} -i ${ThisPackage_TargetDataPackage_affine} && ConvertTransformFile 3 ${TargetDataPackage_ThisPackage_affine} ${TargetDataPackage_ThisPackage_affine} --convertToAffineType";
    my($p,$n,$e)=fileparts(${TargetDataPackage_ThisPackage_affine},3);
    my $p_i_t_c=File::Spec->catfile($p,$n.".sh");
    
    my ($i_out,$i_cmd);
    ($i_out,$i_cmd)=create_explicit_inverse_of_ants_affine_transform(
	$ThisPackage_TargetDataPackage_affine, $TargetDataPackage_ThisPackage_affine);
    if (  ! -e $p_i_t_c ) {
	open(my $f_id,'>',$p_i_t_c);
	print($f_id "#!/bin/bash\n$i_cmd;\n");
	close($f_id);
	#print($f_id "#!/bin/bash\ncd $p;$antsCreateInverse;\n");
        #close($f_id);
    }
    if (  ! -z "$ThisPackage_TargetDataPackage_affine" && ! -e $TargetDataPackage_ThisPackage_affine ) {
        print("have $ThisPackage_TargetDataPackage_affine create $TargetDataPackage_ThisPackage_affine\n");
        qx(bash $p_i_t_c);
    } elsif (  -z "$ThisPackage_TargetDataPackage_affine" || ! -e "$ThisPackage_TargetDataPackage_affine" ) {
        die("Missing(or bad file) $ThisPackage_TargetDataPackage_affine");
        
    }
###
# Create ordered links ( relative links to files in same folder just for our future selve's book keeping.
###
# WARNING: These are the not in ants specification order(which is backwards). 
# This is part of why we get a readme in each bunch.
# Backward path
    my ($t,$p_t);
    $t="_2_${ThisPackageName}_to_${TargetDataPackage}_warp.nii.gz";
    $p_t=File::Spec->catfile(${road_backward},$t);
    if (  ! -e $p_t ) {
        $t=basename $ThisPackage_TargetDataPackage_warp;
        qx(ln -sv $t $p_t);
    }
    $t="_1_${ThisPackageName}_to_${TargetDataPackage}_affine.mat";
    $p_t=File::Spec->catfile(${road_backward},$t);
    if (  ! -e $p_t ) {
        $t=basename $ThisPackage_TargetDataPackage_affine;
        qx(ln -sv $t $p_t);
    }
# Forward path
    $t="_2_${TargetDataPackage}_to_${ThisPackageName}_affine.mat";
    $p_t=File::Spec->catfile(${road_forward},$t);
    if (  ! -e $p_t ) {
        $t=basename $TargetDataPackage_ThisPackage_affine;
        qx(ln -sv $t $p_t);
    }
    $t="_1_${TargetDataPackage}_to_${ThisPackageName}_warp.nii.gz";
    $p_t=File::Spec->catfile(${road_forward},$t);
    if (  ! -e $p_t ) {
        $t=basename $TargetDataPackage_ThisPackage_warp;
        qx(ln -sv $t $p_t);
    }
    return;
}

sub package_transforms_SPEC {
    my ($ThisPackageInRoot,$ThisPackageOutLocation,$ThisPackageName,$TargetDataPackage,$CollectionSource)=@_;
    
###
# Get the affine transforms
###
# do this first so we dont leave a mess if it fails.
# we may need to be sensitive to the affine_target.txt file that is in that directory. 
    # get affine path which is sitting outside("above") the mdt folder. 
    #my $affpath=File::Spec->catfile($BIGGUS_DISKUS,
    #  sprintf("%s-work",$n_vbm),
    #  $c_r );
    my $affpath=File::Spec->catdir($ThisPackageInRoot,File::Spec->updir(),File::Spec->updir());
    my $rig=qx(ls $affpath/${ThisPackageName}_rigid.*)  || die "rigid find fail";
    my $aff=qx(ls $affpath/${ThisPackageName}_affine.*) || die "affine find fail";
    chomp($rig); chomp($aff);

###
# make Package foward and reverse directories
###
    my($road_backward,$road_forward)=transform_dir_setup($ThisPackageInRoot,$ThisPackageOutLocation,$ThisPackageName,
                                                         $TargetDataPackage,$CollectionSource);
###
# handle affines (link/invert)
###
    my ($r_suff)=$rig =~ /.*_(rigid.*)/x;
    my ($a_suff)=$aff =~ /.*_(affine.*)/x;

    # Confusion on which direction of transform we have on hand.
    # Tried these first, but didnt get right answer, though, they're clearly right.
    my $TargetDataPackage_ThisPackageName_rigid=File::Spec->catfile(${road_forward},sprintf("MDT_to_%s_%s",$ThisPackageName,$r_suff));
    my $ThisPackageName_TargetDataPackage_rigid=File::Spec->catfile(${road_backward},basename($rig));
    
    #my $TargetDataPackage_ThisPackageName_rigid=File::Spec->catfile(${road_forward},basename($rig));
    #my $ThisPackageName_TargetDataPackage_rigid=File::Spec->catfile(${road_backward},sprintf("%s_to_MDT_%s",$ThisPackageName,$r_suff));
    my ($i_out,$i_cmd);
    if ( ! -e $TargetDataPackage_ThisPackageName_rigid) {
        if ( 0 ) {
            qx(ln -vs $rig $TargetDataPackage_ThisPackageName_rigid);
        } else {
            ($i_out,$i_cmd)=create_explicit_inverse_of_ants_affine_transform($rig,$TargetDataPackage_ThisPackageName_rigid);
            my $create_inv=File::Spec->catfile($road_forward,
                                               ".create_inverse_R.sh");
            open(my $f_id,'>',$create_inv);
            print($f_id "#!/bin/bash\n$i_cmd;\n");
            close($f_id);
        }
    }
    if ( ! -e $ThisPackageName_TargetDataPackage_rigid) {
        if ( 0 ) { 
            qx(ln -vs $rig $ThisPackageName_TargetDataPackage_rigid);
        } else {
            ($i_out,$i_cmd)=create_explicit_inverse_of_ants_affine_transform(
                $rig,$ThisPackageName_TargetDataPackage_rigid);
            my $create_inv=File::Spec->catfile($road_forward,
                                               ".create_inverse_R.sh");
            open(my $f_id,'>',$create_inv);
            print($f_id "#!/bin/bash\n$i_cmd;\n");
            close($f_id);
        }
    }
    my $TargetDataPackage_ThisPackageName_affine=File::Spec->catfile(${road_forward},sprintf("MDT_to_%s_%s",$ThisPackageName,$a_suff));
    my $ThisPackageName_TargetDataPackage_affine=File::Spec->catfile(${road_backward},basename($aff));
    if ( ! -e $TargetDataPackage_ThisPackageName_affine ) {
        ($i_out,$i_cmd)=create_explicit_inverse_of_ants_affine_transform($aff,$TargetDataPackage_ThisPackageName_affine);
        my $create_inv=File::Spec->catfile($road_forward,".create_inverse_A.sh");
        open(my $f_id,'>',$create_inv);
        print($f_id "#!/bin/bash\n$i_cmd;\n");
        close($f_id);
    }
    if ( ! -e $ThisPackageName_TargetDataPackage_affine ) {
        qx(ln -vs $aff $ThisPackageName_TargetDataPackage_affine);
    }
###
# get the warp
###
    #my $warp=File::Spec->catfile("$ThisPackageInRoot","stats_by_region","labels","transforms","MDT_to_${ThisPackageName}_warp.nii.gz");
    my $warp=File::Spec->catfile("$ThisPackageInRoot","reg_diffeo","MDT_to_${ThisPackageName}_warp.nii.gz");
    my $TargetDataPackage_ThisPackageName_warp=File::Spec->catfile(${road_forward},basename( $warp));
    if ( ! -e $TargetDataPackage_ThisPackageName_warp ) {
        die "EXPCTED warp missing !($warp)" unless -e $warp ;
        qx(ln -s $warp $TargetDataPackage_ThisPackageName_warp);
    }
###
# get the "inverse" warp.
###
    #$warp=File::Spec->catfile("$ThisPackageInRoot","stats_by_region","labels","transforms","${ThisPackageName}_to_MDT_warp.nii.gz");
    $warp=File::Spec->catfile("$ThisPackageInRoot","reg_diffeo","${ThisPackageName}_to_MDT_warp.nii.gz");
    my $ThisPackageName_TargetDataPackage_warp=File::Spec->catfile($road_backward,basename( $warp));
    if (  ! -e $ThisPackageName_TargetDataPackage_warp ) {
        qx(ln -s $warp $ThisPackageName_TargetDataPackage_warp);
    }
###
# Create ordered links ( relative links to files in same folder just for our future selve's book keeping.
###
# WARNING: These are the not in ants specification order(which is backwards). 
# forward path
    my ($t,$p_t);
    $t="_1_${TargetDataPackage}_to_${ThisPackageName}_warp.nii.gz";
    $p_t=File::Spec->catfile(${road_forward},$t);
    if (  ! -e $p_t ) {
        $t=basename $TargetDataPackage_ThisPackageName_warp;
        qx(ln -sv $t $p_t);
    }
    $t="_2_${TargetDataPackage}_to_${ThisPackageName}_affine.mat";
    $p_t=File::Spec->catfile(${road_forward},$t);
    if (  ! -e $p_t ) {
        $t=basename $TargetDataPackage_ThisPackageName_affine;
        qx(ln -sv $t $p_t);
    }
    $t="_3_${TargetDataPackage}_to_${ThisPackageName}_rigid.mat";
    $p_t=File::Spec->catfile(${road_forward},$t);
    if (  ! -e $p_t ) {
        $t=basename $TargetDataPackage_ThisPackageName_rigid;
        qx(ln -sv $t $p_t);
    }
    
# backward path
    $t="_1_${ThisPackageName}_to_${TargetDataPackage}_rigid.mat";
    $p_t=File::Spec->catfile(${road_backward},$t);
    if (  ! -e $p_t ) {
        $t=basename $ThisPackageName_TargetDataPackage_rigid;
        qx(ln -sv $t $p_t);
    }
    $t="_2_${ThisPackageName}_to_${TargetDataPackage}_affine.mat";
    $p_t=File::Spec->catfile(${road_backward},$t);
    if (  ! -e $p_t ) {
        $t=basename $ThisPackageName_TargetDataPackage_affine;
        qx(ln -sv $t $p_t);
    }
    $t="_3_${ThisPackageName}_to_${TargetDataPackage}_warp.nii.gz";
    $p_t=File::Spec->catfile(${road_backward},$t);
    if (  ! -e $p_t ) {
        $t=basename $ThisPackageName_TargetDataPackage_warp;
        qx(ln -sv $t $p_t);
    }
# END arranging
    return;
}

sub package_labels_SPEC { 
#    ($mdtpath,$output_path,$Specimen,$mdtname,$n_vbm);
    #my($ThisPackageInRoot,$ThisPackageOutLocation,$ThisPackageName,$TargetDataPackage,$CollectionSource)=@_;
    my($ThisPackageInRoot,$ThisPackageOutLocation,$ThisPackageName,$LabelNick,$CollectionSource)=@_;
    # root - /mnt/civmbigdata/civmBigDataVol/jjc29/VBM_18enam01_chass_symmetric3_RAS_A2-work/dwi/SyN_0p25_3_0p5_fa/faMDT_all_n8_i6
    # /stats_by_region/labels/pre_rigid_native_space/WHS
    my $source_label_root=File::Spec->catfile($ThisPackageInRoot,'stats_by_region','labels','pre_rigid_native_space');
    #my @label_nicks=find_file_by_pattern($source_label_root,'.*',1);
    # have
    #data_NICK_labels_lookup.txt
    #data_NICK_labels.nii.gz
    #data_NICK_labels_RAS.nii.gz
    # Should only grab one labels file, the RIGHT one. 
    # That is, if workingorientation is RAS, grab normal, else ... grab normal? Wait thats funnny :D Must verify. 
    # Using headers to verify, yes when working orientation is RAS(which it should be from now on)
    # the label fields are equivalent. 
    #
    # There are header discrepancies.
    #
    # That is probably becuase the plain file is an ANTs(ITK) nifti,
    # and the other file is a matlab nifti.
    # We're going in sloppy for now just intentionally removing RAS using a hash filter of the discovered files. 
    # Filtering is tough becuase of full paths etc... so to heck with it.
    my $label_folder=File::Spec->catfile($ThisPackageOutLocation,"labels");
    my $nick_folder=File::Spec->catfile($label_folder,"WHS");
    if ( ! -d $nick_folder ) {
        make_path($nick_folder);
    }
    my $label_in_folder=File::Spec->catfile($source_label_root,$LabelNick);
    my $sub_lookup=transmogrify_folder($label_in_folder,$nick_folder,$ThisPackageName,$ThisPackageName);
    # Filter out the redundant RAS copy
    my $regex='.*RAS.*';
    # In case RAS is in our labelnick(which it could be if we didnt use one), reset the filter to nothing found
    if ($LabelNick =~ /$regex/ ) { 
        $regex='AnUnmatachableString';
    }
    while (my ($key, $value) = each %$sub_lookup ) {
        if ( basename($key) =~ /$regex/ ) {
            delete $sub_lookup->{$key};
        }
    }
    # get the stats file( if its there)
    my $stat_pat="^${ThisPackageName}_${LabelNick}_(measured|labels)_in_[^_]+_space(_.+)*\.(csv|txt|xlsx?)\$";
    my ($stat_file)=find_file_by_pattern($label_in_folder,$stat_pat);
    if ( defined $stat_file && -e $stat_file ) { 
        my $stat_dest=File::Spec->catfile($nick_folder,basename($stat_file));
        if ( ! -e $stat_dest ) {
            $sub_lookup->{$stat_file}=$stat_dest;
        }
    }
    # Debug die showing everything to "transfer".
    #Data::Dump::dump($label_in_folder,$stat_pat,$sub_lookup);die;
    while (my ($key, $value) = each %$sub_lookup ) {
        qx(ln -vs $key $value);
    }

    return;
}
sub fix_ts_new {
    # find all files in direcotory that are not "file"
    # set timestamp of "file" to the newest one found
    #
    # This is a tall order for repeatibility so it is currently abandoned.
    my ($directory,$file)=@_;
    my @files=find_file_by_pattern($directory,'.*');
    my @correct_set= grep(!/$file/xi, @files);
    @files = grep(/$file/xi, @files);
    my $reference_file=file_mod_extreme(\@correct_set,'new');
    Data::Dump::dump((\@correct_set,$reference_file,\@files));die;
    foreach (@files) {
	timestamp_copy($reference_file,$_);
    }
}

sub record_metadata {
    # record_metadata sets all link timestamps to their true source as found by
    # resolve_link and then runs ls -lR on the directory.
    my ($output_path)=@_;
    # find all files in this output_path
    my @files=find_file_by_pattern($output_path,'.*');
    foreach (@files) {
	#my $rp=resolve_link($_); 
	my $rp = Cwd::realpath($_);
	if ( ! -e $_ ) { 
	    confess "issue resolving $_ to its true path, failed at $_";
	}
	if ( -e $rp && -e $_ ) {
	    qx(touch -hr $rp $_);
	} else {
	    die "error on resolve $_, got $rp";
	}
	# save file meta data listing before someone gets the chance to transfer it
	# might be nice to play timestamp games with this to set its timestamp 
	# to the newest file(not folder) of the output...
    }
    my $meta_record_cmd=sprintf("ls -lR %s &> %s/.file_meta.log",$output_path,$output_path);
    qx($meta_record_cmd);
    return;
}

1;
