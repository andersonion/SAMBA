#! /bin/env bash
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

if [[ ! -e "${folder}/${file_name}" ]];then
	echo "Input file does not appear to exist. Dying now..." && exit 1;
fi

ants_test=$(PrintHeader 2>&1 1>/dev/null | wc -l);
if [[ ! $ants_test ]];then
	echo "Ants command 'PrintHeader' either not found or not functioning;";
	echo "You may need to switch to an environment where this is installed;"
	echo "(For example, you may be on a master node, and should be on a child node.)" && exit 2;
fi

tmp_work=${folder}/${file_name%.nii???}_orientation_tester-work/;


if [[ ! -d ${tmp_work} ]]; then
        mkdir -m 775 ${tmp_work};
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
ovs_1=$(PrintHeader ${target} 1 | cut -d  'x' -f1);
ovs_2=$(PrintHeader ${target} 1 | cut -d  'x' -f2);
ovs_3=$(PrintHeader ${target} 1 | cut -d  'x' -f3);

a=$( bc -l <<<"8*$ovs_1 " )
b=$( bc -l <<<"8*$ovs_2 " )
c=$( bc -l <<<"8*$ovs_3 " )
#a=$(( 8*ovs_1 ));
#b=$(( 8*ovs_2 ));
#c=$(( 8*ovs_3 ));

if [[ ! -f ${input} ]];then
        #ResampleImageBySpacing 3 ${image} ${input} .2 .2 .2 0;
        ResampleImageBySpacing 3 ${image} ${input} ${a} ${b} ${c} 0;
fi

ds_target=${tmp_work}${target_name%.nii???}_x8_downsampled.nii.gz;
if [[ ! -f ${ds_target} ]];then
        #ResampleImageBySpacing 3 ${image} ${input} .2 .2 .2 0;
        ResampleImageBySpacing 3 ${target_folder}/${target_name} ${ds_target} ${a} ${b} ${c} 0;
fi

for in_code in ${in_codes[@]}; do
        out_image=${tmp_work}${file_name%.nii???}_${in_code}_to_${out_code}.nii.gz;
        if [[ ! -f ${out_image} ]]; then
                bash ${MATLAB_EXEC_PATH}/img_transform_executable/run_img_transform_exec.sh ${MATLAB_2015b_PATH} ${input} ${in_code} ${out_code} ${out_image};
        fi
done
