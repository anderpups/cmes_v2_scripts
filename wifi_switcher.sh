#!/bin/bash
# v20250711

set -euo pipefail

# This script connects to a specified Wi-Fi profile or disconnects to activate a hotspot.

# --- Configuration ---

# Name of the hotspot connection profile
readonly HOTSPOT_PROFILE='cmes-hotspot'

# Location for the Wi-Fi status file
readonly STATUS_FILE_LOCATION="/home/pi/Cron/wifi_status.txt"

# Location of the content update script
readonly UPDATE_CONTENT_SCRIPT_LOCATION='/home/pi/Cron/UpdateContent-v2.sh'

# Default to updating content
UPDATE_CONTENT=true

# --- Helper Functions ---

# Displays an error message and exits.
# Arguments:
#   $1: The error message.
#   $2: The exit code (optional, defaults to 1).
error_exit() {
  echo "Error: $1" >&2
  exit "${2:-1}"
}

# Displays the usage help message.
show_help() {
  echo "Usage: $(basename "$0") [-h] [-s 'SSID'] [-p 'PASSWORD'] [-d] [-x]"
  echo ""
  echo "Connects to or disconnects from a wireless network."
  echo "Both the SSID and password should be wrapped in single quotes."
  echo ""
  echo "Options:"
  echo "  -s 'SSID'"
  echo "     SSID for the wireless network."
  echo "  -p 'PASSWORD'"
  echo "     Password for the wireless network."
  echo "  -d"
  echo "     Disconnects from the current network and activates the hotspot profile."
  echo "  -x"
  echo "     Disables content updates after connecting."
  echo "  -h"
  echo "     Displays this help message."
  echo ""
  echo "Example:"
  echo "  $(basename "$0") -s 'my-wifi-network' -p 'mysecretpassword'"
  echo "  $(basename "$0") -d"
  exit 0
}

# Checks if a NetworkManager connection profile is active.
# Arguments:
#   $1: The profile name to check.
# Returns:
#   0 if active, 1 otherwise.
is_profile_active() {
  nmcli -t -f active,name con | grep -q "^yes:${1}"
}

# Checks if any Wi-Fi device has an active connection.
# Returns:
#   0 if active, 1 otherwise.
is_wifi_active() {
  nmcli -t -f active dev wifi | grep -qE '^yes'
}

# Gets the SSID of the currently active Wi-Fi connection.
# Returns:
#   The SSID string or an empty string if no Wi-Fi is active.
get_active_wifi_ssid() {
  nmcli -t -f active,ssid dev wifi | grep -E '^yes' | awk -F ':' '{print $2}' || true
}

# --- Argument Parsing ---

DISCONNECT=false
SSID=""
PASSWORD=""

while getopts ":dhs:p:x" flag; do
  case "$flag" in
    s)
      SSID="$OPTARG"
      ;;
    p)
      PASSWORD="$OPTARG"
      ;;
    d)
      DISCONNECT=true
      ;;
    x)
      UPDATE_CONTENT=false
      ;;
    h)
      show_help
      ;;
    \?)
      error_exit "Invalid option: -${OPTARG}. Use -h for more information."
      ;;
    :)
      error_exit "Option -${OPTARG} requires an argument. Use -h for more information."
      ;;
  esac
done

# --- Input Validation ---

if $DISCONNECT; then
  if [[ -n "$SSID" || -n "$PASSWORD" ]]; then
    error_exit "The -d flag cannot be used with -s or -p."
  fi
else
  if [[ -z "$SSID" || -z "$PASSWORD" ]]; then
    error_exit "SSID (-s) and password (-p) are required to connect. Use -h for more information."
  fi
fi

# --- Main Logic ---

if ! $DISCONNECT; then
  # Connect to a specified Wi-Fi network

  echo "Attempting to connect to Wi-Fi network: '$SSID'"

  # If hotspot is active, bring it down first
  if is_profile_active "$HOTSPOT_PROFILE"; then
    echo "Hotspot profile '$HOTSPOT_PROFILE' is active. Bringing it down..."
    if ! nmcli con down "$HOTSPOT_PROFILE"; then
      echo "Warning: Failed to bring down hotspot profile '$HOTSPOT_PROFILE'. Continuing anyway." >&2
    fi
    sleep 3 # Give NetworkManager a moment
  fi

  # Check if already connected to the target SSID
  if is_profile_active "$SSID"; then
    echo "Already connected to '$SSID' network as a client."
  else
    # Attempt to connect to the new Wi-Fi
    if nmcli device wifi connect "$SSID" password "$PASSWORD"; then
      echo "Successfully connected to '$SSID'."
    else
      echo "Connection to '$SSID' failed. Cleaning up..." >&2
      # Try to delete the failed connection profile, if it was created
      nmcli con delete "$SSID" &>/dev/null || true
      # Attempt to bring the hotspot back up
      if nmcli con up "$HOTSPOT_PROFILE"; then
        echo "Hotspot is active." > "$STATUS_FILE_LOCATION"
        error_exit "Failed to connect to '$SSID'. Reverted to hotspot."
      else
        error_exit "Failed to connect to '$SSID' and could not restore hotspot."
      fi
    fi
  fi

  # Trigger Update_Content Script if enabled
  if "$UPDATE_CONTENT"; then
    echo "Updating content..."
    # Using `nohup` for robustness, though `& disown` is also an option.
    # Redirect stdout/stderr to /dev/null to prevent zombie processes.
    nohup "$UPDATE_CONTENT_SCRIPT_LOCATION" -m -u -s &>/dev/null &
    # If the parent script exits before `nohup`, the child process will still run.
    # `disown` is for processes launched with `&` without `nohup`.
  fi

  echo "Connected to '$SSID' network as a client." > "$STATUS_FILE_LOCATION"
  exit 0

else
  # Disconnect from current network and activate hotspot

  echo "Attempting to disconnect and activate hotspot profile: '$HOTSPOT_PROFILE'"

  if is_profile_active "$HOTSPOT_PROFILE"; then
    echo "Hotspot profile '$HOTSPOT_PROFILE' is already active."
  else
    # If any Wi-Fi connection is active, try to disconnect from it
    if is_wifi_active; then
      ACTIVE_SSID=$(get_active_wifi_ssid)
      if [[ -n "$ACTIVE_SSID" ]]; then
        echo "Currently connected to '$ACTIVE_SSID'. Disconnecting..."
        if ! nmcli con delete "$ACTIVE_SSID"; then
          echo "Warning: Failed to delete connection '$ACTIVE_SSID'. Continuing anyway." >&2
        fi
      fi
    fi

    # Bring up the hotspot profile
    if ! nmcli con up "$HOTSPOT_PROFILE"; then
      error_exit "Failed to bring up hotspot profile '$HOTSPOT_PROFILE'."
    fi
  fi

  echo "Hotspot is active." > "$STATUS_FILE_LOCATION"
  exit 0
fi

# This line should ideally not be reached, but acts as a final safeguard.
error_exit "An unexpected error occurred. Wifi settings might be inconsistent. Please toggle Wi-Fi to reset." 1
