#! /bin/env bash

# Are we on a cluster, my friend?
if [[ -d ${GUNNIES} ]];then
	GD=${GUNNIES};
else
	GD=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd );
fi

SPath="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )";
cluster_code=$(bash ${SPath}/cluster_test.bash);
if [[ ${cluster_code} ]];then

    if [[ ${cluster_code} -eq 1 ]];then
		sub_script=${GD}/submit_slurm_cluster_job.bash;
	fi
	
    if [[ ${cluster_code} -eq 2 ]];then
		sub_script=${GD}/submit_sge_cluster_job.bash
	fi
	echo "Great News, Everybody! It looks like we're running on a cluster, which should speed things up tremendously!";
fi



image=$1;
out_code=$2;
target=$3;
if [[ ${image:0:1} != '/' ]];then
        file_name=$image;
        folder=$PWD;
else
        file_name=${image##*/};
        folder=${image%/*}
fi
full_file=${folder}/${file_name};
if [[ ! -f "${full_file}" ]];then
	echo "Input file '${folder}/${file_name}' does not appear to exist or is not a file. Dying now..." && exit 1;
fi

if ((! ${cluster_code}));then
	# This is actually an inverse test.
	ants_test=$(PrintHeader 2>&1 1>/dev/null | wc -l);
	if [[ $ants_test -gt 0 ]];then
		echo "Ants command 'PrintHeader' either not found or not functioning;";
		echo "You may need to switch to an environment where this is installed;"
		echo "(For example, you may be on a master node, and should be on a child node.)" && exit 2;
	fi
fi
i_name=${file_name%.nii???};
tmp_work=${folder}/${i_name}_orientation_tester-work/;


if [[ ! -d ${tmp_work} ]]; then
        mkdir -p -m 775 ${tmp_work};
fi

if [[ ! -d ${tmp_work} ]]; then
	# It's possible we can't write to the directory where the input image is (and is actually probably bad practice)
	# Write to user's home instead
	tmp_work=~/${file_name%.nii???}_orientation_tester-work/;
	if [[ ! -d ${tmp_work} ]]; then
        mkdir -p -m 775 ${tmp_work};
	fi
fi

if [[ ! -d ${tmp_work} ]]; then
    echo "Unable to create a temporary work folder (possibly due to permission issues);"
	echo " Attempted to create: ${tmp_work}. Dying now..." && exit 3;
else
	echo "Downsampled images can be found in: ${tmp_work}."
fi

if [[ "x${target}x" == 'xx' ]];then
        target=${BIGGUS_DISKUS}/../atlases//chass_symmetric3/chass_symmetric3_DWI.nii.gz;
        if [[ ! -e ${target} ]];then
        	target=${ATLAS_PATH}/chass_symmetric3/chass_symmetric3_DWI.nii.gz;
		fi
        out_code='ALS';
fi


if [[ ${target:0:1} != '/' ]];then
        target_name=$target;
        target_folder=$PWD;
else
        target_name=${target##*/};
        target_folder=${target%/*}
fi

# Test for valid out_code
in_codes=();
RHS=(ALS PRS ARI PLI RAS LPS LAI RPI SAL SPR IAR IPL SRA SLP ILA IRP LSA RSP RIA LIP ASR PSL AIL PIR);
LHS=(PLS ARS PRI ALI LAS RPS RAI LPI IAL IPR SAR SPL IRA ILP SLA SRP RSA LSP LIA RIP PSR ASL PIL AIR);

if [[ " ${RHS[*]} " =~ " ${out_code} " ]]; then
    in_codes=(${RHS[@]}) 
elif [[ " ${LHS[*]} " =~ " ${out_code} " ]];then
    in_codes=(${LHS[@]}) 
else
	echo "${out_code} is not a valid SPIRAL orientation code. Dying...";
	exit 1;
fi

input=${tmp_work}${file_name}_down_sampled.nii.gz;
ds_target=${tmp_work}${target_name%.nii???}_x8_downsampled.nii.gz;

if [[ ${cluster_code} -gt 0 ]];then
	sbatch_folder=${tmp_work}/sbatch;
	if [[ ! -d ${sbatch_folder} ]];then
		mkdir -m 775 $sbatch_folder;
	fi
	cmd_1="ovs_1=\$(PrintHeader ${target} 1 | cut -d  'x' -f1);a=\$( bc -l <<<\"8*$ovs_1 \" );";
	cmd_2="ovs_2=\$(PrintHeader ${target} 1 | cut -d  'x' -f2);b=\$( bc -l <<<\"8*$ovs_2 \" );";
	cmd_3="ovs_3=\$(PrintHeader ${target} 1 | cut -d  'x' -f3);c=\$( bc -l <<<\"8*$ovs_3 \" );";
	cmd_4="if [[ ! -f ${input} ]];then ResampleImageBySpacing 3 ${image} ${input} ${a} ${b} ${c} 0; fi;";
	cmd_5="if [[ ! -f ${ds_target} ]];then ResampleImageBySpacing 3 ${target_folder}/${target_name} ${ds_target} ${a} ${b} ${c} 0;fi;";
	
	cmd="${cmd_1}${cmd_2}${cmd_3}${cmd_4}${cmd_5}";
	name="${i_name}_prep_work";
	sub_cmd="${sub_script} ${sbatch_folder} ${name} 0 0 ${cmd}";
	job_id=$(${sub_cmd} | tail -1 | cut -d ';' -f1 | cut -d ' ' -f4);
	prep_jid=0;
	if ((! $?));then
		prep_jid=${job_id};
	fi	
else
	ovs_1=$(PrintHeader ${target} 1 | cut -d  'x' -f1);
	ovs_2=$(PrintHeader ${target} 1 | cut -d  'x' -f2);
	ovs_3=$(PrintHeader ${target} 1 | cut -d  'x' -f3);
	
	a=$( bc -l <<<"8*$ovs_1 " );
	b=$( bc -l <<<"8*$ovs_2 " );
	c=$( bc -l <<<"8*$ovs_3 " );
	
	if [[ ! -f ${input} ]];then
		ResampleImageBySpacing 3 ${image} ${input} ${a} ${b} ${c} 0;
	fi
	
	ds_target=${tmp_work}${target_name%.nii???}_x8_downsampled.nii.gz;
	if [[ ! -f ${ds_target} ]];then
			ResampleImageBySpacing 3 ${target_folder}/${target_name} ${ds_target} ${a} ${b} ${c} 0;
	fi
fi

for in_code in ${in_codes[@]}; do
	out_image=${tmp_work}${file_name%.nii???}_${in_code}_to_${out_code}.nii.gz;
	if [[ ! -f ${out_image} ]]; then
		if (($cluster_code));then
			job_name=${i_name}_img_xform_${in_code}_to_${out_code};
			final_cmd="bash ${MATLAB_EXEC_PATH}/img_transform_executable/run_img_transform_exec.sh ${MATLAB_2015b_PATH} ${input} ${in_code} ${out_code} ${out_image}";
			sub_cmd="${sub_script} ${sbatch_folder} ${job_name} 0 ${prep_jid} ${final_cmd}";
			job_id=$(${sub_cmd} | tail -1 | cut -d ';' -f1 | cut -d ' ' -f4);
			echo "JOB ID = ${job_id}; Job Name = ${job_name}";
		else
			bash ${MATLAB_EXEC_PATH}/img_transform_executable/run_img_transform_exec.sh ${MATLAB_2015b_PATH} ${input} ${in_code} ${out_code} ${out_image};
		fi
	fi
done
