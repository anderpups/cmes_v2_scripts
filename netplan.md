# cmes_mini_wifi for Netplan on Ubuntu Desktop

1. Create `/etc/netplan/02-wifi-access-point.yaml` and chmod 600
    ```yaml
    network:
      wifis:
        all-wlans:
          match:
            name: '*'
          dhcp4: true
          addresses: [192.168.4.1/24]
          access-points:
            "cmes":
              password: "pionthefly"
              mode: ap
    ```