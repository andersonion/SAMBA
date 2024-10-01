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
		echo "Carton has not been successfully instaleld;"
		echo "Rerunning in debug mode to aid in troubleshooting..."
	fi
fi


cd ${SAMBA_APPS_DIR}/SAMBA
carton install
