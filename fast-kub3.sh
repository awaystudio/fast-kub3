#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TITLE="$SCRIPT_DIR/src/title.txt"

# Importa tutte le funzioni
source "$SCRIPT_DIR/functions.sh"

# pannello principale
menu(){
   clear
    cat "$TITLE"
    echo "----------------------------------------"
    echo "Welcome to the FAST-KUB3 Installer"
    echo "----------------------------------------"
    echo "SELECT WHAT YOU WANT DO:"
    echo "1. Basic install"
    echo "2. Install k3s + jellyfin pod"
    echo "3. Remove"
    echo "0. Quit"
    echo -n "Enter your menu choice [1-3]: "

    while :
    do
        read -r choice
        case $choice in
            1) clear; echo "You have selected the option 1"
               echo "Installing... "
               install
               exit 0;;
            2) clear; echo "You have selected the option 2"
               echo "Installing... "
               install
               echo "wait 30 sec for let k3s startup" && sleep 30 
               deploy_jellyfin
               exit 0;;
            3) clear; echo "You have selected the option 3"
               echo "Removing... "
               remove
               exit 0;;
            0) echo "Quitting..."
               exit 0;;
            *) echo "invalid option";;
        esac
    done
}

# Avvia il menu solo se lo script è eseguito direttamente,
# non quando viene "source"-ato (es. dai test bats).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    menu
fi
