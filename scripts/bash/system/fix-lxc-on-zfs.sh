#!/usr/bin/env bash

# Fix LXC containers on ZFS by creating a tmp directory with proper ACLs
# Usage: ./fix-lxc-on-zfs.sh [pool-name]
# Default pool is 'rpool' if not specified

POOL="${1:-rpool}"

zfs create -o mountpoint=/mnt/vztmp "$POOL/vztmp"
zfs set acltype=posixacl "$POOL/vztmp"

echo "Created $POOL/vztmp with mountpoint /mnt/vztmp"
echo "Now set /mnt/vztmp in your /etc/vzdump.conf for tmpdir"
