#!/bin/bash

if [[ "$UID" != 0 ]]; then
		echo "The script should be launched as root"
		exit
fi

ip netns exec $1 bash
