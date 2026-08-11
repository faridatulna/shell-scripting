#!/usr/bin/bash

HOST=$(hostname)
HOST_IP=$(hostname -I)
CLUSTER_NAME=cluster_1

# get donor node from command line argument, if not provided, use HOST_IP -> current node as donor
if [[ -z "${1:-}" ]]; then
	read -r -p "no donor argument given, this node will bootstrap a NEW cluster using itself ($HOST_IP) as donor. Continue? [y/N] " confirm
	if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
		echo "aborted by user"
		exit 1
	fi
	NODE_DONOR="$HOST_IP"
elif [[ "$1" == "$HOST_IP" ]]; then
	echo "donor argument matches this node's IP ($HOST_IP), self-bootstrap"
	NODE_DONOR="$HOST_IP"
fi

set -euo pipefail

is_installed() {
	dpkg -s "$1" >/dev/null 2>&1 && echo true || echo false;
}

is_active() {
	sudo systemctl is-active --quiet "$1" && echo true || echo false
}

install_package() {
   local package_name=$1
   if ! dpkg -s "$package_name" >/dev/null 2>&1; then
	  echo "installing $package_name ..."
	  sudo apt-get update && sudo apt-get install -y "$package_name"
	  echo "$package_name installed"
   else
	  echo "$package_name already installed, skipping"
   fi
}

stop_mariadb() {
   if $(is_active mariadb); then
      echo "stopping mariadb ..."
      sudo systemctl stop mariadb
      echo "mariadb stopped"
   else
      echo "mariadb already stopped ..."
   fi
}

start_mariadb() {
   if $(is_active mariadb); then
      echo "mariadb already active ..."
   else
      echo "activating mariadb ..."
      sudo systemctl start mariadb
      echo "mariadb activated"
   fi
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

download_sampledb() {
	local sampledb_file="./test_db-1.0.7.tar.gz"

	if [[ -f "$sampledb_file" ]]; then
		echo "already have $sampledb_file, skipping download"
	else
		echo "downloading sample data ..."
		wget https://github.com/datacharmer/test_db/releases/download/v1.0.7/test_db-1.0.7.tar.gz
		echo "sample data downloaded"
	fi
}

extract_sampledb() {
	local sampledb_dir="test_db"
	local sampledb_file="./test_db-1.0.7.tar.gz"

	if [[ -e "$sampledb_dir" ]]; then
		echo "already have dir test_db, skipping extract"
	elif [[ -f "$sampledb_file" ]]; then
		echo "extracting sample data ..."
		tar -xzvf $sampledb_file
		echo "sample data extracted"
	fi

	if ! $(is_active mariadb); then
		start_mariadb
	fi

	if [[ $(is_active mariadb) && -f "$sampledb_dir/employees.sql" ]]; then

		local db_exists=$(sudo mariadb -N -e "SHOW DATABASES LIKE 'employees'" 2>/dev/null)
		if [[ -n "$db_exists" ]]; then
			echo "employees database already dumped, skipping"
		else
			echo "mariadb is active, dumping sampledb in $sampledb_dir/employees.sql ..."
			echo "change dir to $sampledb_dir and dump sampledb ..."
			cd "$sampledb_dir" && sudo mariadb < employees.sql
			echo "go back to previous dir ..."
			cd ..
			echo "sampledb dumped"
		fi
	else
		echo "mariadb is not active, skipping dump sampledb"
	fi
}

galera_new_cluster() {
	echo "create new galera cluster ..."
	sudo galera_new_cluster
	echo "galera is created"
}

# ======================================================================================================== #

echo "Provisioning on node $HOST ..."

# install mariadb
install_package mariadb-server

# install galera-4
install_package galera-4

# configuring node
echo "configuring node $HOST ..."

if [[ $NODE_DONOR != $HOST_IP ]]; then
	echo "donor node is $NODE_DONOR"
	stop_mariadb
	write_config_galera "$CLUSTER_NAME" "$NODE_DONOR,$HOST_IP"
	start_mariadb
else
	echo "donor node is current node $HOST_IP"
	download_sampledb
	extract_sampledb
	write_config_galera "$CLUSTER_NAME" "$HOST_IP"
	stop_mariadb
	galera_new_cluster
fi

# 1. install mariadb-server
# 2. install galera-4
# 3. on first node, download and extract sampledb, dump employees.sql, write galera config, create new galera cluster
# 4. on second node, write galera config, restart mariadb
# 5. on third node, write galera config, restart mariadb
# 6. on testing node, same as first node, just for testing purpose, different cluster
# 7. show journalctl -fu mariadb

# ./sh -> first node: galera cluster
# ./sh ip_donor
