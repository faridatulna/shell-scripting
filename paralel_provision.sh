#!/usr/bin/bash

set -euox pipefail

CLUSTER_NAME=""

while getopts "hc:" opt; do
    case $opt in
        c) CLUSTER_NAME="$OPTARG" ;;
        h) echo "Usage: $0 [-c cluster_name] [-h help]" >&2
        exit 1 ;;
    esac
done

is_instance() {
    multipass info "$1" >/dev/null 2>&1 && echo true || echo false
}

is_installed() {
    multipass exec "$1" -- dpkg -s "$2" >/dev/null 2>&1 && echo true || echo false;
}

is_active() {
    multipass exec "$1" -- sudo systemctl is-active --quiet "$2" && echo true || echo false
}

# Create a new instance
create_instance() {
    local instance_name=$1
    if ! $(is_instance "$instance_name"); then
        echo "Creating new instance $instance_name ..."
        multipass launch 24.04 --name "$instance_name"
        echo "Instance $instance_name created"
    else
        echo "Instance $instance_name already exists, skipping creation"
    fi
}

transfer_provision_script() {
    local instance_name=$1
    # Transfer the provisioning scripts to the new instance
    echo "Transferring provisioning scripts to the new instance..."
    multipass transfer config_galera_mariadb.sh galera.cnf.tmpl "$instance_name":/home/ubuntu/
}

install_package() {
    local instance_name=$1
    local package_name=$2
    if ! $(is_installed "$instance_name" "$package_name"); then
        echo "installing $package_name ..."
        multipass exec "$instance_name" -- bash -c "sudo apt-get update && sudo apt-get install -y $package_name"
        echo "on $instance_name: $package_name installed"
    else
        echo "on $instance_name: $package_name already installed, skipping"
    fi
}

stop_mariadb() {
    local instance_name=$1
    if $(is_active "$instance_name" mariadb); then
        echo "stopping mariadb ..."
        multipass exec "$instance_name" -- sudo systemctl stop mariadb
        echo "mariadb stopped"
    else
        echo "mariadb already stopped ..."
    fi
}

start_mariadb() {
    local instance_name=$1
    if $(is_active "$instance_name" mariadb); then
        echo "mariadb already active ..."
    else
        echo "activating mariadb ..."
        multipass exec "$instance_name" -- sudo systemctl start mariadb
        echo "mariadb activated"
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
		tar -xzvf "$sampledb_file"
		echo "sample data extracted"
	fi

	if ! sudo systemctl is-active --quiet mariadb; then
		echo "activating mariadb ..."
        sudo systemctl start mariadb
        echo "mariadb activated"
	fi

	if sudo systemctl is-active --quiet mariadb && [[ -f "$sampledb_dir/employees.sql" ]]; then

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

# ======================================================================== #

HOSTNAME_PREFIX=$CLUSTER_NAME

# =========== 1. create 3 new instances ===========
nodes=()

pid1s=()  # Array to hold the PIDs of background processes
for i in {1..3}; do
  HOST_NAME="$HOSTNAME_PREFIX-node-$i"
  nodes+=("$HOST_NAME")

  create_instance "$HOST_NAME" &
  pid1s+=($!)
done
fail=0
# Wait for all background processes to complete
for pid in "${pid1s[@]}"; do
  echo "Waiting for process $pid to complete..."
  wait "$pid" || fail=1
done
((fail)) && echo "One or more instances failed to create" && exit 1

# =========== 2. transfer galera.cnf.tmpl to each instance ===========
pid2s=()  # Array to hold the PIDs of background processes
for node in "${nodes[@]}"; do
  transfer_provision_script "$node" &
  pid2s+=($!)
done
fail=0
# Wait for all background processes to complete
for pid in "${pid2s[@]}"; do
  echo "Waiting for process $pid to complete..."
  wait "$pid" || fail=1
done
((fail)) && echo "One or more provision scripts failed to transfer" && exit 1

# =========== 3. apt update & install mariadb to 3 instances ===========
pid3s=()  # Array to hold the PIDs of background processes
for node in "${nodes[@]}"; do
  install_package "$node" "mariadb-server" &
  pid3s+=($!)
done
fail=0
# Wait for all background processes to complete
for pid in "${pid3s[@]}"; do
  echo "Waiting for process $pid to complete..."
  wait "$pid" || fail=1
done
((fail)) && echo "One or more instances failed to install mariadb" && exit 1
# =========== 4. stop mariadb & configure galera & mariadb ============
#     - mariadb-node-1: cluster
#     - mariadb-node-2 & mariadb-node-3: node donor 1
pid4s=()  # Array to hold the PIDs of background processes

stop_mariadb ${nodes[0]} && multipass exec ${nodes[0]} -- bash -c "chmod +x /home/ubuntu/config_galera_mariadb.sh && /home/ubuntu/config_galera_mariadb.sh -c $CLUSTER_NAME" & pid4s+=($!)
stop_mariadb ${nodes[1]} && multipass exec ${nodes[1]} -- bash -c "chmod +x /home/ubuntu/config_galera_mariadb.sh && /home/ubuntu/config_galera_mariadb.sh -c $CLUSTER_NAME -d $(multipass info "${nodes[0]}" | grep IPv4|cut -d: -f2 | tr -d '[:blank:]')" & pid4s+=($!)
stop_mariadb ${nodes[2]} && multipass exec ${nodes[2]} -- bash -c "chmod +x /home/ubuntu/config_galera_mariadb.sh && /home/ubuntu/config_galera_mariadb.sh -c $CLUSTER_NAME -d $(multipass info "${nodes[1]}" | grep IPv4|cut -d: -f2 | tr -d '[:blank:]') -s "${nodes[1]}"" & pid4s+=($!)

fail=0
# Wait for all background processes to complete
for pid in "${pid4s[@]}"; do
  echo "Waiting for process $pid to complete..."
  wait "$pid" || fail=1
done
((fail)) && echo "One or more instances failed to configure galera" && exit 1
# =========== 5. mariadb-node-1: create new galera cluster ===========
multipass exec ${nodes[0]} -- bash -c "sudo galera_new_cluster"

# =========== 6. mariadb-node-2 & mariadb-node-3: start mariadb ===========

pid6s=()  # Array to hold the PIDs of background processes
start_mariadb ${nodes[1]} & pid6s+=($!)
start_mariadb ${nodes[2]} & pid6s+=($!)
fail=0
# Wait for all background processes to complete
for pid in "${pid6s[@]}"; do
    echo "Waiting for process $pid to complete..."
    wait "$pid" || fail=1
done
((fail)) && echo "One or more instances failed to start mariadb" && exit 1

# =========== 7. mariadb-node-1: download, extract & dump db sample ===========

multipass exec ${nodes[0]} -- bash -c "$(typeset -f download_sampledb); $(typeset -f extract_sampledb); download_sampledb; extract_sampledb"
