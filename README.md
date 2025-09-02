# Mullvad WireGuard Connection Manager for OpenBSD

This project provides a shell script (`mullvad.sh`) for OpenBSD to automatically switch between random Mullvad WireGuard VPN peers. It is designed for privacy-conscious users who want to regularly rotate their VPN endpoints for enhanced anonymity and security.

## Features

- Randomly selects a Mullvad WireGuard peer from a configurable list
- Safely stops and starts the WireGuard interface
- Backs up and generates new WireGuard configuration files automatically
- Waits for active TCP/UDP/pf connections to close before switching
- Logs all actions with timestamps
- Verifies connection after switching

## Requirements

- **OpenBSD** (may work on other Unix-like systems with minor modifications)
- `ksh` (script uses `/bin/ksh`)
- `wg-quick` (WireGuard quick management tool)
- `netstat`, `pfctl` (for checking active connections)
- Root privileges

## Setup

1. **Install WireGuard** and required tools on your system.
2. **Clone or copy** this repository and place `mullvad.sh` somewhere on your system.
3. **Edit the script**:
   - Set your `PRIVATE_KEY`, `CLIENT_ADDRESS`, and `DNS_SERVER` in the configuration section.
   - Optionally, edit the `PEERS` variable to include your preferred Mullvad endpoints.
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
- It waits for active TCP/UDP/pf connections to close, then safely restarts the WireGuard interface.
- After switching, it verifies the connection and logs the process.

## Customization

- **Peers:** Add or remove Mullvad WireGuard peers in the `PEERS` variable. For the latest peer information, visit [Mullvad Servers](https://mullvad.net/en/servers).
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

## Recent Changes

### 2025-09-01

- Improved active TCP/UDP connection detection for OpenBSD:
  - Uses OpenBSD `netstat` output format to accurately detect active TCP/UDP connections on the downstream interface.
  - Checks for ESTABLISHED TCP connections and active UDP/pf states by matching the downstream interface IP.
- This change ensures reliable detection of active connections before switching VPN peers or reporting downstream activity.
