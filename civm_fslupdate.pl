# 
use strict;
use warnings;
use ENV;
## get list of fsl update files, (hopefully we cna get htem in order

print("---\n");
print("Updating FSL ...... \n");
print ("");#put in updatelist.
print("---\n");
my $scp_cmd;
# find dmg on syros
# my $ants_dmg=`ssh syros ls -tr /Volumes/xsyros/Software/SegmentationSoftware/*dmg| grep ANT |tail -n 1`;
# chomp($ants_dmg);
# $ants_dmg=basename($ants_dmg);
# #scp dmg
# $scp_cmd="scp syros:/Volumes/xsyros/Software/SegmentationSoftware/$ants_dmg ../$ants_dmg";


# my $fslupdate=`civm_fslupdate.pl`;
#tar -zxvf ~/Downloads/fsl-macosx-patch-5.0.2_from_5.0.1.tar.gz

cd $FSLDIR or die  "nofsldir in env";
#tar -xvzf fsl-macosx-patch-5.0.6_from_5.0.5.tar.gz
