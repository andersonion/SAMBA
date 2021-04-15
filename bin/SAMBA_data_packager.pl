#!/usr/bin/env perl
# This was created as to help organize warp chains.
# This is also used to help get data ready for archive
#
# This only creates links, and will only work for the person running the study!
#
# this is one part of the larger idea of "promote" to atlas for an MDT, which we'll
# use as the targetatlas of future SAMBA runs.
#



# sys level include
use strict;
use warnings;
use Carp qw(carp croak cluck confess);

use Cwd qw(abs_path);
use File::Basename;
use File::Path qw(make_path);
use Getopt::Std;
use Scalar::Util qw(looks_like_number);
use List::MoreUtils qw(uniq);

# BOILER PLATE
BEGIN {
    # we could import radish_perl_lib direct to an array, however that complicates the if def checking.
    my @env_vars=qw(RADISH_PERL_LIB BIGGUS_DISKUS WORKSTATION_DATA WORKSTATION_HOME);
    my @errors;
    use Env @env_vars;
    foreach (@env_vars ) {
        push(@errors,"ENV missing: $_") if (! defined(eval("\$$_")) );
    }
    die "Setup incomplete:\n\t".join("\n\t",@errors)."\n  quitting.\n" if @errors;
}
use lib split(':',$RADISH_PERL_LIB);
# my absolute fav civm_simple_util components.
use civm_simple_util qw(activity_log printd $debug_val);

use pipeline_utilities;
# pipeline_utilities uses GOODEXIT and BADEXIT, but it doesnt choose for you which you want.
$GOODEXIT = 0;
$BADEXIT  = 1;
# END BOILER PLATE
use civm_simple_util qw(activity_log can_dump file_trim load_file_to_array write_array_to_file find_file_by_pattern file_mod_extreme is_writable round printd whoami whowasi debugloc sleep_with_countdown $debug_val $debug_locator);
use Headfile;

# ex of use lib a module (called MyModule) in current dir
# use lib dirname(__FILE__) . "MyModule";

use lib dirname(abs_path($0));
use lib File::Spec->catdir(dirname(abs_path($0)),'..');
#use SAMBA_global_variables;
use SAMBA_structure;

exit main();

