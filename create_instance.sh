#!/usr/bin/bash

HOST_NAME=${1:-n}

# Create a new instance
echo "Creating a new instance with name: $HOST_NAME"
multipass launch 24.04 --name "$HOST_NAME"

# Transfer the provisioning scripts to the new instance
echo "Transferring provisioning scripts to the new instance..."
multipass transfer provision_mariadb.sh galera.cnf.tmpl "$HOST_NAME":/home/ubuntu/

# Execute the provisioning script on the new instance
echo "Executing the provisioning script on the new instance..."
multipass exec "$HOST_NAME" -- bash -c "chmod +x /home/ubuntu/provision_mariadb.sh && /home/ubuntu/provision_mariadb.sh"
