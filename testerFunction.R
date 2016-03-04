maskname <-'/Users/omega/Natalie/VBM_phantom_data/inputs_2/MDT_mask_e3.nii'
  controlinputfolder <-'/Users/omega/Natalie/VBM_phantom_data/inputs_2/'
  treatedinputfolder <-'/Users/omega/Natalie/VBM_phantom_data/inputs_2/'
  control_name <- 'Control'
  treated_name <- 'Phantoms'
  contrast <-'fa'
  contrast_string <- paste0("S*",contrast,"*")
  contrast_string2 <- paste0("W*",contrast,"*")
  controlimages <-paste0(paste0("S64944_",contrast,"_to_MDT_s3vox.nii"),",",paste0("S64953_",contrast,"_to_MDT_s3vox.nii"))
  treatedimages <-paste0(paste0("W64944_",contrast,"_to_MDT_s3vox.nii"),",",paste0("W64953_",contrast,"_to_MDT_s3vox.nii"))
  cluster_thresh_size = 200;
  resultsfolder <-"/Users/omega/Natalie/VBM_phantom_data/output/test_output2/"
source("/Users/omega/Natalie/rscripts/ANTsR_vba.R")
  ANTsR_vba(contrast,maskname,controlinputfolder,treatedinputfolder,resultsfolder,control_name,treated_name,controlimages,treatedimages,cluster_thresh_size)
   