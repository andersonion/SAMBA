#!/bin/env bash                                                                                                 

# If you have admin privileges, you can set these variables cluster-wide.
# In that case provide the full path to the script in /etc/profile.d/ as the first argument.

profiled_script=$1;
update_bashrc=1;
if [[ ${profiled_script:0:15} == "/etc/profile.d/" ]];then
	update_bashrc=0;
fi


if [[ "xx" == "x${SAMBA_APPS_DIR}x" ]];then
	echo "Environment variable 'SAMBA_APPS_DIR' has not been defined."
	echo "Either define this in your ~/.bashrc file OR"
	echo "if you have sudo/admin privileges, in a script in /etc/profile.d/"
	echo "The line should look something like:"
	echo "'export SAMBA_APP_DIR=/SAMBAs/parent/folder/'"
	echo "Quitting without doing work now..." && exit 1
fi


if [[ ! -d ${SAMBA_APPS_DIR} ]];then
	echo "Environment variable 'SAMBA_APPS_DIR' is set, but does not exist."
	echo "SAMBA_APPS_DIR=${SAMBA_APPS_DIR}" && exit 1
fi

# Let's making coding easier...
SAD=${SAMBA_APPS_DIR};

pb_test=$(which perlbrew  2> /dev/null | wc -l);
echo "perlbrew test = ${pb_test}";


if [[ ${pb_test} == 0 ]];then
    export PERLBREW_ROOT=${SAD}/perl5;
    curl -L http://install.perlbrew.pl | bash 1> /dev/null;
fi
    src_file=${SAD}/perl5/etc/bashrc;
    src_file=$(ls ${src_file});
    src_cmd="source ${src_file}";
      
    
    if ((${update_bashrc}));then
	    src_test=$(grep "${src_cmd}" ~/.bashrc | wc -l);
    	if [[ ${src_test} == 0 ]]; then
    		echo "Adding local version of perlbrew to ~/.bashrc";
        	echo "# Adding local version of perlbrew:" >> ~/.bashrc;
        	echo ${src_cmd} >> ~/.bashrc;
        fi
	else
		src_test=$(grep "${src_cmd}" ${profiled_script} | wc -l);
		if [[ ${src_test} == 0 ]]; then
			echo "Adding local version of perlbrew to ${profiled_script}";
        	echo "# Adding local version of perlbrew:" | sudo tee -a ${profiled_script};
        	echo ${src_cmd} | sudo tee -a ${profiled_script};
        fi   
    fi
    
    ${src_cmd};
    
    #status=$(${src_cmd});                                                                                  
    #status=$(source /home/rja20/linux/perl5/etc/bashrc);                                                   
    #echo $status;
#fi
pb_test=$(which perlbrew  2> /dev/null | wc -l);
echo "perlbrew test = ${pb_test}";
