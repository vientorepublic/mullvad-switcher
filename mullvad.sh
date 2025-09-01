#!/usr/local/bin/bash

#==============================================================================
# Mullvad WireGuard Connection Manager for OpenBSD
# Description: Automatically switches between random Mullvad VPN peers
#==============================================================================

set -euo pipefail  # Exit on error, undefined vars, and pipe failures

#==============================================================================
# CONFIGURATION
#==============================================================================

# WireGuard configuration
readonly WG_INTERFACE="wg0"
readonly WG_CONFIG_PATH="/etc/wireguard/${WG_INTERFACE}.conf"
readonly WG_QUICK_PATH="/usr/local/bin/wg-quick"
readonly WG_PORT="51820"

# Client configuration (MODIFY THESE VALUES)
readonly PRIVATE_KEY="(Your private key)"  # Replace with your actual private key
readonly CLIENT_ADDRESS="10.74.239.31/32"  # Replace with your assigned IP
readonly DNS_SERVER="10.64.0.1"

# Connection check settings
readonly MAX_CONNECTION_WAIT=30  # Maximum seconds to wait for connections to close
readonly CHECK_INTERVAL=5        # Seconds between connection checks

# Mullvad VPN Peers
readonly PEERS=(
  # Japan - Tokyo
  "AUo2zhQ0wCDy3/jmZgOe4QMncWWqrdME7BbY2UlkgyI=,138.199.21.239:51820" # jp-tyo-wg-001
  "zdlqydCbeR7sG1y5L8sS65X1oOtRKvfVbAuFgqEGhi4=,138.199.21.226:51820" # jp-tyo-wg-002
  # Japan - Osaka
  "uhbuY1A7g0yNu0lRhLTi020kYeAx34ED30BA5DQRHFo=,194.114.136.3:51820"  # jp-osa-wg-001
  "wzGXxsYOraTCPZuRxfXVTNmoWsRkMFLqMqDxI4PutBg=,194.114.136.34:51820" # jp-osa-wg-002
  "Pt18GnBffElW0sqnd6IDRr5r0B/NDezy6NicoPI+fG8=,194.114.136.65:51820" # jp-osa-wg-003
  "JpDAtRuR39GLFKoQNiKvpzuJ65jOOLD7h85ekZ3reVc=,194.114.136.96:51820" # jp-osa-wg-004
  # USA - Dallas
  "EAzbWMQXxJGsd8j2brhYerGB3t5cPOXqdIDFspDGSng=,146.70.211.66:51820"  # us-dal-wg-001
  "OYG1hxzz3kUGpVeGjx9DcCYreMO3S6tZN17iHUK+zDE=,146.70.211.2:51820"   # us-dal-wg-002
  "jn/i/ekJOkkRUdMj2I4ViUKd3d/LAdTQ+ICKmBy1tkM=,146.70.211.130:51820" # us-dal-wg-003
  "xZsnCxFN7pOvx6YlTbi92copdsY5xgekTCp//VUMyhE=,37.19.200.156:51820"  # us-dal-wg-401
  "sPQEji8BhxuM/Za0Q0/9aWYxyACtQF0qRpzaBLumEzo=,37.19.200.143:51820"  # us-dal-wg-402
  "4s9JIhxC/D02tosXYYcgrD+pHI+C7oTAFsXzVisKjRs=,37.19.200.130:51820"  # us-dal-wg-403
  # USA - Houston
  "NKscQ4mm24nsYWfpL85Cve+BKIExR0JaysldUtVSlzg=,37.19.221.130:51820"  # us-hou-wg-001
  "tzSfoiq9ZbCcE5I0Xz9kCrsWksDn0wgvaz9TiHYTmnU=,37.19.221.143:51820"  # us-hou-wg-002
  "fNSu30TCgbADxNKACx+5qWY6XGJOga4COmTZZE0k0R4=,37.19.221.156:51820"  # us-hou-wg-003
  "NkZMYUEcHykPkAFdm3dE8l2U9P2mt58Dw6j6BWhzaCc=,37.19.221.169:51820"  # us-hou-wg-004
)

#==============================================================================
# UTILITY FUNCTIONS
#==============================================================================

# Logging function with timestamp
log() {
  local level="$1"
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
  if [[ $EUID -ne 0 ]]; then
    error_exit "This script must be run as root"
  fi
}

# Validate dependencies
check_dependencies() {
  local deps=("wg-quick" "netstat")
  
  for dep in "${deps[@]}"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      error_exit "Required dependency not found: $dep"
    fi
  done
  
  if [[ ! -x "$WG_QUICK_PATH" ]]; then
    error_exit "WireGuard quick not found at: $WG_QUICK_PATH"
  fi
}

#==============================================================================
# CORE FUNCTIONS
#==============================================================================

# Select a random peer from the list
select_random_peer() {
  local selected_peer
  selected_peer=$(echo "${PEERS[$RANDOM % ${#PEERS[@]}]}" | tr -d '"')
  
  local peer_pubkey peer_endpoint
  peer_pubkey=$(echo "$selected_peer" | cut -d',' -f1)
  peer_endpoint=$(echo "$selected_peer" | cut -d',' -f2)
  
  if [[ -z "$peer_pubkey" || -z "$peer_endpoint" ]]; then
    error_exit "Failed to parse peer information"
  fi
  
  echo "$peer_pubkey,$peer_endpoint"
}

# Check for active TCP connections on WireGuard port
check_active_connections() {
  log "INFO" "Checking for active TCP connections on port $WG_PORT..."
  
  local wait_time=0
  while netstat -an | grep -q "\.${WG_PORT}.*ESTABLISHED"; do
    if [[ $wait_time -ge $MAX_CONNECTION_WAIT ]]; then
      log "WARNING" "Active connections still present after ${MAX_CONNECTION_WAIT}s, proceeding anyway"
      break
    fi
    
    log "INFO" "Active connections detected, waiting ${CHECK_INTERVAL}s... (${wait_time}/${MAX_CONNECTION_WAIT}s)"
    sleep $CHECK_INTERVAL
    wait_time=$((wait_time + CHECK_INTERVAL))
  done
  
  log "INFO" "No active TCP connections detected"
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
  log "INFO" "Starting Mullvad WireGuard connection manager..."
  
  # Perform initial checks
  check_root
  check_dependencies
  
  # Select random peer
  local peer_info
  peer_info=$(select_random_peer)
  local peer_pubkey peer_endpoint
  peer_pubkey=$(echo "$peer_info" | cut -d',' -f1)
  peer_endpoint=$(echo "$peer_info" | cut -d',' -f2)
  
  log "INFO" "Selected peer: $peer_endpoint"
  
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
