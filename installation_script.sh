#!/bin/bash
# Just a debugging thing which i found to reinstall the pods 
sudo swapoff -a

#these lines check if the ric container is present or not is present 
# Define the container name
CONTAINER_NAME="ric" # Replace with your container name if different

# Check if the container is running
if sudo docker ps | grep -q $CONTAINER_NAME; then
    sudo docker stop $CONTAINER_NAME && sudo docker rm $CONTAINER_NAME
else
    # Check if the container exists but is stopped
    if sudo docker ps -a | grep -q $CONTAINER_NAME; then
        sudo docker rm $CONTAINER_NAME
    fi
fi


# Update and install prerequisites
sudo apt update -y
sudo apt install -y git vim tmux build-essential cmake libfftw3-dev libmbedtls-dev \
libboost-program-options-dev libconfig++-dev libsctp-dev libtool autoconf gnuradio \
python3-pip iperf3 libzmq3-dev nfs-common nginx docker.io
sudo snap install kubectl --classic
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
sudo apt-get install apt-transport-https --yes
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm

# Clone OAIC and submodules
cd ~/
git clone https://github.com/dkshitij29/oaic.git

# Install Kubernetes and Docker setup
cd ~/oaic/RIC-Deployment/tools/k8s/bin
./gen-cloud-init.sh
sudo ./k8s-1node-cloud-init-k_1_16-h_2_17-d_cur.sh

# Check Kubernetes pods
sudo kubectl get pods -A

# Set up Influxdb
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

# Install ASN1C compiler
cd ~/oaic/asn1c
git checkout velichkov_s1ap_plus_option_group
autoreconf -iv
./configure
make -j$(nproc)
sudo make install
sudo ldconfig

# Install srslte-e2
cd ~/oaic
git clone https://github.com/openaicellular/srslte-e2
cd srslte-e2
rm -rf build
mkdir build
export SRS=$(realpath .)
cd build
cmake ../ -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DRIC_GENERATED_E2AP_BINDING_DIR=${SRS}/e2_bindings/E2AP-v01.01 \
    -DRIC_GENERATED_E2SM_KPM_BINDING_DIR=${SRS}/e2_bindings/E2SM-KPM \
    -DRIC_GENERATED_E2SM_GNB_NRT_BINDING_DIR=${SRS}/e2_bindings/E2SM-GNB-NRT
make -j$(nproc)
sudo make install
sudo ldconfig
#sudo srslte_install_configs.sh user --force
yes | sudo srslte_install_configs.sh user --force

# Configure Nginx
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

# Modify srslte user database
sudo bash -c 'cat > ~/.config/srslte/user_db.csv <<EOL
ue2,xor,001010123456780,00112233445566778899aabbccddeeff,opc,63bfa50ee6523365ff14c1f45f88737d,8000,000000001635,7,dynamic
ue1,xor,001010123456789,00112233445566778899aabbccddeeff,opc,63bfa50ee6523365ff14c1f45f88737d,9001,00000000131b,7,dynamic
EOL'

# Install SS-xApp
cd ~/oaic
git clone https://github.com/openaicellular/ss-xapp.git
cd ss-xapp
sudo cp config-file.json /var/www/xApp_config.local/config_files/
sudo docker build . -t xApp-registry.local:5008/ss:0.1.0
export MACHINE_IP=$(hostname -I | cut -f1 -d' ')
echo '{"config-file.json_url":"http://'"$MACHINE_IP"':5010/config_files/config-file.json"}' > ss-xapp-onboard.url

# Deploy xApp
export KONG_PROXY=$(sudo kubectl get svc -n ricplt -l app.kubernetes.io/name=kong -o jsonpath='{.items[0].spec.clusterIP}')
curl -L -X POST "http://$KONG_PROXY:32080/onboard/api/v1/onboard/download" \
    --header 'Content-Type: application/json' --data-binary "@ss-xapp-onboard.url"
curl -L -X GET "http://$KONG_PROXY:32080/onboard/api/v1/charts"
curl -L -X POST "http://$KONG_PROXY:32080/appmgr/ric/v1/xapps" \
    --header 'Content-Type: application/json' --data-raw '{"xappName": "ss"}'

# Log SS-xApp
#sudo kubectl logs -f -n ricxapp -l app=ricxapp-ss
