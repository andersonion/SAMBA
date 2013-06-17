#!/bin/bash

for folder in `ls -d */` 
do 
    cd $folder 
    svn propset svn:externals -F .svn.externals . 
    cd ..
done
svn propset svn:externals -F .svn.externals . 
svn update