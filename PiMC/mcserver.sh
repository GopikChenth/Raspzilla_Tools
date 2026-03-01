#!/bin/bash
# ================================================================
#  PiMC - Raspberry Pi Minecraft Server Manager
#  Supports: PaperMC | Auto Port Forward | Friend Join Links
# ================================================================

# ── Colors ──────────────────────────────────────────────────────
RED='\033[0;31m';    GREEN='\033[0;32m';   YELLOW='\033[1;33m'
CYAN='\033[0;36m';   BLUE='\033[0;34m';    PURPLE='\033[0;35m'
WHITE='\033[1;37m';  GRAY='\033[0;37m';    NC='\033[0m'
BOLD='\033[1m'

# ── Config ───────────────────────────────────────────────────────
SERVERS_DIR="$HOME/mc-servers"
PAPER_API="https://api.papermc.io/v2/projects/paper"
MC_PORT=25565
LOG_FILE="/tmp/pimc.log"

# ================================================================
#  BANNER
# ================================================================
banner() {
  clear
  echo -e "${GREEN}"
  echo "  ██████╗ ██╗███╗   ███╗ ██████╗"
  echo "  ██╔══██╗██║████╗ ████║██╔════╝"
  echo "  ██████╔╝██║██╔████╔██║██║     "
  echo "  ██╔═══╝ ██║██║╚██╔╝██║██║     "
  echo "  ██║     ██║██║ ╚═╝ ██║╚██████╗"
  echo "  ╚═╝     ╚═╝╚═╝     ╚═╝ ╚═════╝"
  echo -e "${NC}${GRAY}  Raspberry Pi Minecraft Server Manager${NC}"
  echo -e "${GRAY}  ──────────────────────────────────────${NC}"
  echo ""
}

# ================================================================
#  HELPERS
# ================================================================
info()    { echo -e "${CYAN}[•] $1${NC}"; }
success() { echo -e "${GREEN}[✔] $1${NC}"; }
warn()    { echo -e "${YELLOW}[!] $1${NC}"; }
error()   { echo -e "${RED}[✘] $1${NC}"; }
step()    { echo -e "${PURPLE}[${1}]${NC} ${WHITE}$2${NC}"; }
divider() { echo -e "${GRAY}  ────────────────────────────────────────${NC}"; }

require_root() {
  if [ "$EUID" -ne 0 ]; then
    error "This action requires sudo. Run: sudo bash mcserver.sh"
    exit 1
  fi
}

