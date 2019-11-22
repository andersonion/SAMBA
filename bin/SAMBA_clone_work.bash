#!/bin/bash
# This is a prototype, but looks like it'll be fully functional.
# Just have to expose the suffix and base directory settings outside. 

if [ -z "$1" ];then
    echo "Plese specify old vbm folder";
    exit 1;
fi;
vbm_dir="$1";
if [ ! -d $vbm_dir ];then
    if [ -d $vbm_dir-work ];then
	vbm_dir="$vbm_dir-work";
    else
	echo "Missing dir $vbm_dir";
    fi;
fi;
if [ -z "$2" ];then
    echo "Please specify the new suffix we're \"cloning\" to";
    exit 1; 
fi;
new_suf="_$2";
if [ -z "$3" ];then
    old_suf="";
#    exit 1;
else
    old_suf="_$3";
fi;


#to UPDATE old samba work (or to branch off and do other stuff)
# this is especially helpful when there are sweeping untested/uncharacterized code changes.
# note, this doent change biggus diskus from one place to another!
dir_base=$(echo ${vbm_dir%-*}|sed "s/$old_suf//");
for ft in inputs work results; do 
    if [ ! -d ${dir_base}$new_suf-$ft ];then
	echo "Cloning ${dir_base}$old_suf-$ft  to  ${dir_base}$new_suf-$ft";
	mkdir ${dir_base}$new_suf-$ft
	lndir ${dir_base}$old_suf-$ft ${dir_base}$new_suf-$ft
    fi;
done
# this echo is a safety switch, set to empty string or use unset to run work.
echo='';
#echo='echo';
# patch the hf in our inputs moving the link out of the way.
hf=$(ls ${dir_base}$new_suf-inputs/current_inputs.headfile);
if [ -z "$hf" ];then
    echo "hf update didnt find inputs headfile";
    exit 1; 
fi;
found_suf=$(grep -c "optional_suffix" $hf);
if [ -L $hf ] ;then 
    $echo mv $hf ${hf%.*}.bak.hf;
    $echo cp -p ${hf%.*}.bak.hf $hf; 
    if [ $found_suf -ge 1 ];then
	$echo sed -i'' 's:'"$old_suf:$new_suf"':g' $hf
    else 
	echo "optional_suffix=$new_suf >>  $hf"
    fi;
fi;
in_hf=$hf;
# patch all the hf's in our work folder
for hf in $(find ${dir_base}$new_suf-work -iname "*.headfile" ) ; do
    if [ -L $hf ] ;then 
	$echo mv $hf ${hf%.*}.bak.hf;
	$echo cp -p ${hf%.*}.bak.hf $hf; 
	if [ $found_suf -ge 1 ];then
	    $echo sed -i'' 's:'"$old_suf:$new_suf"':g' $hf
	else 
	    echo "optional_suffix=$new_suf >>  $hf"
	fi;
    fi;
done

echo SAMBA_startup $in_hf
