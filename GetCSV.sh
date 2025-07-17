#!/bin/bash
## Script to download and import CSV files into sql db
## v20250717

# Exit immediately if a command exits with a non-zero status.
# Treat unset variables as an error when substituting.
# The return value of a pipeline is the status of the last command to exit with a non-zero status.
set -euo pipefail

# --- Configuration Variables ---
readonly REMOTE_SCP_USER='cmesworldpi'
readonly REMOTE_SCP_HOST='bridgevm.techieswithoutborders.us'
readonly REMOTE_CSV_PATH='/home/cmesworldpi/elif/CMES-v2/assets/csv/'
readonly SSH_PRIVATE_KEY_PATH='/home/pi/.ssh/id_rsa'

readonly LOCAL_BASE_PATH='/var/www/html/CMES-Pi/assets'
readonly LOCAL_CSV_PATH="${LOCAL_BASE_PATH}/csv"
readonly LOG_PATH="${LOCAL_BASE_PATH}/Log"

readonly MYSQL_HOST='localhost'
readonly MYSQL_PORT='3306'
readonly MYSQL_DEFAULTS_FILE='/root/.mysql_defaults'

FORCE_IMPORT=false # Initialize as false

# --- Helper Functions ---

# Function to display help message
display_help() {
  echo "Usage: $(basename "$0") [-h] [-f]"
  echo ""
  echo "Used to download CSV files from cmes server and import them into MySQL."
  echo ""
  echo "Options:"
  echo "  -f    Force import of files even if there isn't a change to the CSV file."
  echo "  -h    Display this help message."
  exit 0
}

# Function to log messages
log_message() {
  local level="$1"
  local message="$2"
  local timestamp
  timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  echo "${timestamp} [${level}] ${message}" | tee -a "${LOG_PATH}/script_activity.log"
}

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# --- Pre-flight Checks ---
check_dependencies() {
  local dependencies=(rsync ssh cp rm mv mysqlimport diff)
  for cmd in "${dependencies[@]}"; do
    if ! command_exists "$cmd"; then
      log_message "ERROR" "Required command '$cmd' not found. Please install it."
      exit 1
    fi
  done
}

check_paths() {
  local paths_to_check=("$LOCAL_CSV_PATH" "$LOG_PATH")
  for p in "${paths_to_check[@]}"; do
    if [[ ! -d "$p" ]]; then
      log_message "INFO" "Creating directory: $p"
      if ! mkdir -p "$p"; then
        log_message "ERROR" "Failed to create directory: $p"
        exit 1
      fi
    fi
  done

  if [[ ! -f "$SSH_PRIVATE_KEY_PATH" ]]; then
    log_message "ERROR" "SSH private key not found at: $SSH_PRIVATE_KEY_PATH"
    exit 1
  fi

  if [[ ! -f "$MYSQL_DEFAULTS_FILE" ]]; then
    log_message "ERROR" "MySQL defaults file not found at: $MYSQL_DEFAULTS_FILE"
    exit 1
  fi
}

# --- Main Logic ---

# Get flags from script
while getopts ':hf' flag; do
  case "${flag}" in
    f)
      FORCE_IMPORT=true
      log_message "INFO" "Force import enabled."
      ;;
    h)
      display_help
      ;;
    *) # Catch-all for invalid options
      log_message "ERROR" "Invalid option: -${OPTARG}"
      display_help >&2 # Send help to stderr for invalid options
      exit 1
      ;;
  esac
done
shift "$((OPTIND - 1))" # Shift arguments so that $1, $2, etc. refer to non-option arguments

# Run pre-flight checks
check_dependencies
check_paths

