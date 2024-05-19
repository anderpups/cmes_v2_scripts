I was able to allow connection to http://192.168.4.1 but not the internet.
Need to test more. Check if mini can still connect to internet.

These need to be done in the correct order
```bash
sudo ufw allow ssh
sudo ufw allow proto tcp from 192.168.4.1/24 to 192.168.4.1 port 80
sudo ufw deny proto any from 192.168.4.1/24 to 0.0.0.0/0
sudo ufw enable
sudo systemctl enable ufw
```