#!/bin/bash
# ============================================================
#  PiBridge - One-Time Installer
#  Run this ONCE to set up dependencies and persistent config
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}"
echo "  ____  _ ____        _     _            "
echo " |  _ \(_)  _ \      (_)   | |           "
echo " | |_) |_| |_) |_ __ _  __| | __ _  ___ "
echo " |  __/| |  _ <| '__| |/ _\` |/ _\` |/ _ \\"
echo " | |   | | |_) | |  | | (_| | (_| |  __/"
echo " |_|   |_|____/|_|  |_|\__,_|\__, |\___|"
echo "                               __/ |     "
echo "                              |___/      "
echo -e "${NC}"
echo -e "${YELLOW}>>> PiBridge One-Time Installer${NC}"
echo ""

# Check root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[ERROR] Please run as root: sudo bash install.sh${NC}"
  exit 1
fi

echo -e "${CYAN}[1/5] Updating package lists...${NC}"
apt update -y

echo -e "${CYAN}[2/5] Installing dnsmasq and iptables-persistent...${NC}"
DEBIAN_FRONTEND=noninteractive apt install -y dnsmasq iptables-persistent

echo -e "${CYAN}[3/5] Enabling IP forwarding permanently...${NC}"
sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

echo -e "${CYAN}[4/5] Configuring static IP for eth0 (192.168.2.1)...${NC}"
# Remove old eth0 static config if any
sed -i '/^interface eth0/,/^$/d' /etc/dhcpcd.conf
cat >> /etc/dhcpcd.conf <<EOF

interface eth0
static ip_address=192.168.2.1/24
EOF

echo -e "${CYAN}[5/5] Configuring dnsmasq DHCP for eth0...${NC}"
# Backup original dnsmasq config
cp /etc/dnsmasq.conf /etc/dnsmasq.conf.bak 2>/dev/null || true
cat > /etc/dnsmasq.conf <<EOF
# PiBridge - dnsmasq config
interface=eth0
dhcp-range=192.168.2.2,192.168.2.50,255.255.255.0,24h
EOF

systemctl enable dnsmasq
systemctl restart dhcpcd
systemctl restart dnsmasq

echo ""
echo -e "${GREEN}✔ Installation complete!${NC}"
echo -e "  Now run ${YELLOW}sudo bash bridge.sh start${NC} to activate the bridge."
echo ""
