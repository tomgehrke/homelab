zfs create -o mountpoint=/mnt/vztmp rpool/vztmp
zfs set acltype=posixacl rpool/vztmp

ECHO Now set /mnt/vztmp in your /etc/vzdump.conf for tmp
