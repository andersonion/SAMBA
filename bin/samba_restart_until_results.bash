#!/usr/bin/env bash


limit=$1;
max_try=$2;
if [ -z "$limit" ];then
  # to make this easier, limit will be 100 by default, effectively no limit
  limit=100;
fi;
if [ -z "$max_try" ]; then
    max_try=10;
fi;


# Uses samba tmux starter to run until we've got results headfiles, which indicates we finished.
# results headfile pattern
rp="$BIGGUS_DISKUS/VBM*results/*headfile";

function vbmsuffix_regex () {
# filter for results headfiles to only get the ones in the current directory.
for hf in *.headfile; do grep '^optional_suffix=' $hf|tail -n1|cut -d '=' -f2;done |sort -u > ~/.SAMBA_suffix.tmp
suf_count=$(wc -l ~/.SAMBA_suffix.tmp|awk '{print $1}');
vbmsuf_regex=$(cat ~/.SAMBA_suffix.tmp|xargs |sed 's/ /|/g');
rm ~/.SAMBA_suffix.tmp;

hf_count=$(ls *headfile |wc -l);
if [ "$hf_count" -ne "$suf_count" ];then
    echo "ERROR: Optional suffix required in every headfile, and should be unique!";
    exit 1;
fi;
echo "$vbmsuf_regex";
return;
}

# use function to get regex of vbmsuffixes
vbmsuf_regex="$(vbmsuffix_regex)";

echo "Persistent start mode activating now.";
echo "$limit SAMBA runs(at most) scheduling and interfering with one another."
echo "$max_try attempts before a headfile will be moved to max_fail directory";
echo "";
echo " usage $0 limit max_try";
echo " continuing in 8 seconds";
sleep 8;
# I'll suffer this particular abonimation of emaily
declare -x SAMBA_MAIL_USERS=$USER@duke.edu,jjc29@duke.edu
# Start the smart launcher in the background, will pack any that are ready(after 300 second delay),
while [ $(ls $rp|grep -v last |grep -ci "$vbmsuf_regex" ) -lt $(ls *headfile |wc -l) ];
do  samba_smart_tmux $limit 0 $max_try;
    # samba_smart_tmux may move a headfile out of the way, that requires we update the suffix regex
    # use function to get regex of vbmsuffixes
    vbmsuf_regex="$(vbmsuffix_regex)";
    sleep 120;
    samba_pack_ready;
done &

# While the smart launcher loop is active, wait 2 minutes,(spaming this terminal with timestamp)
while [ $(jobs|wc -l ) -gt 0 ];
do  echo -n "Samba auto-restart samba_smart_tmux active: "; date ;
    echo "warning: canceling this terminal doesnt stop the auto-restarter....";
    echo " you'll have to hunt through all the bash processes you have running to do that";
    echo "hint:   ps -ef|grep bash|grep samba|grep $USER";
    sleep 120;
done
