# PiBridge 🌉

Turn your Raspberry Pi into a **WiFi → Ethernet bridge** in seconds.

---

## Folder Structure

```
PiBridge/
├── install.sh   ← Run ONCE on your Pi to set everything up
└── bridge.sh    ← Run whenever you want to start/stop the bridge
```

---

## First Time Setup

Copy this folder to your Raspberry Pi, then:

```bash
sudo bash install.sh
```

This will:

- Install `dnsmasq` and `iptables-persistent`
- Enable IP forwarding permanently
- Configure a static IP (`192.168.2.1`) on `eth0`
- Set up DHCP so your PC gets an IP automatically

---

## Daily Use

| Command                      | What it does                              |
| ---------------------------- | ----------------------------------------- |
| `sudo bash bridge.sh start`  | Activates the WiFi → Ethernet bridge      |
| `sudo bash bridge.sh stop`   | Deactivates the bridge                    |
| `sudo bash bridge.sh status` | Shows interfaces, NAT rules & DHCP leases |

---

## How It Works

```
Internet → Router (WiFi) → [Pi wlan0] → [Pi eth0] → Cable → Your PC
```

Your PC's Ethernet should be set to **"Obtain IP automatically (DHCP)"** — it will receive an IP in the `192.168.2.x` range.

---

## Troubleshooting

- **PC not getting an IP?** → Run `sudo systemctl status dnsmasq` on the Pi
- **No internet on PC?** → Make sure Pi is connected to WiFi: `ping 8.8.8.8` on the Pi
- **Wrong interface names?** → Edit `WIFI_IF` and `ETH_IF` variables at the top of `bridge.sh`
