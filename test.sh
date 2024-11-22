#!/bin/bash -x

# Helper Functions
wait_for_pods_running() {
  NS="$2"
  CMD="kubectl get pods --all-namespaces"
  if [ "$NS" != "all-namespaces" ]; then
    CMD="kubectl get pods -n $NS"
  fi
  KEYWORD="Running"
  if [ "$#" == "3" ]; then
    KEYWORD="${3}.*Running"
  fi

  CMD2="$CMD | grep \"$KEYWORD\" | wc -l"
  NUMPODS=$(eval "$CMD2")
  echo "waiting for $NUMPODS/$1 pods running in namespace [$NS] with keyword [$KEYWORD]"
  while [ $NUMPODS -lt $1 ]; do
    sleep 5
    NUMPODS=$(eval "$CMD2")
    echo "> waiting for $NUMPODS/$1 pods running in namespace [$NS] with keyword [$KEYWORD]"
  done
}

# Initial Environment Setup
export DEBIAN_FRONTEND=noninteractive
sudo swapoff -a
echo "$(hostname -I) $(hostname)" >> /etc/hosts

# Update Repositories
sudo apt-get update -y
sudo apt-get install -y curl apt-transport-https gnupg software-properties-common

# Kubernetes Repository Fix
sudo curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
sudo apt-add-repository "deb https://apt.kubernetes.io/ kubernetes-xenial main"

# Install Kubernetes Tools
sudo apt-get update -y
sudo apt-get install -y kubeadm kubectl kubelet

# Install Docker
sudo apt-get install -y docker.io
sudo systemctl enable docker.service
sudo systemctl start docker

# Docker Configuration for Kubernetes
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF
sudo systemctl daemon-reload
sudo systemctl restart docker

# Kubernetes Initialization
sudo kubeadm init --pod-network-cidr=10.244.0.0/16
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Deploy Flannel CNI
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
kubectl taint nodes --all node-role.kubernetes.io/master-

# Install Helm
sudo curl https://baltocdn.com/helm/signing.asc | sudo apt-key add -
sudo apt-add-repository "deb https://baltocdn.com/helm/stable/debian/ all main"
sudo apt-get update
sudo apt-get install -y helm

# Clone OAIC Repository
cd ~/
if [ -d "oaic" ]; then
  sudo rm -rf oaic
fi
git clone https://github.com/dkshitij29/oaic.git
cd oaic
git submodule update --init --recursive

# Deploy RIC Platform
cd ~/oaic/RIC-Deployment/tools/k8s/bin
sudo ./gen-cloud-init.sh
sudo ./k8s-1node-cloud-init-k_1_16-h_2_17-d_cur.sh
kubectl get pods -A

# Install Dependencies
sudo apt-get install -y asn1c libpcsclite-dev libsctp-dev libtool autoconf

# Install srslte-e2
cd ~/oaic
git clone https://github.com/openaicellular/srslte-e2.git
cd srslte-e2
rm -rf build
mkdir build
cd build
cmake ../ -DCMAKE_BUILD_TYPE=RelWithDebInfo
make -j$(nproc)
sudo make install
sudo ldconfig

# Configure Nginx
sudo apt-get install -y nginx
sudo systemctl enable nginx
sudo systemctl start nginx
sudo unlink /etc/nginx/sites-enabled/default
sudo mkdir -p /var/www/xApp_config.local/config_files
cat <<EOF | sudo tee /etc/nginx/conf.d/xApp_config.local.conf
server {
    listen 5010 default_server;
    server_name xApp_config.local;
    location /config_files/ {
        root /var/www/xApp_config.local/;
    }
}
EOF
sudo nginx -t
sudo systemctl reload nginx

# Deploy SS-xApp
cd ~/oaic
git clone https://github.com/openaicellular/ss-xapp.git
cd ss-xapp
sudo cp config-file.json /var/www/xApp_config.local/config_files/
sudo docker build . -t xApp-registry.local:5008/ss:0.1.0

# Set Environment Variables for Kong Proxy
export KONG_PROXY=$(kubectl get svc -n ricplt -l app.kubernetes.io/name=kong -o jsonpath='{.items[0].spec.clusterIP}')

# Onboard xApp to Kong
curl -L -X POST "http://$KONG_PROXY:32080/onboard/api/v1/onboard/download" \
    --header 'Content-Type: application/json' --data-binary "@ss-xapp-onboard.url"
curl -L -X GET "http://$KONG_PROXY:32080/onboard/api/v1/charts"
curl -L -X POST "http://$KONG_PROXY:32080/appmgr/ric/v1/xapps" \
    --header 'Content-Type: application/json' --data-raw '{"xappName": "ss"}'

echo "Installation Completed Successfully!"
