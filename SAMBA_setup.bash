#!/bin/env bash                                                                                                 

# If you have admin privileges, you can set these variables cluster-wide.
# In that case provide the full path to the script in /etc/profile.d/ as the first argument.
DEBUG=0;
db=' 2>/dev/null ';
if (($DEBUG));then
	db='';
fi
profiled_script=$1;
update_bashrc=1;
# Originally presumed that we had to edi a script in the /etc/profile.d/
# but since we switched to a symbolic link pointing elsewhere,
# we want to loosen that restriction for us and others during setup.
#if [[ ${profiled_script:0:15} == "/etc/profile.d/" ]];then
if [[ -e ${profiled_script} ]];then
	update_bashrc=0;
fi

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )";

brc_SAMBA=${SCRIPTPATH}/bashrc_for_SAMBA
if [[ ! -f ${brc_SAMBA} ]];then
	echo "CRITICAL ERROR: The file ${brc_SAMBA} does not exist! Let's fix this:"
	echo " 1) Please make a copy of ${brc_SAMBA}_template named ${brc_SAMBA}."
	echo "command: \'cp ${brc_SAMBA}_template ${brc_template}\'"
	echo " 2) Edit and save the variables to match your setup."
        echo " 3) Rerun SAMBA_setup" && exit 1
else
	source ${brc_SAMBA}
fi

if [[ ! -d ${SAMBA_APPS_DIR} ]];then
	echo "Environment variable 'SAMBA_APPS_DIR' is set, but does not exist."
	echo "Please double-check that you have set it appropriately."
	echo "SAMBA_APPS_DIR=${SAMBA_APPS_DIR}" && exit 1
fi

# Let's making coding easier...
SAD=${SAMBA_APPS_DIR};


function append_startup_script(){
	local msg=$1;
	local bashrc_cmd=$2;
	local bashrc_msg=$3;
	local external_bashrc=$4;
	#local  __resultvar=$2;
	#local c_number='';
	
	if [[ "x${external_bash}x" != "xx" ]];then
		target=${brc_SAMBA};
	else   
		if ((${update_bashrc}));then
			target=~/.bashrc; 
		else
			target=${profiled_script};
		fi
	fi
	
	src_test=$(grep "${bashrc_cmd}" ${target} | wc -l);
	if [[ ${src_test} == 0 ]]; then
		echo ${msg} " ${target}";
		if [[ ${bashrc_msg} ]];then
			echo "# ${bashrc_msg}" | sudo tee -a ${target};
		fi
		echo ${bashrc_cmd} | sudo tee -a ${target};
	fi
	
  	#eval $__resultvar="'${c_number}'";
}

######
# Install matlab_execs and local MATLAB
mefs=${MATLAB_EXEC_PATH}
matlab_test=$(ls ${mefs} 2> /dev/null | wc -l);
if [[ ${matlab_test} == 0 ]];then
	echo "matlab_execs not found. Attempting to install now..."
	if [[ ! -f ${mefs} ]];then
		echo "matlab_execs directory not found; attempting to clone from github;"
		echo "Repository: https://github.com/andersonion/matlab_execs_for_SAMBA.git"
		cd ${SAMBA_APPS_DIR};
		git clone https://github.com/andersonion/matlab_execs_for_SAMBA.git
	fi

fi 

matlab_test=$(ls ${mefs} 2> /dev/null | wc -l);
if [[ ${matlab_test} == 0 ]];then
	echo "matlab_execs folder has NOT been installed;"
	echo "Please check your permissions, etc, and try again."
else
	echo "matlab_execs folder is installed."
	M2P=${MATLAB_2015b_PATH}
	m2015b_test=$(ls ${M2P} 2> /dev/null | wc -l);
	if [[ ${m2015b_test} == 0 ]];then
		echo "MATLAB2015b not found. Attempting to install now..."
		bash ${mefs}/install_matlab_for_SAMBA
	fi
fi

m2015b_test=$(ls ${M2P} 2> /dev/null | wc -l);
if [[ ${m2015b_test} == 0 ]];then
	echo "MATLAB2015b has NOT been installed;"
	echo "Please check your permissions, etc, and try again."
