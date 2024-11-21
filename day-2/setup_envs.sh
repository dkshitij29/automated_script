#!/bin/bash

# Prompt user for Day 1 or Day 2 setup
echo "Which setup do you want to load?"
echo "1) Day 1"
echo "2) Day 2"
read -p "Enter 1 or 2: " day_choice

# Load environment variables based on user's choice
if [ "$day_choice" == "1" ]; then
    echo "Loading environment variables for Day 1..."

    # Environment variables for Day 1
    export MACHINE_IP=$(hostname -I | cut -f1 -d' ')
    echo "MACHINE_IP is set to $MACHINE_IP"

elif [ "$day_choice" == "2" ]; then
    echo "Loading environment variables for Day 2..."

    # Environment variables for Day 2
    export SRS=$(realpath ~/oaic/srsRAN-e2)
    export KONG_PROXY=$(sudo kubectl get svc -n ricplt -l app.kubernetes.io/name=kong -o jsonpath='{.items[0].spec.clusterIP}')
    export XAPP_PORT=$(sudo kubectl get svc -n ricxapp ricxapp-ric-app-ml -o jsonpath='{.spec.ports[0].nodePort}')
    export HOST_IP=$(hostname -I | cut -f1 -d' ')
    export MACHINE_IP=$(hostname -I | cut -f1 -d' ')
    echo "SRS is set to $SRS"
    echo "KONG_PROXY is set to $KONG_PROXY"
    echo "XAPP_PORT is set to $XAPP_PORT"
    echo "HOST_IP is set to $HOST_IP"
    echo "MACHINE_IP is set to $MACHINE_IP"

else
    echo "Invalid choice! Please run the script again and enter either 1 or 2."
    exit 1
fi
