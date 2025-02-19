#!/bin/bash

sudo apt install unzip fontconfig
mkdir ~/Downloads
wget https://github.com/ryanoasis/nerd-fonts/releases/download/v2.2.2/CascadiaCode.zip -O ~/Downloads/CascadiaCode.zip
unzip ~/Downloads/CascadiaCode.zip -d ~/.fonts
fc-cache -f -v
