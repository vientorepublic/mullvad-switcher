#!/bin/ksh

#==============================================================================
# Mullvad WireGuard Connection Manager for OpenBSD
# Description: Automatically switches between random Mullvad VPN peers
#==============================================================================

# OpenBSD ksh: set -e (no -u/-o pipefail)
set -e

#==============================================================================
# CONFIGURATION
#==============================================================================

WG_INTERFACE=wg0
WG_CONFIG_PATH="/etc/wireguard/${WG_INTERFACE}.conf"
WG_QUICK_PATH="/usr/local/bin/wg-quick"
WG_PORT=51820

# Client configuration (MODIFY THESE VALUES)
PRIVATE_KEY="your_private_key"  # Replace with your actual private key
CLIENT_ADDRESS="10.74.239.31/32"  # Replace with your assigned IP
DNS_SERVER="10.64.0.1"

# Connection check settings
# Set MAX_CONNECTION_WAIT to 0 or negative to wait indefinitely for connections to close
MAX_CONNECTION_WAIT=30  # Maximum seconds to wait for connections to close (0 or negative = unlimited)
CHECK_INTERVAL=5        # Seconds between connection checks

# Downstream interface (set to your LAN-facing interface)
DOWNSTREAM_INTERFACE=em1  # Change to your downstream interface name

# Mullvad VPN Peers Configuration
# Format: Region - Server Description
# Each peer contains: PublicKey,Endpoint:Port
#
# To add a new peer:
# 1. Call add_peer "REGION-##" "PublicKey" "IP:Port"
# 2. Use consistent region codes
# 3. Number servers sequentially within each region

# Initialize peer database (ksh compatible)
init_peer_database() {
  # Japan, Osaka
  add_peer "JP-OSA-001" "uhbuY1A7g0yNu0lRhLTi020kYeAx34ED30BA5DQRHFo=" "194.114.136.3:51820"
  add_peer "JP-OSA-002" "wzGXxsYOraTCPZuRxfXVTNmoWsRkMFLqMqDxI4PutBg=" "194.114.136.34:51820"
  add_peer "JP-OSA-003" "Pt18GnBffElW0sqnd6IDRr5r0B/NDezy6NicoPI+fG8=" "194.114.136.65:51820"
  add_peer "JP-OSA-004" "JpDAtRuR39GLFKoQNiKvpzuJ65jOOLD7h85ekZ3reVc=" "194.114.136.96:51820"
  
  # Japan, Tokyo
  add_peer "JP-TYO-001" "AUo2zhQ0wCDy3/jmZgOe4QMncWWqrdME7BbY2UlkgyI=" "138.199.21.239:51820"
  add_peer "JP-TYO-002" "zdlqydCbeR7sG1y5L8sS65X1oOtRKvfVbAuFgqEGhi4=" "138.199.21.226:51820"
  add_peer "JP-TYO-201" "0j7u9Vd+EsqFs8XeV/T/ZM7gE+TWgEsYCsqcZUShvzc=" "146.70.138.194:51820"
  add_peer "JP-TYO-202" "yLKGIH/eaNUnrOEPRtgvC3PSMTkyAFK/0t8lNjam02k=" "146.70.201.2:51820"
  add_peer "JP-TYO-203" "tgTYDEfbDgr35h6hYW01MH76CJrwuBvbQFhyVsazEic=" "146.70.201.66:51820"
}

# Peer management (OpenBSD ksh compatible)
PEER_COUNT=0
PEER_NAMES=""
PEER_PUBKEYS=""
PEER_ENDPOINTS=""

# Add a peer to the database
add_peer() {
  local name="$1"
  local pubkey="$2"
  local endpoint="$3"
  
  PEER_COUNT=$((PEER_COUNT + 1))
  
  if [ -z "$PEER_NAMES" ]; then
    PEER_NAMES="$name"
    PEER_PUBKEYS="$pubkey"
    PEER_ENDPOINTS="$endpoint"
  else
    PEER_NAMES="${PEER_NAMES}|${name}"
    PEER_PUBKEYS="${PEER_PUBKEYS}|${pubkey}"
    PEER_ENDPOINTS="${PEER_ENDPOINTS}|${endpoint}"
  fi
}

