#!/bin/bash
. /etc/profile

log_path=/usr/local/orange/logs/ 
bin=/usr/local/bin/orange
time=$( date +"%F" -d -1day )
Y=$( echo $time|cut -d'-' -f1 )
M=$( echo $time|cut -d'-' -f2 )
log_file=( access.log )
oldlog_path=${log_path}oldlogs/$Y/$M/

[ -d $oldlog_path ] || mkdir -p $oldlog_path
for f in $log_file
do
	if [ -s ${log_path}${f} ];then 
    		mv ${log_path}${f} ${oldlog_path}access-${time}.log  
    		$bin reload >/dev/null 2>&1
		cd $oldlog_path
    		tar -czf ./access-${time}.log.tar.gz ./access-${time}.log --remove-files
	fi
done
find $oldlog_path -mtime +60 -exec rm -f {} \; 

