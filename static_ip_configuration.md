# Static IP Configuration Guide

This comprehensive guide will help you configure ethernet ports to use static IP addresses on Linux systems using NetworkManager.

## ⚠️ Important Warning

**Only perform this configuration if you have direct console access to the host**, as incorrect network settings can disconnect you from the system remotely.

> **Note:** If you must configure over SSH, ensure you are NOT connecting through the network interface you plan to make static, as this will disconnect your session.

## Prerequisites

Before starting, ensure you have:

- **Root/sudo access** to the system
- **Direct console access** (not SSH) in case of configuration errors
- **A reserved static IP address** on your local network (coordinate with network administrator)
- **Default gateway** IP address for your local network (typically the first usable IP, e.g., 192.168.1.1)
- **DNS server IP addresses** (typically your router's IP like 192.168.1.1, or public DNS like 8.8.8.8)
- **Network prefix size** for your local network (usually /24 for home networks)

## Step-by-Step Configuration

### Step 1: Gather Network Information

**How to find the network interfaces:**

```bash
# Get the ethernet device names
sudo nmcli device status | grep ethernet | awk '{print $1}'
```

**Example output:**

```
enp1s0
enp2s0
```

**How to find the gateway:**

```bash
route -n | grep 'UG[ \t]' | awk '{print $2}'
```

Check for the default route associated with the router on the network

**How to find the network prefix:**

Check current network configuration for a specific device

```bash
ip addr show enp1s0
```

Look for entries like: 192.168.1.89/24 (where /24 is the prefix)

### Step 2: Remove Existing Network Connections

First, check for existing connections:

```bash
# List all current connections
sudo nmcli connection show
```

If there is an active connection associated with the device, delete it. Replace `netplan-enp1s0` with the actual connection name from the output above:

```bash
# Delete existing connection (replace with actual connection name)
sudo nmcli connection delete netplan-enp1s0
```

### Step 3: Create New Static IP Connection

Create a new NetworkManager connection with static IP configuration. **Customize the following parameters:**

- **con-name & ifname**: Replace with your device name (e.g., `enp1s0`)
- **ipv4.address**: Replace with your static IP and network prefix (e.g., `192.168.1.202/24`)
- **ipv4.gateway**: Replace with your gateway IP (e.g., `192.168.1.1`)
- **ipv4.dns**: Replace with your DNS servers (e.g., `8.8.8.8`)

```bash
sudo nmcli con add type ethernet \
  con-name enp1s0 \
  ifname enp1s0 \
  ipv4.method manual \
  ipv4.address 192.168.1.202/24 \
  ipv4.gateway 192.168.1.1 \
  ipv4.dns 8.8.8.8
```

> ⚠️ **Warning:** This command will immediately apply the network configuration and may disconnect your current session if done over SSH.

### Step 4: Verify the Configuration

Test your network connection to ensure everything is working properly:

```bash
# Check interface status and IP assignment
ip addr show enp1s0

# Test internet connectivity
ping -c 4 8.8.8.8

# Test DNS resolution
nslookup google.com

# Verify routing table
ip route show

# Check NetworkManager connection status
sudo nmcli connection show
```

**Expected results:**

- `ip addr show` should display your static IP address
- `ping` should receive 4 successful replies
- `nslookup` should resolve google.com to an IP address
- `ip route show` should show your gateway in the default route

## Troubleshooting

### Common Issues and Solutions

**1. Connection doesn't activate**

```bash
# Check NetworkManager logs for errors
sudo journalctl -u NetworkManager -f

# Verify connection status
sudo nmcli connection show

# Try to manually activate the connection
sudo nmcli connection up enp1s0
```

**2. IP conflict detected**

```bash
# Check for IP conflicts on the network
sudo arping -c 3 192.168.1.202

# If conflict exists, choose a different IP address and recreate the connection
```

**3. DNS not working**

```bash
# Test DNS resolution
nslookup google.com

# Check DNS configuration
cat /etc/resolv.conf

# Manually test DNS servers
nslookup google.com 8.8.8.8
```

**4. Gateway not reachable**

```bash
# Test gateway connectivity
ping -c 4 192.168.1.1

# Check routing table
ip route show

# Verify gateway IP is correct for your network
```

## Multiple Interface Configuration

For systems with multiple ethernet ports, repeat the process for each interface:

```bash
# Configure second interface with different static IP
sudo nmcli con add type ethernet \
  con-name enp2s0 \
  ifname enp2s0 \
  ipv4.method manual \
  ipv4.address 192.168.1.203/24 \
  ipv4.gateway 192.168.1.1 \
  ipv4.dns 8.8.8.8
```

## Reverting to DHCP

If you need to revert back to automatic IP assignment:

```bash
# Delete the static connection
sudo nmcli connection delete enp1s0

# Create a new DHCP connection
sudo nmcli con add type ethernet con-name enp1s0 ifname enp1s0 ipv4.method auto

# Activate the connection
sudo nmcli connection up enp1s0
```

## Additional Configuration Options

### Adding Multiple DNS Servers

```bash
# Add multiple DNS servers (comma-separated)
sudo nmcli con modify enp1s0 ipv4.dns "192.168.1.1,8.8.8.8,8.8.4.4"
```

### Setting Connection Priority

```bash
# Set connection priority (lower number = higher priority)
sudo nmcli con modify enp1s0 connection.autoconnect-priority 10
```

### Auto-connect Settings

```bash
# Enable auto-connect on boot
sudo nmcli con modify enp1s0 connection.autoconnect yes

# Disable auto-connect
sudo nmcli con modify enp1s0 connection.autoconnect no
```

## Useful Commands Reference

```bash
# Show all network devices
nmcli device status

# Show all connections
nmcli connection show

# Show detailed connection info
nmcli connection show enp1s0

# Restart NetworkManager service
sudo systemctl restart NetworkManager

# Check NetworkManager status
sudo systemctl status NetworkManager
```

---
