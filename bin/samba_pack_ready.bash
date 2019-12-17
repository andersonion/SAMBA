#!/usr/bin/env bash
# package any ready data
# this uses the stats headfile as the "ready" flag becuase at that point we've labeled our data, 
# and have all the transforms and stats sheets we want.

# While any atlas dir has plain nii files, try again
# while [ $(ls $BIGGUS_DISKUS/atlas/*|grep -c nii\$) -gt 1 ];
# do echo -n "MDT->atlas prep "; date;
for shf in *.headfile; 
do 
    # for the test sets the vbmsuffix was both in the file AND in the filename.
    #vbmsuffix=$(echo ${hf%.*}|cut -d '_' -f2);
    vbmsuffix=$(grep '^optional_suffix=' $shf|tail -n1|cut -d '=' -f2);
    hf=$(ls $BIGGUS_DISKUS/VBM*${vbmsuffix}-work/dwi/SyN*fa/fa*i6/vox*/pre*/stats*headfile 2> /dev/null)
    #hf=$(ls /home/jjc29/TMP_BIGGUS/VBM_18gaj42_chass_symmetric3_RAS_${vbmsuffix}_hybrid-work/dwi/SyN*fa/fa*i6/median_images/faMDT_all_n*_temp.headfile 2> /dev/null)
    #MDT_images/.faMDT_all_n8_amw_temp.headfile;
    # if we want to check for tmux'd samba
    #if [ $(tmux list-session|grep -c $vbmsuffix: ) -le 0 ];then echo samba not running for $vbmsufix;fi
    # This uses stat hf instead of results because results will take longer, and this step is quasi parallel.
    if [ ! -z "$hf" -a -f "$hf" ];
    then 
	SAMBA_data_packager --hf_path=$hf --output_base=$BIGGUS_DISKUS/18gaj42_pak/${vbmsuffix} --mdtname=${vbmsuffix} --rsync_location=delos.dhe.duke.edu:/Volumes/delosspace/18gaj42_pak;#--no-instant_feedback ;
    else echo -n ''; 
	echo "$N is not ready (skipped).";
    fi;
done;
#echo waiting 300 seconds ; sleep 300;
#done