else
	echo "MATLAB2015b is instslled."
fi


######
## Install perlbrew

pb_test=$(which perlbrew  2> /dev/null | wc -l);

src_file=${SAD}/perl5/etc/bashrc;

if [[ ${pb_test} == 0 ]];then
	if [[ ! -f ${src_file} ]];then
		export PERLBREW_ROOT=${SAD}/perl5;
		curl -L http://install.perlbrew.pl | bash 1> /dev/null;
	fi
fi

if [[ -f ${src_file} ]];then
	src_file=$(ls ${src_file});
	src_cmd="source ${src_file}";
	msg="Adding local version of perlbrew to";
	comment="Adding local version of perlbrew:"
	append_startup_script "${msg}" "${src_cmd}" "${comment}"
	${src_cmd};
else
	echo "Cannot find ${src_file}";
	echo "Perlbrew installation has appeared to have failed." && exit 1
fi
pb_test=$(which perlbrew  2> /dev/null | wc -l);
if [[ ${pb_test} -gt 0 ]];then
	echo "Perlbrew has been successfully installed."
else
	echo "Perlbrew has NOT been installed;";
	echo "Rerunning in debug mode to aid in troubleshooting..."
	export PERLBREW_ROOT=${SAD}/perl5;
	curl -L http://install.perlbrew.pl | bash 1> /dev/null;
fi	
######

list_test=$(perlbrew list 2>/dev/null | wc -l);

if [[ ${list_test} != 0 ]];then
	eval perlbrew use perl-5.16.3 ${db};
	list_test=$(perlbrew list | grep "\-5.16.3" | wc -l);
fi

if ((${list_test}));then
	echo "Perl-5.16.3 has been successfully installed."
else
	echo "Perl-5.16.3 is not installed.";
	echo "Attempting to install it now..."
	eval perlbrew --notest install  perl-5.16.3 ${db}
	eval perlbrew use perl-5.16.3 ${db};
	list_test=$(perlbrew list | grep "\-5.16.3" | wc -l);
	if ((${list_test}));then
		echo "Perl-5.16.3 has been successfully installed.";
	else
		echo "Perl-5.16.3 has NOT been installed;";
		echo "Rerunning in debug mode to aid in troubleshooting..."
		perlbrew --notest install  perl-5.16.3
	fi	
fi

# Do we actually use perl-5.16.3@SAMBA??
eval perlbrew lib create perl-5.16.3@SAMBA ${db}

# Test to see which 'use' command we want.
#perlbrew use perl-5.16.3@SAMBA
perlbrew use perl-5.16.3

eval perlbrew install-cpanm ${db}

carton_test=$(which carton  2> /dev/null | wc -l);
if [[ ${carton_test} -gt 0 ]];then
	echo "Carton is found and ready to do work."
else
	echo "Carton not found. Attempting to install now..."
	if [[ ! -f ${SAMBA_APPS_DIR}/carton ]];then
		echo "Carton directory not found; attempting to clone from github;"
		echo "Repository: https://github.com/perl-carton/carton.git"
		cd ${SAMBA_APPS_DIR};
		git clone https://github.com/perl-carton/carton.git
		touch cpanfile
		touch cpanfile.snapshot
	fi
	eval cpanm -f Carton ${db}
	#cpanm install Carton;
	
	
	carton_test=$(which carton  2> /dev/null | wc -l);
	if [[ ${carton_test} -gt 0 ]];then
		echo "Carton is found and ready to do work."
	else
		echo "Carton has not been successfully installed;"
		echo "Rerunning in debug mode to aid in troubleshooting..."
	fi
fi


cd ${SAMBA_APPS_DIR}/SAMBA
carton install

# Add bashrc_for_SAMBA to appropriate file.
msg="Adding source command for bashrc_for_SAMBA to";
src_cmd="source ${brc_SAMBA}"
comment="Adding source command for bashrc_for_SAMBA:"
append_startup_script "${msg}" "${src_cmd}" "${comment}" 1
