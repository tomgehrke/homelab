#!/usr/bin/env bash

set -euo pipefail

FONT="CascadiaCode"
LATEST=$(curl -fsSL "https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest" | grep '"tag_name"' | cut -d'"' -f4)

echo "Installing Nerd Fonts $FONT $LATEST..."
sudo apt install unzip fontconfig
mkdir -p ~/Downloads
curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/download/${LATEST}/${FONT}.zip" -o ~/Downloads/"${FONT}.zip"
unzip ~/Downloads/"${FONT}.zip" -d ~/.fonts
fc-cache -f -v
