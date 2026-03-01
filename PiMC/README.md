# PiMC 🍓⛏️

**Raspberry Pi Minecraft Server Manager** — Create and run PaperMC servers with automatic port forwarding and instant friend join links.

---

## Features

- 🔍 **Fetches all available PaperMC versions** from the official API
- ⚙️ **Optimized JVM flags** for Raspberry Pi performance
- 🌐 **Automatic port forwarding** via UPnP → falls back to playit.gg
- 🔗 **Instant friend join link** shown after server starts
- 🖥️ **Background server** via `screen` sessions
- 📋 **Full server manager** — create, start, stop, list, delete

---

## First Time Setup

```bash
# Make executable
chmod +x mcserver.sh

# Run (uses sudo for network setup)
sudo bash mcserver.sh
```

---

## Usage

### Interactive Menu (Recommended)

```bash
sudo bash mcserver.sh
```

### Direct Commands

```bash
sudo bash mcserver.sh create    # Create a new server
sudo bash mcserver.sh start     # Start an existing server
sudo bash mcserver.sh stop      # Stop a running server
sudo bash mcserver.sh list      # List all servers
sudo bash mcserver.sh delete    # Delete a server
```

---

## Creating a Server — Walkthrough

```
  Server name: MyServer
  Minecraft version [latest: 1.21.4]: 1.21.4
  RAM to allocate [suggested: 2048M]: 2048M

  [1/5] Fetching latest PaperMC build...  ✔ build #123
  [2/5] Downloading paper-1.21.4-123.jar  ████████ 100%
  [3/5] Writing config files...           ✔
  [4/5] Generating world...               ✔
  [5/5] Setting up port forwarding...
        ✔ UPnP successful!

  ✔ Server is ready!
     Join link: 123.45.67.89:25565
```

---

## Port Forwarding Strategy

| Method        | How                       | Required                 |
| ------------- | ------------------------- | ------------------------ |
| **UPnP**      | Auto-detected from router | Router must support UPnP |
| **playit.gg** | Free tunnel fallback      | Internet access          |

The tool tries UPnP first. If your router doesn't support it, playit.gg gives your friends a permanent address like `abc123.mc.playit.gg`.

---

## Managing Running Servers

```bash
# Attach to server console
screen -r mc_MyServer

# Detach without stopping
Ctrl + A, then D

# Run server command from outside
screen -S mc_MyServer -X stuff "say Hello everyone!\n"
```

---

## Server Files Location

```
~/mc-servers/
└── MyServer/
    ├── server.jar        ← PaperMC
    ├── start.sh          ← Optimized launch script
    ├── eula.txt
    ├── server.properties
    ├── .pimc             ← PiMC metadata
    └── world/            ← World data
```

---

## Performance Tips for Raspberry Pi

- Pi 4 with **4GB+ RAM** recommended
- Allocate **max 50% of total RAM** to Java
- Keep **view-distance at 6** (set in server.properties)
- Limit to **5–8 players** for smooth gameplay
- Use a fast **microSD or USB SSD** for world storage
