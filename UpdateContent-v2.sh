#!/bin/sh 
#20250710

REMOTE_SCP_USER='cmesworldpi'
REMOTE_SCP_HOST='40.71.203.3'
REMOTE_CONTENT_PATHS='/home/cmesworldpi/elif/CMES-Pi/assets/Content/ :/home/cmesworldpi/elif/CMES-Pi/assets/VideoContent/'
SSH_PRIVATE_KEY_PATH='/home/pi/.ssh/id_rsa'

LOCAL_CONTENT_PATH='/var/www/html/CMES-Pi/assets/Content/'
LOG_PATH='/home/pi/Cron'

UPDATE_METADATA_SCRIPT_LOCATION='/home/pi/Cron/GetCSV.sh'
SENDLOGS_SCRIPT_LOCATION='/home/pi/Cron/SendLogs.sh'
WIFI_SWITCHER_SCRIPT_LOCATION='/home/pi/Cron/wifi_switcher.sh'


## Get flags
while getopts :mush flags; do
  case $flags in
    m)
      UPDATE_METADATA=true >&2
      ;;
    u)
      UPLOAD_LOGS=true >&2
      ;;
    s)
      SWITCH_WIFI=true >&2
      ;;
    h)
      echo "usage: UpdateContent-v2.sh [-x] [-h]" >&2
      echo ""  >&2
      echo "Updates CMES Content" >&2
      echo "" >&2
      echo "options" >&2
      echo "  -m"  >&2
      echo "     update metadata (run GetCSV.sh)" >&2
      echo "  -u"  >&2
      echo "     update metadata (run SendLogs.sh)" >&2
      echo "  -s"  >&2
      echo "     switch back to hotspot mode (run SendLogs.sh)" >&2
      echo "  -h" >&2
      echo "     display help message" >&2
      echo "" >&2
      echo "example" >&2
      echo "  wifi_switcher.sh -s 'wifi-network' -p 'test'" >&2
      echo "" >&2
      exit 0
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      echo "Use -h for more information" >&2
      exit 1
      ;;
  esac
done

## Get the number of files being synced.
NO_OF_FILES=$(/usr/bin/rsync --dry-run --recursive --update --times --stats -e "ssh -i $SSH_PRIVATE_KEY_PATH" ${REMOTE_SCP_USER}@${REMOTE_SCP_HOST}:${REMOTE_CONTENT_PATHS} ${LOCAL_CONTENT_PATH} | grep 'Number of created files' | awk '{print $5}'| sed 's/,//g')

if [ $NO_OF_FILES -gt 0 ]; then
  /usr/bin/rsync --recursive --update --times --info=progress -e "ssh -i $SSH_PRIVATE_KEY_PATH" ${REMOTE_SCP_USER}@${REMOTE_SCP_HOST}:${REMOTE_CONTENT_PATHS} ${LOCAL_CONTENT_PATH} | stdbuf --output=0  sed "s/^.*xfr#\(.*\),.*/\1\/$NO_OF_FILES/" > "${LOG_PATH}/UpdateContent_status.txt"
fi

## Update metadata if -m flag is set
if  [ "${UPDATE_METADATA+set}" ]; then
  echo 'Updating metadata' > "${LOG_PATH}/UpdateContent_status.txt"
  "$UPDATE_METADATA_SCRIPT_LOCATION"
fi

## Upload logs if -u flag is set
if  [ "${UPLOAD_LOGS+set}" ]; then
  echo 'Uploading logs' > "${LOG_PATH}/UpdateContent_status.txt"
  "$SENDLOGS_SCRIPT_LOCATION"
fi

## Set the wifi back to hotspot if -s flag is set
if  [ "${SWITCH_WIFI+set}" ]; then
  echo 'Switching wifi' > "${LOG_PATH}/UpdateContent_status.txt"
  "$WIFI_SWITCHER_SCRIPT_LOCATION" "-d"
fi

echo 'All files synced' > "${LOG_PATH}/UpdateContent_status.txt"
