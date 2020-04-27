#!/bin/bash

if [[ "$UID" != 0 ]]; then
	echo "The script should be launched as root"
	exit
fi

function delete {
	ip netns pids "$1" | xargs -I "{}" kill "{}"
	if [[ -n $(ip netns pids "$1") ]]; then
		sleep 0.5
		ip netns pids "$1" | xargs -I "{}" kill -9 "{}"
	fi
	ip netns delete "$1"
}

for i in $(ip netns | cut -d " " -f 1); do
	echo "deleting $i..."
	delete "$i"
done

for f in /etc/netns/* ; do
	unlink "$f"
done

rm -rf /etc/netns/
rm /etc/radvd.conf

#mv /etc/resolv.conf.bak /etc/resolv.conf
