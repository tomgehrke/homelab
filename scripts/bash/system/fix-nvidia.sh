# Clean out old driver
sudo apt purge nvidia* libnvidia*

# Clean out dkms
sudo rm -rf /var/lib/dkms/nvidia

# Install/Reinstall dkms 
sudo apt install --reinstall dkms

# Download and install new driver
sudo sh ~/homelab/scripts/support/install-nvidia-driver-on-ubuntu.sh

# Install toolkit for Docker support
sudo apt install nvidia-container-toolkit

# Restart Docker
sudo service docker restart
