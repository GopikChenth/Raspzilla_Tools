#!/bin/bash
# ============================================================
#  PiBridge - Bridge Controller
#  Usage:  sudo bash bridge.sh start
#          sudo bash bridge.sh stop
#          sudo bash bridge.sh status
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

WIFI_IF="wlan0"
ETH_IF="eth0"

banner() {
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
}

check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] Run with sudo: sudo bash bridge.sh $1${NC}"
    exit 1
  fi
}

start_bridge() {
  banner
  echo -e "${YELLOW}>>> Starting PiBridge  ($WIFI_IF → $ETH_IF)${NC}\n"

  echo -e "${CYAN}[1/4] Flushing old iptables rules...${NC}"
  iptables -t nat -F
  iptables -F FORWARD

  echo -e "${CYAN}[2/4] Applying NAT masquerade on $WIFI_IF...${NC}"
  iptables -t nat -A POSTROUTING -o "$WIFI_IF" -j MASQUERADE

  echo -e "${CYAN}[3/4] Enabling forwarding rules...${NC}"
  iptables -A FORWARD -i "$WIFI_IF" -o "$ETH_IF" -m state --state RELATED,ESTABLISHED -j ACCEPT
  iptables -A FORWARD -i "$ETH_IF" -o "$WIFI_IF" -j ACCEPT

  echo -e "${CYAN}[4/4] Saving rules & restarting services...${NC}"
  netfilter-persistent save
  systemctl restart dnsmasq

  echo ""
  echo -e "${GREEN}✔ Bridge is UP!${NC}"
  echo -e "  Your PC should receive an IP in ${BLUE}192.168.2.x${NC} range."
  echo -e "  Pi gateway IP on eth0: ${BLUE}192.168.2.1${NC}"
  echo ""
}

stop_bridge() {
  banner
  echo -e "${YELLOW}>>> Stopping PiBridge...${NC}\n"

  echo -e "${CYAN}[1/2] Flushing iptables rules...${NC}"
  iptables -t nat -F
  iptables -F FORWARD

  echo -e "${CYAN}[2/2] Saving cleared rules...${NC}"
  netfilter-persistent save

  echo ""
  echo -e "${RED}✘ Bridge is DOWN.${NC}"
  echo ""
}

show_status() {
  banner
  echo -e "${YELLOW}>>> PiBridge Status${NC}\n"

  echo -e "${CYAN}--- Interfaces ---${NC}"
  ip -brief addr show "$WIFI_IF" 2>/dev/null || echo "  $WIFI_IF not found"
  ip -brief addr show "$ETH_IF"  2>/dev/null || echo "  $ETH_IF not found"

  echo ""
  echo -e "${CYAN}--- IP Forwarding ---${NC}"
  FWD=$(cat /proc/sys/net/ipv4/ip_forward)
  [ "$FWD" -eq 1 ] && echo -e "  ${GREEN}Enabled ✔${NC}" || echo -e "  ${RED}Disabled ✘${NC}"

  echo ""
  echo -e "${CYAN}--- NAT Rules ---${NC}"
  iptables -t nat -L POSTROUTING -n --line-numbers 2>/dev/null | grep -v "^$" || echo "  (none)"

  echo ""
  echo -e "${CYAN}--- DHCP Leases ---${NC}"
  if [ -f /var/lib/misc/dnsmasq.leases ]; then
    cat /var/lib/misc/dnsmasq.leases | awk '{print "  IP: "$3"  MAC: "$2"  Host: "$4}'
  else
    echo "  No leases found (or dnsmasq not running)"
  fi
  echo ""
}

# ---- Main ----
case "$1" in
  start)
    check_root start
    start_bridge
    ;;
  stop)
    check_root stop
    stop_bridge
    ;;
  status)
    show_status
    ;;
  *)
    banner
    echo -e "Usage: ${YELLOW}sudo bash bridge.sh [start|stop|status]${NC}"
    echo ""
    echo -e "  ${GREEN}start${NC}   — Enable WiFi → Ethernet bridge"
    echo -e "  ${RED}stop${NC}    — Disable the bridge"
    echo -e "  ${BLUE}status${NC}  — Show interface info, NAT rules & DHCP leases"
    echo ""
    ;;
esac
