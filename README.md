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

    Note: If you are configuring for the Pi you will need to replace `wlo1` with `wlan0`

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

1. Allow access from hotspot clients.
    - for mini: `sudo ufw allow in on wlo1`
    - for pi: `sudo ufw allow in on wlan0`
1. Allow ssh

    `sudo ufw allow ssh` 
1. Allow hotspot clients access CMES site
  
    `sudo ufw allow proto tcp from 192.168.4.0/24 to 192.168.4.1 port 80`
1. Allow clients connecting from the ethernet connection
    - for mini: 
      - `sudo ufw allow in on enp1s0`
      - `sudo ufw allow in on enp2s0`
    - for pi: `sudo ufw allow in eth0`
1.  Deny access to internet for hotspot clients

    `sudo ufw deny proto any from 192.168.4.0/24 to 0.0.0.0/0`
1. Enable the firewall in runtime

    `sudo ufw enable`

## Configure script

1. Place `wifi_switcher.sh` script on the mini.
1. Set the owner and permissions
    ```bash
    sudo chown root:root wifi_switcher.sh
    sudo chmod 755 wifi_switcher.sh
    ```
1. Install package to manage user permissions via PolicyKit. `sudo apt install polkitd-pkla -y`


1. Grant the user permission to make Wi-Fi changes

   1. Create folder `sudo mkdir /etc/polkit-1/localauthority/50-local`.

   1. Create a file at `/etc/polkit-1/localauthority/50-local/10-pi.network-permissions.pkla` with the below info. This assumes the user running the script is `pi`.

       ```ini
       [Let pi user modify system settings for network]
       Identity=unix-user:pi
       Action=org.freedesktop.NetworkManager.settings.modify.system;org.freedesktop.NetworkManager.network-control;org.freedesktop.NetworkManager.wifi.share.protected;org.freedesktop.NetworkManager.enable-disable-wifi
       ResultAny=yes
       ResultInactive=yes
       ResultActive=yes
       ```

4. Run the script with required flags. You can run `wifi_switcher.sh -h` for help.
