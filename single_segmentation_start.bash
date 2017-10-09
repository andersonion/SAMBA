#!/bin/bash

remote_tensor_hf=$1;
atlas=$2;
#headfile_template="$WORKSTATION_DATA/single_seg_input_template.headfile"; #DOESNT QUITE WORK RIGHT
headfile_template="/cm/shared/CIVMdata/single_seg_input_template.headfile"

echo "Using defaults for single segmentation as defined in ${headfile_temp}.";
staart_headfile="$HOME/.seghf";# Must define.. probably shouldnt be in tmp...

if [ -z "$remote_tensor_hf" ]; then
    echo "You must specify the headfile path on your workstation";
exit; 
fi;

if [ -z "$atlas" ]; then
    echo "Please specify requested atlas";
    echo "---"
    # can we get atlas list here, 
    # $workstation_data/data/atlas?
    pushd $PWD;
    cd $WORKSTATION_DATA/atlas/ ;
    find . -maxdepth 1;
    popd;
    echo "---"
    exit;
fi;

# if get_workstation_hosts doesnt work, can just hard code list of engines to get data fro m
hst_list="andros delos piper vidconfmac";#$(get_workstation_hosts);
tensor_hf="/tmp/$(basename $remote_tensor_hf)";

for hst in $hst_list; do 
    if [ ! -f $tensor_hf ]; then
	echo "trying $hst";
	scp omega@$hst.duhs.duke.edu:/Volumes/${hst}space/$remote_tensor_hf /tmp/ && success=$hst
    else 
	continue;
    fi
done
echo '' > $staart_headfile; # clear startup headfile

U_runno=$(grep 'U_runno=' $tensor_hf|cut -d '=' -f2 );

if [ ! "${U_runno}" ]; then
    U_runno=$(grep 'U_runno_m00=' $tensor_hf|cut -d '=' -f2 );
fi

U_code=$(grep 'U_code=' $tensor_hf|cut -d '=' -f2 );
if [ ! "${U_code}" ]; then
    U_code=$(grep 'U_code_m00=' $tensor_hf|cut -d '=' -f2 );
fi


# OR 
grep U_* ${tensor_hf}  >> $staart_headfile;
echo "project_name=${U_code}"  >> $staart_headfile;
echo "group_1_runnos=${U_runno%_*}"  >> $staart_headfile;
echo "rigid_atlas_name=$atlas" >> $staart_headfile;
echo "label_atlas_name=$atlas" >> $staart_headfile;
echo "recon_machine=$success" >> $staart_headfile;
cat $headfile_template >> $staart_headfile;


#SAMBA_startup $staart_headfile;
more $staart_heaedfile;


