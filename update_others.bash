#!/bin/bash
# simple script to run and svn update directories on each host

hostlist=""
# get just names from the files
for file in `ls $WORKSTATION_HOME/pipeline_settings/engine_deps/engine_*_dependencies`
do 
    filename=`basename $file`
    hostlist="$hostlist `echo $filename | cut -d '_' -f2`"
done
# put names in a file one line at a time
for host in $hostlist ; do echo $host >>temphost.list; done 

# get only uniq elements from file list
for host in `cat temphost.list | sort -u`
do
    dir=`pwd`
    echo " --- updating host $host : $dir ---"
    ssh -o ConnectTimeout=1 $host /opt/subversion/bin/svn cleanup $dir 2>&1 > $WORKSTATION_HOME/logs/svn_update_${host}.log 
    ssh -o ConnectTimeout=1 $host /opt/subversion/bin/svn update $dir 2>&1 >> $WORKSTATION_HOME/logs/svn_update_${host}.log &
done
rm temphost.list
