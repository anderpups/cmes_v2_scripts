#!/bin/bash
# This script connects to a specified Wi-Fi profile or disconnects to activate a hotspot.
# v20250722

# Exit immediately if a command exits with a non-zero status.
# Treat unset variables as an error when substituting.
# The return value of a pipeline is the status of the last command to exit with a non-zero status.
set -euo pipefail

# --- Configuration ---

# Name of the default hotspot connection profile
readonly HOTSPOT_PROFILE='cmes-hotspot'

# Location for the Wi-Fi status file
readonly STATUS_FILE_LOCATION="/var/www/html/CMES-Pi/wifi_status.txt"

# Location of the content update script
readonly UPDATE_CONTENT_SCRIPT_LOCATION='/var/www/html/CMES-Pi/assets/Cron/UpdateContent-v2.sh'

# Default to updating content
UPDATE_CONTENT=true

readonly LOG_PATH='/var/www/html/CMES-Pi/assets/Log'

# --- Helper Functions ---

# Displays an error message and exits.
# Arguments:
#   $1: The error message.
#   $2: The exit code (optional, defaults to 1).
error_exit() {
  log_message "ERROR" "Error: $1"
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
  echo "     Disconnects from the current network and activates the default CMES hotspot wi-fi profile."
  echo "  -x"
  echo "     Disables content updates after connecting."
  echo "  -h"
  echo "     Displays this help message."
  echo ""
  echo "Example:"
  echo "  $(basename "$0") -s 'my-wi-fi-network' -p 'mysecretpassword'"
  echo "  $(basename "$0") -d"
  exit 0
}

# Function to log messages
log_message() {
  local level="$1"
  local message="$2"
  local timestamp
  timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  echo "${timestamp} [${level}] ${message}" | tee -a "${LOG_PATH}/wifi_switcher-script_activity.log"
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

  log_message "INFO" "Attempting to connect to Wi-Fi network: '$SSID'"

  # If CMES wi-fi profile is active, bring it down first
  if is_profile_active "$HOTSPOT_PROFILE"; then
    # Attempt to connect to the new Wi-Fi
    echo  "Attempting to connect to supplied wi-fi network. This will disconnect your current session." > "$STATUS_FILE_LOCATION"
    echo  "Please wait for the CMES wi-fi to become available and reconnect" >> "$STATUS_FILE_LOCATION"
    sleep 4
    log_message "INFO" "wi-fi profile '$HOTSPOT_PROFILE' is active. Bringing it down..."
    # Attempt to bring down the hotspot profile
    # If it fails, log a warning but continue
    if ! nmcli con down "$HOTSPOT_PROFILE"; then
      log_message "WARNING" "Failed to bring down wi-fi profile '$HOTSPOT_PROFILE'. Continuing anyway."
    fi
    sleep 3 # Give NetworkManager a moment
  fi

  # Check if already connected to the target SSID
  if is_profile_active "$SSID"; then
    log_message "INFO" "Already connected to '$SSID' network as a client."
  else
    if nmcli device wifi connect "$SSID" password "$PASSWORD"; then
      log_message "INFO" "Successfully connected to '$SSID'."
    else
      log_message "ERROR" "Connection to '$SSID' failed. Cleaning up..."
      # Try to delete the failed connection profile, if it was created
      nmcli con delete "$SSID" &>/dev/null || true
      # Attempt to bring the hotspot back up
      if nmcli con up "$HOTSPOT_PROFILE"; then
        echo "Failed to connect to '$SSID' wi-fi." > "$STATUS_FILE_LOCATION"
        echo "CMES wi-fi is active." >> "$STATUS_FILE_LOCATION"
        error_exit "Failed to connect to '$SSID'. Reverted to hotspot."
      else
        error_exit "Failed to connect to '$SSID' and could not restore hotspot."
      fi
    fi
  fi

  # Trigger Update_Content Script if enabled
  if "$UPDATE_CONTENT"; then
    log_message "INFO" "Running content update script: $UPDATE_CONTENT_SCRIPT_LOCATION"
    # Redirect stdout/stderr to /dev/null to prevent zombie processes.
    nohup "$UPDATE_CONTENT_SCRIPT_LOCATION" -m -u -s &>/dev/null &
    # If the parent script exits before `nohup`, the child process will still run.
  fi

  log_message "INFO" "Successfully connected to '$SSID'."
  exit 0

else
  # Disconnect from current network and activate hotspot

  log_message "INFO" "Attempting to disconnect and activate hotspot profile: '$HOTSPOT_PROFILE'"

  if is_profile_active "$HOTSPOT_PROFILE"; then
    log_message "INFO" "Hotspot profile '$HOTSPOT_PROFILE' is already active."
  else
    # If any Wi-Fi connection is active, try to disconnect from it
    if is_wifi_active; then
      ACTIVE_SSID=$(get_active_wifi_ssid)
      if [[ -n "$ACTIVE_SSID" ]]; then
        log_message "INFO" "Currently connected to '$ACTIVE_SSID'. Disconnecting"
        if ! nmcli con delete "$ACTIVE_SSID"; then
          log_message "WARNING" "Failed to delete connection '$ACTIVE_SSID'. Continuing anyway."
        fi
      fi
    fi

    # Bring up the hotspot profile
    if ! nmcli con up "$HOTSPOT_PROFILE"; then
      error_exit "Failed to bring up hotspot profile '$HOTSPOT_PROFILE'."
    else
      log_message "INFO" "Hotspot profile '$HOTSPOT_PROFILE' active."
    fi
  fi

  # Only add a line if it's not already there.
  if tail -n 1 "$STATUS_FILE_LOCATION" | grep -qv "CMES wi-fi is active"; then
    echo "CMES wi-fi is active." >> "$STATUS_FILE_LOCATION"
  fi
  exit 0
fi

# This line should ideally not be reached, but acts as a final safeguard.
error_exit "An unexpected error occurred. wi-fi settings might be inconsistent. Please run 'wi-fi_switcher.sh -d' to reset." 1
