#!/bin/bash
## Script to export logs from SQL and upload via rsync
## v20250711

# Exit immediately if a command exits with a non-zero status.
# Treat unset variables as an error when substituting.
# Exit if any command in a pipeline fails.
set -eo pipefail

# --- Configuration Variables ---
readonly REMOTE_SCP_USER='cmesworldpi'
readonly REMOTE_SCP_HOST='40.71.203.3'
readonly REMOTE_LOG_PATH='/home/cmesworldpi/elif/CMES-mini-CodeBase/Usagelogs/'
readonly SSH_PRIVATE_KEY_PATH='/home/pi/.ssh/id_rsa'
readonly LOCAL_LOG_DIR='/var/lib/mysql-files'
readonly MYSQL_HOST='localhost'
readonly MYSQL_PORT='3306'
readonly MYSQL_DEFAULTS_FILE='/home/pi/.mysql_defaults'
readonly MYSQL_DATABASE='CMES_mini'

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

# --- Main Script Logic ---

echo "Starting log export and upload process..."

for LOG_TABLE in "${LOG_TABLES[@]}"; do
  LOCAL_FILE_PATH="${LOCAL_LOG_DIR}/${LOG_TABLE}.csv"
  REMOTE_FILE_NAME="${LOG_TABLE}_${HOSTNAME}.csv" # Use HOSTNAME for clarity
  REMOTE_TARGET="${REMOTE_SCP_USER}@${REMOTE_SCP_HOST}:${REMOTE_LOG_PATH}/${REMOTE_FILE_NAME}"

  echo "Processing log table: $LOG_TABLE"

  echo "  Exporting data from '$LOG_TABLE' to '$LOCAL_FILE_PATH'..."
  
  if ! /usr/bin/mysql --defaults-extra-file="$MYSQL_DEFAULTS_FILE" \
    --host="$MYSQL_HOST" --port="$MYSQL_PORT" --database="$MYSQL_DATABASE" \
    --execute="SELECT * FROM \`$LOG_TABLE\` INTO OUTFILE '$LOCAL_FILE_PATH' FIELDS TERMINATED BY ',' ENCLOSED BY '\"' LINES TERMINATED BY '\n';" &> /dev/null; then
    echo "Error: MySQL export failed for table '$LOG_TABLE'." >&2
    continue # Skip to the next log table
  fi

  # Check if the exported file was actually created and is not empty
  if [[ ! -s "$LOCAL_FILE_PATH" ]]; then
    echo "Warning: Exported file '$LOCAL_FILE_PATH' is empty or not created." >&2
    continue # Skip to the next log table
  fi

  echo "  Uploading '$LOCAL_FILE_PATH' to '$REMOTE_TARGET'..."
  # Use explicit full path for scp and add -q for quiet mode
  if ! /usr/bin/scp -q -i "$SSH_PRIVATE_KEY_PATH" "$LOCAL_FILE_PATH" "$REMOTE_TARGET"; then
    echo "Error: SCP upload failed for '$LOCAL_TABLE'." >&2
    continue # Skip to the next log table
  fi

  echo "  Successfully processed '$LOG_TABLE'."
done

echo "Log export and upload process completed."