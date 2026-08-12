#!/usr/bin/bash

HOST=$(hostname)
HOST_IP=$(ip route get 1.1.1.1 | awk '{print $7; exit}' || hostname -I)

NODE_DONOR=""
CLUSTER_NAME="cluster_1"
SST_DONOR=""

while getopts "c:d:s:h" opt; do
  case ${opt} in
    h ) 
      echo "Usage: $0 [-h help] [-c cluster_name] [-d donor_ip] [-s sst_donor]" >&2
      exit 0
      ;;
    c ) 
      CLUSTER_NAME=$OPTARG
      ;;
    d ) 
      NODE_DONOR=$OPTARG
      ;;
    s ) 
      SST_DONOR=$OPTARG
      ;;
    \? ) 
      echo "Invalid option"
      exit 1
      ;;
  esac
done

if [[ -z "${NODE_DONOR:-}" ]]; then
	echo "donor argument matches this node's IP ($HOST_IP), self-bootstrap"
	NODE_DONOR="$HOST_IP"
fi

is_installed() {
	dpkg -s "$1" >/dev/null 2>&1 && echo true || echo false;
}

write_config_galera () {
	local is_galera_installed=$(is_installed galera-4)
	local is_mariadb_installed=$(is_installed mariadb-server)

	echo "checking status of galera: $is_galera_installed and mariadb: $is_mariadb_installed ..."
	if [[ $is_galera_installed && $is_mariadb_installed ]]; then
		echo "writing galera cluster configuration on $HOST ..."

		local tmpl="/home/ubuntu/galera.cnf.tmpl"
		local dest="/etc/mysql/mariadb.conf.d/60-galera.cnf"
		local cluster_name=$1
		local cluster_address=$2
		local sst_donor=${3:-}

		if [[ -z "$cluster_name" || -z "$cluster_address" ]]; then
			echo "error: cluster_name or cluster_address is empty, aborting"
			exit 1;
		fi

		sed -e "s|{{CLUSTER_NAME}}|$cluster_name|g" -e "s|{{CLUSTER_ADDRESS}}|$cluster_address|g" -e "s|{{HOST_NAME}}|$HOST|g" -e "s|{{SST_DONOR}}|$sst_donor|g" -e "s|{{HOST_ADDRESS}}|$HOST_IP|g" "$tmpl" | sudo tee "$dest" > /dev/null

		echo "finished write galera cluster configuration"
	else
		echo "skipping write galera cluster configuration, mariadb-server or galera-4 is not installed"
		exit 1;
	fi
}

# ============================================================================== #

if [[ $NODE_DONOR != $HOST_IP ]]; then
	write_config_galera "$CLUSTER_NAME" "$NODE_DONOR,$HOST_IP" "$([[ -n "$SST_DONOR" ]] && echo "$SST_DONOR")"
else
	write_config_galera "$CLUSTER_NAME" "$HOST_IP"
fi