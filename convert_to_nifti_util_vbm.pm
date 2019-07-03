#!/usr/bin/perl
# convert_to_nifti_util.pm 
#
# created 2009/10/28 Sally Gewalt CIVM
# consider this library for nifti? http://nifti.nimh.nih.gov/pub/dist/src/
# http://afni.nimh.nih.gov/pub/dist/doc/program_help/nifti_tool.html

use strict;
use pipeline_utilities;

my $ggo = 1;
my $debug_val=5;

# ------------------
sub convert_to_nifti_util {
# ------------------
# convert the source image volumes used in this SOP to nifti format (.nii)
# could use image name (suffix) to figure out datatype

  my ($go, $data_setid, $nii_raw_data_type_code, $flip_y, $flip_z, $Hf, $Hf_in) = @_;
  $ggo=$go;

  # the input headfile has image description
  # the second value is a more generic version, this was specifically added to support the brukerextract code and bruker images.
  my $xdim    = $Hf_in->get_value('S_xres_img');
  if ($xdim eq "NO_KEY") {
      $xdim    = $Hf_in->get_value('dim_X');
  }
  my $ydim    = $Hf_in->get_value('S_yres_img');
  if ($ydim eq "NO_KEY") {
      $ydim    = $Hf_in->get_value('dim_Y');
  }
  my $zdim    = $Hf_in->get_value('S_zres_img');
  if ($zdim eq "NO_KEY") {
      $zdim    = $Hf_in->get_value('dim_Z');
  }
  my $xfov_mm = $Hf_in->get_value('RH_xfov');
  if ($xfov_mm eq "NO_KEY") {
      $xfov_mm    = $Hf_in->get_value('B_xfov');
  }
  if ($xfov_mm eq "NO_KEY") {
      $xfov_mm    = $Hf_in->get_value('fovx');
  }
  my $yfov_mm = $Hf_in->get_value('RH_yfov');
  if ($yfov_mm eq "NO_KEY") {
      $yfov_mm    = $Hf_in->get_value('B_yfov');
  }
  if ($yfov_mm eq "NO_KEY") {
      $yfov_mm    = $Hf_in->get_value('fovy');
  } 
  my $zfov_mm = $Hf_in->get_value('RH_zfov');
  if ($zfov_mm eq "NO_KEY") {
      $zfov_mm    = $Hf_in->get_value('B_zfov');
  }
  if ($zfov_mm eq "NO_KEY") {
      $zfov_mm    = $Hf_in->get_value('fovz');
  } 
  if ($zfov_mm eq "NO_KEY") {
      my $slthick=$Hf_in->get_value('z_Bruker_PVM_SliceThick'); # this is used instead of slthick, as slthick might be the wrong guy.
#      my $slicespacing=$Hf_in->get_value('');
      my $slicespacing=0;
      $zfov_mm=($slthick+$slicespacing)*$zdim-$slicespacing;
      
  }
  my $input_specid=$Hf_in->get_value("U_specid");
  my $out_specid=$Hf->get_value("U_specid");
  #if (  $out_specid eq "NO_KEY" || $out_specid eq "UNDEFINED_VALUE" || $out_specid eq "EMPTY_VALUE" ) {
  if ( $out_specid !~ m/^[0-9]{6}-[0-9]+:[0-9]+$/x ) 
  {
      print ("setting specid in output to $input_specid\n");
      $Hf->set_value("U_specid",$input_specid);
  }
  my $image_suffix   = $Hf->get_value("${data_setid}-image-suffix");
  if ($image_suffix eq 'NO_KEY') { $image_suffix   = $Hf->get_value("${data_setid}_image_suffix"); }
  if ($image_suffix !~ m/[raw|nii]/ ) { error_out("nifti_ize: image suffix $image_suffix not known to be handled by matlab nifti converter (just \.raw or \.nii)");}
  my @voxelsize=();
# ($image_suffix !~ m/[nii]/ ));
  if ($xdim eq "NO_KEY" || $zdim eq "NO_KEY" || $ydim eq "NO_KEY" || $xfov_mm eq "NO_KEY"|| $yfov_mm eq "NO_KEY"|| $zfov_mm eq "NO_KEY") {
      error_out("Could not find good value for xyz or xyz fov\n\tx=$xdim, y=$ydim, z=$zdim, xfov=$xfov_mm, yfov=$yfov_mm, zfov=$zfov_mm\n") unless(($ggo==0) || ($image_suffix =~ m/[nii]/ ));
      @voxelsize=(0,0,0);
      ($xfov_mm,$yfov_mm,$zfov_mm)=(0,0,0);
      ($xdim,$ydim,$zdim)=(1,1,1);
  } else  {
      @voxelsize=($xfov_mm/$xdim,$yfov_mm/$ydim,$zfov_mm/$zdim);
#  my $iso_vox_mm = $xfov_mm/$xdim;
#  $iso_vox_mm = sprintf("%.4f", $iso_vox_mm);#  
#  print ("ISO_VOX_MM: $iso_vox_mm\n");
      print ("convert to nifti util \n\txdim:$xdim\txfov:$xfov_mm\n\tydim:$ydim\tzfov:$zfov_mm\n\tzdim:$zdim\tyfov:$yfov_mm\n") if ($debug_val>=25);
      print ("FOV_MM: $xfov_mm $yfov_mm $zfov_mm\n");
      print ("VOX_MM: @voxelsize\n");
  }




#  my $nii_raw_data_type_code = 4; # civm .raw  (short - big endian)
#  my $nii_i32_data_type_code = 8; # .i32 output of t2w image set creator 

  my $nii_setid ;
  if  ($image_suffix !~ m/[nii]/ ) {
      $nii_setid = nifti_ize_util ($data_setid, $xdim, $ydim, $zdim, $nii_raw_data_type_code,$xfov_mm/$xdim,$yfov_mm/$ydim,$zfov_mm/$zdim , $flip_y, $flip_z, $Hf);
  } else {
      $nii_setid = 
	  nifti_ize_util ($data_setid, $xdim, $ydim, $zdim, $nii_raw_data_type_code,0,0,0 , $flip_y, $flip_z, $Hf);
      # 0,0,0 is magic number for voxel size to set a nifti being reprocessed the same as its input settings.
  }
  ## dimensions are for the SOP acquisition. 
  ##nifti_ize ("input", 512, 256, 256, $nii_raw_data_type_code, 2, $flip_y, $flip_z, $Hf);
  #should become
  #nifti_ize ("T2star", 512, 256, 256, $nii_raw_data_type_code, 0.043, $flip_y, $Hf);
}

