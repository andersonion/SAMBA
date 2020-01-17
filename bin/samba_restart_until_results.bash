#!/usr/bin/env bash


# Uses samba tmux starter to run until we've got results headfiles, which indicates we finished.
# results headfile pattern
rp="$BIGGUS_DISKUS/VBM*results/*headfile";

# filter for results headfiles to only get the ones in the current directory.
for hf in *.headfile; do grep '^optional_suffix=' $hf|tail -n1|cut -d '=' -f2;done |sort -u > ~/.SAMBA_suffix.tmp
suf_count=$(wc -l ~/.SAMBA_suffix.tmp|awk '{print $1}');
vbmsuf_regex=$(cat ~/.SAMBA_suffix.tmp|xargs |sed 's/ /|/g');
rm ~/.SAMBA_suffix.tmp;
hf_count=$(ls *headfile |wc -l);
if [ "$hf_count" -ne "$suf_count" ];then
    echo "ERROR: Optional suffix required in every headfile, and should be unique!";
fi;

# Start the smart launcher in the background, will pack any that are ready(after 300 second delay), 
while [ $(ls $rp|grep -v last |grep -ci "$vbmsuf_regex" ) -lt $(ls *headfile |wc -l) ]; do samba_smart_tmux; sleep 300;samba_pack_ready;done &

# While the smart launcher loop is active, wait 2 minutes,(spaming this terminal with timestamp)
while [ $(jobs|wc -l ) -gt 0 ];do echo -n "Samba Restarts active: "; date ; sleep 120;done


