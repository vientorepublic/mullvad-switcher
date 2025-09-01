# Mullvad WireGuard Connection Manager for OpenBSD

This project provides a Bash script (`mullvad.sh`) to automatically switch between random Mullvad VPN WireGuard peers on OpenBSD. It is designed for privacy-conscious users who want to regularly rotate their VPN endpoints for enhanced anonymity and security.

## Features

- Randomly selects a Mullvad WireGuard peer from a configurable list
- Safely stops and starts the WireGuard interface
- Backs up and generates new WireGuard configuration files on the fly
- Waits for active connections to close before switching
- Logs all actions with timestamps
- Verifies connection after switching

## Requirements

- **OpenBSD** (may work on other Unix-like systems with minor modifications)
- `bash` (script uses `/usr/local/bin/bash`)
- `wg-quick` (WireGuard quick management tool)
- `netstat` (for checking active connections)
- Root privileges

## Setup

1. **Install WireGuard** and required tools on your system.
2. **Clone or copy** this repository and place `mullvad.sh` somewhere on your system.
3. **Edit the script**:
   - Set your `PRIVATE_KEY`, `CLIENT_ADDRESS`, and `DNS_SERVER` in the configuration section.
   - Optionally, edit the `PEERS` array to include your preferred Mullvad endpoints.
4. **Make the script executable:**
   ```sh
   chmod +x mullvad.sh
   ```
5. **Run as root:**
   ```sh
   sudo ./mullvad.sh
   ```

## How It Works

- The script checks for root privileges and required dependencies.
- It randomly selects a peer from the list and generates a new WireGuard config.
- It waits for active connections to close, then safely restarts the WireGuard interface.
- After switching, it verifies the connection and logs the process.

## Customization

- **Peers:** Add or remove Mullvad WireGuard peers in the `PEERS` array.
- **Connection Settings:** Adjust `MAX_CONNECTION_WAIT` and `CHECK_INTERVAL` as needed.
- **WireGuard Interface:** Change `WG_INTERFACE` if you use a different interface name.

## Security Notes

- **Never share your private key!**
- The script backs up your previous config before overwriting.
- Use strong permissions on your config files and this script.

## Disclaimer

This script is provided as-is, without warranty. Use at your own risk. Not affiliated with Mullvad.

## License

MIT License
