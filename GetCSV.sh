#!/bin/bash
## Script to download and import CSV files into sql db
## v20250710

set -eo pipefail

## Get flags from script
while getopts :h:f flags; do
  case $flags in
    f)
      FORCE=true
      ;;
    h)
      echo "usage: GetCSV.sh [-h] [-f]"
      echo ""
      echo "Used to download csv files from cmes server and import them into mysql"
      echo ""
      echo "options"
      echo "  -f"
      echo "     Force import of files even if there isn't a change to the csv file"
      echo "  -h"
      echo "     display help message"
      exit 0
      ;;
    \?)
      echo "Invalid option: -$OPTARG"
      exit 1
      ;;
  esac
done

REMOTE_SCP_USER='cmesworldpi'
REMOTE_SCP_HOST='40.71.203.3'
REMOTE_CSV_PATH='/home/cmesworldpi/elif/CMES-mini/assets/csv/'
SSH_PRIVATE_KEY_PATH='/home/pi/.ssh/id_rsa'

LOCAL_CSV_PATH='/var/www/html/CMES-Pi/assets/csv/'
LOG_PATH='/var/www/html/CMES-Pi/assets/Log/'

MYSQL_HOST='localhost'
MYSQL_PORT='3306'
MYSQL_DEFAULTS_FILE='/home/pi/.mysql_defaults'

function getCSV {
  ## Check if the csv file exists
  if [ -f "${LOCAL_CSV_PATH}/${1}.csv" ]; then
    echo "Copying ${1}.csv to ${1}.csv.old"
    ## Copy existing to .old
    /usr/bin/cp -f ${LOCAL_CSV_PATH}/${1}.csv ${LOCAL_CSV_PATH}/${1}.csv.old
  fi

  ## Check and grab the latest csv file from the remote scp host
  echo "Attempting to download ${1}.csv"
  if /usr/bin/rsync --log-file "${LOG_PATH}/csvTo${1}.log" -e "ssh -i $SSH_PRIVATE_KEY_PATH" \
    -t "${REMOTE_SCP_USER}@${REMOTE_SCP_HOST}:${REMOTE_CSV_PATH}/${1}.csv" "${LOCAL_CSV_PATH}/${1}.csv"; then
    echo "Downloaded ${1}.csv"
  else
    ## Fail if the rsync commnad fails
    echo "Failed to download ${1}.csv"
    echo "Look at ${LOG_PATH}csvTo${1}.log for more information"
    return 1
  fi
  # If the force flag is not set, check if there is a diff
  if [ -z "$FORCE" ]; then
    # Check if the .old file exists
    if [ -f "${LOCAL_CSV_PATH}/${1}.csv.old" ]; then
      # return 0 if the new and old csvs are identical
      if /usr/bin/diff -q "${LOCAL_CSV_PATH}/${1}.csv" "${LOCAL_CSV_PATH}/${1}.csv.old" 2>&1 >/dev/null; then
        echo There have been no updates to ${1}.csv. No action taken | tee "${LOG_PATH}/csvTo${1}.log"
        rm "${LOCAL_CSV_PATH}/${1}.csv.old"
        return 0
      fi
    fi
  fi

  # import new csv file
  echo "Attempting to import ${1}.csv"
  if /usr/bin/mysqlimport --defaults-extra-file="$MYSQL_DEFAULTS_FILE" \
    -h "$MYSQL_HOST" -P "$MYSQL_PORT" --ignore CMES_mini --verbose --local --ignore-lines=1 --lines-terminated-by='\n' --fields-terminated-by=',' \
    -c "${2}" "${LOCAL_CSV_PATH}${1}.csv" >"${LOG_PATH}/csvTo${1}.log" 2>&1; then
    ## If import was successful
    if [ -f "${LOCAL_CSV_PATH}/${1}.csv.old" ]; then
      ## Delete old file
      rm "${LOCAL_CSV_PATH}/${1}.csv.old"
    fi
    echo "Completed import of ${1}.csv"
  else
    ## If sql import fails
    ## Move failed csv file to .bad
    mv "${LOCAL_CSV_PATH}/${1}.csv" "${LOCAL_CSV_PATH}/${1}.csv.bad"
    echo "Failed to import ${1}.csv"
    echo "The failed csv has been renamed ${1}.csv.bad"
    if [ -f "${LOCAL_CSV_PATH}/${1}.csv.old" ]; then
      ## Reset the csv file to the old copy
      mv "${LOCAL_CSV_PATH}/${1}.csv.old" "${LOCAL_CSV_PATH}/${1}.csv"
      echo "The original csv has been restored"
    fi
    echo "Look at ${LOG_PATH}csvTo${1}.log for more information"
    return 1
  fi
}

# Call the function with arguments fo each of the files and their columns used for sql import
getCSV 'Author' 'AuthorID,AuthorFName,AuthorLName'
getCSV 'CmesExtra' 'Id,Title,FolderName'
getCSV 'File' 'FileID,TopicID,FileName,FileType,FileSize'
getCSV 'Tag' 'TagID,Tag'
getCSV 'Topic' 'TopicID,TopicName,TopicVolume,TopicIssue,TopicYear,TopicMonth,ContentProvider'
getCSV 'TopicAuthor' 'TopicID,AuthorID'
getCSV 'TopicTag' 'TopicID,TagID'
