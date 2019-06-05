SAMBA_dir=$PWD; # pwd for now
old_perl_path='\/usr\/local\/pipeline-link\/perl';
new_perl_path=$(which perl);
new_perl_path=${new_perl_path//\//\\\/}; # Protect the slashes

for perl_script in $(ls ${SAMBA_dir}/*.pl);do
echo "Attempting to fix perl path in: ${perl_script}";
   perl -pi -e "s/\#\!${old_perl_path}/\#\!${new_perl_path}/g"  ${perl_script};
done

for perl_mod in $(ls ${SAMBA_dir}/*.pm);do
echo "Attempting to fix perl path in: ${perl_mod}";
   perl -pi -e "s/\#\!${old_perl_path}/\#\!${new_perl_path}/g"  ${perl_mod};
done
