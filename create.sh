#!/bin/bash

# Displays an error message
# $1 : the message to display
function error {
	echo "[ERROR] $1"
}

# Displays an alert message
# $1 : the message to display
function alert {
	echo "[ALERT] $1"
}

# Displays an info message
# $1 : the message to display
function info {
	echo "[INFO] $1"
}

# Execute a script on a node
# $1 : the node name
# $2 : the script to execute
function node_exec {
	local filename="$CONFIG_DIR/$2"
	if [[ -x "$filename" ]]; then
		ip netns exec "$1" "$filename"
	else
		alert "No executable $filename found"
	fi
}

# Boot a node by executing all the script in the folder startup/{node}/
# $1 : the node name
function node_boot {
	info "Booting $1"
	DIR=$(cd $(dirname "$0") && pwd) # Get the path
	for file in "$DIR"/startup/"$1"/*; do
		[ -f "$file" ] || continue # If file do not exist = the dir is empty
		if [[ -x "$file" ]]; then
			ip netns exec $1 $file
		else
			ip netns exec $1 bash $file
		fi
	done
}

# Create a new namespace with name
# $1 : namespace name
function mk_node {
	info "Creating node $1"
	ip netns add "$1"
	ip netns exec "$1" ip link set dev lo up
	IFACE[$1]=0
	LAN[$1]=0
	mkdir -p "${CONFIG_DIR}/${1}"
	mkdir -p "${STARTUP_DIR}/${1}"
	mkdir -p "${TMP_DIR}/${1}"
	$(cd "/etc/netns" && ln -s "/home/thomas/networking_lab/ipv6_network/${CONFIG_DIR}/${1}" "$1")
}

# Create a new pair of interfaces
# $1 : name of interface1
# $2 : name of interface2
function mk_link {
	ip link add "$1" type veth peer name "$2"
}

# Move an interface to a namespace
# $1 : the name of the interface to move
# $2 : the name of the namespace
function mv_to_ns {
	ip link set "$1" netns "$2"
	ip netns exec "$2" ip link set dev "$1" up
}

# Return the next interface name available for a node. Return value in global variable $__ret
# Format : [node]-eth(n)
# $1 : name of the node
function next_iface {
	if [[ -z ${IFACE[$1]+isset} ]]; then
		mk_node "$1"
	fi
	
	__ret="${1}-eth${IFACE[$1]}"
	let "IFACE[$1] += 1"
}

# Return the next LAN name available for a node. Return value in global variable $__ret
# Format : [node]-lan(n)
# $1 : name of the node
function next_LAN {
	if [[ -z ${LAN[$1]+isset} ]]; then
		mk_node "$1"
	fi
	
	__ret="${1}-lan${LAN[$1]}"
	let "LAN[$1] += 1"
}

# Create a link between two nodes
# $1 : Name of one of the two node
# $2 : Name of the other node
function add_link {
	next_iface "$1"
	local iface1="$__ret"
	next_iface "$2"
	local iface2="$__ret"
	info "Link $iface1 ($1) $iface2 ($2) created"
	mk_link "$iface1" "$iface2"
	mv_to_ns "$iface1" "$1"
	mv_to_ns "$iface2" "$2"
}

# Attach an interface to a LAN
# $1 the node that has the LAN
# $2 the name of the LAN
# $3 the node to attach
function attach_to_LAN {
	next_iface "$3"
	local src="$__ret"
	local dst="br-${1}-${3}"

	info "Adding $3 ($src) in LAN $2 via $dst ($1)"

	mk_link "$src" "$dst"	
	mv_to_ns "$src" "$3"
	mv_to_ns "$dst" "$1"

	ip netns exec "$1" ip link set dev "$dst" master "$2"
}

# Create a bridge on a node
# $1 : name of the node
# $2 : the name of the bridge
function mk_bridge {
	ip netns exec "$1" ip link add dev "$2" type bridge
	ip netns exec "$1" ip link set dev "$2" up
}

# Create a LAN on a node and add the specified nodes in it
# $1 : Node on which the LAN will be created
# $2+ : the nodes to add in the LAN
function mk_LAN {
	next_LAN "$1"
	local bridge="$__ret"
	mk_bridge "$1" "$bridge"
	local node="$1"
	shift
	for i in $@; do
		attach_to_LAN "$node" "$bridge" "$i"
	done
}

function main {

	# Create the /etc/netns folder that will replace
	# the default etc folder for the namspaces
	mkdir -p /etc/netns

	# Remove the old resolv.conf and replace it by a new one
#	mv /etc/resolv.conf /etc/resolv.conf.bak
#	touch /etc/resolv.conf

	# Unexisting files
	touch /etc/radvd.conf
	
	# Global variables !
	declare -A IFACE
	declare -A LAN

	CONFIG_DIR="config"
	STARTUP_DIR="startup"
	TMP_DIR="tmp"

	STARTUP="startup"

	source "topology"

	if [[ "$UID" != 0 ]]; then
		error "The script should be launched as root"
		exit
	fi

	mk_topo

	for i in ${!IFACE[@]}; do
		# Only execute the file {node}_startup
		#node_exec "$i" "${i}_${STARTUP}"
		# Execute all file in startup/{node}/ folder
		node_boot "$i"
	done
}

main $@
