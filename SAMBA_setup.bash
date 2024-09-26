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
echo "perlbrew test = ${pb_test}";
echo "if perlbrew test is greater than 0, then you have been successful!"
######

list_test=$(perlbrew list 2>/dev/null | wc -l);
echo "list_test = x${list_test}x"
if [[ ${list_test} != 0 ]];then
	list_test=$(perlbrew list | grep -5.16.3 | wc -l);
	echo "perl-5.16.3_test = ${list_test}";
fi

if ((! ${list_test}));then
	perlbrew --notest install  perl-5.16.3
fi
perlbrew lib create perl-5.16.3@SAMBA
perlbrew use perl-5.16.3

perlbrew install-cpanm


carton_test=$(which carton  2> /dev/null | wc -l);

echo "carton_test = x${carton_test}x"
if [[ ${carton_test} != 0 ]];then
	cpanm install Carton;
fi
carton_test=$(which carton  2> /dev/null | wc -l);
echo "carton_test = x${carton_test}x"

######
if ((0));then
carton_test=$(which carton  2> /dev/null | wc -l);

src_file=${SAD}/perl5/etc/bashrc;

if [[ ${carton_test} == 0 ]];then
	cd ${SAMBA_APPS_DIR};
	git clone https://github.com/perl-carton/carton.git
	touch cpanfile
	touch cpanfile.snapshot
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
echo "perlbrew test = ${pb_test}";
echo "if perlbrew test is greater than 0, then you have been successful!"


fi