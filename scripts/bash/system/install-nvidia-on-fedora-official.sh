#!/bin/bash

clear
echo "========================================"
echo "NVIDIA Driver Installation on Fedora"
echo "========================================"

stage1() {
    echo "Checking prerequisites..."

    # Check UEFI secure boot status
    echo
    mokutil --sb-state

    echo
    echo "Is the UEFI secure boot disabled?"
    select yn in "Yes" "No"; do
        case $yn in
            Yes ) break;;
            No ) echo "UEFI secure boot must be disabled to continue."; exit;;
        esac
    done

    # Check for NVIDIA GPU
    echo
    lspci | grep -Ei 'VGA|3D'

    echo
    echo "Do you have an NVIDIA GPU installed?"
    select yn in "Yes" "No"; do
        case $yn in
            Yes ) break;;
            No ) echo "You really shouldn't install a driver for a GPU you do not have installed."; exit;;
        esac
    done

    # Grab the driver
    echo
    echo "Downloading driver 550.90.07..."
    wget https://us.download.nvidia.com/XFree86/Linux-x86_64/550.90.07/NVIDIA-Linux-x86_64-550.90.07.run -O ~/nvidia-driver.run
    sudo chmod +x ~/nvidia-driver.run

    # Update package cache
    echo
    echo "Update package database cache..."
    sudo dnf makecache

    # Get up to date
    echo
    echo "Make sure everything is up to date..."
    sudo dnf update

    # Install required packages
    echo
    echo "Install prerequisites..."
    sudo dnf install -y kernel-devel kernel-headers gcc make dkms acpid libglvnd-glx libglvnd-opengl libglvnd-devel libxcb egl-wayland pkgconf-pkg-config xorg-x11-server-Xwayland xorg-x11-server-Xwayland-devel xorg-x11-server-Xorg xorg-x11-server-devel

    # Check for Nouveau driver
    echo
    lsmod | grep nouveau

    echo
    echo "Is the nouveau driver enabled?"
    select yn in "Yes" "No"; do
        case $yn in
            Yes ) disableNouveau=1; break;;
            No ) disableNouveau=0; break;;
        esac
    done

    if [ disableNouveau==1 ]; then
        sudo touch /etc/modprobe.d/blacklist-nouveau.conf
        echo -e "blacklist nouveau\noptions nouveau modeset=0" | sudo tee -a  /etc/modprobe.d/blacklist-nouveau.conf >/dev/null
        sudo cp /etc/default/grub /etc/default/grub.bak
        sudo sed -i '/^GRUB_CMDLINE_LINUX=/ s/"$/ rd.driver.blacklist=nouveau nvidia-drm.modeset=1"/' /etc/default/grub
        sudo dracut --force
        sudo grub2-mkconfig -o /boot/grub2/grub.cfg
    fi

    echo
    echo "Switching to text-based UI..."
    sudo systemctl set-default multi-user.target

    echo
    echo "We will reboot now. Setup script will resume after login."
    echo -e "$(readlink -f "$0") stage2" >> ~/.bashrc

    sudo reboot
}

stage2() {
    sudo ~/nvidia-driver.run

    echo "Switching back to graphical desktop environment..."
    sed -i "/^$(readlink -f "$0") stage2\$/d" ~/.bashrc
    sudo systemctl set-default graphical.target
    sudo reboot
}

echo
echo "We're going to need elevated privileges..."
sudo -v

if [[ "$1" == "stage2" ]]; then
    echo "Continuing installation of NVIDIA driver..."
    stage2
    exit 0
fi

stage1
