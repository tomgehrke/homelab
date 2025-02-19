echo '# Disable IPv6' | sudo tee /etc/sysctl.d/disable-ipv6.conf
echo 'net.ipv6.conf.all.disable_ipv6 = 1' | sudo tee --append /etc/sysctl.d/disable-ipv6.conf
echo 'net.ipv6.conf.default.disable_ipv6 = 1' | sudo tee --append /etc/sysctl.d/disable-ipv6.conf
