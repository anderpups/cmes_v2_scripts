#!/bin/bash
#v20250710

set -euo pipefail
## Script that will connect you to a wifi profile.

## Declare the name of the hotspot connection profile
HOTSPOT_PROFILE='cmes-hotspot'
## Declare the location of status file
STATUS_FILE_LOCATION="$HOME/Cron/wifi_status.txt"
## Declare the location of the UpdateContent.sh script
UPDATE_CONTENT_SCRIPT_LOCATION="$HOME/Cron/UpdateContent-v2.sh"
UPDATE_CONTENT=true

## Get flags from script
while getopts :hdxs:p: flags; do
  case $flags in
    s)
      SSID=$OPTARG >&2
      ;;
    p)
      PASSWORD=$OPTARG >&2
      ;;
    d)
      DISCONNECT=true >&2
      ;;
    x)
      UPDATE_CONTENT=false >&2
      ;;
    h)
      echo "usage: wifi_switcher.sh [-h] [-s 'SSID'] [-p 'PASSWORD'] [-d] [-h] [-x]" >&2
      echo ""  >&2
      echo "Connects and disconnects from a wireless network." >&2
      echo "Both the SSID and password need to be wrapped in single quotes." >&2
      echo "" >&2
      echo "options" >&2
      echo "  -s 'SSID'" >&2
      echo "     SSID for wireless network." >&2
      echo "  -p 'PASSWORD'" >&2
      echo "     password for wireless network" >&2
      echo "  -d"  >&2
      echo "     disconnect from wireless network" >&2
      echo "  -x"  >&2
      echo "     disables updating content" >&2
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

## Check to make sure the correct flags are passed
if  [ -z "${DISCONNECT+set}" ]; then
  if [[ -z "${SSID+set}" || -z "${PASSWORD+set}" || $OPTIND -eq 1 ]]; then
    echo "The needed flags were not passed to the script"
    echo "Use -h for more information" >&2
    exit 1
  fi
fi

## Check to make sure -d is exclusive 
if  [[ "${DISCONNECT+set}" && ( "${SSID+set}" || "${PASSWORD+set}" ) ]]; then
    echo "The -d flag can not be used with any other flag"
    echo "Use -h for more information" >&2
    exit 1
fi

## Set the wireless network
if  [ -z "${DISCONNECT+set}" ]; then
  if $(nmcli -t -f active,name con | grep '^yes' | grep -q "$HOTSPOT_PROFILE"); then
    nmcli con down "$HOTSPOT_PROFILE" || true
  fi
  ## Pause for three seconds
  sleep 3
  ## Check if already connected.
  if $(nmcli -t -f active,name con | grep '^yes' | grep -q "$SSID"); then
    echo "Already connected to $SSID network as a client!"
  else
    ## Connect to wifi, delete profile and switch back to hotspot profile if failed
    nmcli device wifi connect "$SSID" password "$PASSWORD" || \
      (echo "Connection to $SSID failed."; nmcli con delete "$SSID"; nmcli con up "$HOTSPOT_PROFILE"; \
      echo "Hotspot is active" > "$STATUS_FILE_LOCATION"; exit 1)
  fi
  ## Trigger Update_Content Script unless -x flag is set
  if [ "$UPDATE_CONTENT" = true ]; then
    echo 'Updating content'
    "$UPDATE_CONTENT_SCRIPT_LOCATION" "-m" "-u" "-s" &>/dev/null & disown
  fi

  echo "Connected to $SSID network as a client" > "$STATUS_FILE_LOCATION"
  exit 0
fi

## Disconnect from wireless network
if  [ "${DISCONNECT+set}" ]; then
  ## Test whether $HOTSPOT_PROFILE is active
  if $(nmcli -t -f active,name con | grep '^yes' | grep -q "$HOTSPOT_PROFILE"); then
    echo "$HOTSPOT_PROFILE already active"
    echo "Hotspot is active" > "$STATUS_FILE_LOCATION"
    ## Bring up WIFI profile
  else
    ## Check if there is an active connection
    if $(nmcli -t -f active dev wifi | grep -qE '^yes'); then
      ## Get active connection
      ACTIVE_SSID=$(nmcli -t -f active,ssid dev wifi | grep -E '^yes' | awk -F ':' '{print $2}')
      ## Delete that connection
      nmcli con delete "$ACTIVE_SSID" || true #Always complete so we can try to bring the profile back up
    fi
    ## Bring up WIFI profile
    nmcli con up "$HOTSPOT_PROFILE"
  fi
  echo "Hotspot is active" > "$STATUS_FILE_LOCATION"
  exit 0
fi

echo "Something went wrong! Run with -d to enable default wireless profile"
echo "Wifi settings are inconsistent, please toggle the wifi to reset" > "$STATUS_FILE_LOCATION"
exit 1
