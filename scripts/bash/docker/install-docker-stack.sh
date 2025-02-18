
# Reference - https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository

sudo apt install ca-certificates curl gnupg lsb-release -y

sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update

sudo apt install docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-compose -y

# Optional if not running as root
sudo usermod -aG docker $USER

# Install Docker-Compose
#sudo curl -L "https://github.com/docker/compose/releases/download/1.29.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
#sudo chmod +x /usr/local/bin/docker-compose

# Add NFS mount for Docker volumes
sudo mkdir /nfs_docker
echo '# NFS Mount of Docker persistent storage' | sudo tee --append /etc/fstab
echo '192.168.0.200:/volume1/nfs_docker       /nfs_docker     nfs4    rw,noatime,rsize=8192,wsize=8192,tcp,timeo=14   0       0' | sudo tee --append /etc/fstab
sudo mount /nfs_docker
