#!/usr/bin/bash

HOST_NAME=""
CLUSTER_NAME=""
DONOR_IP="" # optional argument for donor IP, if not provided, instance will bootstrap a new cluster using itself as donor
SST_DONOR="" # optional argument for SST donor

while getopts "n:c:d:s:h" opt; do
  case $opt in
    n) HOST_NAME="$OPTARG" ;;
    c) CLUSTER_NAME="$OPTARG" ;;
    d) DONOR_IP="$OPTARG" ;;
    s) SST_DONOR="$OPTARG" ;;
    h) echo "Usage: $0 [-n host_name] [-c cluster_name] [-d donor_ip] [-s sst_donor] [-h help]" >&2
       exit 1 ;;
  esac
done

echo "host_name="$HOST_NAME" cluster_name="$CLUSTER_NAME" donor_ip="$DONOR_IP" sst_donor="$SST_DONOR""

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
multipass transfer provision_mariadb_v2.sh galera.cnf.tmpl "$HOST_NAME":/home/ubuntu/

# Execute the provisioning script on the new instance
echo "Executing the provisioning script on the $HOST_NAME instance with cluster_name=$CLUSTER_NAME $([[ -n "$DONOR_IP" ]] && echo "donor_ip=$DONOR_IP") $([[ -n "$SST_DONOR" ]] && echo "sst_donor=$SST_DONOR")..."
multipass exec "$HOST_NAME" -- bash -c "chmod +x /home/ubuntu/provision_mariadb_v2.sh && /home/ubuntu/provision_mariadb_v2.sh -c $CLUSTER_NAME $([[ -n "$DONOR_IP" ]] && echo "-d $DONOR_IP") $([[ -n "$SST_DONOR" ]] && echo "-s $SST_DONOR")"
