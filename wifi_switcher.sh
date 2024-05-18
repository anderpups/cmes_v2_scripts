#!/bin/bash
set -euo pipefail
## Script that will connect you to a wifi profile.

## Declare the name of the hotspot connection profile
HOTSPOT_PROFILE='cmes-hotspot'

## Get flags from script
while getopts :hs:p:d flags; do
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
    h)
      echo "usage: wifi_switcher.sh [-h] [-s 'SSID'] [-p 'PASSWORD'] [-d] [-h]" >&2
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
      echo "     disconnect from wireless netwok" >&2
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
  nmcli con down "$HOTSPOT_PROFILE"
  ## Pause for three seconds
  sleep 3
  ## Connect to wifi
  nmcli device wifi connect "$SSID" password "$PASSWORD"
  exit 0
fi

## Disconnect from wireless network
if  [ "${DISCONNECT+set}" ]; then
  ## get the active SSID
  SSID=$({ iwgetid -r || true; })
  ## Delete that connection
  if [[ "$SSID" != "$HOTSPOT_PROFILE" && "$SSID" != '' ]]; then
    nmcli con delete "$SSID"
    ## Bring up WIFI profile
    nmcli con up "$HOTSPOT_PROFILE"
  else
  echo "$HOTSPOT_PROFILE already active"
  fi
  exit 0
fi

echo "Something went wrong! Run with -d to enable default wireless profile"
exit 1
