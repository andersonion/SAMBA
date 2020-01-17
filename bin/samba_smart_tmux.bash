#!/usr/bin/env bash
# tries to smartly tmux launch samba headfiles in your current directory.
# REQUIRES optional_suffix in your headfile!!!
#
# Smart as in, each headfile is launched in its own tmux window, named after optional_suffix
# Only if it is not currently running, and
# only if the results headfile is not created yet.
#
# Part of larger helper bits which will try to keep SAMBA runing until successful
# Note, this can waste a great deal of CPU time when things go bad, so use with caution.
# 
# saves live output to "samba_logs/optional_suffix.log" 
# can watch live output with tmux attach -t optional_suffix


# If no reservation keep empty string.
# Better idea, Let this be better handled elsewhere
# reservation_name=jjc29_119
# reservation_name="";
if [ ! -d samba_logs ];then
    mkdir samba_logs;fi;
for shf in *.headfile; 
do 
    # for the test sets the vbmsuffix was both in the file AND in the filename.
    #vbmsuffix=$(echo ${hf%.*}|cut -d '_' -f2);
    vbmsuffix=$(grep '^optional_suffix=' $shf|tail -n1|cut -d '=' -f2);
    if [ -z "$vbmsuffix" ];then
	echo "DIDNT LAUNCH $shf BECAUSE NO optional_suffix FOUND..";
	continue;
    fi;
    # result pattern
    rp="$BIGGUS_DISKUS/VBM*$vbmsuffix-results/*headfile";
    if [ $(tmux list-session 2> /dev/null |grep -c $vbmsuffix: 2>/dev/null) -le 0 ];then
	# headfile path or empty when the file doesnt exist.
	# Now that I look at things, might be able to do our ls check, 
	# and capture status with $?, and test status
	# (instead of running ls twice).
	hfp=$(ls $rp 2> /dev/null);
	#if [ ! -f "$hfp" ];then
	# If we didn't find a file using above ls command 
	# OR, the one found is Older, launch.
	if [ -z "$hfp" -o \( "$hfp" -ot $shf \) ]; then
	    echo "Launching in 2 seconds ... ";
	    echo tmux new-session -d -s $vbmsuffix -- "\" source ~/.bashrc && SAMBA_startup $PWD/$shf 2>&1 | tee -a samba_logs/$vbmsuffix.log\"";
	    sleep 2; tmux new-session -d -s $vbmsuffix -- " source ~/.bashrc && SAMBA_startup $PWD/$shf 2>&1 | tee -a samba_logs/$vbmsuffix.log";
	    
	else 
	    echo "Dat:$vbmsuffix complete $hfp";
	fi;
    else
	echo "Dat:$vbmsuffix in progress";
    fi;
done