# ------------------
sub nifti_ize_util
# ------------------
{

  my ( $setid, $xdim, $ydim, $zdim, $nii_datatype_code, $xvox, $yvox, $zvox, $flip_y, $flip_z, $Hf) = @_;
  my $usedash=1; # switches between - or _ in headfile key names
  my $runno          = $Hf->get_value("${setid}-runno");  # runno of civmraw format scan 
  if ($runno eq 'NO_KEY') {  $runno          = $Hf->get_value("${setid}_runno"); } # runno of civmraw format scan 
  my $src_image_path = $Hf->get_value("${setid}-path");
  if ($src_image_path eq 'NO_KEY') { $usedash=0; $src_image_path = $Hf->get_value("${setid}_path"); }
  if ($src_image_path eq 'NO_KEY') { error_out("could not get src image path, there'ss some bad code floatin about"); }
  my $dest_dir       = $Hf->get_value("dir-work");
  if ($dest_dir eq 'NO_KEY' ) { $dest_dir       = $Hf->get_value("dir_work"); }
  my $image_base     = $Hf->get_value("${setid}-image-basename");
  if ($image_base eq 'NO_KEY') { $image_base     = $Hf->get_value("${setid}_image_basename"); }
  my $padded_digits  = $Hf->get_value("${setid}-image-padded-digits");
  if ($padded_digits eq 'NO_KEY') { $padded_digits  = $Hf->get_value("${setid}_image_padded_digits"); }
  my $image_suffix   = $Hf->get_value("${setid}-image-suffix");
  if ($image_suffix eq 'NO_KEY') { $image_suffix   = $Hf->get_value("${setid}_image_suffix"); }
  if($image_suffix !~ m/[raw|nii]/ ) { error_out("nifti_ize: image suffix $image_suffix not known to be handled by matlab nifti converter (just \.raw or \.nii)");}
#  $Hf->set_value("$setid\_image_suffix", $image_suffix);  # wtf mates? we just read this value out?
  my $sliceselect    = $Hf->get_value_like("slice-selection");  # using get_value like is experimental, should be switched to get_value if this fails.
  my  $NIFTI_MFUNCTION = $Hf->get_value("nifti_matlab_converter");
  if ( $NIFTI_MFUNCTION eq 'NO_KEY' ){
      error_out("nifti_matlab_converter not set in hf");
  }
  my ($zstart, $zstop); # = split('-',$sliceselect);  
  my $roll_string    = $Hf->get_value_like("roll_string");  # using get_value like is experimental, should be switched to get_value if this fails.

  my $ndigits = length($padded_digits);
  if ($ndigits < 3) { error_out("nifti_ize needs fancier padder"); }
  my $padder;
  if ($ndigits > 3) {
    $padder = 0 x ($ndigits - 3);
  }
  else { $padder = ''; }


  my $dest_nii_file;# = "$runno\.nii";
  my $dest_nii_path;# = "$dest_dir/$dest_nii_file";
  my $image_prefix ;
  if ($image_suffix !~ m/[nii]/ ) { 
      $image_prefix = $image_base . '.' . $padder; 
      $dest_nii_file = "$runno\.nii";
      $dest_nii_path = "$dest_dir/$dest_nii_file";
      
  } else {
      $image_prefix = $image_base ;
      $dest_nii_file = "$image_base\.nii";
      $dest_nii_path = "$dest_dir/$dest_nii_file";
      
  }


  print("srcpath:$src_image_path\trunno:$runno\n\tdest:$dest_dir\n\timage_name:$image_base\tdigits:$padded_digits\tsuffix:$image_suffix\n") if ($debug_val >=25);
  # --- handle image filename number padding (.0001, .001).
  # --- figure out the img prefix that the case stmt for the filename will need (inside the nifti.m function)
  #     something like: 'N12345fsimx.0'

  my $args;
  if ( $roll_string eq "NO_KEY" || $roll_string eq "UNDEFINED_VALUE" || $roll_string eq "EMPTY_VALUE" ) {
    $roll_string="0:0";
  }
  if ( $sliceselect eq "all" || $sliceselect eq "NO_KEY" || $sliceselect eq "UNDEFINED_VALUE" || $sliceselect eq "EMPTY_VALUE" ) {
    ($zstart, $zstop) = ( 1, $zdim);
  #$args =   "\'$src_image_path\', \'$image_prefix\', \'$image_suffix\', \'$dest_nii_path\', $xdim, $ydim, $zdim, $nii_datatype_code, $xvox,$yvox,$zvox, $flip_y, $flip_z";
  } else { 
    ($zstart, $zstop) = split('-',$sliceselect);
  }
#      $args = "\'$src_image_path\', \'$image_prefix\', \'$image_suffix\', \'$dest_nii_path\', $xdim, $ydim, $zdim, $nii_datatype_code, $xvox,$yvox,$zvox, $flip_y, $flip_z, $zstart, $zstop";   
  $args = "\'$src_image_path\', \'$image_prefix\', \'$image_suffix\', \'$dest_nii_path\', $xdim, $ydim, $zdim, $nii_datatype_code, $xvox,$yvox,$zvox, $flip_y, $flip_z, $zstart, $zstop, \'$roll_string\'";

  my $cmd =  make_matlab_command ($NIFTI_MFUNCTION, $args, "$setid\_", $Hf); 
  if ( ! -e $dest_nii_path) { 
      if (! execute($ggo, "nifti conversion", $cmd) ) {
	  error_out("Matlab could not create nifti file from runno $runno:\n  using $cmd\n");
      }
      if (! -e $dest_nii_path) {
	  error_out("Matlab did not create nifti file $dest_nii_path from runno $runno:\n  using $cmd\n");
      }
  }


  # --- required return and setups -----

  my $nii_setid;
  if($usedash==1) { # the new behavior use - to separate words in keynames added to headfile by pipeline 
      $nii_setid = "${setid}-nii";
      $Hf->set_value("${nii_setid}-file" , $dest_nii_file);
      $Hf->set_value("${nii_setid}-path", $dest_nii_path);
      print "** nifti-ize created [${nii_setid}-path]=$dest_nii_path\n";
  } else { # the old behavior use _ to separate words in keynames added to the headfile by the pipeline
      $nii_setid = "${setid}_nii";
      $Hf->set_value("${nii_setid}_file" , $dest_nii_file);
      $Hf->set_value("${nii_setid}_path", $dest_nii_path);
      print "** nifti-ize created [${nii_setid}_path]=$dest_nii_path\n";
  }
  return ($nii_setid);
}



1;

