sudo systemctl stop mariadb && sudo apt-get purge -y mariadb-server mariadb-server-core-* mariadb-client mariadb-common galera-4 && sudo apt-get autoremove -y && sudo rm -rf /var/lib/mysql && sudo rm -rf /etc/mysql && sudo rm -rf /var/log/mysql* && sudo rm -rf /run/mysqld

multipass exec second -- bash -c "sudo systemctl stop mariadb && sudo apt-get purge -y mariadb-server mariadb-server-core-* mariadb-client mariadb-common galera-4 && sudo apt-get autoremove -y && sudo rm -rf /var/lib/mysql && sudo rm -rf /etc/mysql && sudo rm -rf /var/log/mysql* && sudo rm -rf /run/mysqld"

