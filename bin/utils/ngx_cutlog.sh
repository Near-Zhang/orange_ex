#!/bin/bash
. /etc/profile

log_path=/usr/local/orange/logs/
oldlog_base=/usr/local/orange/logs/oldlogs/
time=$( date +"%F" -d -1day )
Y=$( echo $time|cut -d'-' -f1 )
M=$( echo $time|cut -d'-' -f2 )
log_file=( access.log error.log api_access.log api_error.log )
oldlog_path=${oldlog_base}$Y/$M/

[ -d $oldlog_path ] || mkdir -p $oldlog_path
for f in $log_file
do
	if [ -s ${log_path}${f} ];then 
    	cp -a ${log_path}${f} ${oldlog_path}$( echo $f|cut -d'.' -f1 )-${time}.log  
    	> ${log_path}${f}
		cd $oldlog_path
    	tar -czf ./$( echo $f|cut -d'.' -f1 )-${time}.log.tar.gz ./$( echo $f|cut -d'.' -f1 )-${time}.log --remove-files
	fi
done
find $oldlog_base -mtime +180 -exec rm -f {} \;
