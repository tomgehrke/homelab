#!/usr/bin/env bash

if [[ ! -f /etc/sudoers.d/$USER ]]; then
    echo "Adding $USER as sudoer..."
    echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/$USER
    sudo chmod 440 /etc/sudoers.d/$USER
fi
