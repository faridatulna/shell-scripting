#!/usr/bin/bash

HOST_NAME=""
CLUSTER_NAME=""
DONOR_IP="" # optional argument for donor IP, if not provided, instance will bootstrap a new cluster using itself as donor

while getopts "n:c:d:h" opt; do
  case $opt in
    n) HOST_NAME="$OPTARG" ;;
    c) CLUSTER_NAME="$OPTARG" ;;
    d) DONOR_IP="$OPTARG" ;;
    h) echo "Usage: $0 [-n host_name] [-c cluster_name] [-d donor_ip] [-h help]" >&2
       exit 1 ;;
  esac
done

echo "host_name=$HOST_NAME cluster_name=$CLUSTER_NAME donor_ip=$DONOR_IP"

is_instance() {
  multipass info "$1" >/dev/null 2>&1 && echo true || echo false
}

# Create a new instance
if [[ $(is_instance "$HOST_NAME") == "false" ]]; then
  echo "Creating a new instance with name: $HOST_NAME"
  multipass launch 24.04 --name "$HOST_NAME"
else
  echo "instance '$HOST_NAME' already exists, skipping launch"
fi

# Transfer the provisioning scripts to the new instance
echo "Transferring provisioning scripts to the new instance..."
multipass transfer provision_mariadb_2.sh galera.cnf.tmpl "$HOST_NAME":/home/ubuntu/

# Execute the provisioning script on the new instance
echo "Executing the provisioning script on the $HOST_NAME instance with cluster_name=$CLUSTER_NAME $([[ -n "$DONOR_IP" ]] && echo "donor_ip=$DONOR_IP")..."
multipass exec "$HOST_NAME" -- bash -c "chmod +x /home/ubuntu/provision_mariadb_2.sh && /home/ubuntu/provision_mariadb_2.sh -c $CLUSTER_NAME $([[ -n "$DONOR_IP" ]] && echo "-d $DONOR_IP")"
