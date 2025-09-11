#!/bin/ksh

#==============================================================================
# Active Connection Checker Utility
# Description: Standalone utility to check for active connections on downstream interface
#==============================================================================

# OpenBSD ksh: set -e (no -u/-o pipefail)
set -e

#==============================================================================
# CONFIGURATION
#==============================================================================

# Downstream interface (set to your LAN-facing interface)
DOWNSTREAM_INTERFACE=em1  # Change to your downstream interface name

# Connection check settings
# Set MAX_CONNECTION_WAIT to 0 or negative to wait indefinitely for connections to close
MAX_CONNECTION_WAIT=30  # Maximum seconds to wait for connections to close (0 or negative = unlimited)
CHECK_INTERVAL=5        # Seconds between connection checks

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

#==============================================================================
# CORE FUNCTION
#==============================================================================

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

#==============================================================================
# MAIN FUNCTION
#==============================================================================

main() {
  log "INFO" "Starting active connection checker utility..."
  
  # Perform the check
  check_active_connections
  
  log "INFO" "Active connection check completed successfully!"
}

#==============================================================================
# SCRIPT EXECUTION
#==============================================================================

# Trap to ensure cleanup on exit
trap 'log "INFO" "Script interrupted, exiting..."' INT TERM

# Run main function
main "$@"
