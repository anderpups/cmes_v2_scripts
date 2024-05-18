# configure mini

## TODO
- Make Policykit permissions stricter for cmes
- Prevent routing to other network devices when a hotspot

## Install ssh if needed
```bash
sudo apt install ssh -y
sudo systemctl enable ssh
sudo systemctl start ssh
```

## Configure hotspot

1. Create a file at `/etc/NetworkManager/system-connections/cmes-hotspot.nmconnection` with the below info.

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
    proto=wpa;
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

## Configure script

1. Place `wifi_switcher.sh` script on the mini.
2. Set the owner and permissions
    ```bash
    sudo chown root:root wifi_switcher.sh
    sudo chmod 755 wifi_switcher.sh
    ```
4. Install package to manage user permissions via PolicyKit. `sudo apt install polkitd-pkla -y`


3. Grant the user permission to make wifi changes

   *Still working on this for now do the following*

   Create a file at `/etc/NetworkManager/system-connections/cmes-hotspot.nmconnection` with the below info. This assumes the user running the script is `cmes`.

   *Needs to have stricter permissions*
   
   ```ini
   [Let cmes modify system settings for network]
   Identity=unix-user:cmes
   Action=org.freedesktop.NetworkManager.*
   ResultAny=yes
   ResultInactive=yes
   ResultActive=yes
   ```




