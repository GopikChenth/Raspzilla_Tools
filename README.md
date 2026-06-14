# Raspzilla 🍓

A collection of Raspberry Pi utilities for home networking and gaming.

---

## Projects

| Project | Description |
|---------|-------------|
| **[PiMC](PiMC/)** | Minecraft server manager — create and run PaperMC servers with auto port forwarding |
| **[PiBridge](PiBridge/)** | WiFi → Ethernet bridge — share your Pi's WiFi connection via Ethernet cable |

---

## Quick Start

### PiMC — Minecraft Server
```bash
cd PiMC
chmod +x mcserver.sh
sudo bash mcserver.sh
```
See [PiMC/README.md](PiMC/README.md) for full documentation.

### PiBridge — WiFi to Ethernet Bridge
```bash
cd PiBridge
sudo bash install.sh    # Run ONCE
sudo bash bridge.sh start
```
See [PiBridge/README.md](PiBridge/README.md) for full documentation.

---

## Requirements

- Raspberry Pi (Pi 4 with 4GB+ RAM recommended)
- Raspberry Pi OS (64-bit recommended)
- Internet connection for initial setup

---

## Project Structure

```
Raspzilla/
├── PiMC/
│   ├── mcserver.sh      # Main Minecraft server manager
│   └── README.md
└── PiBridge/
    ├── install.sh       # One-time setup
    ├── bridge.sh        # Start/stop/status bridge
    └── README.md
```