#!/bin/bash

# Load environment variables
source ./env_vars.sh

# Disable swap for Kubernetes
sudo swapoff -a

# Update and install prerequisites
sudo apt update -y
sudo apt install -y git vim tmux build-essential cmake libfftw3-dev libmbedtls-dev \
libboost-program-options-dev libconfig++-dev libsctp-dev libtool autoconf gnuradio \
python3-pip iperf3 libzmq3-dev nfs-common nginx docker.io kubectl helm snapd \
python3 python3-venv libsctp-dev
sudo snap install helm

# Install Python dependencies
pip install numpy tensorflow scikit-learn matplotlib

# Clone OAIC and submodules
cd ~/
git clone https://github.com/dkshitij29/oaic.git
cd oaic
git submodule update --init --recursive --remote

# Install Kubernetes and Docker setup
cd ~/oaic/RIC-Deployment/tools/k8s/bin
./gen-cloud-init.sh
sudo ./k8s-1node-cloud-init-k_1_16-h_2_17-d_cur.sh

# Check Kubernetes pods
sudo kubectl get pods -A

# Set up InfluxDB
sudo kubectl create ns ricinfra
sudo helm install stable/nfs-server-provisioner --namespace ricinfra --name nfs-release-1
sudo kubectl patch storageclass nfs -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
sudo apt install nfs-common -y

# Pull E2 docker image
sudo docker run -d -p 5001:5000 --restart=always --name ric registry:2
sudo docker pull oaic/e2:5.5.0
sudo docker tag oaic/e2:5.5.0 localhost:5001/ric-plt-e2:5.5.0
sudo docker push localhost:5001/ric-plt-e2:5.5.0

# Deploy Near-Realtime RIC
cd ~/oaic/RIC-Deployment/bin
sudo ./deploy-ric-platform -f ../RECIPE_EXAMPLE/PLATFORM/example_recipe_oran_e_release_modified_e2.yaml
sudo kubectl get pods -A

# Compile and install E2-like srsRAN
cd ~/oaic
git clone https://github.com/openaicellular/srsRAN-e2.git
cd srsRAN-e2
rm -rf build
mkdir build
cd build
cmake ../ -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DENABLE_E2_LIKE=1 \
    -DENABLE_AGENT_CMD=1 \
    -DRIC_GENERATED_E2AP_BINDING_DIR=${SRS}/e2_bindings/E2AP-v01.01 \
    -DRIC_GENERATED_E2SM_KPM_BINDING_DIR=${SRS}/e2_bindings/E2SM-KPM \
    -DRIC_GENERATED_E2SM_GNB_NRT_BINDING_DIR=${SRS}/e2_bindings/E2SM-GNB-NRT
make -j$(nproc)
sudo make install
yes | sudo srsran_install_configs.sh user --force

# Create RAM filesystem for E2-like communication
sudo mkdir -p /mnt/tmp
sudo mount -t tmpfs none -o size=64M /mnt/tmp
sudo touch /mnt/tmp/agent_cmd.bin /mnt/tmp/iq_data_last_full.bin /mnt/tmp/iq_data_tmp.bin
sudo chmod -R 755 /mnt/tmp

# Configure Nginx for xApp
sudo systemctl enable nginx
sudo systemctl start nginx
sudo unlink /etc/nginx/sites-enabled/default
sudo mkdir -p /var/www/xApp_config.local/config_files
echo '
server {
    listen 5010 default_server;
    server_name xApp_config.local;
    location /config_files/ {
        root /var/www/xApp_config.local/;
    }
}' | sudo tee /etc/nginx/conf.d/xApp_config.local.conf
sudo nginx -t
sudo systemctl reload nginx

# Clone and configure Python xApp
cd ~/oaic
git clone https://github.com/openaicellular/ric-app-ml.git
cd ric-app-ml
sudo cp init/config.json /var/www/xApp_config.local/config_files/ml-config-file.json
sudo chmod 755 /var/www/xApp_config.local/config_files/ml-config-file.json
sudo systemctl reload nginx

# Build Docker image for Python xApp
cd ~/oaic/ric-app-ml
sudo docker build . -t xApp-registry.local:5008/ric-app-ml:1.0.0

# Onboard and deploy Python xApp
curl -L -X POST "http://$KONG_PROXY:32080/onboard/api/v1/onboard/download" \
    --header 'Content-Type: application/json' --data-binary "@ml-onboard.url"
curl -L -X POST "http://$KONG_PROXY:32080/appmgr/ric/v1/xapps" \
    --header 'Content-Type: application/json' --data-raw '{"xappName": "ric-app-ml"}'

# Expose port for E2-like communication
sudo kubectl expose deployment ricxapp-ric-app-ml --port=5000 --target-port=5000 --protocol=SCTP -n ricxapp --type=NodePort
