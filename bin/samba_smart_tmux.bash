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
limit=$1;
confirm=$2;
max_try=$3;

if [ -z "$limit" ];then
    # to make code easier, limit will be 100 by default, effectively no limit
    limit=100;
fi;
if [ -z "$confirm" ];then
    confirm=1;
fi;
if [ -z "$max_try" ]; then
    max_try=10;
fi;

if [ ! -d samba_logs ];then
    mkdir samba_logs;fi;

for shf in $(ls -tr *.headfile);
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
        # check limit; skip if nee dbe
        if [ $limit -le 0 ];then
            #echo "Limit reached, skipping $vbmsuffix";
            continue;
        fi;
        # headfile path or empty when the file doesnt exist.
        # Now that I look at things, might be able to do our ls check,
        # and capture status with $?, and test status
        # (instead of running ls twice).
        hfp=$(ls -t $rp 2> /dev/null |head -n1);
        #if [ ! -f "$hfp" ];then
        # If we didn't find a file using above ls command
        # OR, the one found is Older, launch.
        if [ -z "$hfp" -o \( "$hfp" -ot $shf \) ]; then
            st_count=$(grep -ci 'start work' samba_logs/$vbmsuffix.log 2> /dev/null || echo 0);
            if [ $st_count -gt $max_try ];then
                if [ ! -d max_fail ];then mkdir max_fail; fi;
                mv $shf max_fail/$(basename $shf); echo "too many failures for $vbmsuffix";
                continue;
            fi;
            echo tmux new-session -d -s $vbmsuffix -- "\" source ~/.bashrc && SAMBA_startup $PWD/$shf 2>&1 | tee -a samba_logs/$vbmsuffix.log\"";
            if [ $confirm -eq 1 ];then
                read -p "Start ${vbmsuffix}: $(basename $shf)(yN)" start_now
            else
                start_now=y;
            fi;
            if [ "$start_now" == y -o "$start_now" == Y ];then
                echo "Launching in 2 seconds ... ";
                sleep 2; tmux new-session -d -s $vbmsuffix -- " source ~/.bashrc && SAMBA_startup $PWD/$shf 2>&1 | tee -a samba_logs/$vbmsuffix.log";
                let limit=$limit-1;
            fi;
        else
            echo "Dat:$vbmsuffix complete $hfp";
        fi;
    else
        let limit=$limit-1;
        echo "Dat:$vbmsuffix in progress";
    fi;
done
