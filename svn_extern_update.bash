#!/bin/bash



# for folder in `ls -d */` 
# do 
#     cd $folder 
#     svn propset svn:externals -F .svn.externals . 
#     cd ..
# done
start=`pwd`
for location in `find . -iname ".svn.externals"`
do 
    dir=`dirname $location`
    echo  -n "svn propset svn:externals -F .svn.externals $dir ... "
    cd $dir
    svn propset svn:externals -F .svn.externals . 
    cd $start
done
svn update