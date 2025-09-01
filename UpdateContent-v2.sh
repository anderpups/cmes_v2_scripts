#!/bin/bash
## Script to Update CMES Content via rsync
# 20250717

# --- Configuration ---

readonly REMOTE_SCP_USER='cmesworldpi'
readonly REMOTE_SCP_HOST='bridgevm.techieswithoutborders.us'
# Use an array for REMOTE_CONTENT_PATHS to handle multiple paths more cleanly
readonly REMOTE_CONTENT_PATHS=(
  '/home/cmesworldpi/elif/CMES-v2/assets/Content/'
  '/home/cmesworldpi/elif/CMES-v2/assets/VideoContent/'
)
readonly SSH_PRIVATE_KEY_PATH='/home/pi/.ssh/id_rsa'

readonly LOCAL_CONTENT_PATH='/var/www/html/CMES-Pi/assets/Content/'
readonly LOG_PATH='/var/www/html/CMES-Pi/assets/Log'

readonly STATUS_FILE_LOCATION='/var/www/html/CMES-Pi/wifi_status.txt'
readonly UPDATE_METADATA_SCRIPT_LOCATION='/var/www/html/CMES-Pi/assets/Cron/GetCSV.sh'
readonly SENDLOGS_SCRIPT_LOCATION='/var/www/html/CMES-Pi/assets/Cron/SendLogs.sh'
readonly WIFI_SWITCHER_SCRIPT_LOCATION='/var/www/html/CMES-Pi/wifi_switcher.sh'

# --- Functions ---
error_exit() {
  log_message "ERROR" "Error: $1"
  exit "${2:-1}"
}

# Function to display help message
show_help() {
  echo "Usage: $(basename "$0") [-mush]"
  echo ""
  echo "Updates CMES Content by synchronizing files from a remote server."
  echo ""
  echo "Options:"
  echo "  -m    Update metadata (runs GetCSV.sh)"
  echo "  -u    Upload logs (runs SendLogs.sh)"
  echo "  -s    Switch Wi-Fi back to CMES hotspot mode (runs wifi_switcher.sh -d)"
  echo "  -h    Display this help message"
  echo ""
  echo "Example:"
  echo "  $(basename "$0") -m -u"
  echo "  $(basename "$0") -s"
  echo ""
  exit 0
}

# Function to log messages to the status file and stderr
log_message() {
  local level="$1"
  local message="$2"
  local timestamp
  timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  echo "${timestamp} [${level}] ${message}" | tee -a "${LOG_PATH}/UpdateContent-v2_activity.log"
}

run_rsync() {
  RSYNC_OUTPUT=$(/usr/bin/rsync --recursive --human-readable --update --delete --times --stats -e "ssh -i \"$SSH_PRIVATE_KEY_PATH\"" ${RSYNC_REMOTE_SOURCES} "${LOCAL_CONTENT_PATH}" 2>&1)
  echo "Information from Transfer on $(date)" > $STATUS_FILE_LOCATION
  echo "---------------" >> $STATUS_FILE_LOCATION
  FILES_DOWNLOADED=$(echo "$RSYNC_OUTPUT" | grep -oP 'Number of created files: \K[0-9]+')
  FILES_DELETED=$(echo "$RSYNC_OUTPUT" | grep -oP 'Number of deleted files: \K[0-9]+')
  SIZE_OF_TRANSFER=$(echo "$RSYNC_OUTPUT" | grep -oP 'Total transferred file size: \K.+ ' | xargs)
  echo "$FILES_DOWNLOADED files downloaded using $SIZE_OF_TRANSFER of data." >> $STATUS_FILE_LOCATION
  echo "$FILES_DELETED local files deleted" >> $STATUS_FILE_LOCATION
}

# --- Main Script Logic ---

# Initialize flags
UPDATE_METADATA=false
UPLOAD_LOGS=false
SWITCH_WIFI=false

# Get flags
while getopts ":mush" opt; do
  case "$opt" in
    m) UPDATE_METADATA=true ;;
    u) UPLOAD_LOGS=true ;;
    s) SWITCH_WIFI=true ;;
    h) show_help ;;
    \?)
      error_exit "Invalid option: -${OPTARG}. Use -h for more information."
      ;;
    :)
      error_exit "Option -${OPTARG} requires an argument. Use -h for more information."
      exit 1
      ;;
  esac
done
shift "$((OPTIND - 1))" # Shift positional parameters to process remaining arguments if any

# Clear the log file at the start of execution

log_message "INFO" "Starting content synchronization at $(date)"

# Construct the rsync source paths dynamically from the array
RSYNC_REMOTE_SOURCES=""
for path in "${REMOTE_CONTENT_PATHS[@]}"; do
  RSYNC_REMOTE_SOURCES+="${REMOTE_SCP_USER}@${REMOTE_SCP_HOST}:${path} "
done

# Get the number of files being synced using --dry-run
log_message "INFO" "Checking for updates"
NO_OF_FILES=$(/usr/bin/rsync --dry-run --recursive --delete --update --times --stats -e "ssh -i \"$SSH_PRIVATE_KEY_PATH\"" ${RSYNC_REMOTE_SOURCES} "${LOCAL_CONTENT_PATH}" 2>&1 | grep 'Number of created files' | awk '{print $5}' | sed 's/,//g')
if [[ "$NO_OF_FILES" -gt 0 ]]; then
  log_message "INFO" "Found $NO_OF_FILES new or updated files to sync."
  # Perform the actual rsync
  run_rsync
  if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    error_exit "rsync failed. $(echo "$RSYNC_OUTPUT" | tail -n1)"
  fi
  log_message "INFO" "Content synchronization complete."

elif [[ -z "$NO_OF_FILES" ]]; then # Check if NO_OF_FILES is empty, indicating a dry-run error
    log_message "WARNING" "Could not determine number of files to sync. Rsync dry-run might have failed or found no matching files."
    run_rsync
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        error_exit "rsync failed. $(echo "$RSYNC_OUTPUT" | tail -n1)"
    fi
    log_message "WARNING" "Content synchronization complete, although the dry-run failed."
else
  log_message "INFO" "No new or updated files found. Content is up-to-date."
  echo "No updates found. Last check was $(date) " > $STATUS_FILE_LOCATION
fi
echo "---------------" >> $STATUS_FILE_LOCATION
# Update metadata if -m flag is set
if "$UPDATE_METADATA"; then
  log_message "INFO" "Updating metadata..."
  if ! "$UPDATE_METADATA_SCRIPT_LOCATION"; then
    log_message "ERROR" "Metadata update script failed."
    # Optionally exit here or continue depending on criticality
  fi
fi

# Upload logs if -u flag is set
if "$UPLOAD_LOGS"; then
  log_message "INFO" "Uploading logs"
  if ! "$SENDLOGS_SCRIPT_LOCATION"; then
    log_message "ERROR" "Log upload script failed."
  fi
fi
# Set the wifi back to hotspot if -s flag is set
if "$SWITCH_WIFI"; then
  log_message "INFO" "Switching Wi-Fi to hotspot mode..."
  if ! "$WIFI_SWITCHER_SCRIPT_LOCATION" "-d"; then
    log_message "ERROR" "Wi-Fi switcher script failed."
  fi
fi

log_message "INFO" "All tasks completed."

exit 0
