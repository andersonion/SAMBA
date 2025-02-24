#!/usr/bin/env perl
`perlbrew switch perl-5.16.3`;
my $cleanup = 1;
use Carp qw(carp croak cluck confess);

my $valid_formats_string = 'hdr|img|nii|nii.gz|ngz|nhdr|nrrd';

if (0) {
my $test_dir = '/mnt/newStor/paros/paros_WORK/upgraded_gradients_in_vivo_images';
if ( ! -e ${test_dir}) {
	$test_dir = "/mnt/munin2/Badea/Lab/mouse//upgraded_gradients_in_vivo_images";
}
}

my ${tmp_dir} = "~/tmp_filename_tester/";
if ( ! -f $tmp_dir ) {
	`mkdir ${tmp_dir}`;
}


my $test_result;
my @runnos = ("A22050912","A22050913","A22050914","A22080806","A22080807","A22080808","A22050911","A22060617","A22060618","A23011802","A23011803","A23011720","A22060602","A22060603","A22060604","A22060605","A22060606","A21112226","A21112227","A21112228","A22011008","A22011009","A22011010","A22030709","A22030710");
my @cons = ('T1','T1map');
my $runno;
my $con;
my $correct_file;
my $failures=0;
my $successes=0;
$test_dir = "${SAMBA_PATH}/filename_testing/" ;
# Anticipated collisions we want to test for:
# Note: SAMBA is currently case INSENSITIVE
# Note: SAMBA always will prefer a '_masked' of there is more than one options.
# 1) Runnos containing substrings of other runnos
# 2) Contrasts containing substrings of other runnos
# 3) 'mask' vs. 'masked' --> usually when calling for 'mask' but getting a similarly named image instead
# 4) Sometimes we'll have some nonsense like 'coreg_${runno}' at the front--but prefer the runno to be the very first thing.

my @test_runnos=('A12345','QA12345','A12345_f','A12345-1','A12345-10');
my @test_contrasts=('T1', 'T1map', 'DWI', 'DWI_stack', 'dwi_mask', 'fa', 'nqa', 'qa', 'mask');
my @garbage_1=('','coreg_','denoised_');
my @garbage_2=('','_RARESpace_','_to_MDT_','_in_T1_space_','_color_');


foreach $tR (@test_runnos) {
	foreach $tc (@test_contrasts) {
		foreach $g1 (@garbage_1) {
			foreach $g2 (@garbage_2) {
				my $file = "${tmp_dir}/${g1}${tR}${g2}${tc}.nii.gz";
				if ( ! -f $file ) {
					`touch $file`;
				}
				if ( $tc ne 'mask' ) {
					$file = "${tmp_dir}/${g1}${tR}${g2}${tc}_masked.nii.gz";
					if ( ! -f $file ) {
						`touch $file`;
					}
				}
			}
		}
	}
}


# Test cases for 1):
# A12345, QA12345, A12345_f, A1234501
$correct_file="${test_dir}/A12345_FA.nii.gz";
$runno='A12345';
$con='FA';
$test_result=get_nii_from_inputs($test_dir, $runno, $con);

if ( $test_result eq $correct_file) {
	$successes++;
} else {
	$failures++
}
##
$correct_file="${test_dir}/QA12345_FA.nii.gz";
$runno='QA12345';
$con='FA';
$test_result=get_nii_from_inputs($test_dir, $runno, $con);

if ( $test_result eq $correct_file) {
	$successes++;
} else {
	$failures++
}

##

$correct_file="${test_dir}/A12345_f_FA.nii.gz";
$runno='A12345_f';
$con='fa';
$test_result=get_nii_from_inputs($test_dir, $runno, $con);

if ( $test_result eq $correct_file) {
	$successes++;
} else {
	$failures++
}
##

$correct_file="${test_dir}/A1234501_FA.nii.gz";
$runno='A1234501';
$con='fa';
$test_result=get_nii_from_inputs($test_dir, $runno, $con);

if ( $test_result eq $correct_file) {
	$successes++;
} else {
	$failures++
}

# Test cases for 2):
# T1, T1map, DWI, DWI_stack, color_fa, fa, nqa, qa

$correct_file="${test_dir}/A12345_FA.nii.gz";
$runno='A1234501';
$con='fa';
$test_result=get_nii_from_inputs($test_dir, $runno, $con);

if ( $test_result eq $correct_file) {
	$successes++;
} else {
	$failures++
}




# Test cases for 3):
# A12345_mask, A12345_Fa_masked, A12345_FA

# Test cases for 4):
# coreg_A12345, A12345




