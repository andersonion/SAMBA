#!/bin/bash
# simple script to run and svn update directories on each host

for host in `ls pipeline_settings/engine_deps/engine_*_dependencies | cut -d '_' -f4 | sort -u`
do
    echo " --- updating host $host ---"
    ssh -o ConnectTimeout=1 $host /opt/subversion/bin/svn update /Volumes/workstation_home/Software 2>&1 > logs\svn_update_${host}.log &
done