# Function to download and import a CSV file
getCSV() {
  local csv_filename="$1"
  local mysql_columns="$2"
  local base_name="${csv_filename%.csv}" # Remove .csv extension if present

  log_message "INFO" "Processing ${csv_filename}.csv"

  local local_csv_file="${LOCAL_CSV_PATH}/${csv_filename}.csv"
  local old_csv_file="${LOCAL_CSV_PATH}/${csv_filename}.csv.old"
  local bad_csv_file="${LOCAL_CSV_PATH}/${csv_filename}.csv.bad"
  local rsync_log="${LOG_PATH}/rsync_${base_name}.log"
  local mysql_import_log="${LOG_PATH}/mysql_import_${base_name}.log"

  # Clean up previous bad/old files before starting
  rm -f "$bad_csv_file"

  ## Check if the csv file exists locally and back it up
  if [[ -f "$local_csv_file" ]]; then
    log_message "INFO" "Copying ${csv_filename}.csv to ${csv_filename}.csv.old"
    if ! cp -f "$local_csv_file" "$old_csv_file"; then
      log_message "ERROR" "Failed to backup ${csv_filename}.csv. Aborting for this file."
      return 1
    fi
  else
    log_message "INFO" "No existing ${csv_filename}.csv found locally. Will attempt fresh download."
  fi

  ## Download the latest csv file from the remote scp host
  log_message "INFO" "Attempting to download ${csv_filename}.csv"
  if ! rsync --archive --verbose --compress \
    --log-file="$rsync_log" \
    -e "ssh -i $SSH_PRIVATE_KEY_PATH -o StrictHostKeyChecking=no" \
    "${REMOTE_SCP_USER}@${REMOTE_SCP_HOST}:${REMOTE_CSV_PATH}/${csv_filename}.csv" "$local_csv_file"; then
    log_message "ERROR" "Failed to download ${csv_filename}.csv. See $rsync_log for details."
    # If rsync fails and there was an old file, restore it
    if [[ -f "$old_csv_file" ]]; then
      log_message "INFO" "Restoring original ${csv_filename}.csv from backup."
      mv "$old_csv_file" "$local_csv_file" || log_message "ERROR" "Failed to restore backup."
    fi
    return 1 # Indicate failure for this file
  fi
  log_message "INFO" "Downloaded ${csv_filename}.csv successfully."

  # If the force flag is not set, check if there is a diff
  if ! "$FORCE_IMPORT"; then
    if [[ -f "$old_csv_file" ]]; then
      if diff -q "$local_csv_file" "$old_csv_file" >/dev/null 2>&1; then
        log_message "INFO" "No updates detected for ${csv_filename}.csv. No import needed."
        rm -f "$old_csv_file" # Clean up the old file
        return 0 # Indicate success as no action was needed
      else
        log_message "INFO" "Changes detected in ${csv_filename}.csv. Proceeding with import."
      fi
    else
      log_message "INFO" "No old ${csv_filename}.csv to compare against. Proceeding with import."
    fi
  else
    log_message "INFO" "Force import enabled. Skipping difference check."
  fi

  # Import new csv file
  log_message "INFO" "Attempting to import ${csv_filename}.csv into MySQL."
  if mysqlimport --defaults-extra-file="$MYSQL_DEFAULTS_FILE" \
    -h "$MYSQL_HOST" -P "$MYSQL_PORT" --ignore CMES_mini --verbose \
    --local --ignore-lines=1 --lines-terminated-by='\n' --fields-terminated-by=',' \
    -c "$mysql_columns" "${local_csv_file}" >"$mysql_import_log" 2>&1; then
    log_message "INFO" "Successfully imported ${csv_filename}.csv."
    rm -f "$old_csv_file" # Clean up old file if import was successful
  else
    log_message "ERROR" "Failed to import ${csv_filename}.csv. See $mysql_import_log for details."
    log_message "INFO" "Moving failed CSV to ${base_name}.csv.bad"
    mv "$local_csv_file" "$bad_csv_file" || log_message "ERROR" "Failed to rename bad CSV."

    if [[ -f "$old_csv_file" ]]; then
      log_message "INFO" "Restoring original ${csv_filename}.csv from backup due to import failure."
      mv "$old_csv_file" "$local_csv_file" || log_message "ERROR" "Failed to restore original CSV."
    fi
    return 1 # Indicate failure for this file
  fi
}

# --- Main Execution Loop ---
# Define an associative array for easier management of files and their columns
declare -A csv_files=(
  ['Author']='AuthorID,AuthorFName,AuthorLName'
  ['CmesExtra']='Id,Title,FolderName'
  ['File']='FileID,TopicID,FileName,FileType,FileSize'
  ['Tag']='TagID,Tag'
  ['Topic']='TopicID,TopicName,TopicVolume,TopicIssue,TopicYear,TopicMonth,ContentProvider'
  ['TopicAuthor']='TopicID,AuthorID'
  ['TopicTag']='TopicID,TagID'
)

# Iterate over the associative array
overall_status=0 # 0 for success, 1 for failure
for file_name in "${!csv_files[@]}"; do
  if ! getCSV "$file_name" "${csv_files[$file_name]}"; then
    log_message "ERROR" "Processing of ${file_name}.csv failed."
    overall_status=1 # Set overall status to failure
  fi
done

if [[ "$overall_status" -eq 0 ]]; then
  log_message "INFO" "All CSV files processed successfully."
else
  log_message "ERROR" "One or more CSV file processes failed. Check logs for details."
fi

exit "$overall_status"