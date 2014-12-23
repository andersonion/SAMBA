#!/usr/local/pipeline-link/perl

# study_variables_vbm.pm 

# Created 2014/12/23 BJ Anderson for use in VBM pipeline.


my $PM = "study_variables_vbm.pm";
my $VERSION = "2014/12/23";
my $NAME = "In lieu of commandline functionality, here is the place to define various variables.";


my $obrien = 0;
my $colton = 1;


use strict;
use warnings;

use vars qw($test_mode);

use vars qw(
$project_name 
@control_group
@compare_group
@channel_array
$flip_x
$flip_z 
$optional_suffix
$atlas_name
$rigid_contrast
$mdt_contrast
$atlas_dir
$skull_strip_contrast
$threshold_code
$do_mask
$thresh_ref
 );


sub study_variables_vbm {
## Study variables for O'Brien
    if ($obrien) {
	
	$project_name = "14.obrien.01";
	@control_group = qw(
        controlSpring2013_4
        controlSpring2013_7
        controlSpring2013_8
        controlSpring2013_9
        controlSpring2013_10
        controlSpring2013_11
        controlSummer2012_1
        controlSummer2012_5
        controlSummer2012_8
        controlWinter2012_1
        controlWinter2012_6
        controlWinter2012_9
        );
    
	@compare_group = qw(
        reacherSpring2013_1
        reacherSpring2013_2
        reacherSpring2013_3
        reacherSpring2013_5
        reacherSpring2013_6
        reacherSummer2012_2
        reacherSummer2012_3
        reacherSummer2012_5
        reacherWinter2012_3
        reacherWinter2012_5
        reacherWinter2012_7
        reacherWinter2012_8
        );

	@channel_array = qw(dwi fa); 

	$flip_x = 0;
	$flip_z = 0;

	$optional_suffix = '';
	$atlas_name = 'DTI';
	$rigid_contrast = 'dwi';
	$mdt_contrast = 'fa';
	$skull_strip_contrast = 'dwi';
	$threshold_code = 4;
	$do_mask = 0;

	$thresh_ref = {};

    }
    
    elsif ($colton) 
    
### Study variables for Colton.
    {
	$project_name = "13.colton.01";
	print " Test mode = ${test_mode}\n";
	if ($test_mode) {
	    @control_group = qw(N51193 N51211 N51221 N51406);
	    @compare_group = qw(N51136 N51201 N51234 N51392);
	} else {
	    @control_group = qw(N51193 N51211 N51221 N51231 N51383 N51386 N51404 N51406);
	    @compare_group = qw(N51136 N51201 N51234 N51241 N51252 N51282 N51390 N51392 N51393);
	}
	
	@channel_array = qw(adc dwi e1 e2 e3 fa); # This will be determined by command line, and will be able to include STI, T1, T2, T2star, etc.
    
	$flip_x = 1;
	$flip_z = 0;
	
	$optional_suffix = 'two_wild_and_crazy_channels';
	$atlas_name = 'DTI';
	$rigid_contrast = 'dwi';
	$mdt_contrast = 'adc_e3';
	$skull_strip_contrast = 'dwi';
	$threshold_code = 4;
	$do_mask = 1;
    
#custom thresholds for Colton study
	$thresh_ref = {
	    'N51124'   => 2296,
	    'N51130'   => 2644,
	    'N51393'   => 2034,
	    'N51392'   => 2372,
	    'N51390'   => 2631,
	    'N51388'   => 2298,
	    'N51136'   => 1738,
	    'N51133'   => 1808,
	    'N51282'   => 2131,
	    'N51234'   => 2287,
	    'N51201'   => 1477,
	    'N51241'   => 1694,
	    'N51252'   => 1664,
	    'N51383'   => 1981,
	    'N51386'   => 2444,
	    'N51231'   => 1964,
	    'N51404'   => 2057,
	    'N51406'   => 2004,
	    'N51211'   => 1668,
	    'N51221'   => 2169,
	    'N51193'   => 2709,
	    'N51182'   => 1841,
	    'N51151'   => 2188,
	    'N51131'   => 2098,
	    'N51164'   => 2001,
	    'N51617'   => 2867,
	    'N51620'   => 2853,
	    'N51622'   => 3160,
	};
	
    }

}
1;

