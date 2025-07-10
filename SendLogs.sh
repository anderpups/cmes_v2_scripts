#!/bin/bash
## Script to export logs from sql and upload via rsync
## v20250605

set -eo pipefail

## Yell if there is a flag
while getopts : flags; do
  case $flags in
    \?)
      echo "Invalid option: -$OPTARG"
      echo "usage: SendLogs.sh"
      echo ""
      echo "Used to export logs from mysql and upload"
      exit 1
      ;;
  esac
done

REMOTE_SCP_USER='cmesworldpi'
REMOTE_SCP_HOST='40.71.203.3'
REMOTE_LOG_PATH='/home/cmesworldpi/elif/CMES-mini-CodeBase/Usagelogs/'
SSH_PRIVATE_KEY_PATH='/home/pi/.ssh/id_rsa'

## file path due to --secure-file-priv
LOCAL_LOG_PATH='/var/lib/mysql-files'

MYSQL_HOST='localhost'
MYSQL_PORT='3306'
MYSQL_DEFAULTS_FILE='/home/pi/.mysql_defaults'

LOGS=("UserLogin" "UserSearch" "UserUsage" "TopTopic")

## Loop through LOGS array
for LOG in "${LOGS[@]}"; do
  ## Remove log file if needed
  if [ -f "/var/lib/mysql-files//${LOG}.csv" ]; then
    rm "/var/lib/mysql-files/${LOG}.csv"
  fi
  ## Export log file to 
  /usr/bin/mysql --defaults-extra-file="$MYSQL_DEFAULTS_FILE" \
  --host "localhost" --port "3306" --database CMES_mini \
  --execute "SELECT * FROM $LOG INTO OUTFILE '${LOCAL_LOG_PATH}/${LOG}.csv' FIELDS TERMINATED BY ',' ENCLOSED BY '\"' LINES TERMINATED BY '\n';"
  ## scp and rename file with hostname appended to name
  /usr/bin/scp -i "$SSH_PRIVATE_KEY_PATH" "${LOCAL_LOG_PATH}/${LOG}.csv" "${REMOTE_SCP_USER}@${REMOTE_SCP_HOST}:${REMOTE_LOG_PATH}/${LOG}_${HOSTNAME}.csv"
done
