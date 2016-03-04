args <- commandArgs(trailingOnly = TRUE)
(contrast,maskname,controlinputfolder,treatedinputfolder,resultsfolder,control_name,treated_name,controlimages,treatedimages,cluster_thresh_size) <- commandArgs(trailingOnly = TRUE)
library(knitr)
library(ANTsR)
#setwd(resultsfolder)
if(!exists("simple_voxel_based_analysis", mode="function")) source("/home/rja20/cluster_code/workstation_code/analysis/vbm_pipe/simple_voxel_based_analysis.R")
if(!exists("simple_roi_analysis", mode="function")) source("/home/rja20/cluster_code/workstation_code/analysis/vbm_pipe/simple_roi_analysis.R")
control_images<-unlist(strsplit(controlimages, ","))
num_control = length(control_images)

controlFileNames = {}
for (i in 1:num_control) {
temp_name = paste0(controlinputfolder,control_images[i])
  controlFileNames <- c(controlFileNames,temp_name)
}

treated_images<-unlist(strsplit(treatedimages, ","))
num_treated = length(treated_images)
treatedFileNames = {}
for (i in 1:num_treated) {
  temp_name = paste0(treatedinputfolder,treated_images[i])
  treatedFileNames <- c(treatedFileNames,temp_name)
}

images <- c(controlFileNames, treatedFileNames)

#output <- antsImageRead('MDT_fa.nii')
#mask<-thresholdImage(output, 0.3, 1.3)
#getMask(mask) 
#maskname <- ("../inputs/MDT_mask_A.nii")
#antsImageWrite(mask,maskname)
directions = c(1,-1)
for (direction in directions) {
  message_1 <- paste0("direction = ", direction)
  print(message_1)
diagnosis <- c(rep(1*direction, num_control), rep(-1*direction,num_treated))

outputPath <- resultsfolder

if(direction == 1) {
  prefix <- paste0(control_name,"_gt_",treated_name,"_")
} else {
  prefix <- paste0(treated_name,"_gt_",control_name,"_")
}
if (0) {
simple_voxel_based_analysis(dimensionality = 3, imageFileNames = images, predictors = data.frame(diagnosis),
                            maskFileName = maskname, outputPrefix = paste0(outputPath, prefix), testType = "student.t")
}
message_2 <- paste0("VBA completed for direction: ", direction)
print(message_2)
timg <- antsImageRead(paste0(outputPath, prefix, "tValues.nii.gz"), 2)

#Read in uncorrected t-statistics image
unc_t_file_name = paste0(outputPath,prefix,"1minuspValues.nii.gz")
#x = antsImageRead("ANTsR_t.test_1minuspValues.nii.gz")
x = antsImageRead(unc_t_file_name)

#Perform cluster analysis with uncorrected values, minimum cluster size, lower threshold, upper threshold

lower_thresh <- 0.8 # what are good values for the two threshs?
upper_thresh <- 1   #
clusts <-image2ClusterImages(x,cluster_thresh_size,lower_thresh,upper_thresh) 

num_clusts <- length(unlist(clusts))
#Values for each cluster
mask_clust1ind1<-getMask(clusts[[1]], 0.000001, 100000)
myvals1<-imagesToMatrix(images,mask_clust1ind1)
write.table(myvals1, "firstcluster.csv", append = FALSE, sep = ",", col.names = TRUE, row.names = FALSE, quote = FALSE)

mask_clust1ind2<-getMask(clusts[[2]], 0.000001, 100000)
myvals2<-imagesToMatrix(images,mask_clust1ind2)
write.table(myvals2, "secondcluster.csv", append = FALSE, sep = ",", col.names = TRUE, row.names = FALSE, quote = FALSE)

mask_clust1ind3<-getMask(clusts[[3]], 0.000001, 100000)
myvals3<-imagesToMatrix(images,mask_clust1ind3)
write.table(myvals3, "thirdcluster.csv", append = FALSE, sep = ",", col.names = TRUE, row.names = FALSE, quote = FALSE)

# adding all the values of the first xx rows (control)
rowcon1 <-rowSums(myvals1[1:num_control,])
rowcon2 <-rowSums(myvals2[1:num_control,])
rowcon3 <-rowSums(myvals3[1:num_control,])

# adding all the values of the yy 10 rows (experimental)
colcon1 <-rowSums(myvals1[(num_control+1):(num_control+num_treated),])
colcon2 <-rowSums(myvals2[(num_control+1):(num_control+num_treated),])
colcon3 <-rowSums(myvals3[(num_control+1):(num_control+num_treated),])

#T-Test on all the values from control vs experimental
cluster1 <- t.test(rowcon1,colcon1)
cluster2 <- t.test(rowcon2,colcon2)
cluster3 <- t.test(rowcon3,colcon3)

#Converts T-test output into a data frame
cluster1 = as.data.frame(do.call(rbind, cluster1))
cluster2 = as.data.frame(do.call(rbind, cluster2))
cluster3 = as.data.frame(do.call(rbind, cluster3))

#Writes output to a CSV file
write.table(cluster1, "sumvalsclust1.csv", append = FALSE, sep = ",", col.names = TRUE, row.names = TRUE, quote = FALSE)
write.table(cluster2, "sumvalsclust2.csv", append = FALSE, sep = ",", col.names = TRUE, row.names = TRUE, quote = FALSE)
write.table(cluster3, "sumvalsclust3.csv", append = FALSE, sep = ",", col.names = TRUE, row.names = TRUE, quote = FALSE)
}

}



