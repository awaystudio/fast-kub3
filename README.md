## 🚀 fast-kub3

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![Status](https://img.shields.io/badge/status-stable-orange)
![Version](https://img.shields.io/badge/version-1.1.0-brightgreen)

fast-kub3 is a Bash-based automation tool designed to quickly set up a lightweight Kubernetes environment using K3s, with optional deployment of a sample application (Jellyfin) and the K9s CLI management interface. It runs on both **Raspberry Pi (ARM)** and **x86 machines / VMs (amd64)** — the host architecture is detected automatically.

## ✨ Features
✅ Automated installation of K3s (lightweight Kubernetes)

✅ Installation of K9s, a terminal UI for managing Kubernetes clusters

✅ Optional deployment of Jellyfin media server as a demo workload

✅ Clean removal of all installed components

✅ Automatic host-architecture detection (installs the correct K9s build for amd64 / arm64 / arm)

## 🧱 Requirements
🐧 A Linux host: Raspberry Pi (ARM: arm64/armv7) **or** an x86_64/amd64 machine or VM

📦 Operating system: Raspberry Pi OS or any Debian-based distro

🌐 Active internet connection

🔧 User with sudo privileges

## 🚀 Quick Start
Clone the repository and run the main installer script:

```
git clone https://github.com/awaystudio/fast-kub3.git
cd fast-kub3
chmod +x *.sh
./fast-kub3.sh
```

## 📋 Main Menu Options
Upon launch, the installer displays an interactive menu with the following options:

Basic install → Installs K3s and K9s

Install k3s + jellyfin pod → Installs everything and deploys Jellyfin

Remove → Uninstalls K3s, K9s, and removes Jellyfin

Quit → Exit the script

## 🧪 Testing

The test suite uses **[bats](https://github.com/bats-core/bats-core)** (Bash Automated Testing System).  
All external commands (`curl`, `wget`, `apt`, `kubectl`, `sudo`, …) are replaced by stub binaries
in a temporary directory so tests run without touching the real system.

```bash
sudo apt install bats
bats tests/fast-kub3.bats
```

A GitHub Actions workflow runs `shellcheck` and `bats` automatically on every push and pull request.

## 📁 File Structure
```
fast-kub3/
├── fast-kub3.sh             # Main script (menu interface)
├── functions.sh             # All core installation/removal functions
├── src/
│   ├── title.txt            # ASCII title banner for the menu
│   └── deployment/
│       └── jellyfin-deployment.yaml  # YAML for Jellyfin deployment
└── README.md
```

Check pod status: kubectl get pods -A

K3s config file: /etc/rancher/k3s/k3s.yaml (Automatically exported in ~/.bashrc)

## 🧼 Full Removal
The Remove option performs:

Jellyfin deployment deletion (if applied)

Full uninstallation of K3s (k3s-uninstall.sh)

Removal of the K9s binary

## ⚠️ Notes
This script is designed for single-node setups.

Jellyfin deployment is provided as a working demo — feel free to replace it with your own YAML.

The directory ~/deployment/ will be created during deployment if not already present.

## 📮 Contact
For issues, suggestions, or contributions — feel free to open a GitHub issue or pull request.

## 📝 License
This project is licensed under the MIT License.
