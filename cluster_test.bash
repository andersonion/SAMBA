#!/bin/env bash  

#Are we on a cluster? Asking for a friend...

chatterbox=$1

cluster=0;
SGE_cluster=$(qstat  2>&1 | grep 'command not found' | wc -l | tr -d [:space:]);
slurm_cluster=$(sbatch --help  2>&1 | grep 'command not found' | wc -l | tr -d [:space:]);
# This returns '1' if NOT on a cluster, so let's reverse that...
if ((! ${slurm_cluster}));then
	cluster=1;
elif ((! ${SGE_cluster}));then
	cluster=2;
fi

if [[ ${chatterbox} ]];then
	echo "Great News, Everybody! It looks like we're running on a cluster, which should speed things up tremendously!";
fi

echo ${cluster} && exit ${cluster};