# Get peer information by index
get_peer_info() {
  local index="$1"
  local name=$(echo "$PEER_NAMES" | cut -d'|' -f"$index")
  local pubkey=$(echo "$PEER_PUBKEYS" | cut -d'|' -f"$index")
  local endpoint=$(echo "$PEER_ENDPOINTS" | cut -d'|' -f"$index")
  echo "$name,$pubkey,$endpoint"
}

#==============================================================================
# UTILITY FUNCTIONS
#==============================================================================

# Get downstream interface IP
get_downstream_ip() {
  ifconfig "$DOWNSTREAM_INTERFACE" | awk '/inet / {print $2; exit}'
}

# Logging function with timestamp
log() {
  level="$1"
  shift
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" >&2
}

# Error handling
error_exit() {
  log "ERROR" "$1"
  exit 1
}

# Check if running as root
check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    error_exit "This script must be run as root"
  fi
}

# Validate dependencies
check_dependencies() {
  for dep in wg-quick netstat; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      error_exit "Required dependency not found: $dep"
    fi
  done
  if [ ! -x "$WG_QUICK_PATH" ]; then
    error_exit "WireGuard quick not found at: $WG_QUICK_PATH"
  fi
}

#==============================================================================
# CORE FUNCTIONS
#==============================================================================

# Select a random peer from the database (OpenBSD ksh compatible)
select_random_peer() {
  if [ "$PEER_COUNT" -eq 0 ]; then
    error_exit "No peers available in database"
  fi
  
  # Generate random index using awk (1-based indexing)
  idx=$(awk -v max="$PEER_COUNT" 'BEGIN { srand(); print int(rand()*max)+1 }')
  
  # Get peer information
  peer_info=$(get_peer_info "$idx")
  peer_name=$(echo "$peer_info" | cut -d',' -f1)
  peer_pubkey=$(echo "$peer_info" | cut -d',' -f2)
  peer_endpoint=$(echo "$peer_info" | cut -d',' -f3)
  
  if [ -z "$peer_pubkey" ] || [ -z "$peer_endpoint" ]; then
    error_exit "Failed to parse peer information for index $idx"
  fi
  
  log "INFO" "Selected peer: $peer_name ($peer_endpoint)"
  echo "$peer_pubkey,$peer_endpoint"
}

# List all available peers (for debugging/information)
list_peers() {
  log "INFO" "Available peers:"
  i=1
  while [ "$i" -le "$PEER_COUNT" ]; do
    peer_info=$(get_peer_info "$i")
    peer_name=$(echo "$peer_info" | cut -d',' -f1)
    peer_endpoint=$(echo "$peer_info" | cut -d',' -f3)
    log "INFO" "  $i. $peer_name - $peer_endpoint"
    i=$((i + 1))
  done
}

# Select peers by region prefix (e.g., "AMS" for Amsterdam)
select_peer_by_region() {
  local region_prefix="$1"
  local matching_indices=""
  local match_count=0
  
  i=1
  while [ "$i" -le "$PEER_COUNT" ]; do
    peer_info=$(get_peer_info "$i")
    peer_name=$(echo "$peer_info" | cut -d',' -f1)
    
    # Check if peer name starts with region prefix
    case "$peer_name" in
      "$region_prefix"-*)
        match_count=$((match_count + 1))
        if [ -z "$matching_indices" ]; then
          matching_indices="$i"
        else
          matching_indices="${matching_indices} $i"
        fi
        ;;
    esac
    i=$((i + 1))
  done
  
  if [ "$match_count" -eq 0 ]; then
    error_exit "No peers found for region: $region_prefix"
  fi
  
  # Select random peer from matching region
  idx=$(awk -v max="$match_count" 'BEGIN { srand(); print int(rand()*max)+1 }')
  selected_idx=$(echo "$matching_indices" | cut -d' ' -f"$idx")
  
  peer_info=$(get_peer_info "$selected_idx")
  peer_name=$(echo "$peer_info" | cut -d',' -f1)
  peer_pubkey=$(echo "$peer_info" | cut -d',' -f2)
  peer_endpoint=$(echo "$peer_info" | cut -d',' -f3)
  
  log "INFO" "Selected peer from region $region_prefix: $peer_name ($peer_endpoint)"
  echo "$peer_pubkey,$peer_endpoint"
}

