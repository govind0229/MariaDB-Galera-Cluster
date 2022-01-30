#!/bin/bash
#########################################################################
# Configure Galera Mariadb cluster setup script for RHEL,Centos,Fedra   #
#               Govind Sharma <govind.sharma@live.com>                  #
#                    GNU GENERAL PUBLIC LICENSE                         #
#                       Version 3, 29 June 2007                         #
#                                                                       #
# Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>  #
# Everyone is permitted to copy and distribute verbatim copies          #
# of this license document, but changing it is not allowed.             #
#                                                                       #
#########################################################################

C='\033[0m'
R='\033[0;31m'          
G='\033[0;32m'        
Y='\033[0;33m'

export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

galerafile='/etc/my.cnf.d/galera.cnf'

if [ ! -f ".env" ]; then
    
    echo "ERROR : .env file not found"
    exit 1;
fi

source ./.env

function mariadb_server_galera(){

    echo -e "${G}Galera Mariadb cluster rpm installation...${C}"
    echo ""
    sudo dnf -y epel-release &>/dev/null
    sudo dnf -y update &>/dev/null
    sudo dnf -y install mariadb-server-galera &>/dev/null
    firewall
}

function firewall(){

    sudo sudo systemctl enable --now 'firewalld.service'
    sudo firewall-cmd --add-service=mysql --permanent &>/dev/null #(mysql)
    sudo firewall-cmd --add-port=4567/tcp --permanent &>/dev/null #(galera)
    sudo firewall-cmd --add-port=4568/tcp --permanent &>/dev/null #(galera IST tcp)
    sudo firewall-cmd --add-port=4444/tcp --permanent &>/dev/null #(rsync / SST)
    sudo firewall-cmd --add-port=4568/udp --permanent &>/dev/null #(galera IST udp)
    sudo firewall-cmd --add-port=9999/tcp --permanent &>/dev/null #(Must be open on the controller, streaming port for Xtrabackup)
    sudo firewall-cmd --add-port=9200/tcp --permanent &>/dev/null #(HAProxy healthcheck)
    sudo firewall-cmd --reload &>/dev/null
}

function galera_config_set(){
    
    #Galera configuration
    echo "Galera configuring...."
    sed -i 's/"my_wsrep_cluster"/'${cluster_name}'/' ${galerafile}
    sed -i 's/#wsrep_provider_options=/wsrep_provider_options="gcache.size=2G;gcs.fc_limit=128"/' ${galerafile}
    echo "wsrep_cluster_address="gcomm://${wsrep_cluster_address},${nodes}"" | tee -a ${galerafile}
}

function mariadb_service(){

    comm=$(mysql -u root -e "SHOW GLOBAL STATUS LIKE 'wsrep_cluster_size';" | grep wsrep_cluster_size | awk '{print $2}')

    if [[ -n "${comm}" ]]; then

        echo -e "${G}Maiadb cluster already running${C} ${wsrep_cluster_address}, Total cluster nodes count is: ${R}${comm}${C}"
        break
    else
        #Galera cluster setup
        
        mariadb_server_galera
        galera_config_set
        
        sudo galera_new_cluster
        sudo systemctl enable 'mariadb.service' &>/dev/null
        sudo sudo systemctl start 'mariadb.service' &>/dev/null
        
        if [ $? -eq 0 ]; then 

            echo -e "${G}Mariadb Galera cluster successfully started!${C}"
        else 
            echo -e "${R}Failed ${Y}Check error logs and configuration then run script again!${C}"
            exit
        fi
    fi
}

function nodes_setup(){

   echo 'Nodes setup inprogress...'
   
    if [ -d "/var/lib/mysql" ]; then
        echo "directory \"/var/lib/mysql\" exists"
        sudo systemctl stop 'mariadb.service' &>/dev/null        
        rm -rf /var/lib/mysql/*
    fi

    sudo sudo systemctl enable 'mariadb.service' &>/dev/null
    sudo systemctl start 'mariadb.service' &>/dev/null
    
    if [ $? -eq 0 ]; then

       echo "Node successfully added"
           
    else
        
       echo "Failed to add node!"
       
    fi

}

function main (){

    comm=$(mysql -u root -e "SHOW GLOBAL STATUS LIKE 'wsrep_cluster_size';" | grep wsrep_cluster_size | awk '{print $2}')

    if [[ -n "${comm}" ]]; then
        echo "Node already running"
        exit
    else
        mariadb_server_galera
        firewall
        nodes_setup
    fi
}

function nodes(){

    dnf -y install sshpass &>/dev/null

    for node in $(echo $nodes | sed -e 's/,/ /'); do
        echo "${node}"

        if [[ "${SSH_KEY_ENABLED}" = "no" ]]; then

            sshpass -p ${SSH_PASSWD} scp -P${SSH_PORT} ${galerafile} ${SSH_USER}@${node}:${galerafile}
            sshpass -p ${SSH_PASSWD} ssh -l ${SSH_USER} ${node} "$(declare -f); main"
        
        else
        
            scp -i ${SSH_KEY} -P${SSH_PORT} ${galerafile} ${SSH_USER}@${node}:${galerafile}
            ssh -i ${SSH_KEY} -l ${SSH_USER} ${node} "$(declare -f); main"
        
        fi
    done
    
}


echo 'Galera Mariadb cluster installation...'
mariadb_service
nodes