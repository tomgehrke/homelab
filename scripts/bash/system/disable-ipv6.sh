#!/usr/bin/env bash

# Disable IPv6 using sysctl

sudo tee /etc/sysctl.d/disable-ipv6.conf > /dev/null << 'EOF'
# Disable IPv6
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF

sudo sysctl -p /etc/sysctl.d/disable-ipv6.conf

echo "IPv6 has been disabled. Please reboot for changes to fully take effect."
