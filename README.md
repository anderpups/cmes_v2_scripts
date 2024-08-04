# configure mini

## Install ssh if needed
```bash
sudo apt install ssh -y
sudo systemctl enable ssh
sudo systemctl start ssh
```

## Enable and Start resolved.service

This wasn't needed for the mini, but on the Pi you will need to enable and start resolved.service

```bash
sudo systemctl start systemd-resolved.service
sudo systemctl enable systemd-resolved.service
```

## Configure hotspot

1. Create a file at `/etc/NetworkManager/system-connections/cmes-hotspot.nmconnection` with the below info.

    If you are configuring for the Pi you will need to replace `wlo1` with `wlan0`

    ```ini
    [connection]
    id=cmes-hotspot
    type=wifi
    interface-name=wlo1

    [ipv4]
    method=shared
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
    proto=wpa
    ```

2. Set the owner and permissions
    ```bash
    sudo chown root:root /etc/NetworkManager/system-connections/cmes-hotspot.nmconnection
    sudo chmod 600 /etc/NetworkManager/system-connections/cmes-hotspot.nmconnection
    ```

3. Generate and apply new netplan config
    ```bash
    sudo netplan generate
    sudo netplan apply
    ```

4. Confirm cmes-hostpot is active
    ```bash
    cmes@cmes-U59:~$ nmcli con show --active
    NAME            UUID                                  TYPE      DEVICE 
    cmes-hotspot    d2ab13be-53e1-3ab9-82c4-fd41fb10684e  wifi      wlo1   
    ```

## Configure Firewall

Run the following commands to configure firewall

1. `sudo ufw allow in on wlo1` Allows access from hotspot clients.  If you are configuring for the Pi you will need to replace `wlo1` with `wlan0`
2. `sudo ufw allow ssh` Allows ssh
3. `sudo ufw allow proto tcp from 192.168.4.1/24 to 192.168.4.1 port 80` Allows hotspot clients access CMES site
4. `sudo ufw deny proto any from 192.168.4.1/24 to 0.0.0.0/0` Deny all other access for hotspot clients
5. `sudo ufw enable` # Enables the firewall in runtime
6. `sudo systemctl enable ufw` # Enables firewall at boot

## Configure script

1. Place `wifi_switcher.sh` script on the mini.
2. Set the owner and permissions
    ```bash
    sudo chown root:root wifi_switcher.sh
    sudo chmod 755 wifi_switcher.sh
    ```
4. Install package to manage user permissions via PolicyKit. `sudo apt install polkitd-pkla -y`


3. Grant the user permission to make Wi-Fi changes

   Create a file at `/etc/polkit-1/localauthority/50-local/10-cmes.network-permissions.pkla` with the below info. This assumes the user running the script is `cmes`.

   ```ini
   [Let cmes modify system settings for network]
   Identity=unix-user:cmes
   Action=org.freedesktop.NetworkManager.settings.modify.system;org.freedesktop.NetworkManager.network-control;org.freedesktop.NetworkManager.wifi.share.protected;org.freedesktop.NetworkManager.enable-disable-wifi
   ResultAny=yes
   ResultInactive=yes
   ResultActive=yes
   ```

4. Run the script with required flags. You can run `wifi_switcher.sh -h` for help.
