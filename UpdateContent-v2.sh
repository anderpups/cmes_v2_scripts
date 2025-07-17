#!/bin/bash
## Script to Update CMES Content via rsync
# 20250717

# --- Configuration ---

readonly REMOTE_SCP_USER='cmesworldpi'
readonly REMOTE_SCP_HOST='bridgevm.techieswithoutborders.us'
# Use an array for REMOTE_CONTENT_PATHS to handle multiple paths more cleanly
readonly REMOTE_CONTENT_PATHS=(
  '/home/cmesworldpi/elif/CMES-Pi/assets/Content/'
  '/home/cmesworldpi/elif/CMES-v2/assets/VideoContent/'
)
readonly SSH_PRIVATE_KEY_PATH='/home/pi/.ssh/id_rsa'

readonly LOCAL_CONTENT_PATH='/var/www/html/CMES-Pi/assets/Content/'
readonly LOG_DIR='/var/www/html/CMES-Pi'
readonly LOG_FILE="${LOG_DIR}/wifi_status.txt"

readonly UPDATE_METADATA_SCRIPT_LOCATION='/var/www/html/CMES-Pi/assets/Cron/GetCSV.sh'
readonly SENDLOGS_SCRIPT_LOCATION='/var/www/html/CMES-Pi/assets/Cron/SendLogs.sh'
readonly WIFI_SWITCHER_SCRIPT_LOCATION='/var/www/html/CMES-Pi/wifi_switcher.sh'

# --- Functions ---

# Function to display help message
show_help() {
  echo "Usage: $(basename "$0") [-mush]"
  echo ""
  echo "Updates CMES Content by synchronizing files from a remote server."
  echo ""
  echo "Options:"
  echo "  -m    Update metadata (runs GetCSV.sh)"
  echo "  -u    Upload logs (runs SendLogs.sh)"
  echo "  -s    Switch Wi-Fi back to hotspot mode (runs wifi_switcher.sh -d)"
  echo "  -h    Display this help message"
  echo ""
  echo "Example:"
  echo "  $(basename "$0") -m -u"
  echo "  $(basename "$0") -s"
  echo ""
  exit 0
}

# Function to log messages to the status file and stderr
log_status() {
  local message="$1"
  echo "$message" | tee -a "$LOG_FILE" >&2
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
      log_status "Error: Invalid option: -$OPTARG"
      exit 1
      ;;
    :)
      log_status "Error: Option -$OPTARG requires an argument."
      log_status "Use -h for more information."
      exit 1
      ;;
  esac
done
shift "$((OPTIND - 1))" # Shift positional parameters to process remaining arguments if any

# Ensure LOG_DIR exists
mkdir -p "$LOG_DIR" || { log_status "Error: Could not create log directory $LOG_DIR"; exit 1; }

# Clear the log file at the start of execution
> "$LOG_FILE"

log_status "Starting content synchronization at $(date)"

# Construct the rsync source paths dynamically from the array
RSYNC_REMOTE_SOURCES=""
for path in "${REMOTE_CONTENT_PATHS[@]}"; do
  RSYNC_REMOTE_SOURCES+="${REMOTE_SCP_USER}@${REMOTE_SCP_HOST}:${path} "
done

# Get the number of files being synced using --dry-run
log_status "Checking for changes..."
NO_OF_FILES=$(/usr/bin/rsync --dry-run --recursive --delete --update --times --stats -e "ssh -i \"$SSH_PRIVATE_KEY_PATH\"" ${RSYNC_REMOTE_SOURCES} "${LOCAL_CONTENT_PATH}" 2>&1 | grep 'Number of created files' | awk '{print $5}' | sed 's/,//g')

if [[ "$NO_OF_FILES" -gt 0 ]]; then
  log_status "Found $NO_OF_FILES new or updated files to sync."
  # Perform the actual rsync, logging progress
  /usr/bin/rsync --recursive --update --delete --times --info=progress -e "ssh -i \"$SSH_PRIVATE_KEY_PATH\"" ${RSYNC_REMOTE_SOURCES} "${LOCAL_CONTENT_PATH}" 2>&1 | \
  stdbuf --output=0  sed -un "s/^.*xfr#\(.*\),.*/\1\/$NO_OF_FILES/p" | \
  tee "$LOG_FILE" >&2  
  if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    log_status "Error: rsync failed. Check permissions or network connectivity."
    exit 1
  fi
  log_status "Content synchronization complete."
elif [[ -z "$NO_OF_FILES" ]]; then # Check if NO_OF_FILES is empty, indicating a dry-run error
    log_status "Warning: Could not determine number of files to sync. Rsync dry-run might have failed or found no matching files."
    log_status "Attempting full sync without progress estimation."
    /usr/bin/rsync --recursive --update --delete --times -e "ssh -i \"$SSH_PRIVATE_KEY_PATH\"" ${RSYNC_REMOTE_SOURCES} "${LOCAL_CONTENT_PATH}" 2>&1 | tee -a "$LOG_FILE" >&2
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        log_status "Error: rsync failed even without progress estimation. Check permissions or network connectivity."
        exit 1
    fi
    log_status "Content synchronization complete (no file count estimate)."
else
  log_status "No new or updated files found. Content is up-to-date."
fi

# Update metadata if -m flag is set
if "$UPDATE_METADATA"; then
  log_status "Updating metadata..."
  if ! "$UPDATE_METADATA_SCRIPT_LOCATION"; then
    log_status "Error: Metadata update script failed."
    # Optionally exit here or continue depending on criticality
  fi
fi

# Upload logs if -u flag is set
if "$UPLOAD_LOGS"; then
  log_status "Uploading logs..."
  if ! "$SENDLOGS_SCRIPT_LOCATION"; then
    log_status "Error: Log upload script failed."
  fi
fi

# Set the wifi back to hotspot if -s flag is set
if "$SWITCH_WIFI"; then
  log_status "Switching Wi-Fi to hotspot mode..."
  if ! "$WIFI_SWITCHER_SCRIPT_LOCATION" "-d"; then
    log_status "Error: Wi-Fi switcher script failed."
  fi
fi

log_status "All tasks completed."
exit 0