sub main {
    activity_log();
    # must define the options hashref before referincing inside it...of course.
    my $output_base;
    my $hf_path;
    my $mdtname;
    my $mdt_out_path;
    my $v_ok;

    my $opts={};
    $opts->{"output_base=s"}=\$output_base;
    $opts->{"hf_path=s"}=\$hf_path;
    $opts->{"mdtname=s"}=\$mdtname;

    # mdtdir prefixes for the mdt dir.
    ${$opts->{"mdtdir_prefix=s"}}="MDT_";
    $opts->{"mdt_out_path=s"}=\$mdt_out_path;
    # this disables that behavior, alternatively you could specify --mdtdir_prefix=""
    ${$opts->{"disable_mdtdir_prefix"}}=0;
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
    ${$opts->{"instant_feedback!"}}=1;
    $opts=auto_opt($opts,\@ARGV);

    # insert positionals if we didnt get --args
    if ( ! defined $mdtname ) {
        $mdtname=$ARGV[2];
        printd(80,"POSITIONAL mdtname ($mdtname)\n") if defined $mdtname;
    }
    if ( ! defined $hf_path ) {
        $hf_path=$ARGV[1];
        printd(80,"POSITIONAL hf_path ($hf_path)\n") if defined $hf_path;
    }
    if ( ! defined $output_base ) {
        $output_base=$ARGV[0];
        printd(80,"POSITIONAL output_base ($output_base)\n") if defined $output_base;
    }

    # Fomer handling of output/mdtnaming was confusing.
    # Promoting everything to a proper option while trying to handle the original behavior as kindly as possible.
    # Added instant_feedback option default on to show users what we're going do and then STOP before we do it.

    # Ex. flag option usage for my reference.
    #if( ${$opts->{"FLAG"}} ) {
    #}
    if( ${$opts->{"disable_mdtdir_prefix"}} ) {
        ${$opts->{"mdtdir_prefix"}}="";
    }
    # If min args not defined here, quit with request for good minimal args
    # output_base could output_base/mdt_out_dirname at this point, we resolve that just after loading the headfile
    if(! defined $output_base || ! defined $hf_path ) {
        die "Need mininmum args! please specify --output_base=/path/to/samba_paks/ --mdtname=template_group_criteria --hf_path=/path/to/some_samba.headfile\n";
    }

    ###
    # Read headfile
    ###
    my @input_errors;
    my $hf=new Headfile ('ro', $hf_path);
    $hf->check() or push(@input_errors,"Unable to open $hf_path\n");
    $hf->read_headfile or push(@input_errors,"Unable to read $hf_path\n");

    # use the results_dir key to see if we're a results headfile or not.
    ($v_ok,my $main_results)=$hf->get_value_check("results_dir");
    my $main_dir;
    if ( ! $v_ok ) {
        # If we're not a results headfile, try to find our results headfile and
        # merge it with the input one so we have all the vars, and many will be
        # exactly right.
        #printd(5,"WARNING: Input headfiles not well supported\n");
        require SAMBA_global_variables;
        my @unused_vars=SAMBA_global_variables::populate($hf);
        my @individuals=SAMBA_global_variables::all_runnos();
        my $pc="CODE_NOT_FOUND";
        $pc=${SAMBA_global_variables::project_name} or push(@input_errors,'Global project_name not found');
        my $ran="RIGID_ATLAS_NOT_FOUND";
        $ran=${SAMBA_global_variables::rigid_atlas_name} or push(@input_errors,'Global rigid_atlas_name not found');
        my $opt_s="OPTIONAL_SUFFIX_NOT_FOUND";
        $opt_s=${SAMBA_global_variables::optional_suffix} or push(@input_errors,'Global optional_suffix not found');
        $main_dir=SAMBA_structure::main_dir($pc, scalar(@individuals),$ran,$opt_s);

        my $r_hfp=File::Spec->catfile($ENV{"BIGGUS_DISKUS"},$main_dir."-results","$main_dir.headfile");
        my $rhf=new Headfile ('ro', $r_hfp );
        $rhf->check() or push(@input_errors,"Unable to open $r_hfp\n");
        $rhf->read_headfile or push(@input_errors,"Unable to read $r_hfp\n");
        # Copy our results hf in, overwriting the inputs(as would have happend in pipeline)
        $hf->copy_in($rhf);
        ($v_ok,$main_results)=$hf->get_value_check("results_dir");
    }


    if ( scalar(@input_errors)>0 ){
        die join('',@input_errors);
    }
    ($v_ok,my $o_s)=$hf->get_value_check("optional_suffix");
    if (!$v_ok) { $o_s=''; }

    ###
    # Final chance to resolve mdtname.
    ###
    if(! defined $mdtname ){
        # neither positional mdtname nor option specified.
        # Last chance try it as part of our outputbase.
        # output_base MUST be defined for this to work.
        # That is only supported if the final dir component starts with MDT[-_]
        #  OR maybe, we could allow a specified mdtdir_prefix
        #
        my ($p,$n,$e)=fileparts($output_base,2);
        # Maybe we should force case here? Final decision is to force uniform case, but not decide otherwise.
        # $mp=uc($mp);
        # $mp=lc($mp);
        my ($mp,$sep,$mn) = $n =~ m/^(mdt|MDT)([-_])(.+)$/x;
        if(defined $mp && $mp =~ m/mdt/ix ) {
            if (  ( !  ( ${$opts->{"mdtdir_prefix"}} eq ""
                         || ${$opts->{"mdtdir_prefix"}} eq "MDT_" )  )
                  && ${$opts->{"mdtdir_prefix"}} ne $mp.$sep  ) {
                die "GUESSING mdtdir_prefix is dangerous, You should be more specific (add your mdtname to input args).\n";
            }
            ${$opts->{"mdtdir_prefix"}}=$mp.$sep;
            $mdtname=$mn;
            $output_base=$p;
        } else {
            # if mdtname not set, and we had an o_s assume the o_s is mdname, else error
            if ( $o_s ne '' ) {
                printd(5,"no mdtname specified, but we found an optional suffix $o_s, this is what we're going to call the mdt, it will be in all your transform names for this set of packaged data.\n"
                   ."IF YOU DON'T LIKE THAT CANCEL NOW AND SPECIFY AN MDTNAME on the command line\n");
                sleep_with_countdown(8) if ( $debug_val < 15 && ! ${$opts->{"instant_feedback"}} ) ;
                $mdtname=$o_s;
            } else {
                die "optional_suffix not available, Reqired arg missing ( --mdtname=template_group_criteria )\n";
            }
        }
    }
    if ($mdtname =~ m/mdt/ix ) {
        croak "your requested mdtname($mdtname) has MDT in it, this will generate trouble!\n"
            ." IF you want your folder containing the MDT to have MDT in it, you can do that,\n"
            ."    use the option --mdtname=NAME ";
    }
    if ( ! defined $mdt_out_path ) {
        $mdt_out_path=File::Spec->catdir($output_base,${$opts->{"mdtdir_prefix"}}.$mdtname);
        printd(80,"mdt_out_path auto-gen to $mdt_out_path\n");
        #die( "Not enough input arguments, please specify your mdt_out_path, SAMBA startup file, and optionally the MDT name\n");
    }

    # squash any bonus path separators and remove trailing ones.
    $mdt_out_path=file_trim($mdt_out_path);
    $output_base=file_trim($output_base);

    my $SingleSegMode=0;
    ###
    # This whole path resolution segment belongs in some "samba_helper.pm" file.
    # something like "samba pathing" ... or "samba structure"
    ###

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
    } elsif (scalar(@individuals)==1) {
        ## Detect SingleSeg mode.
        $SingleSegMode=1;
        printd(5,"SingleSegmentation Mode, there is no MDT, Sorry there is some handwaving in this mode.\n");
        # Postfixing the data name with Reg for use in capturing the transforms from the MDT dir.
        # Then we merge transform links,
        # from: Atlas <-> SpecRig <-> Spec
        #   to: Atlas <-> Spec
        # and then remove any identity transforms.
        $mdtname=$individuals[0]."Rig";
        my $Specimen=$individuals[0];
        ${$opts->{"link_images"}}=0;
        $mdt_out_path=File::Spec->catfile($output_base,$Specimen);
        printd(5,"Adjusted \"MDT\" Transforms to $mdtname\n");
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
    #my $l;
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

    ###
    # name of vbm folder, there will be three sibling direcrories with this prefix, that is -inputs, -work, and -results.

    # if given a results headfile, the vbm name is explicitly specified, under a strange key "project_id"
    # That is more reliable than making it up in place, so if its available we'll use it.
    # alternate names might make sense, like
    # analysis_name, analysis_id, process_name, VBM_name, working_name, SAMBA_process, SAMBA_data, local_name, local_storage etc.
    # The thing wrong with project_id, is that sounds like project_code, and thats confusing.
    my $n_vbm;
    ($v_ok,my $n_vbm_r)=$hf->get_value_check("project_id");
    if( $v_ok ){
        $n_vbm=$n_vbm_r;
    } else {
        printd(5,"Main work dir not found in input headfile.\n");
        # Second best try is our new "main_dir" function
        #$n_vbm=SAMBA_structure::main_dir($n_p,scalar(@individuals),$n_a_r,$o_s);
        # main_dir set much earlier now
        $n_vbm=$main_dir;
        ###
        # Custom vbm folder naming code, now deprecated in favor of SAMBA_global_vars::main_dir(code,count,atlas,
        my $main_work=File::Spec->catdir($BIGGUS_DISKUS,$n_vbm.'-work');
        if ( ! -e $main_work ) {
            printd(5,"Main work dir not found with $n_vbm");
            my @vbmname_parts=("VBM");
            push(@vbmname_parts,$n_p,$n_a_r);
            if ($o_s ne ''){
                push(@vbmname_parts,$o_s);  }
            #my $n_vbm=sprintf("VBM_%s_%s%s",$n_p,$n_a_r,$o_s);
            $n_vbm=join("_",@vbmname_parts);
        }
        ###
    }
    # get affine path which is sitting outside("above") the mdt folder.
    # Its a constant up two, so we're gonna switch to just that now.
    #my $affpath=File::Spec->catfile($BIGGUS_DISKUS,
    #                                sprintf("%s-work",$n_vbm),
    #                                $c_r );
    # template_work_dir may be hfkey alternative for mdtpath.
    ( $v_ok,my $mdtpath) = $hf->get_value_check("template_work_dir");
    if ( ! $v_ok ) {
        $mdtpath=File::Spec->catfile($BIGGUS_DISKUS,
                                     sprintf("%s-work",$n_vbm),
                                     $c_r,
                                     sprintf("SyN_%s_%s",$p_d,$c_mdt),
                                     sprintf("%sMDT_%s_n%i_i%i",$c_mdt,$mdt_p,$MDT_n,$i_mdt)  );
    }
    if(! -e $mdtpath ) {
        die("MDTPATH SET failed! Got $mdtpath");
    }
    # the anoyingly named "inputs_dir" which is NOT the -inputs dir!
    ( $v_ok,my $base_images) = $hf->get_value_check("inputs_dir");
    if ( ! $v_ok ) {
        $base_images=File::Spec->catfile($BIGGUS_DISKUS,
                                         sprintf("%s-inputs",$n_vbm),
                                         "preprocess",
                                         "base_images"  );
    }
    ####
    # Now that samba structural elements are resolved, we can begin our work proper.
    ##########


    if ($debug_val==100 ) {
        Data::Dump::dump(($mdt_out_path));
        die "db:100 stop";
    }
    if( ${$opts->{"instant_feedback"}} ){
        Data::Dump::dump($opts) if can_dump();
	display_complex_data_structure($opts) if ! can_dump();
        printf( "Packing \"MDT\" into $mdt_out_path\n"
                ."  (from deep in $n_vbm\n"
                ."\t".File::Spec->catdir($mdtpath,'median_images')."\n  )\n"
                ."and specimen data into ".File::Spec->catdir($output_base,"Specimen")." (probably arranged by runno)\n"
            );
        my $proceed='NULL';
        while($proceed !~ /^[yn]?$/ix ) {
            $proceed=user_prompt("Do you with to proceed? (Y/n)"); }
        if ($proceed !~ /^y?$/ix ) {
            die "User requested halt\n";
        }
    }
    ####
    # handle MDT median_images
    ###
    if( -d $mdt_out_path) {
        warn("output ($mdt_out_path) already exists! attempting validation\n");
    }  elsif(! -e $mdt_out_path ) {
        make_path($mdt_out_path) or die $!;
    }
    if ( ${$opts->{"link_images"}} ) {
        my $in_im_dir=File::Spec->catfile($mdtpath,"median_images");
        print("MDT images from $in_im_dir\n");
        my $mdt_lookup={};
        ###
        # discover images to link
        ###
        $mdt_lookup=transmogrify_folder($in_im_dir,$mdt_out_path,'MDT',$mdtname);
        if ( scalar(keys(%$mdt_lookup)) ) {
            ###
            # do the linking of images
            ###
            print("\t Linking up images\n");
            while (my ($key, $value) = each %$mdt_lookup ) {
		#  copy_paired_data($in_file,$out_file,$prep,$update,$link_mode)=@_;
		if($key =~ /[.](nhdr|nrrd)$/){
		    copy_paired_data($key,$value,0,1,0);
		} else {
		    qx(ln -vs $key $value);
		}
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
        my $lo_o=File::Spec->catfile($mdt_out_path,"labels_${mdtname}");
        # "accepted standard" labels out
        my $lo=File::Spec->catfile($mdt_out_path,"labels");
        # if labels available for linkage
        if ( -e $lp  ) {
            # handle move former spec
            if ( ! -e $lo && -e $lo_o  ) {
                qx(mv $lo_o $lo);
            }
            # If we havnt got them yet, make symbolic link stack for labels folder
	    # This is to capture all the meta data tracking out of the pipeline.
            # This is only done the first time. If we have need to repeat this(due to pipeline additions)
            # best practice would be to remove the existing labels package.
            if(! -e $lo) {
                mkdir($lo);
                qx(lndir $lp $lo);
            }
            # handle label nicks(dir)
            my $ln=File::Spec->catfile($lo,$n_a_l_n);
            if(! -e $ln) {
                mkdir($ln);
            }
            # run through link stack setting up the name.
	    # if the name(and location) is already righteous we will not do anything
            my $sub_lookup=transmogrify_folder($lo,$ln,'MDT',$mdtname);
            while (my ($key, $value) = each %$sub_lookup ) {
		if($key =~ /[.](nhdr|nrrd)$/){
		    printd(25,"$key .. $value");
		    copy_paired_data($key,$value,0,1,'move');
		} else {
		    qx(mv $key $value);
		}
            }
        }
    } else {
        print("\tNot linked today, just getting the transforms together.\n");
    }
# transcribe the name of the atlas for labels into targetatlas for code clarity.
    my $TargetDataPackage=$n_a_l;
    package_transforms_MDT($mdtpath,$mdt_out_path,$mdtname,$TargetDataPackage,$n_vbm);
    #fix_ts_new($mdt_out_path,'README.txt');
    record_metadata($mdt_out_path);
# END arranging

    ###
    # Handle per specimen images as measured.
    ###
    # There are other specimen images available, but this seems like the best choice.
    ($v_ok, my $hf_dir)=$hf->get_value_check('pristine_input_dir');
    if(! $v_ok ){
        undef $hf_dir;
    }
    # While we say specimen here, we may actually have runnos's... You were warned.
    my @spec_errs;
    for my $Specimen (@individuals) {
        my $spec_out_path=File::Spec->catfile($output_base,$Specimen);
        if( -d $spec_out_path) {
            warn("output ($spec_out_path) already exists! attempting validation\n");
        }  elsif(! -e $spec_out_path ) {
            make_path($spec_out_path) or die $!;
        }
        # pre_rigid_native_space should actually be the measure space....
        # Best science comes from untouched voxels, (we think)
        # so hard coding this isn't the worst idea.
        # New updates in the labels have ruined this structure finding
        # Furhter complicating things the output results headfile only has one entry for the label_images_dir and it gets overwritten for each measure space.
        # That should be fixed, but before that we need to most always grab pre_rigid_native_space
        # Turns out that is "preprocess" 99+% of the time, 99+% of the time base-images just links up to preprocess.
        # When it doesn't, it's not clear if there is an error or not, so we'll handle those one at a time manually
        # Annoyingly the preprocess and base_images names ARE NOT DESIRED OUTPUT NAMES.
        # we're gonna hide the renamey in transmogrify.
        my $in_im_dir=multi_choice_dir(
            [
             $base_images,
             File::Spec->catfile($mdtpath,"vox_measure","pre_rigid_native_space"),
             File::Spec->catfile($mdtpath,"stats_by_region","labels","pre_rigid_native_space","images"),
             # $hf->get_value("label_images_dir"),
            ]
            );
	
        #my $sub_lookup=transmogrify_folder($in_im_dir,$spec_out_path,$Specimen,$Specimen);
        # 4 part macthcing, speimen, _something{1..n}, _masked{0,1}, compoundext
        my $inpat="($Specimen)((?:_[^_]+)+?)(_masked)?((?:[.][^.]+)+)\$";
        my $outpat='$1$2$4';
        #$outpat='\1\2\4';
        my $sub_lookup=transmogrify_folder($in_im_dir,$spec_out_path,$inpat,$outpat);
        if ( scalar(keys(%$sub_lookup)) ) {
            print("\t Linking up images\n");
            while (my ($key, $value) = each %$sub_lookup ) {
		if($key =~ /[.](nhdr|nrrd)$/){
		    copy_paired_data($key,$value,0,1,"copy");
		} else {
		    qx(ln -vs $key $value);
		}
            }
        }
        # we were missing TRANSLATION FROM INPUTS TO BASE IMAGES, !
        # THE FULL WORK is inputs->reorient+mask(preprocess)->translation(base_images)
	my $translation_xforms=File::Spec->catfile($base_images,"translation_xforms");
	my ($translator)=civm_simple_util::find_file_by_pattern($translation_xforms,$Specimen.".*InitialMovingTranslation[.].*");
	if( ! defined $translator){
	    croak("suspicious! We didnt find a translator! typically we find those!");
	} else {
	    printd(45,"translator found for $spec_out_path at $translator\n");
	}
	# not sure if we have the fwd or the back transform.
        # Ref is first, img is second
	my $transform_dir=File::Spec->catdir($spec_out_path,"transforms");
	if(! -d $transform_dir){
	    mkdir($transform_dir);
	}
	my $translator_fwd=File::Spec->catfile(${transform_dir},$Specimen."inputs"."_to_".$Specimen."work.mat");
	if( ! -e $translator_fwd){ qx(ln -vs $translator $translator_fwd); }
	my $translator_bak=File::Spec->catfile(${transform_dir},$Specimen."work"."_to_".$Specimen."inputs.mat");
	if( ! -e $translator_bak){ 
	    my $create_inv=File::Spec->catfile(${transform_dir},".create_inv_t_translator.sh");
	    create_inverse_affine_transform($create_inv, $translator, $translator_bak);
	}
        package_transforms_SPEC($mdtpath,$spec_out_path,$Specimen,$mdtname,$n_vbm);
        if ( $SingleSegMode ) {
            # When in single seg mode we have a messy batch of transform in our directory.
            # This'll fix that by combining link dirs,and re-numbering, then pruning any identity files
            merge_transform_links($spec_out_path,$Specimen,$mdtname,$n_a_l);
        } else {
            foreach ( glob(File::Spec->catdir($spec_out_path,"transforms","*/") ) ) {
                prune_identity_transforms($_);
            }
        }
        # n_a_l_n - the nickname for the labelset.
        package_labels_SPEC($mdtpath,$spec_out_path,$Specimen,$n_a_l_n,$n_vbm);

        # if we're an input headfile we wont have a complete enough story for the image data.
        # We can tell if the rigid_work_dir is set.
        ($v_ok,my $rwd)=$hf->get_value('rigid_work_dir');
        my $sHF;
        if ( ! $v_ok ) {
            # Find hf in progress from the image dirs.
            # Old name, faMDT_NoNameYet_n1_temp.headfile
            # New name .faMDT_all_n1_amw_temp.headfile
            # We may get multiple returns but they're all equally correct in this context.
            my ($s_hf)=find_file_by_pattern($in_im_dir,"[.]?.*[.]headfile\$",1);
            if ( ! defined $s_hf ) {
                # rigid_work_dir
                error_out("Didn't find samba headfile in $in_im_dir\n");
            }
            $sHF= new Headfile('ro',$s_hf);
            $sHF->check() or push(@spec_errs,"unable to open SAMBA headfile\n (  $s_hf )\n");
            $sHF->read_headfile() or push(@spec_errs,"unable to read SAMBA headfile\n  ( $s_hf )\n");
        } else {
            $sHF=$hf;
        }
        # Fetch the "headfile" from the input, die on multiple choices.
        my $res_hf=File::Spec->catfile($spec_out_path,sprintf("SAMBA_%s.headfile",$Specimen));
        if ( defined $hf_dir && ! -e $res_hf ) {
            # can tell tensor from diffusion via archivedestination_unique_item_name
            # That should be solid forever, But we dont need to here, We just want to make sure we capture what happend.
            #archivedestination_unique_item_name=diffusionN57240dsi_studio
            my @headfiles=find_file_by_pattern($hf_dir,".*$Specimen.*[.]headfile\$",1);
            if( scalar(@headfiles) != 1 ){
                croak "Input Headfile lookup found # ".scalar(@headfiles)." headfiles, not sure how to proceed."
                    ."\t Maybe archive share disconnected ? \n"
                    ."\t  use  \"cifscreds add -u $USER -d dhe\" to connect \n"
                    ."\t (Searched $hf_dir for *$Specimen*.headfile)";
            }
            my $hfname=basename($headfiles[0]);
            my $cp_cmd=sprintf("cp --preserve=timestamps %s %s && chmod u+w %s",$headfiles[0],$res_hf,$res_hf);
            printd(45,"$cp_cmd\n");
            run_and_watch($cp_cmd);
            #qx($cp_cmd) or die "error:$!\n"
            #."copying input hf to $res_hf\n"
            #."Is the archive connected?";
        } elsif( ! -e $res_hf) {
            carp("ERR Couldn't fetch input headfile to maintain data logging.");
        }
        my $rHF= new Headfile('rw',$res_hf);
        $rHF->check() or push(@spec_errs,"unable to open $Specimen headfile\n  ( $res_hf )\n");
        $rHF->read_headfile() or push(@spec_errs,"unable to read $Specimen headfile\n  ($res_hf )\n");
        $rHF->set_value("SAMBA_tag","R_");
        $rHF->copy_in($sHF,"R_");
        # add/ammend vars from the samba pipeline.
        $rHF->write_headfile($res_hf);
        record_metadata($spec_out_path);
    }
    if(scalar(@spec_errs) ){
        die join('',@spec_errs);
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
    print("\n Data \"packaged\" sucessfully! THIS IS A PRESENTATION SET, NOT what we would archive.\n");
    print(" To get archive ready please use the SAMBA_archive_prep\n");
    print("\n");
    print(" You can send all your data to one of our workstations (piper) for continuting work with the following:\n");
    print("   rsync -va --copy-unsafe-links $output_base/ $rsync_location \n");
    print(" To archive you will need to dereference the linkages, with the following command:\n");
    print("   rsync -va --copy-unsafe-links $output_base/ NEW_PATH/ \n");
    print(" You can ask Lucy or James to help you with that step.\n\n");
    print("To use this MDT for your next SAMBA run, add its path to your transform chain:\n");
    print("\t$mdt_out_path \n");
    #print("  cp -RPpn $mdt_out_path $WORKSTATION_DATA/atlas/".basename( $mdt_out_path)."\n");
    #print("#Or at least the linky stack,");
    #print("  cp -RPpn $road $WORKSTATION_DATA/atlas/".basename( $mdt_out_path)."/$n_r\n");

    #print("WARNING!!!! WITH RSYNC TRAILING SLASHES ARE IMPORTANT AND BOTH MUST BE PRESENT FOR CORRECT BEHAIVOR\n");
    return 0;
}


# repl from
# https://stackoverflow.com/questions/392643/how-to-use-a-variable-in-the-replacement-side-of-the-perl-substitution-operator/392649#392649
sub repl {
    my $find = shift;
    my $replace = shift;
    my $var = shift;

    # Capture first
    my @items = ( $var =~ $find );
    $var =~ s/$find/$replace/;
    for( reverse 0 .. $#items ){
        my $n = $_ + 1;
        #  Many More Rules can go here, ie: \g matchers  and \{ }
        #::ADDITIONAL COMENTARY::
        # I dont understand what is meant by "ManyMoreRules cangohere"
        # For my simple needs, no more rules were required.
#printd(25,"n:$n $items[$_]\n") ;
        $var =~ s/\\$n/${items[$_]}/g ;
        $var =~ s/\$$n/${items[$_]}/g ;
    }
    return $var;
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
    my ($in_path,$out_path,$in_key,$oreg)=@_;
    my %transfer_setup;
    #printd(30,"in_key:$in_key conv to $oreg\n");
    my @files = find_file_by_pattern($in_path,".*$in_key.*",1);

    #compound contrast test code sloppyily hacked in.
    # result was that fa_color became color, which isnt too bad really.
    #push(@files,"/mnt/civmbigdata/civmBigDataVol/jjc29/VBM_18gaj42_chass_symmetric3_RAS_BXD62_stat-work/dwi/SyN_0p25_3_0p5_fa/faMDT_all_n4_i6/median_images/MDT_fa_color.nii.gz");
    my $test=grep m/_masked/x, @files;
    if ($test ) {
        #
#       push(@files,'/mnt/civmbigdata/civmBigDataVol/jjc29/VBM_18gaj42_chass_symmetric3_RAS_BXD62_stat-work/preprocess/base_images/N57008_fa_color_masked.nii.gz');
        #Data::Dump::dump(@files);die;
    }
    # out is regular expression, because we've got compplicated bits to work over. 
    my $out_is_reg=1;
    if($in_key =~ /[(].*[)]/x ){
        # Has match portions already, do not adjust
    } else {
        #Adjust non-pat match in/out keys to be pattern match
        if ($in_key eq $oreg ){
            # When in and out are the same
            $in_key="^(.*)($in_key)(.*)\$";
            $oreg='$1$2$3';
        } else {
            # when in and out are not the same
            $in_key="^(.*)($in_key)(.*)\$";
            $oreg="\$1$oreg\$3";
        }
    }
    # a more legit solution to the evaled replace string
    # per https://stackoverflow.com/questions/392643/how-to-use-a-variable-in-the-replacement-side-of-the-perl-substitution-operator
    #however, it appears string::sub is not a default module
    #use String::Substitution qw( sub_modify );
    #my $find = 'start (.*) end';
    #my $replace = 'foo $1 bar';
    #my $var = "start middle end";
    #sub_modify($var, $find, $replace);
    foreach (@files) {
        if( $_ !~ /^.*((txt|csv|xlsx?|headfile)|(nhdr|nrrd)|(nii([.]gz)?))$/ ) {
            next;
        }
        my $n=basename$_;
        my $o=$n;
	if($out_is_reg) {
	    # out is regular expression, because we've got compplicated bits to work over. 
            #require String::Substitution;
            #String::Substitution->import(qw( sub_modify ));
            #sub_modify($o, $in_key, $oreg);
            # an alternative way to get it done, and may be the code inside sub_modify.
            #my @parts=~($o =~ $in_key);
            #Data::Dump::dump([$o,$in_key,\@parts,$oreg]);die;
            #$o=~ s/$in_key/$oreg/;
            #foreach (reverse 0..$#parts ){
            #my $n=$_+1;
            ##$o = ~/\\$n/${parts[$_]}/g;
            #}
            $o=repl($in_key,$oreg,$o);
            #Data::Dump::dump([$n,$in_key,$oreg,$o]);
        } else{
            $o=~s/$in_key/$oreg/;
        }
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
    my $road_forward="$road/${ThisPackageName}_to_${TargetDataPackage}";
    my $road_backward="$road/${TargetDataPackage}_to_${ThisPackageName}";
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
    #my @dir_choices;
    #push(@dir_choices,File::Spec->catfile($ThisPackageInRoot,"transforms","MDT_to_${TargetDataPackage}"));
    #push(@dir_choices,File::Spec->catfile($ThisPackageInRoot,"transforms"));
    #push(@dir_choices,File::Spec->catfile($ThisPackageInRoot,"stats_by_region","labels","transforms"));
    #my $a_dir=multi_choice_dir(\@dir_choices);

    my $a_dir=multi_choice_dir(
        [
         File::Spec->catfile($ThisPackageInRoot,"transforms","MDT_to_${TargetDataPackage}")  ,
         File::Spec->catfile($ThisPackageInRoot,"transforms")  ,
         File::Spec->catfile($ThisPackageInRoot,"stats_by_region","labels","transforms")
        ]  );
    my $aff;
    if ( ! defined $aff ) {
        $aff=qx(ls $a_dir/MDT_*_to_${TargetDataPackage}_affine.*) || die "affine find fail, even tried old fashioned location";
    }
    chomp($aff);

    my $t_merge_file=File::Spec->catfile($ThisPackageOutLocation,"transforms",".merge.log");
    if( -e $t_merge_file ) {
        warn("DID NOT UPDATE TRANFORMS for $ThisPackageName!\n"
             ."\tSome(or all) former transform links were merged, see hidden .merge.log for detail\n");
        return;}
###
# make Package forward and reverse directories
###
    my($road_backward,$road_forward)=transform_dir_setup($ThisPackageInRoot,$ThisPackageOutLocation,$ThisPackageName,
                                                         $TargetDataPackage,$CollectionSource);
###
# link the affine
###
    my $ThisPackage_TargetDataPackage_affine=File::Spec->catfile(${road_forward},basename($aff));
    if ( ! -e $ThisPackage_TargetDataPackage_affine ) {
        qx(ln -vs $aff $ThisPackage_TargetDataPackage_affine);
    }
###
# get the warp
###
    #"$ThisPackageInRoot","stats_by_region","labels","transforms"
    my $warp=File::Spec->catfile($a_dir,"MDT_to_${TargetDataPackage}_warp.nii.gz");
    my $ThisPackage_TargetDataPackage_warp=File::Spec->catfile(${road_forward},basename( $warp));
    if ( ! -e $ThisPackage_TargetDataPackage_warp ) {
        die "EXPCTED warp missing !($warp)" unless -e $warp ;
        qx(ln -s $warp $ThisPackage_TargetDataPackage_warp);
    }
###
# get the "inverse" warp.
###
    #"$ThisPackageInRoot","stats_by_region","labels","transforms"
    $warp=File::Spec->catfile($a_dir,"${TargetDataPackage}_to_MDT_warp.nii.gz");
    my $TargetDataPackage_ThisPackage_warp=File::Spec->catfile($road_backward,basename( $warp));
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
    my $TargetDataPackage_ThisPackage_affine="$road_backward/".$n_ThisPackage_t_a;
    #my $antsCreateInverse="ComposeMultiTransform 3 ${TargetDataPackage_ThisPackage_affine} -i ${ThisPackage_TargetDataPackage_affine} && ConvertTransformFile 3 ${TargetDataPackage_ThisPackage_affine} ${TargetDataPackage_ThisPackage_affine} --convertToAffineType";
    my($p,$n,$e)=fileparts(${TargetDataPackage_ThisPackage_affine},3);
    
    my $p_i_t_c=File::Spec->catfile($p,$n.".sh");
    create_inverse_affine_transform($p_i_t_c,$ThisPackage_TargetDataPackage_affine, $TargetDataPackage_ThisPackage_affine);
    my $old_way=0;
    if( $old_way ){
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
    }

###
# Create ordered links ( relative links to files in same folder just for our future selve's book keeping.
###
# WARNING: These are the not in ants specification order(which is backwards).
# This is part of why we get a readme in each bunch.
# Backward path
    my ($t,$p_t);
    $t="_2_${ThisPackageName}_to_${TargetDataPackage}_warp.nii.gz";
    $p_t=File::Spec->catfile(${road_forward},$t);
    if (  ! -e $p_t ) {
        $t=basename $ThisPackage_TargetDataPackage_warp;
        qx(ln -sv $t $p_t);
    }
    $t="_1_${ThisPackageName}_to_${TargetDataPackage}_affine.mat";
    $p_t=File::Spec->catfile(${road_forward},$t);
    if (  ! -e $p_t ) {
        $t=basename $ThisPackage_TargetDataPackage_affine;
        qx(ln -sv $t $p_t);
    }
# Forward path
    $t="_2_${TargetDataPackage}_to_${ThisPackageName}_affine.mat";
    $p_t=File::Spec->catfile(${road_backward},$t);
    if (  ! -e $p_t ) {
        $t=basename $TargetDataPackage_ThisPackage_affine;
        qx(ln -sv $t $p_t);
    }
    $t="_1_${TargetDataPackage}_to_${ThisPackageName}_warp.nii.gz";
    $p_t=File::Spec->catfile(${road_backward},$t);
    if (  ! -e $p_t ) {
        $t=basename $TargetDataPackage_ThisPackage_warp;
        qx(ln -sv $t $p_t);
    }
    return;
}

sub package_transforms_SPEC {
    my ($ThisPackageInRoot,$ThisPackageOutLocation,$ThisPackageName,$TargetDataPackage,$CollectionSource)=@_;
    # ThisPackage should be the SPEC.
    # Target should be our MDT name.
    # the roadfoward is This to Target
    # the roadbackward is Target to This
###
# Get the affine transforms
###
# do this first so we dont leave a mess if it fails.
# we may need to be sensitive to the affine_target.txt file that is in that directory.
    # get affine path which is sitting outside("above") the mdt folder.
    #my $affpath=File::Spec->catfile($BIGGUS_DISKUS,
    #  sprintf("%s-work",$n_vbm),
    #  $c_r );
    #may want to use multi_choice_dir here in the future.
    my $affpath=File::Spec->catdir($ThisPackageInRoot,File::Spec->updir(),File::Spec->updir());
    my $rig=qx(ls $affpath/${ThisPackageName}_rigid.*)  || die "rigid find fail";
    my $aff=qx(ls $affpath/${ThisPackageName}_affine.*) || die "affine find fail";
    chomp($rig); chomp($aff);

###
# make Package foward and reverse directories
###
    my $t_merge_file=File::Spec->catfile($ThisPackageOutLocation,"transforms",".merge.log");
    if( -e $t_merge_file ) {
        warn("DID NOT UPDATE TRANFORMS for $ThisPackageName!\n"
             ."\tSome(or all) former transform links were merged, see hidden .merge.log for detail\n");
        return;}
    my($road_backward,$road_forward)=transform_dir_setup($ThisPackageInRoot,$ThisPackageOutLocation,$ThisPackageName,
                                                         $TargetDataPackage,$CollectionSource);
    #Data::Dump::dump([$road_backward,$road_forward]);
###
# handle affines (link/invert)
###
    my ($r_suff)=$rig =~ /.*_(rigid.*)/x;
    my ($a_suff)=$aff =~ /.*_(affine.*)/x;

    # Confusion on which direction of transform we have on hand for the rigid.
    # Pretty sure is a forward transform.
    my $rigid_is_forward=1;
    my ($TargetDataPackage_ThisPackageName_rigid,$ThisPackageName_TargetDataPackage_rigid);
    if ($rigid_is_forward ) {
        $ThisPackageName_TargetDataPackage_rigid=File::Spec->catfile(${road_forward},basename($rig));

        $TargetDataPackage_ThisPackageName_rigid=File::Spec->catfile(${road_backward},
                                                                     sprintf("MDT_to_%s_%s",$ThisPackageName,$r_suff));
        if ( ! -e $ThisPackageName_TargetDataPackage_rigid) {
            qx(ln -vs $rig $ThisPackageName_TargetDataPackage_rigid);
        }
    } elsif (! $rigid_is_forward ) {
        $TargetDataPackage_ThisPackageName_rigid=File::Spec->catfile(${road_forward},
                                                                     sprintf("%s_to_MDT_%s",$ThisPackageName,$r_suff));
        $ThisPackageName_TargetDataPackage_rigid=File::Spec->catfile(${road_backward},basename($rig));
        if ( ! -e $TargetDataPackage_ThisPackageName_rigid) {
            qx(ln -vs $rig $TargetDataPackage_ThisPackageName_rigid);
        }
    }
    #Data::Dump::dump([$ThisPackageName_TargetDataPackage_rigid,$TargetDataPackage_ThisPackageName_rigid]);
    my ($i_out,$i_cmd);
    if ( ! -e $TargetDataPackage_ThisPackageName_rigid) {
        die "Error, rigid is the backward transform, it must exist" if ! $rigid_is_forward;
        #if ( 0 ) {
        #    qx(ln -vs $rig $TargetDataPackage_ThisPackageName_rigid);
        #} else {
        #    ($i_out,$i_cmd)=create_explicit_inverse_of_ants_affine_transform($rig,$TargetDataPackage_ThisPackageName_rigid);
        #    my ($p,$n)=fileparts($TargetDataPackage_ThisPackageName_rigid,2);
        #    my $create_inv=File::Spec->catfile($road_backward,
        #                                       ".create_inv_t_".$n."_R.sh");
        #    open(my $f_id,'>',$create_inv);
        #    print($f_id "#!/bin/bash\n$i_cmd;\n");
        #    close($f_id);
        #}
    }
    if ( ! -e $ThisPackageName_TargetDataPackage_rigid) {
        die "Error, rigid is the forward transform, it must exist" if $rigid_is_forward;
        #if ( 0 ) {
        #    qx(ln -vs $rig $ThisPackageName_TargetDataPackage_rigid);
        #} else {
        #    ($i_out,$i_cmd)=create_explicit_inverse_of_ants_affine_transform(
        #        $rig,$ThisPackageName_TargetDataPackage_rigid);
        #    my ($p,$n)=fileparts($ThisPackageName_TargetDataPackage_rigid,2);
        #    my $create_inv=File::Spec->catfile($road_backward,
        #                                       ".create_inv_t_".$n."_R.sh");
        #    open(my $f_id,'>',$create_inv);
        #    print($f_id "#!/bin/bash\n$i_cmd;\n");
        #    close($f_id);
        #}
    }

    my $ThisPackageName_TargetDataPackage_affine=
        File::Spec->catfile(${road_forward},basename($aff));
    my $TargetDataPackage_ThisPackageName_affine=
        File::Spec->catfile(${road_backward},sprintf("MDT_to_%s_%s",$ThisPackageName,$a_suff));
    #File::Spec->catfile(${road_backward},sprintf("%s_to_MDT_%s",$ThisPackageName,$a_suff));
    if($rigid_is_forward ) {
        if ( ! -e $ThisPackageName_TargetDataPackage_affine) {
            qx(ln -vs $aff $ThisPackageName_TargetDataPackage_affine);
        }
    } elsif (! $rigid_is_forward ) {
        if ( ! -e $TargetDataPackage_ThisPackageName_affine) {
            qx(ln -vs $aff $TargetDataPackage_ThisPackageName_affine);
        }
    }
    if ( ! -e $ThisPackageName_TargetDataPackage_affine) {
        die "Error, affine is the forward transform, it must exist" if $rigid_is_forward;
    }
    if ( ! -e $TargetDataPackage_ThisPackageName_affine) {
        die "Error, affine is the backward transform, it must exist" if ! $rigid_is_forward;
    }
    if ( ! -e $TargetDataPackage_ThisPackageName_affine ) {
        my ($p,$n)=fileparts($TargetDataPackage_ThisPackageName_affine,2);
        my $create_inv=File::Spec->catfile($road_forward,".create_inv_t_".$n."_A.sh");

	create_inverse_affine_transform($create_inv,$aff,$TargetDataPackage_ThisPackageName_affine);
	my $old_way=0;
	if($old_way) {
        ($i_out,$i_cmd)=create_explicit_inverse_of_ants_affine_transform($aff,$TargetDataPackage_ThisPackageName_affine);
        open(my $f_id,'>',$create_inv) or croak "error on open $create_inv: $!";
        print($f_id "#!/bin/bash\n$i_cmd;\n");
        close($f_id);
	}
    }
###
# get the warp
###
    #my $warp=File::Spec->catfile("$ThisPackageInRoot","stats_by_region","labels","transforms","MDT_to_${ThisPackageName}_warp.nii.gz");
    my $warp=File::Spec->catfile("$ThisPackageInRoot","reg_diffeo","MDT_to_${ThisPackageName}_warp.nii.gz");
    my $TargetDataPackage_ThisPackageName_warp=File::Spec->catfile(${road_backward},basename( $warp));
    if ( ! -e $TargetDataPackage_ThisPackageName_warp ) {
        die "EXPCTED warp missing !($warp)" unless -e $warp ;
        qx(ln -s $warp $TargetDataPackage_ThisPackageName_warp);
    }
###
# get the "inverse" warp.
###
    #$warp=File::Spec->catfile("$ThisPackageInRoot","stats_by_region","labels","transforms","${ThisPackageName}_to_MDT_warp.nii.gz");
    $warp=File::Spec->catfile("$ThisPackageInRoot","reg_diffeo","${ThisPackageName}_to_MDT_warp.nii.gz");
    my $ThisPackageName_TargetDataPackage_warp=File::Spec->catfile($road_forward,basename( $warp));
    if (  ! -e $ThisPackageName_TargetDataPackage_warp ) {
        qx(ln -s $warp $ThisPackageName_TargetDataPackage_warp);
    }
###
# Create ordered links ( relative links to files in same folder just for our future selve's book keeping.
###
# backward path
    my ($t,$p_t);
    $t="_1_${TargetDataPackage}_to_${ThisPackageName}_warp.nii.gz";
    $p_t=File::Spec->catfile(${road_backward},$t);
    if (  ! -e $p_t ) {
        $t=basename $TargetDataPackage_ThisPackageName_warp;
        qx(ln -sv $t $p_t);
    }
    $t="_2_${TargetDataPackage}_to_${ThisPackageName}_affine.mat";
    $p_t=File::Spec->catfile(${road_backward},$t);
    if (  ! -e $p_t ) {
        $t=basename $TargetDataPackage_ThisPackageName_affine;
        qx(ln -sv $t $p_t);
    }
    $t="_3_${TargetDataPackage}_to_${ThisPackageName}_rigid.mat";
    $p_t=File::Spec->catfile(${road_backward},$t);
    if (  ! -e $p_t ) {
        $t=basename $TargetDataPackage_ThisPackageName_rigid;
        qx(ln -sv $t $p_t);
    }

# forward path
    $t="_1_${ThisPackageName}_to_${TargetDataPackage}_rigid.mat";
    $p_t=File::Spec->catfile(${road_forward},$t);
    if (  ! -e $p_t ) {
        $t=basename $ThisPackageName_TargetDataPackage_rigid;
        qx(ln -sv $t $p_t);
    }
    $t="_2_${ThisPackageName}_to_${TargetDataPackage}_affine.mat";
    $p_t=File::Spec->catfile(${road_forward},$t);
    if (  ! -e $p_t ) {
        $t=basename $ThisPackageName_TargetDataPackage_affine;
        qx(ln -sv $t $p_t);
    }
    $t="_3_${ThisPackageName}_to_${TargetDataPackage}_warp.nii.gz";
    $p_t=File::Spec->catfile(${road_forward},$t);
    if (  ! -e $p_t ) {
        $t=basename $ThisPackageName_TargetDataPackage_warp;
        qx(ln -sv $t $p_t);
    }
# END arranging
    return;
}

sub merge_transform_links {
    #merge_transform_links($output_path,$mdtname,$Specimen);
    my($link_dir,@nodes) = @_;
    # Given list of nodes, merge the transform links between these nodes to a singular pair.
    if (scalar(@nodes)<3) {
        die("Needs at least 3 nodes to merge");
    } elsif(scalar(@nodes)>3 && $debug_val<45 ) {
        die("UNTESTED MULTI LINK REMOVAL! will only proceed with serious debug val!");
    }
    my $t_merge_file=File::Spec->catfile($link_dir,"transforms",".merge.log");
    my $missing_node_tollerance=0;
    if ( -e $t_merge_file ) {
        $missing_node_tollerance=1;
    }

    open(my $m_id,'>>',$t_merge_file);
    # Prev, current, next node.
    my ($node_P,$node_C,$node_N);
    # might be able to convert to a while loop like:
    # while node count > 2   ?
    # each loop iter would re-create nodes array removing the current node.
    for(my $i_n=1;$i_n<$#nodes; $i_n++) {
        # node P should actually always be the first node because we will remove the current node
        # once we extract its transforms.
        #$node_P=$nodes[$i_n-1];
        $node_P=$nodes[0];
        # If we switch to a while loop i_n will always be 1 because we remove it at the end of the loop.
        $node_C=$nodes[$i_n];
        $node_N=$nodes[$i_n+1];
        printd(5,"\t  dispersing transform node $node_C to $node_P and $node_N\n");

        # link vars, forward/reverse curent, previous, and new link_f link_r
        # we need to merge the forward link into the reverse link and clean out any unnecessary identities.
        # the pair to merge forward
        my $l_fp=File::Spec->catdir($link_dir,"transforms",$node_P."_to_".$node_C);
        my $l_fc=File::Spec->catdir($link_dir,"transforms",$node_C."_to_".$node_N);

        #the pair to merge backward
        my $l_rc=File::Spec->catdir($link_dir,"transforms",$node_N."_to_".$node_C);
        my $l_rp=File::Spec->catdir($link_dir,"transforms",$node_C."_to_".$node_P);

        # the result birectional pair which skips current becuase we merged it away.
        my $n_l_f=File::Spec->catdir($link_dir,"transforms",$node_P."_to_".$node_N);
        my $n_l_r=File::Spec->catdir($link_dir,"transforms",$node_N."_to_".$node_P);

        if( -d $l_fp && -d $l_fc
            && $l_rc && -d $l_rp) {
            printd(65,"\tF:$l_fp\n\t\t$l_fc\n");
            printd(65,"\tR:$l_rc\n\t\t$l_rp\n");
            my @cmds;
            push(@cmds,concatenate_transform_dirs($l_fp, $l_fc));
            push(@cmds,sprintf("mv %s %s",$l_fp, $n_l_f) );
            push(@cmds,sprintf("cat %s >> %s",
                               File::Spec->catfile($l_fc,"README.txt"),
                               File::Spec->catfile($n_l_f,"README.txt")));
            push(@cmds,sprintf("rm %s",File::Spec->catfile($l_fc,"README.txt")) );
            push(@cmds,sprintf("find %s -iname \"%s\" -exec mv {} %s \\; ",$l_fc,".create_inv_t*.sh",$n_l_f) );
            push(@cmds,sprintf("rmdir %s",$l_fc) );


            push(@cmds,concatenate_transform_dirs($l_rc, $l_rp));
            push(@cmds,sprintf("mv %s %s",$l_rc, $n_l_r) );
            push(@cmds,sprintf("cat %s >> %s",
                               File::Spec->catfile($l_rp,"README.txt"),
                               File::Spec->catfile($n_l_r,"README.txt")));
            push(@cmds,sprintf("find %s -iname \"%s\" -exec mv {} %s \\; ",$l_rp,".create_inv_t*.sh",$n_l_r) );
            push(@cmds,sprintf("rm %s",File::Spec->catfile($l_rp,"README.txt")) );
            push(@cmds,sprintf("rmdir %s",$l_rp) );

            #execute(1,"ReduceTransformDirs",@cmds);
            printf($m_id "# Eliminate $node_C\n");
            foreach(@cmds){
                run_and_watch($_);
                printf($m_id $_."\n");
            }
            # eliminating identity links
            printd(15,"\t  Cleaning up identity transforms\n");
            prune_identity_transforms($n_l_r);
            prune_identity_transforms($n_l_f);
        } else {
            if( $missing_node_tollerance
                && -e $n_l_f
                && -e $n_l_r ) {
                warn("DID NOT (re)MERGE TRANFORMS $node_C! It appears to have been done.\n");
            } else {
                die "Link mis-match:\n"
                    ."$l_fp\n\t$l_fc\n"
                    ."$l_rc\n\t$l_rp";
            }
        }
    }
    close($m_id);
}
sub package_labels_SPEC {
#    ($mdtpath,$output_path,$Specimen,$mdtname,$n_vbm);
    #my($ThisPackageInRoot,$ThisPackageOutLocation,$ThisPackageName,$TargetDataPackage,$CollectionSource)=@_;
    my($ThisPackageInRoot,$ThisPackageOutLocation,$ThisPackageName,$LabelNick,$CollectionSource)=@_;
    # root - /mnt/civmbigdata/civmBigDataVol/jjc29/VBM_18enam01_chass_symmetric3_RAS_A2-work/dwi/SyN_0p25_3_0p5_fa/faMDT_all_n8_i6
    # /stats_by_region/labels/pre_rigid_native_space/WHS

    #my $source_label_root=File::Spec->catfile($ThisPackageInRoot,'stats_by_region','labels','pre_rigid_native_space');
    my $source_label_root=multi_choice_dir(
        [
         File::Spec->catfile($ThisPackageInRoot,"vox_measure","pre_rigid_native_space"),
         File::Spec->catfile($ThisPackageInRoot,'stats_by_region','labels','pre_rigid_native_space'),
        ]  );


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
    # Accidentially had whs in here all the time WIll patch that up to the correctly bit here.
    my $WHS_nick_folder=File::Spec->catfile($label_folder,"WHS");
    my $nick_folder=File::Spec->catfile($label_folder,$LabelNick);
    if ( -d $WHS_nick_folder && ! -e $nick_folder ) {
        rename($WHS_nick_folder,$nick_folder);
    }
    if ( ! -d $nick_folder ) {
        make_path($nick_folder);
    }
    my $label_in_folder=multi_choice_dir(
        [
         File::Spec->catfile($source_label_root,$LabelNick),
         $source_label_root
        ]
        );
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
	#  copy_paired_data($in_file,$out_file,$prep,$update,$link_mode)=@_;
	if($key =~ /[.](nhdr|nrrd)$/){
	    copy_paired_data($key,$value,0,1,"copy");
	} else {
	    qx(ln -vs $key $value);
	}
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

sub prune_identity_transforms {
    # using the _N_ transform files to allow procession in order remove identity transforms.
    # Make a log of the identity files removed.
    # Do not bother to renumber allowing us to re-neg on this if we need to.
    my ($transform_dir)=@_;

    my @t_list=find_file_by_pattern($transform_dir,"^_.*");
    my @i_list;
    foreach(@t_list) {
        if(is_ident_transform($_) ) {
            my $realname=readlink($_);
            push(@i_list,File::Spec->catfile($transform_dir,$realname));
            push(@i_list,$_);
        }
    }
    #Data::Dump::dump(\@i_list) ;die;
    if( scalar(@i_list) ) {
    my $rm_cmd=sprintf("rm %s",join(" ",@i_list) );
    #execute(1,"remove identity transforms",$rm_cmd);
    printd(45,"\t".$rm_cmd."\n");
    run_and_watch($rm_cmd);
    } else {
        printd(45," No identity transforms in $transform_dir\n");
    }
}

sub is_ident_transform {
    my ($transform)=@_;

    # For warps we will not be using a very intelligent algorithm.
    # We'll use the fact that zeros compress very well.
    # If our warp size in bytes is less than 500 + 0.1*full_volume_size * 3(vector components)
    # we'll assume its an identity.
    my $is_ident=0;
    if ( $transform =~ /[.]nii[.]gz$/ ){
        my $nii_hf = new Headfile ('nifti', $_) or die;
        $nii_hf->check() or print "nii check error\n";
        my $FSLHD_PATH=qx/which fslhd/;
        chomp($FSLHD_PATH);
        if ( ! -f $FSLHD_PATH ) {
            my $EC=load_engine_deps();
            my $FSLHD_PATH=File::Spec->catfile($EC->get_value('engine_app_fsl_dir'),"fslhd");
        }
        if ( ! -f $FSLHD_PATH ) {
            croak("Couldnt find fslhd, is fsl installed?!")
        }
        my $ret = $nii_hf->read_nii_header($FSLHD_PATH, 0);
        require HeadfileIO;
        my $err=HeadfileIO::transcribe($nii_hf);
        if ( ! $ret || $err ) {
            print("HF load_sucess:$ret Read errors:$err\n");
        }
        # min transform size is
        # 500 bytes for gzippy
        # + 10% of (s
        # 8x bytes for double ( using nbyper )
        # 3x vector component
        # prod(dimenssions)  )
        my $min_t_size=(500.0 + 0.1 * $nii_hf->get_value("nbyper") * 3
                        *$nii_hf->get_value('dim_X')
                        *$nii_hf->get_value('dim_Y')
                        *$nii_hf->get_value('dim_Z')
            );
        # Cwd::realpath($test_path);
        my $t_size=-s Cwd::realpath($transform);
        #printd(5,"transform is size $t_size \n");
        if( $t_size < $min_t_size ) {
            #warn("Identity Me $transform\n");
            $is_ident=1;
        } else {
            printd(45,"Transform size $t_size greater than min $min_t_size\n");
        }
    } elsif($transform =~/[.]mat|txt$/ ) {
        # This accidentially gobbles up non transform txt files, cant really be
        # helped so we'll try to accept and adjust to that.
        my $TI_PATH=qx/which antsTransformInfo/;
        chomp($TI_PATH);
        if(! -f $TI_PATH && exists $ENV{"ANTSPATH"} ) {
            printd(5,"ANTSPATH not part of path, but really it should be\n");
            $TI_PATH=File::Spec->catfile($ENV{"ANTSPATH"},'antsTransformInfo');
        }
        my @transform_dump=qx($TI_PATH $transform);
        #Data::Dump::dump(\@transform_dump);die;
        my ($mat,$inv);
        while ( my $line= shift @transform_dump) {
            if( $line !~ m/.*(Matrix|Inverse):.*/x ) {
                #printd(45, "Skip -  $line");
                next;
            } elsif( $line =~ /.*Matrix:.*/ ) {
                $mat=shift @transform_dump;
                $mat=$mat.shift @transform_dump;
                $mat=$mat.shift @transform_dump;
            } elsif( $line =~ /.*Inverse:.*/ ) {
                $inv=shift @transform_dump;
                $inv=$inv.shift @transform_dump;
                $inv=$inv.shift @transform_dump;
            }
        }
        if(!defined $inv || ! defined $mat ) {
            croak "TRANSFORM read error!";
        }
        if($inv eq $mat ) {
            #warn("Identity Me $transform\n");
            $is_ident=1;
        }

    } else {
        printd(15,"Not a transform $transform\n");
    }
    return $is_ident;
}

sub concatenate_transform_dirs {
    my ($expanding_dir,$shrinking_dir)=@_;
    my @cmds;
    # find transforms in expanding
    my @expand_list=find_file_by_pattern($expanding_dir,"^_.*");
    # get highest N from expanding list
    my ($maxN ) = basename($expand_list[$#expand_list]) =~ m/^_([0-9]+)_.*$/x;
    my @shrink_list=find_file_by_pattern($shrinking_dir,"^_.*");
    foreach ( @shrink_list ) {
        if ( ! -e $_ ) {
            die("file find error on $_, link may have gone stale");
        }
        my ( $realname,$ln_name);
        $realname=basename($_);
        my( $cur_N) = $realname =~ m/^_([0-9]+)_.*$/x;
        my $outname = $realname;
        $maxN=$maxN+1;
        $outname=~ s/$cur_N/$maxN/x;
        $ln_name="";
        if ( -l $_ ) {
            $ln_name="L \"$realname\"";
            $realname=readlink($_);
        } else {
            die "Links expected, something fishy going on";
        }
        if( -e File::Spec->catfile($expanding_dir,$realname) ){
            die("Existing transform in merge target! $realname in $expanding_dir\n"
                ."transform dirs are extra messy when merged, re-check is not supported, trash transform dir \n");
            #.File::Spec->catfile($link_dir,"transforms"));
        }
        printd(65,"Transfer %s -- %s  to dir %s\n",$ln_name,$realname,$expanding_dir);
        push(@cmds,sprintf("mv %s %s",File::Spec->catfile($shrinking_dir,$realname),$expanding_dir));
        push(@cmds,sprintf("mv %s %s",$_,File::Spec->catfile($expanding_dir,$outname)));
    }
    return @cmds;
}

1;
