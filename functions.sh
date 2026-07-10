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
    local arch
    arch="$(detect_k9s_arch)" || exit 1
    echo "Detected host architecture: $(uname -m) -> k9s package '$arch'"
    cd ~ || exit 1
    wget "https://github.com/derailed/k9s/releases/latest/download/k9s_linux_${arch}.deb" && sudo apt install "./k9s_linux_${arch}.deb" ; rm ./k9s_linux_*
}

# Mappa l'architettura dell'host (uname -m) sul suffisso del pacchetto .deb
# rilasciato da k9s. Cosi' fast-kub3 gira sia su Raspberry Pi (arm64/arm) sia
# su VM/server x86 (amd64), non solo su ARM.
detect_k9s_arch() {
    local machine
    machine="$(uname -m)"
    case "$machine" in
        x86_64 | amd64)          echo "amd64" ;;
        aarch64 | arm64)         echo "arm64" ;;
        armv7l | armv6l | arm)   echo "arm" ;;
        *)
            echo "Unsupported architecture: $machine" >&2
            echo "Supported: x86_64/amd64, aarch64/arm64, armv7l/armv6l/arm." >&2
            return 1
            ;;
    esac
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
