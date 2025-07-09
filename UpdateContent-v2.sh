#!/bin/sh 
#20250709

REMOTE_SCP_USER='cmesworldpi'
REMOTE_SCP_HOST='40.71.203.3'
REMOTE_CONTENT_PATHS='/home/cmesworldpi/elif/CMES-Pi/assets/Content/ :/home/cmesworldpi/elif/CMES-Pi/assets/VideoContent/'
SSH_PRIVATE_KEY_PATH='/home/pi/.ssh/id_rsa'

LOCAL_CONTENT_PATH='/var/www/html/CMES-Pi/assets/Content/'
LOG_PATH='/home/pi/Cron'

NO_OF_FILES=$(/usr/bin/rsync --dry-run --recursive --update --times --stats -e "ssh -i $SSH_PRIVATE_KEY_PATH" ${REMOTE_SCP_USER}@${REMOTE_SCP_HOST}:${REMOTE_CONTENT_PATHS} ${LOCAL_CONTENT_PATH} | grep 'Number of created files' | awk '{print $5}'| sed 's/,//g')

if [ $NO_OF_FILES -gt 0 ]; then
  /usr/bin/rsync --recursive --update --times --info=progress -e "ssh -i $SSH_PRIVATE_KEY_PATH" ${REMOTE_SCP_USER}@${REMOTE_SCP_HOST}:${REMOTE_CONTENT_PATHS} ${LOCAL_CONTENT_PATH} | stdbuf --output=0  sed "s/^.*xfr#\(.*\),.*/\1\/$NO_OF_FILES/" > "${LOG_PATH}/UpdateContent_status.txt"
fi

echo 'All files synced' > "${LOG_PATH}/UpdateContent_status.txt"
