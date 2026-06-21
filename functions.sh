#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JELLYFIN_DEPLOYMENT="$SCRIPT_DIR/src/deployment/jellyfin-deployment.yaml"
IP=$(hostname -I | awk '{print $1}')

install(){
    install_k3s
    install_k9s
    config_k9s
}

install_k3s() {
    echo "Installing K3s..."
    curl -sfL https://get.k3s.io | sh -
}

install_k9s (){
    echo "Installing K9s..."
    cd ~ || exit 1
    wget https://github.com/derailed/k9s/releases/latest/download/k9s_linux_arm64.deb && sudo apt install ./k9s_linux_arm64.deb ; rm ./k9s_linux_*
}

config_k9s (){
    echo "Configuring K9s..."
    sudo chown "$(whoami)" /etc/rancher/k3s/k3s.yaml
    echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> ~/.bashrc
}

deploy_jellyfin() {
    echo "Deploying Jellyfin pod..."
    mkdir -p ~/deployment/ && cp "$JELLYFIN_DEPLOYMENT" ~/deployment/jellyfin-deployment.yaml
    envsubst < ~/deployment/jellyfin-deployment.yaml | kubectl apply -f -
    echo "Jellyfin pod deployed. You can access it at http://$IP:30096"

}

remove() {
    echo "Removing Jellyfin deployment..."
    kubectl delete -f ~/deployment/jellyfin-deployment.yaml 2>/dev/null

    echo "Uninstalling K3s..."
    /usr/local/bin/k3s-uninstall.sh 2>/dev/null

    echo "Removing K9s..."
    sudo apt remove k9s -y 2>/dev/null
    sudo rm -f /usr/local/bin/k9s /usr/bin/k9s  2>/dev/null
    echo "Cleanup complete."
}
