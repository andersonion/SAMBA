#! /bin/env bash
package_dir=$1
local_MATLAB=$2;
SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )";

if [[ xx == "x${package_dir}x" ]];then
   package_dir=${SCRIPTPATH};
fi

if [[ xx == "x${local_MATLAB}x" ]];then
   local_MATLAB=${SCRIPTPATH};
fi


if [[ ! -d ${package_dir} ]];then
    mkdir -m 775 ${package_dir};
fi

if [[ ! -d ${local_MATLAB} ]];then
    mkdir -m 775 ${local_MATLAB};
fi

installer="${package_dir}/MCR_R2015b_glnxa64_installer.zip";
if [[ ! -f $installer ]];then
 wget -P ${package_dir} "http://ssd.mathworks.com/supportfiles/downloads/R2015b/deployment_files/R2015b/installers/glnxa64/MCR_R2015b_glnxa64_installer.zip";
fi

# Unzip to temp folder
if [[ ! -d ${package_dir}/temp ]];then
    mkdir -m 775 ${package_dir}/temp;
fi

if [[ ! -d ${package_dir}/temp/bin ]];then
unzip -d ${package_dir}/temp ${installer};
fi
# Non-interactive install to local directory
${package_dir}/temp/install -mode silent -agreeToLicense yes -destinationFolder ${local_MATLAB}

#
# Check for success
# cleanup temp folder
#
#
