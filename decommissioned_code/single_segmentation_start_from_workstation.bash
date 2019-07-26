#!/bin/bash
# Inputs: [runno] [users_net_id] [study/project_code] [number_of_dti_volumes*] [atlas_with_labels]
#
# *(counting from 1, not zero)



runno=$1;

c_user=$2;

study=$3
if [ -z "$study" ]; then # Assume this is the Sills study
    study='17.sills.02';
fi
echo "Study name: $study"


n_dti_volumes=$4;
if [ -z "$n_dti_volumes" ]; then # Assume this is the Sills study
    n_dti_volumes=18;
fi
echo "Number of DTI volumes: $n_dti_volumes";
atlas=$5;
if [ -z "$atlas" ]; then # Assume this is the Sills study
    atlas='xmas2015rat';
fi
echo "Label atlas: ${atlas}"

magnet="7T"; # Assume this is the 7T scanner

if [[ $runno == N* ]]; then
    magnet="9T";
fi

host=$WORKSTATION_HOSTNAME;
domain='dhe.duke.edu';
if [ $host == 'civmcluster1' ]; then
    #domain='dhe.duke.edu';
    echo "This script is not meant to be ran on the cluster!  It is for workstation only.  Dying now...";
    exit;
fi

if [ -z "$c_user" ]; then
    echo "c_user = ${c_user}";
    echo "You have not specified your netid (your cluster user name). Fix this and rerun.  Dying now...";
    exit;
fi

#echo ssh-copy-id ${c_user}@civmcluster1.${domain};

sleep_sec=60;




echo "Checking for reconstructed images...";
n_ready_vols=$(ls $BIGGUS_DISKUS/${runno}_m*/${runno}_m*images/*0001*raw | wc -l | xargs );
#echo n ready vols $n_ready_vols
while [[ "$n_ready_vols" -lt "$n_dti_volumes" ]]; do
    echo "Only ${n_ready_vols} of ${n_dti_volumes} DTI volumes are ready. Will check again in ${sleep_sec} seconds."
    sleep ${sleep_sec};
    n_ready_vols=$(ls $BIGGUS_DISKUS/${runno}_m*/${runno}_m*images/*0001*raw | wc -l | xargs );
done

echo "All ${n_dti_volumes} DTI volumes are ready; checking for righteous headfile...";

n_ready_hfs=$(grep z_Agilent_dro $BIGGUS_DISKUS/${runno}_m*/${runno}_m*images/*headfile | wc -l | xargs );
#echo ready hfs $n_ready_hfs
while [[ "$n_ready_hfs" -lt "$n_dti_volumes" ]]; do
    echo "Only ${n_ready_hfs} of ${n_dti_volumes} headfiles are ready. Will check again in ${sleep_sec} seconds."
    sleep ${sleep_sec};
    n_ready_hfs=$(grep z_Agilent_dro $BIGGUS_DISKUS/${runno}_m*/${runno}_m*images/*headfile | wc -l | xargs );
done

echo "All ${n_ready_hfs} headfiles are ready; beginning tensor create (if needed)."
sleep 2;

tensor_hf_count=$(ls -t $BIGGUS_DISKUS/tensor${runno}_m*/tensor${runno}_m*.headfile | wc -l | xargs);
#tensor_hf=$(ls -t $BIGGUS_DISKUS/tensor${runno}_m*/tensor${runno}_m*.headfile | head -1 );
if [[ "$tensor_hf_count" == 0 ]]; then
echo "No tensor headfile.  Running tensor create now."

found_runs=$(find $BIGGUS_DISKUS/ -maxdepth 1 -name "${runno}_m*" -exec basename {} \; )


tc_cmd="tensor_create ${c_user} ${study} ${study} ${magnet} ${n_dti_volumes} ${found_runs}"

echo "tensor create command is:"
echo ${tc_cmd};

$tc_cmd;

echo "Tensor create appears to be finished!";
else
echo "Tensor create appears to already have ran...not rerunning."
fi

tensor_hf=$(ls -t $BIGGUS_DISKUS/tensor${runno}_m*/tensor${runno}_m*.headfile | head -1);
tensor_hf="/Volumes/${tensor_hf}";
if [ ! -f $tensor_hf ]; then
echo "No tensor headfile found! FAILING NOW."

else
echo "Now sending to the cluster for single_segmentation pipeline processing...";
ss_cmd="ssh ${c_user}@civmcluster1.${domain} single_segmentation $tensor_hf $atlas";
echo "Running remote command: $ss_cmd";

$ss_cmd;
fi