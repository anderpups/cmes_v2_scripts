#!/bin/bash
## Script to export logs from SQL and upload via rsync
## v20250721

# Treat unset variables as an error when substituting.
# Exit if any command in a pipeline fails.
set -o pipefail

# --- Configuration Variables ---
readonly REMOTE_SCP_USER='cmesworldpi'
readonly REMOTE_SCP_HOST='bridgevm.techieswithoutborders.us'
readonly REMOTE_EXPORT_PATH='/home/cmesworldpi/elif/CMES-v2-CodeBase/Usagelogs/'
readonly SSH_PRIVATE_KEY_PATH='/home/pi/.ssh/id_rsa'
readonly LOCAL_LOG_DIR='/var/lib/mysql-files'
readonly MYSQL_HOST='localhost'
readonly MYSQL_PORT='3306'
readonly MYSQL_DEFAULTS_FILE='/root/.mysql_defaults'
readonly MYSQL_DATABASE='CMES_mini'
readonly LOG_PATH='/var/www/html/CMES-Pi/assets/Log'

# Array of log tables to export
readonly LOG_TABLES=("UserLogin" "UserSearch" "UserUsage" "TopTopic")

# --- Function Definitions ---

# Function to display usage information
usage() {
  echo "Usage: $(basename "$0") [-h]"
  echo ""
  echo "Exports logs from MySQL tables and uploads them to a remote server via SCP."
  echo "  -h  Display this help message."
  exit 1
}

# --- Command Line Argument Parsing ---

while getopts ":h" opt; do
  case $opt in
    h)
      usage
      ;;
    \?)
      echo "Error: Invalid option -$OPTARG" >&2
      usage
      ;;
  esac
done
shift $((OPTIND-1))

# Function to log messages
log_message() {
  TRUNCATED_LOG=$(tail -n 150 ${LOG_PATH}/SendLogs-script_activity.log)
  echo "$TRUNCATED_LOG" > ${LOG_PATH}/SendLogs-script_activity.log
  local level="$1"
  local message="$2"
  local timestamp
  timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  echo "${timestamp} [${level}] ${message}" | tee -a "${LOG_PATH}/SendLogs-script_activity.log"
}

# --- Main Script Logic ---
log_message "INFO" "Starting log export and upload process..."

for LOG_TABLE in "${LOG_TABLES[@]}"; do
  LOCAL_FILE_PATH="${LOCAL_LOG_DIR}/${LOG_TABLE}.csv"
  REMOTE_FILE_NAME="${LOG_TABLE}_${HOSTNAME}.csv" # Use HOSTNAME for clarity
  REMOTE_TARGET="${REMOTE_SCP_USER}@${REMOTE_SCP_HOST}:${REMOTE_EXPORT_PATH}/${REMOTE_FILE_NAME}"
  
  ## Delete the local file if it exists
  /usr/bin/rm -f "$LOCAL_FILE_PATH"

  log_message "INFO" "Processing log table: $LOG_TABLE"

  # Capture MySQL output for logging in case of failure
  mysql_output=$(/usr/bin/mysql --defaults-extra-file="$MYSQL_DEFAULTS_FILE" \
    --host="$MYSQL_HOST" --port="$MYSQL_PORT" --database="$MYSQL_DATABASE" \
    --execute="SELECT * FROM \`$LOG_TABLE\` INTO OUTFILE '$LOCAL_FILE_PATH' FIELDS TERMINATED BY ',' ENCLOSED BY '\"' LINES TERMINATED BY '\n';" 2>&1)
  mysql_exit_code=$?
  if [ $mysql_exit_code -ne 0 ]; then
    log_message "ERROR" "MySQL export failed for table '$LOG_TABLE'. MySQL output: $mysql_output"
    continue # Skip to the next log table
  fi

  # Check if the exported file was actually created and is not empty
  if [[ ! -s "$LOCAL_FILE_PATH" ]]; then
    log_message "WARNING" "Exported file '$LOCAL_FILE_PATH' is empty or not created."
    continue # Skip to the next log table
  fi

  log_message "INFO" "Uploading '$LOCAL_FILE_PATH' to '$REMOTE_TARGET'..."
  # Use explicit full path for scp and add -q for quiet mode
  scp_output=$(/usr/bin/scp -q -i "$SSH_PRIVATE_KEY_PATH" "$LOCAL_FILE_PATH" "$REMOTE_TARGET" 2>&1)
  if [ $? -ne 0 ]; then
    log_message "ERROR" "SCP upload failed for '$LOG_TABLE'. SCP output: $scp_output"
    continue # Skip to the next log table
  fi

  log_message "INFO" "Successfully processed '$LOG_TABLE'."
done

log_message "INFO" "Log export and upload process completed."