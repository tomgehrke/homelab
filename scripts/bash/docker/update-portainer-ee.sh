docker stop portainer
docker rm portainer
docker pull portainer/portainer-ee:latest
docker run -d -p 8000:8000 -p 9000:9000 -p 9443:9443 \
    --name=portainer --restart=always \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /portainer/data:/data \
    portainer/portainer-ee:latest