print "\nUnit test completed!\n";
print "Number of successful tests: ${successes}.\n";
print "Number of failed tests: ${failures}.\n";

if ( $cleanup && ( $tmp_dire ne '' ) ) {
	`rm -r $tmp_dir`;	
}

if (0){

#$RUNNO='A22040411';
#$con='T1';
foreach $runno (@runnos) {
	foreach $con (@cons) {	
		$test_result = get_nii_from_inputs($test_dir, $runno, $con);
		print $test_result;
	}
}
}


# ------------------
sub get_nii_from_inputs {
# ------------------
    #### :D #### 
    #### :D #### 
    #funct_obsolete('get_nii_from_inputs','SAMBA_pipeline_utilities::find_file_by_pattern("dir","regex"');
    #### :D #### 
    #### :D #### 
# Update to only return hdr/img/nii/nii.gz formats.
# Case insensitivity added.
# Order of selection (using contrast = 'T2' and 'nii' as an example):
#        1)  ..._contrast_masked.nii   S12345_T2_masked.nii    but not...   S12345_T2star.nii or S12345_T2star.nii
#        2)  ..._contrast.nii          S12345_T2.nii           but not...   S12345_T2star.nii
#        3)  ..._contrast_*.nii        S12345_T2_unmasked.nii  but not...   S12345_T2star.nii or S12345_T2star.nii
#        4)  ..._contrast*.nii         S12345_T2star.nii  or S12345_T2star_masked.nii, etc
#        5)  Returns error if nothing matches any of those formats
#
#        Note that on 17 July 2017, the first two cases were swapped, thus giving '_masked' preference.  It appears that sometimes an unmasked version of an image may not get removed from a folder, and will be selected when it is, in general, the masked version which is wanted.
#
# Need to add exception for fa/color_fa--> requesting fa can inadvertently return color_fa, which can be problematic for finding atlas fa's
    #require SAMBA_global_variables;
    #SAMBA_global_variables->import(qw($valid_formats_string));
    #require vars qw($valid_formats_string);
    #use SAMBA_global_variables qw($valid_formats_string);
    # the OR didnt work... Investigate!
    #or my $valid_formats_string="GLOBALS_MISSING";
    #die("format_string:${SAMBA_global_variables::valid_formats_string}");
    #my $valid_formats_string="GLOBALS_MISSING";
    #$valid_formats_string=${SAMBA_global_variables::valid_formats_string} or die $valid_formats_string;
    my ($inputs_dir,$runno,$contrast) = @_;
    my $error_msg='';
    #pattern to rule them alls :D 
    # Missing from this is the selection order behavior, or protection from substring constrats that include name demarkations.
    # Name demarkations in use are . _ and -, it is expected that contrast is framed by those.
    # TODO: modify both instances of '.*' in the line below to explicitly exclude "color" (this should break as soon as we try to pull tensor_create results--30 April 2019 
    my $pattern=$runno.".*[\.\_\-]{1}(".$contrast.'|'.uc($contrast).")[\.\_\-]{1}.*(".$valid_formats_string.")\$";

# 29 July 2023 --BJA: Turning of James' code since it is behaving poorly
if (0) {
    my @found=SAMBA_pipeline_utilities::find_file_by_pattern($inputs_dir,$pattern,1);
    $error_msg="SAMBA_pipeline_utilities function get_nii_from_inputs: Unable to locate file using the input criteria:\n\t\$inputs_dir: ${inputs_dir}\n\t\$runno: $runno\n\t\$contrast: $contrast\n";
    # filter found to masked if(and only if) there are extra
    @found=grep /_masked/ ,@found if (scalar(@found) > 1);

    if ($inputs_dir =~ /inputs/){
#	Data::Dump::dump($inputs_dir,$pattern,@found);die;
    }
    if ( scalar(@found) ) {
        if (scalar(@found) > 1) { 
            Data::Dump::dump("Found too many in $inputs_dir, this is scary to proceed!",@found);
            confess "Found too many in $inputs_dir, dont dare proceed!".join("\n\t".@found);  # Turned on 24 March 2023 -- turn off if switching back
        }
        return $found[0];  # Turned on 24 March 2023 -- turn off if switching back
    } else {
        #confess "failed to find data in $inputs_dir with $runno $contrast $valid_formats_string";
        return $error_msg; # Turned on 24 March 2023 -- turn off if switching back
    }
} # PAirs with if ((0)) above
    
   # 24 March 2023 (Fri) --BJA: Turning off this code, as file-checking is taking excruciatingly long on BIAC cluster for large studies.
    # 29 July 2023 (Sat) --BJA: Turning this code back on, since the other option couldn't tell the difference between mask and masked.
   #if (0) {

    my $test_contrast;
    if ((defined $contrast) && ($contrast ne '')) {
        if ($contrast =~ /^fa$/i) {
            $contrast='(?<!color_)fa(?!_color)'; # 7 July 2017: use negative look behind assertion to avoid finding 'color_fa' when looking for just 'fa'.  
        }

        if ($contrast =~ /^nqa$/i) {
            $contrast='(?<!color_)nqa(?!_color)'; # 7 July 2017: use negative look behind assertion to avoid finding 'color_fa' when looking for just 'fa'.  
        }
        $test_contrast = "_${contrast}";
    } else {
        $test_contrast = "";
    }
    
    my $input_file='';
    if (-d $inputs_dir) {
        opendir(DIR, $inputs_dir);
        my @input_files_0= grep(/^($runno).*(${test_contrast})_masked\.($valid_formats_string){1}(\.gz)?$/i ,readdir(DIR));
        #my @input_files_0= grep(/^($runno).*(${test_contrast})_masked\.($valid_formats_string){1}(\.gz)?$/i ,glob ("${inputs_dir}/*"));
        #my @input_files_X= grep(/^.*($runno).*$/i ,readdir(DIR));
        #my @input_files= glob ("${inputs_dir}/*"); ;
        print("\nCheckpoint 0\n");
        print("$runno $con ${test_contrast}\n");
        #print join("\n",@input_files),"\n" ;
        #print @input_files ;
        #print "SHUCKKKKKS" ;
        $input_file= $input_files_0[0];
        if ( defined $input_file) { 
        	print("Checkpoint 1\n");
        	print(join("\n",@input_files_0),"\n");
        }
        if ((! defined $input_file) || ($input_file eq '') ) {
            #my @input_files_1= grep(/\/${runno}.*${test_contrast}\.($valid_formats_string)$/i ,glob ("${inputs_dir}/*")); #27 Dec 2016, added "^" because new phantom naming method of prepending (NOT substituting) "P" "Q" etc to beginning of runno results in ambiguous selection of files. Runno "S64944" might return "PS64944" "QS64944" or "S64944".
            opendir(DIR, $inputs_dir);
            my @input_files_1= grep(/^($runno).*(${test_contrast}).*\.($valid_formats_string){1}(\.gz)?$/i ,readdir(DIR));
            $input_file = $input_files_1[0];
			if ( defined $input_file) { 
				print("Checkpoint 2\n");
				print(join("\n",@input_files_1),"\n");
			}
            if ((! defined $input_file) || ($input_file eq '')) {
				
                opendir(DIR, $inputs_dir);
                #my @input_files_2= grep(/\/($runno).*(${test_contrast})_.*\.($valid_formats_string){1}(\.gz)?$/i ,glob ("${inputs_dir}/*")); #28 Dec 2016, added "^" like above.
                my @input_files_2=grep(/^($runno).*(${test_contrast})_.*\.($valid_formats_string){1}(\.gz)?$/i ,readdir(DIR));
                $input_file = $input_files_2[0];
				if ( defined $input_file) { 
					print("Checkpoint 3\n");
					print(join("\n",@input_files_2),"\n");
				}
                if ((! defined $input_file) || ($input_file eq '') ) {
                    opendir(DIR, $inputs_dir);
                    #my @input_files_3= grep(/\/($runno).*(${test_contrast}).*\.($valid_formats_string){1}(\.gz)?$/i ,glob ("${inputs_dir}/*"));  #28 Dec 2016, added "^" like above.
                    my @input_files_3= grep(/^($runno).*(${test_contrast}).*\.($valid_formats_string){1}(\.gz)?$/i ,readdir(DIR)); 
                    $input_file = $input_files_3[0];
					if ( defined $input_file) { 
						print("Checkpoint 4\n");
						print(join("\n",@input_files_3),"\n");
					}
                }
            }
        }
        
        if ((defined $input_file) && ($input_file ne '') ) {
            my $path= $inputs_dir.'/'.$input_file;
            return($path);
            
        } else {
            $error_msg="SAMBA_pipeline_utilities function get_nii_from_inputs: Unable to locate file using the input criteria:\n\t\$inputs_dir: ${inputs_dir}\n\t\$runno: $runno\n\t\$contrast: $contrast\n";
            return($error_msg);
        }
    } else {
        $error_msg="SAMBA_pipeline_utilities function get_nii_from_inputs: The input directory $inputs_dir does not exist.\n";
        return($error_msg);
    }
    # } # Comment out  if reactivating codeblock above (pairs with if (0) )
}
