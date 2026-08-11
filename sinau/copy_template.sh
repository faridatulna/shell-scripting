#!/usr/bin/bash

HOST=testing
HOST_IP=1.1.1.1

tmpl="/home/dicoding/Dicoding/INFRA/Multipass/scripts/galera.cnf.tmpl"
dest="/home/dicoding/Dicoding/INFRA/Multipass/scripts/galera.conf"


write_in_file() {
	sed -e "s|{{CLUSTER_NAME}}|$HOST|g" -e "s|{{CLUSTER_ADDRESS}}|$HOST_IP|g" -e "s|{{HOST_NAME}}|$HOST|g" -e "s|{{HOST_ADDRESS}}|$HOST_IP|g" "$tmpl"
}	

write_in_file  | tee "$dest" > /dev/null

