#!/bin/bash

set -e

# Constants
RIC_REPO="https://github.com/openaicellular/oaic.git"
ML_XAPP_REPO="https://github.com/openaicellular/ric-app-ml.git"
SRSLTE_E2LIKE_REPO="https://github.com/openaicellular/srsRAN-e2.git"
RIC_PLATFORM_CONFIG="example_recipe_oran_e_release_modified_e2.yaml"
NGINX_PORT=5010
RIC_NAMESPACE="ricinfra"
DOCKER_IMAGE_NAME="xApp-registry.local:5008/ric-app-ml:1.0.0"
NGINX_CONFIG_FILE="/etc/nginx/conf.d/xApp_config.local.conf"
CONFIG_FILE_NAME="ml-config-file.json"

# Helper functions
install_packages() {
    echo "Installing required packages..."
    apt update -y
    apt install -y git vim tmux build-essential cmake libfftw3-dev libmbedtls-dev \
        libboost-program-options-dev libconfig++-dev libsctp-dev libtool autoconf \
        gnuradio python3-pip iperf3 libzmq3-dev docker.io nginx
}

setup_near_ric() {
    echo "Setting up Near-Realtime RIC..."
    git clone $RIC_REPO ~/oaic
    cd ~/oaic
    git submodule update --init --recursive --remote

    cd ~/oaic/RIC-Deployment/tools/k8s/bin
    ./gen-cloud-init.sh
    sudo ./k8s-1node-cloud-init-k_1_16-h_2_17-d_cur.sh

    kubectl create namespace $RIC_NAMESPACE || true
    helm install stable/nfs-server-provisioner --namespace $RIC_NAMESPACE --name nfs-release-1 || true
    kubectl patch storageclass nfs -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' || true

    docker run -d -p 5001:5000 --restart=always --name ric registry:2
    cd ~/oaic/RIC-Deployment/bin
    sudo ./deploy-ric-platform -f ../RECIPE_EXAMPLE/PLATFORM/$RIC_PLATFORM_CONFIG
}

setup_nginx() {
    echo "Setting up Nginx..."
    systemctl enable nginx
    systemctl start nginx

    unlink /etc/nginx/sites-enabled/default || true
    mkdir -p /var/www/xApp_config.local/config_files
    echo "server {
        listen $NGINX_PORT default_server;
        server_name xApp_config.local;
        location /config_files/ {
            root /var/www/xApp_config.local/;
        }
    }" > $NGINX_CONFIG_FILE

    nginx -t
    systemctl reload nginx
}

setup_e2like_srslte() {
    echo "Setting up E2-like srsRAN..."
    git clone $SRSLTE_E2LIKE_REPO ~/oaic/srsRAN-e2
    cd ~/oaic/srsRAN-e2
    mkdir -p build
    export SRS=$(realpath .)
    cd build
    cmake ../ -DCMAKE_BUILD_TYPE=RelWithDebInfo -DENABLE_E2_LIKE=1 -DENABLE_AGENT_CMD=1
    make -j$(nproc)
    sudo make install
    sudo ldconfig
    sudo srsran_install_configs.sh user --force
}

setup_python_xapp() {
    echo "Setting up Python-based xApp..."
    git clone $ML_XAPP_REPO ~/oaic/ric-app-ml
    cp ~/oaic/ric-app-ml/init/config.json /var/www/xApp_config.local/config_files/$CONFIG_FILE_NAME
    systemctl reload nginx

    cd ~/oaic/ric-app-ml
    docker build . -t $DOCKER_IMAGE_NAME
}

deploy_python_xapp() {
    echo "Deploying Python-based xApp..."
    export KONG_PROXY=$(kubectl get svc -n ricplt -l app.kubernetes.io/name=kong -o jsonpath='{.items[0].spec.clusterIP}')
    curl -L -X POST "http://$KONG_PROXY:32080/onboard/api/v1/onboard/download" \
        --header 'Content-Type: application/json' --data-binary "@ml-onboard.url"
    curl -L -X GET "http://$KONG_PROXY:32080/onboard/api/v1/charts"
    curl -L -X POST "http://$KONG_PROXY:32080/appmgr/ric/v1/xapps" \
        --header 'Content-Type: application/json' --data-raw '{"xappName": "ric-app-ml"}'
}

# Main script
echo "Starting Python-based xApp setup..."
install_packages
setup_near_ric
setup_nginx
setup_e2like_srslte
setup_python_xapp
deploy_python_xapp
echo "Python-based xApp setup complete. Monitor logs with 'kubectl logs -f -n ricxapp -l app=ricxapp-ric-app-ml'."
