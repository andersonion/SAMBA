#!/bin/env bash  
# 14 February 2025 (Friday), BJ Anderson
#Are we on a cluster? Asking for a friend...

chatterbox=$1

if [[ "x${chatterbox}x" == "xx" || "x${chatterbox}x" == "x0x"   ]];then
	chatterbox=0;
else
	chatterbox=1;
fi

cluster=0;
SGE_cluster=$(qstat  2>&1 | grep 'command not found' | wc -l | tr -d [:space:]);
slurm_cluster=$(sbatch --help  2>&1 | grep 'command not found' | wc -l | tr -d [:space:]);
# This returns '1' if NOT on a cluster, so let's reverse that...
if ((! ${slurm_cluster}));then
	cluster=1;
elif ((! ${SGE_cluster}));then
	cluster=2;
fi

if ((${chatterbox}));then
	if ((${cluster}));then
		echo "Great News, Everybody! It looks like we're running on a cluster, which should speed things up tremendously!";
		if [[ ${cluster} -eq 1 ]];then
			echo "Cluster type: SLURM"
		elif [[ ${cluster} -eq 2 ]];then
			echo "Cluster type: SGE"
		else
			echo "Cluster type: CURRENTLY UNDEFINED"
		fi
	else
		echo "Shucks! We're not running on a cluster, which will probably slow things down tremendously.";
	fi
fi

echo ${cluster} && exit ${cluster};