# cmes_mini_wifi
Notes and stuff for cmes_mini wifi

1. apt install network-manager
1. touch /etc/NetworkManager/conf.d/10-globally-managed-devices.conf
1. nmcli dev set enp1s0 managed yes # This doesn't survive reboot
1. nmcli dev set enp2s0 managed yes # This doesn't survive reboot
1. systemctl restart NetworkManager
1. Connect and disconnect from wifi
    ```bash
     nmcli device wifi connect 'SSID' password 'xx'
     nmcli con delete 'SSID'
    ```
1. AP config should be in `/etc/NetworkManager/system-connections/cmes-hotspot.nmconnection` and look something like this
Right now routing to internet through the ethernet port is still working. Needto figure out how to block that.

```ini
[connection]
id=cmes-hotspot
type=wifi
interface-name=wlo1

[ipv4]
method=auto
address1=192.168.4.1/24

[ipv6]
method=disabled

[wifi]
ssid=CMES
mode=ap

[wifi-security]
key-mgmt=wpa-psk
psk=pionthefly
pmf=1 # For Android devices
proto=wpa;
```