# Get available regions
list_regions() {
  regions=""
  i=1
  while [ "$i" -le "$PEER_COUNT" ]; do
    peer_info=$(get_peer_info "$i")
    peer_name=$(echo "$peer_info" | cut -d',' -f1)
    region=$(echo "$peer_name" | cut -d'-' -f1)
    
    # Add region to list if not already present
    case "|$regions|" in
      *"|$region|"*) ;;
      *) 
        if [ -z "$regions" ]; then
          regions="$region"
        else
          regions="${regions}|${region}"
        fi
        ;;
    esac
    i=$((i + 1))
  done
  
  echo "$regions"
}

# Check for active TCP connections on WireGuard port
check_active_connections() {
  log "INFO" "Checking for active TCP/UDP connections from downstream interface and pf state table..."
  wait_time=0
  downstream_ip=$(get_downstream_ip)
  if [ -z "$downstream_ip" ]; then
    error_exit "Failed to get downstream interface IP for $DOWNSTREAM_INTERFACE"
  fi

  log "INFO" "Checking for active connections from $DOWNSTREAM_INTERFACE ($downstream_ip)..."
  while :; do
    tcp_active=$(netstat -n | grep "^tcp" | grep ESTABLISHED | grep "${downstream_ip}." | wc -l)
    udp_active=$(netstat -n | grep "^udp" | grep "${downstream_ip}." | wc -l)
    pf_active=$(pfctl -ss | grep "$downstream_ip" | grep -E 'ESTABLISHED|MULTIPLE' | wc -l)
    total_active=$((tcp_active + udp_active + pf_active))
    if [ $total_active -eq 0 ]; then
      break
    fi
    if [ $MAX_CONNECTION_WAIT -gt 0 ] && [ $wait_time -ge $MAX_CONNECTION_WAIT ]; then
      log "WARNING" "Active connections still present after ${MAX_CONNECTION_WAIT}s, proceeding anyway"
      break
    fi
    log "INFO" "Active connections detected (TCP: $tcp_active, UDP: $udp_active, pf: $pf_active), waiting ${CHECK_INTERVAL}s... (${wait_time}/${MAX_CONNECTION_WAIT}s)"
    sleep $CHECK_INTERVAL
    wait_time=$(expr $wait_time + $CHECK_INTERVAL)
  done

  log "INFO" "No active TCP/UDP/pf connections detected on $DOWNSTREAM_INTERFACE ($downstream_ip)"
}

# Stop WireGuard interface
stop_wireguard() {
  log "INFO" "Stopping WireGuard interface $WG_INTERFACE..."
  
  if ! "$WG_QUICK_PATH" down "$WG_INTERFACE" 2>/dev/null; then
    log "WARNING" "Failed to stop WireGuard interface (may not be running)"
  else
    log "INFO" "WireGuard interface stopped successfully"
  fi
}

# Generate WireGuard configuration
generate_config() {
  local peer_pubkey="$1"
  local peer_endpoint="$2"
  
  log "INFO" "Generating WireGuard configuration..."
  
  # Backup existing config
  if [[ -f "$WG_CONFIG_PATH" ]]; then
    cp "$WG_CONFIG_PATH" "${WG_CONFIG_PATH}.backup.$(date +%s)"
    log "INFO" "Backed up existing configuration"
  fi
  
  # Create directory if it doesn't exist
  mkdir -p "$(dirname "$WG_CONFIG_PATH")"
  
  # Generate new configuration
  cat > "$WG_CONFIG_PATH" << EOF
[Interface]
PrivateKey = $PRIVATE_KEY
Address = $CLIENT_ADDRESS
DNS = $DNS_SERVER

[Peer]
PublicKey = $peer_pubkey
AllowedIPs = 0.0.0.0/0
Endpoint = $peer_endpoint
EOF

  if [[ ! -f "$WG_CONFIG_PATH" ]]; then
    error_exit "Failed to create WireGuard configuration"
  fi
  
  log "INFO" "Configuration generated successfully"
}

