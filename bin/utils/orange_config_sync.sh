#!/bin/bash
slave_list=(
	10.19.33.251
	10.13.174.6
	10.13.132.240
	10.23.175.132
	10.23.173.108
)

orange reload
for i in ${slave_list[*]}
do
	rsync -avz --delete -e "ssh" /usr/local/orange/conf $i:/usr/local/orange/
	ssh $i ". /etc/profile;orange reload"
done