check_dependencies() {
  local missing=()
  command -v java   &>/dev/null || missing+=("openjdk-17-jre-headless")
  command -v curl   &>/dev/null || missing+=("curl")
  command -v jq     &>/dev/null || missing+=("jq")
  command -v screen &>/dev/null || missing+=("screen")

  if [ ${#missing[@]} -gt 0 ]; then
    warn "Missing dependencies: ${missing[*]}"
    info "Installing them now..."
    sudo apt-get update -qq
    sudo apt-get install -y "${missing[@]}" 2>&1 | grep -E '(installed|upgraded|error)' || true
    success "Dependencies installed!"
  fi
}

# ================================================================
#  PAPER MC API
# ================================================================

# Cache for versions (avoid repeated API calls)
VERSIONS_CACHE=""

get_versions() {
  # Return cached result if available
  if [ -n "$VERSIONS_CACHE" ]; then
    echo "$VERSIONS_CACHE"
    return 0
  fi

  local raw
  raw=$(curl -s --connect-timeout 10 --max-time 15 "$PAPER_API" 2>/dev/null)

  if [ -z "$raw" ]; then
    return 1
  fi

  # Use jq if available, otherwise fall back to grep/sed parsing
  if command -v jq &>/dev/null; then
    VERSIONS_CACHE=$(echo "$raw" | jq -r '.versions[]?' 2>/dev/null)
  else
    # Fallback: grep the versions array from raw JSON
    VERSIONS_CACHE=$(echo "$raw" | grep -o '"[0-9][0-9]*\.[0-9][^"]*"' | tr -d '"')
  fi

  if [ -z "$VERSIONS_CACHE" ]; then
    return 1
  fi

  echo "$VERSIONS_CACHE"
}

get_latest_build() {
  local version="$1"
  local raw
  raw=$(curl -s --connect-timeout 10 --max-time 15 \
    "$PAPER_API/versions/$version/builds" 2>/dev/null)

  if command -v jq &>/dev/null; then
    echo "$raw" | jq -r '.builds[-1].build?' 2>/dev/null
  else
    # Fallback: get the last build number from JSON
    echo "$raw" | grep -o '"build":[0-9]*' | tail -1 | grep -o '[0-9]*'
  fi
}

download_paper() {
  local version="$1"
  local build="$2"
  local dest="$3"
  local url="$PAPER_API/versions/$version/builds/$build/downloads/paper-$version-$build.jar"
  curl -L --progress-bar --connect-timeout 15 --max-time 600 "$url" -o "$dest"
}

version_exists() {
  local version="$1"
  # Use cache if already populated
  local all_versions
  all_versions=$(get_versions 2>/dev/null)
  echo "$all_versions" | grep -qx "$version"
}

# ================================================================
#  PORT FORWARDING
# ================================================================
try_upnp() {
  info "Trying UPnP automatic port forwarding..."
  if ! command -v upnpc &>/dev/null; then
    sudo apt install -y miniupnpc &>/dev/null
  fi

  LOCAL_IP=$(hostname -I | awk '{print $1}')
  RESULT=$(upnpc -a "$LOCAL_IP" $MC_PORT $MC_PORT TCP 2>&1)

  if echo "$RESULT" | grep -q "done"; then
    success "UPnP port forward successful! (port $MC_PORT → $LOCAL_IP)"
    return 0
  else
    warn "UPnP failed or router doesn't support it."
    return 1
  fi
}

get_public_ip() {
  curl -s https://api.ipify.org 2>/dev/null
}

setup_playit() {
  info "Setting up playit.gg tunnel (no port forwarding needed)..."

  if ! command -v playit &>/dev/null; then
    step "→" "Installing playit.gg agent..."
    curl -SsL https://playit-cloud.github.io/ppa/key.gpg \
      | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/playit.gpg 2>/dev/null
    echo "deb [signed-by=/etc/apt/trusted.gpg.d/playit.gpg] https://playit-cloud.github.io/ppa/data ./" \
      | sudo tee /etc/apt/sources.list.d/playit-cloud.list &>/dev/null
    sudo apt update -qq && sudo apt install -y playit &>/dev/null
    success "playit.gg installed!"
  fi

  echo ""
  warn "playit.gg needs a one-time setup:"
  echo -e "  ${WHITE}1. Run ${YELLOW}playit${WHITE} in a new terminal"
  echo -e "  2. Open the link it shows in your browser"
  echo -e "  3. Sign in and claim your tunnel"
  echo -e "  4. You'll get an address like: ${GREEN}abc123.mc.playit.gg${NC}"
  echo -e "  5. Share that with your friends!"
  echo ""
  echo -e "  ${GRAY}To start the tunnel: ${YELLOW}playit &${NC}"
  echo ""
}

auto_port_forward() {
  echo ""
  divider
  echo -e "  ${BOLD}${WHITE}Setting Up Friend Access${NC}"
  divider
  echo ""

  # Try UPnP first
  if try_upnp; then
    PUBLIC_IP=$(get_public_ip)
    echo ""
    echo -e "  ${GREEN}${BOLD}✔ Port forwarding is active!${NC}"
    echo ""
    echo -e "  ${WHITE}Share this with your friends:${NC}"
    echo -e "  ${YELLOW}${BOLD}  ➜  $PUBLIC_IP:$MC_PORT${NC}"
    echo ""
    JOIN_LINK="$PUBLIC_IP:$MC_PORT"
  else
    # Fall back to playit.gg
    setup_playit
    JOIN_LINK="(see playit.gg tunnel address above)"
  fi
}

# ================================================================
#  SERVER CREATION
# ================================================================
create_server() {
  banner
  echo -e "  ${BOLD}${WHITE}Create New Minecraft Server${NC}"
  divider
  echo ""

  # ── Server Name ──────────────────────────────────────────────
  while true; do
    echo -ne "  ${CYAN}Server name${NC} (no spaces, e.g. MyServer): "
    read -r SERVER_NAME
    SERVER_NAME=$(echo "$SERVER_NAME" | tr ' ' '_')
    if [ -z "$SERVER_NAME" ]; then
      error "Name cannot be empty."
    elif [ -d "$SERVERS_DIR/$SERVER_NAME" ]; then
      error "A server named '$SERVER_NAME' already exists."
    else
      break
    fi
  done

  echo ""

  # ── Dependencies (ensure installed before API calls) ────────────
  check_dependencies

  # ── Version Selection ─────────────────────────────────────────
  info "Fetching available PaperMC versions..."
  VERSIONS=$(get_versions 2>/dev/null)
  API_OK=true

  if [ -z "$VERSIONS" ]; then
    echo ""
    warn "Could not reach PaperMC API. Possible causes:"
    echo -e "  ${GRAY}• No internet connection on the Pi"
    echo -e "  • DNS not resolving (try: ping api.papermc.io)"
    echo -e "  • Firewall blocking HTTPS${NC}"
    echo ""
    echo -ne "  ${CYAN}Type a version manually (e.g. 1.21.4) or press Enter to cancel:${NC} "
    read -r MANUAL_VERSION
    if [ -z "$MANUAL_VERSION" ]; then
      error "Cancelled."
      return
    fi
    MC_VERSION="$MANUAL_VERSION"
    API_OK=false
  else
    # Show last 10 versions
    echo ""
    echo -e "  ${BOLD}Available versions (latest 10):${NC}"
    echo "$VERSIONS" | tail -10 | while read -r v; do
      echo -e "    ${GREEN}•${NC} $v"
    done
    LATEST=$(echo "$VERSIONS" | tail -1)
    echo ""

    while true; do
      echo -ne "  ${CYAN}Minecraft version${NC} [press Enter for latest: ${GREEN}$LATEST${NC}]: "
      read -r MC_VERSION
      MC_VERSION=${MC_VERSION:-$LATEST}

      if version_exists "$MC_VERSION"; then
        break
      else
        error "'$MC_VERSION' is not a valid PaperMC version. Try again."
      fi
    done
  fi

  # ── RAM Allocation ────────────────────────────────────────────
  echo ""
  TOTAL_RAM=$(free -m | awk '/Mem:/ {print $2}')
  SUGGESTED_RAM=$(( TOTAL_RAM / 2 ))
  [ "$SUGGESTED_RAM" -lt 512  ] && SUGGESTED_RAM=512
  [ "$SUGGESTED_RAM" -gt 4096 ] && SUGGESTED_RAM=4096

  echo -ne "  ${CYAN}RAM to allocate${NC} [suggested: ${GREEN}${SUGGESTED_RAM}M${NC}]: "
  read -r SERVER_RAM
  SERVER_RAM=${SERVER_RAM:-${SUGGESTED_RAM}M}

  echo ""
  echo ""
  divider

  # ── Download PaperMC ──────────────────────────────────────────
  SERVER_DIR="$SERVERS_DIR/$SERVER_NAME"
  mkdir -p "$SERVER_DIR"

  step "1/5" "Fetching latest build for PaperMC $MC_VERSION..."
  BUILD=$(get_latest_build "$MC_VERSION")

  if [ -z "$BUILD" ] || [ "$BUILD" = "null" ]; then
    error "Could not find a build for version $MC_VERSION"
    rm -rf "$SERVER_DIR"
    exit 1
  fi

  success "Using build #$BUILD"
  echo ""
  step "2/5" "Downloading paper-$MC_VERSION-$BUILD.jar..."
  download_paper "$MC_VERSION" "$BUILD" "$SERVER_DIR/server.jar"
  echo ""
  success "Downloaded!"

  # ── Write Config Files ────────────────────────────────────────
  step "3/5" "Writing configuration files..."

  # EULA
  echo "eula=true" > "$SERVER_DIR/eula.txt"

  # server.properties
  cat > "$SERVER_DIR/server.properties" <<EOF
server-port=$MC_PORT
gamemode=survival
difficulty=normal
max-players=20
level-name=$SERVER_NAME
motd=§a$SERVER_NAME §r| Running on §2Raspberry Pi
enable-command-block=true
spawn-protection=0
view-distance=6
simulation-distance=4
EOF

  # Optimized start script
  cat > "$SERVER_DIR/start.sh" <<EOF
#!/bin/bash
cd "\$(dirname "\$0")"
java -Xms512M -Xmx$SERVER_RAM \\
  -XX:+UseG1GC \\
  -XX:+ParallelRefProcEnabled \\
  -XX:MaxGCPauseMillis=200 \\
  -XX:+UnlockExperimentalVMOptions \\
  -XX:+DisableExplicitGC \\
  -XX:G1NewSizePercent=30 \\
  -XX:G1MaxNewSizePercent=40 \\
  -XX:G1HeapRegionSize=8M \\
  -XX:InitiatingHeapOccupancyPercent=15 \\
  -Dusing.aikars.flags=https://mcflags.emc.gs \\
  -jar server.jar nogui
EOF
  chmod +x "$SERVER_DIR/start.sh"

  # Server metadata
  cat > "$SERVER_DIR/.pimc" <<EOF
SERVER_NAME=$SERVER_NAME
MC_VERSION=$MC_VERSION
PAPER_BUILD=$BUILD
SERVER_RAM=$SERVER_RAM
CREATED=$(date '+%Y-%m-%d %H:%M')
EOF

  success "Configuration files written!"

  # ── First Run (generate files) ────────────────────────────────
  step "4/5" "Running server once to generate world files..."
  echo ""
  info "This will take about 30–60 seconds..."
  cd "$SERVER_DIR"
  timeout 60 bash start.sh &>/dev/null || true
  cd - &>/dev/null

  success "World generated!"

  # ── Port Forwarding ───────────────────────────────────────────
  step "5/5" "Setting up friend access..."
  auto_port_forward

  # ── Done! ─────────────────────────────────────────────────────
  divider
  echo ""
  echo -e "  ${GREEN}${BOLD}✔ Server '$SERVER_NAME' is ready!${NC}"
  echo ""
  echo -e "  ${WHITE}Details:${NC}"
  echo -e "    Version   : ${GREEN}$MC_VERSION${NC} (PaperMC build #$BUILD)"
  echo -e "    RAM       : ${GREEN}$SERVER_RAM${NC}"
  echo -e "    Location  : ${GRAY}$SERVER_DIR${NC}"
  if [ -n "$JOIN_LINK" ]; then
    echo -e "    Join link : ${YELLOW}${BOLD}$JOIN_LINK${NC}"
  fi
  echo ""
  echo -e "  ${WHITE}To start the server:${NC} ${YELLOW}sudo bash mcserver.sh start${NC}"
  echo ""
  divider
}

# ================================================================
#  START SERVER
# ================================================================
start_server() {
  banner
  echo -e "  ${BOLD}${WHITE}Start a Server${NC}"
  divider
  echo ""

  SERVERS=$(ls "$SERVERS_DIR" 2>/dev/null)
  if [ -z "$SERVERS" ]; then
    warn "No servers found. Create one first!"
    return
  fi

  echo -e "  ${WHITE}Available servers:${NC}"
  i=1
  declare -a SERVER_LIST
  while IFS= read -r s; do
    META="$SERVERS_DIR/$s/.pimc"
    if [ -f "$META" ]; then
      VER=$(grep MC_VERSION "$META" | cut -d= -f2)
      echo -e "    ${GREEN}[$i]${NC} $s  ${GRAY}(MC $VER)${NC}"
    else
      echo -e "    ${GREEN}[$i]${NC} $s"
    fi
    SERVER_LIST+=("$s")
    ((i++))
  done <<< "$SERVERS"

  echo ""
  echo -ne "  ${CYAN}Pick a server [1-${#SERVER_LIST[@]}]:${NC} "
  read -r CHOICE
  CHOICE=$((CHOICE - 1))

  if [ -z "${SERVER_LIST[$CHOICE]}" ]; then
    error "Invalid choice."
    return
  fi

  SELECTED="${SERVER_LIST[$CHOICE]}"
  SERVER_DIR="$SERVERS_DIR/$SELECTED"

  # Check if already running
  if screen -list | grep -q "mc_$SELECTED"; then
    warn "Server '$SELECTED' is already running!"
    echo -e "  ${GRAY}Attach to it with: ${YELLOW}screen -r mc_$SELECTED${NC}"
    return
  fi

  echo ""
  info "Starting $SELECTED in background (screen session)..."
  screen -dmS "mc_$SELECTED" bash "$SERVER_DIR/start.sh"
  sleep 3

  if screen -list | grep -q "mc_$SELECTED"; then
    success "Server is running!"
  else
    error "Server failed to start. Check: $SERVER_DIR/logs/latest.log"
    return
  fi

  # Refresh port forward
  echo ""
  auto_port_forward

  echo ""
  echo -e "  ${CYAN}Useful commands:${NC}"
  echo -e "    Attach to console : ${YELLOW}screen -r mc_$SELECTED${NC}"
  echo -e "    Detach from console: ${YELLOW}Ctrl+A then D${NC}"
  echo -e "    Stop server       : ${YELLOW}sudo bash mcserver.sh stop${NC}"
  echo ""
}

# ================================================================
#  STOP SERVER
# ================================================================
stop_server() {
  banner
  echo -e "  ${BOLD}${WHITE}Stop a Server${NC}"
  divider
  echo ""

  RUNNING=$(screen -list 2>/dev/null | grep "mc_" | awk '{print $1}')

  if [ -z "$RUNNING" ]; then
    warn "No servers are currently running."
    return
  fi

  echo -e "  ${WHITE}Running servers:${NC}"
  i=1
  declare -a RUN_LIST
  while IFS= read -r s; do
    NAME=$(echo "$s" | sed 's/.*mc_//')
    echo -e "    ${GREEN}[$i]${NC} $NAME"
    RUN_LIST+=("$NAME")
    ((i++))
  done <<< "$RUNNING"

  echo ""
  echo -ne "  ${CYAN}Pick a server to stop [1-${#RUN_LIST[@]}]:${NC} "
  read -r CHOICE
  CHOICE=$((CHOICE - 1))
  SELECTED="${RUN_LIST[$CHOICE]}"

  info "Sending stop command to $SELECTED..."
  screen -S "mc_$SELECTED" -X stuff "stop
"
  sleep 4
  screen -S "mc_$SELECTED" -X quit &>/dev/null || true

  success "Server '$SELECTED' stopped!"
}

# ================================================================
#  LIST SERVERS
# ================================================================
list_servers() {
  banner
  echo -e "  ${BOLD}${WHITE}Your Minecraft Servers${NC}"
  divider
  echo ""

  SERVERS=$(ls "$SERVERS_DIR" 2>/dev/null)
  if [ -z "$SERVERS" ]; then
    warn "No servers found. Run: sudo bash mcserver.sh create"
    return
  fi

  while IFS= read -r s; do
    META="$SERVERS_DIR/$s/.pimc"
    RUNNING=""
    screen -list | grep -q "mc_$s" && RUNNING="${GREEN}● RUNNING${NC}" || RUNNING="${GRAY}○ stopped${NC}"

    echo -e "  ${WHITE}${BOLD}$s${NC}  $RUNNING"

    if [ -f "$META" ]; then
      VER=$(grep MC_VERSION "$META"   | cut -d= -f2)
      RAM=$(grep SERVER_RAM "$META"   | cut -d= -f2)
      DATE=$(grep CREATED "$META"     | cut -d= -f2)
      echo -e "    ${GRAY}Version: $VER  |  RAM: $RAM  |  Created: $DATE${NC}"
    fi
    echo ""
  done <<< "$SERVERS"
}

# ================================================================
#  DELETE SERVER
# ================================================================
delete_server() {
  banner
  echo -e "  ${BOLD}${WHITE}Delete a Server${NC}"
  divider
  echo ""

  SERVERS=$(ls "$SERVERS_DIR" 2>/dev/null)
  if [ -z "$SERVERS" ]; then
    warn "No servers to delete."
    return
  fi

  i=1
  declare -a SERVER_LIST
  while IFS= read -r s; do
    echo -e "    ${RED}[$i]${NC} $s"
    SERVER_LIST+=("$s")
    ((i++))
  done <<< "$SERVERS"

  echo ""
  echo -ne "  ${CYAN}Pick a server to delete [1-${#SERVER_LIST[@]}]:${NC} "
  read -r CHOICE
  CHOICE=$((CHOICE - 1))
  SELECTED="${SERVER_LIST[$CHOICE]}"

  echo ""
  echo -ne "  ${RED}Are you sure you want to delete '$SELECTED'? This CANNOT be undone! [yes/no]:${NC} "
  read -r CONFIRM

  if [ "$CONFIRM" = "yes" ]; then
    screen -S "mc_$SELECTED" -X quit &>/dev/null || true
    rm -rf "$SERVERS_DIR/$SELECTED"
    success "Server '$SELECTED' deleted."
  else
    warn "Cancelled."
  fi
}

# ================================================================
#  MAIN MENU
# ================================================================
main_menu() {
  mkdir -p "$SERVERS_DIR"
  check_dependencies

  banner
  echo -e "  ${BOLD}${WHITE}Main Menu${NC}"
  divider
  echo ""
  echo -e "    ${GREEN}[1]${NC} Create new server"
  echo -e "    ${CYAN}[2]${NC} Start a server"
  echo -e "    ${RED}[3]${NC} Stop a server"
  echo -e "    ${WHITE}[4]${NC} List all servers"
  echo -e "    ${YELLOW}[5]${NC} Get friend join link"
  echo -e "    ${RED}[6]${NC} Delete a server"
  echo -e "    ${GRAY}[0]${NC} Exit"
  echo ""
  divider
  echo ""
  echo -ne "  ${CYAN}Choose an option:${NC} "
  read -r OPT

  case "$OPT" in
    1) create_server ;;
    2) start_server  ;;
    3) stop_server   ;;
    4) list_servers  ;;
    5)
      PUBLIC_IP=$(get_public_ip)
      if upnpc -l &>/dev/null 2>&1; then
        echo -e "\n  ${YELLOW}${BOLD}Your join link: $PUBLIC_IP:$MC_PORT${NC}\n"
      else
        echo -e "\n  ${YELLOW}Using playit.gg tunnel — run 'playit' to see your address${NC}\n"
      fi
      ;;
    6) delete_server ;;
    0) echo ""; exit 0 ;;
    *) warn "Invalid option." ;;
  esac
}

# ================================================================
#  ENTRY POINT
# ================================================================
case "$1" in
  create) create_server ;;
  start)  start_server  ;;
  stop)   stop_server   ;;
  list)   list_servers  ;;
  delete) delete_server ;;
  *)      main_menu     ;;
esac
