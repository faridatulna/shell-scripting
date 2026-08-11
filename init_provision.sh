#!/usr/bin/bash

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
  multipass transfer provision_mariadb_v2.sh galera.cnf.tmpl "$instance_name":/home/ubuntu/
}

exec_provision_script() {
  local instance_name=$1
  local cluster_name=$2
  local donor_ip=${3:-}
  local sst_donor=${4:-}
  # Execute the provisioning script on the new instance
  echo "Executing the provisioning script on the $HOST_NAME instance with cluster_name=$CLUSTER_NAME $([[ -n "$DONOR_IP" ]] && echo "donor_ip=$DONOR_IP") $([[ -n "$SST_DONOR" ]] && echo "sst_donor=$SST_DONOR")..."
  multipass exec "$HOST_NAME" -- bash -c "chmod +x /home/ubuntu/provision_mariadb_v2.sh && /home/ubuntu/provision_mariadb_v2.sh -c $CLUSTER_NAME $([[ -n "$DONOR_IP" ]] && echo "-d $DONOR_IP") $([[ -n "$SST_DONOR" ]] && echo "-s $SST_DONOR")"
}

# ======================================================================================================= #

echo "Provisioning 3 mariadb nodes with cluster_name=$CLUSTER_NAME ..."

for i in {1..3}; do
  HOST_NAME="mariadb-node-$i"
  DONOR_IP=""
  SST_DONOR=""
  if [[ $i -eq 1 ]]; then
    # First node, no donor
    DONOR_IP=""
    SST_DONOR=""
  elif [[ $i -eq 2 ]]; then
    # Second node, first node is donor
    DONOR_IP="$(multipass exec mariadb-node-1 -- sh -c 'ip route get 1.1.1.1 | awk "{print \$7; exit}" || hostname -I')"
    SST_DONOR=""
  else
    # Third node, second node is donor and SST donor
    DONOR_IP="$(multipass exec mariadb-node-2 -- sh -c 'ip route get 1.1.1.1 | awk "{print \$7; exit}" || hostname -I')"
    SST_DONOR="mariadb-node-2"
  fi

  create_instance "$HOST_NAME"
  transfer_provision_script "$HOST_NAME"
  exec_provision_script "$HOST_NAME" "$CLUSTER_NAME" "$DONOR_IP" "$SST_DONOR"
done
