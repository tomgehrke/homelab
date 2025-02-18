#!/usr/bin/env bash

if [[ $EUID == 0 ]]; then
        echo "User is already root!"
        exit 1
fi

if [[ ! -f /etc/sudoers.d/$USER ]]; then
    echo "Adding $USER as sudoer..."
    echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/$USER
    sudo chmod 440 /etc/sudoers.d/$USER
fi