# Start WireGuard interface
start_wireguard() {
  log "INFO" "Starting WireGuard interface $WG_INTERFACE..."
  
  if ! "$WG_QUICK_PATH" up "$WG_INTERFACE"; then
    error_exit "Failed to start WireGuard interface"
  fi
  
  log "INFO" "WireGuard interface started successfully"
}

# Verify connection
verify_connection() {
  local peer_pubkey="$1"
  local peer_endpoint="$2"
  
  log "INFO" "Verifying connection..."
  
  # Check if interface is up
  if ! ip link show "$WG_INTERFACE" >/dev/null 2>&1; then
    error_exit "WireGuard interface $WG_INTERFACE is not up"
  fi
  
  # Additional verification could be added here (e.g., ping test)
  log "INFO" "Connection verified - Connected to peer $peer_pubkey at $peer_endpoint"
}

#==============================================================================
# MAIN FUNCTION
#==============================================================================

main() {
  local region=""
  local show_help=false
  local list_regions_flag=false
  local list_peers_flag=false
  
  # Parse command line arguments
  while [ $# -gt 0 ]; do
    case "$1" in
      -r|--region)
        region="$2"
        shift 2
        ;;
      -l|--list-peers)
        list_peers_flag=true
        shift
        ;;
      --list-regions)
        list_regions_flag=true
        shift
        ;;
      -h|--help)
        show_help=true
        shift
        ;;
      *)
        log "ERROR" "Unknown option: $1"
        show_help=true
        shift
        ;;
    esac
  done
  
  # Show help if requested
  if [ "$show_help" = true ]; then
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -r, --region REGION    Connect to a specific region (AMS, FRA, DUB, STO)"
    echo "  -l, --list-peers       List all available peers"
    echo "  --list-regions         List all available regions"
    echo "  -h, --help             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                     Connect to a random peer"
    echo "  $0 -r AMS              Connect to a random Amsterdam peer"
    echo "  $0 --list-peers        Show all available peers"
    echo "  $0 --list-regions      Show all available regions"
    exit 0
  fi
  
  log "INFO" "Starting Mullvad WireGuard connection manager..."
  
  # Initialize peer database
  init_peer_database
  log "INFO" "Loaded $PEER_COUNT peers from database"
  
  # Handle list options
  if [ "$list_regions_flag" = true ]; then
    regions=$(list_regions)
    log "INFO" "Available regions:"
    echo "$regions" | tr '|' '\n' | while read -r region_name; do
      log "INFO" "  $region_name"
    done
    exit 0
  fi
  
  if [ "$list_peers_flag" = true ]; then
    list_peers
    exit 0
  fi
  
  # Perform initial checks
  check_root
  check_dependencies
  
  # Select peer (by region or random)
  local peer_info
  if [ -n "$region" ]; then
    peer_info=$(select_peer_by_region "$region")
  else
    peer_info=$(select_random_peer)
  fi
  
  peer_pubkey=$(echo "$peer_info" | cut -d',' -f1)
  peer_endpoint=$(echo "$peer_info" | cut -d',' -f2)
  
  # Connection management sequence
  check_active_connections
  stop_wireguard
  generate_config "$peer_pubkey" "$peer_endpoint"
  start_wireguard
  verify_connection "$peer_pubkey" "$peer_endpoint"
  
  log "INFO" "WireGuard connection established successfully!"
}

#==============================================================================
# SCRIPT EXECUTION
#==============================================================================

# Trap to ensure cleanup on exit
trap 'log "INFO" "Script interrupted, exiting..."' INT TERM

# Run main function
main "$@"
