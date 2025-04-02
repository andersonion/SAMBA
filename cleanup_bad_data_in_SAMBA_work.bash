#! /bin/bash

work_dir=$1;
bad_runnos=$2;
action_flag=$3;
if [[ "x${action_flag}x" == "xx" ]];then
    action_flag=0;
fi

if (($action_flag == 1));then
	action='rm';
else
	action='ls';
fi
#bad_runnos="${bad_runno_1} ${bad_runno_2} ${bad_runno_3}"; # Space-delimited list of bad runnos

# Remove from preprocess and/or dwi:
for runno in $bad_runnos;do ${action} ${work_dir}/*/*${runno}*  2>/dev/null;done

# Remove from preprocess/masks:
for runno in $bad_runnos;do ${action} ${work_dir}/preprocess/masks/*${runno}*  2>/dev/null;done

# Remove from base_images:
for runno in $bad_runnos;do ${action} ${work_dir}/preprocess/base_images:/*${runno}*  2>/dev/null;done

# Remove from translation_xforms: --THIS ONE IS MOST LIKELY TO BE OVERLOOKED BY HUMAN!
for runno in $bad_runnos;do ${action} ${work_dir}/preprocess/base_images:/translation_xforms/*${runno}*  2>/dev/null;done

# Remove from template creation subfolder:
for runno in $bad_runnos;do ${action} ${work_dir}/*/SyN_*/*/*/*${runno}*  2>/dev/null;done

# Remove from label subfolders:
for runno in $bad_runnos;do ${action} ${work_dir}/*/SyN_*/*/stats_by_region/labels/*/*/*${runno}* 2>/dev/null;done
for runno in $bad_runnos;do ${action} ${work_dir}/*/SyN_*/*/stats_by_region/labels/*/*/stats/*/*/*${runno}* 2>/dev/null;done

 # Remove from even vbal subfolders:
for runno in $bad_runnos;do ${action} ${work_dir}/*/SyN_*/*/vbm_analysis/*/*/*${runno}* 2>/dev/null;done
for runno in $bad_runnos;do ${action} ${work_dir}/*/SyN_*/*/vbm_analysis/*/*${runno}* 2>/dev/null;done


####
