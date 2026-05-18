# Training_1 VM Internet Connectivity Troubleshooting Guide

**Date:** 2026-04-29  
**Objective:** Enable internet connectivity for training_1 VM (192.168.50.20)  
**Current Status:** VM not responding to ping tests

## Current State

### Connectivity Tests (✓ = Working, ✗ = Failed)
- ✓ Host → pfSense LAN (192.168.10.1): **Working**
- ✓ Host → pfSense Training Gateway (192.168.50.1): **Working**
- ✗ Host → training_1 VM (192.168.50.20): **NOT responding**

### pfSense Configuration
- **OPT1 Interface (Training LAN)**: Enabled and operational
- **IP Address**: 192.168.50.1/24
- **Firewall Rules on OPT1**:
  - "Allow TRAINING-LAN to any" (pass any → any)
  - "Allow ICMP to TRAINING-LAN gateway" (pass icmp → opt1)

### Known Issues
1. **training_1 VM not responding** - Primary blocker
2. **NAT API endpoints return 404** - Cannot verify/configure NAT via API
3. **VM status check requires elevated privileges** - Cannot confirm VM power state programmatically

## Root Cause Analysis

The training_1 VM is not responding, which indicates one or more of the following:

1. **VM is powered off or suspended**
2. **VM network adapter not connected** to training-vm-lan-new switch
3. **VM internal network configuration incorrect**:
   - IP address not set to 192.168.50.20
   - Subnet mask not 255.255.255.0
   - Gateway not set to 192.168.50.1
   - DNS servers not configured
4. **pfSense NAT not configured** for 192.168.50.0/24 subnet
5. **VM firewall blocking ICMP** (less likely but possible)

## Troubleshooting Steps

### Step 1: Verify training_1 VM is Running

**Via Hyper-V Manager (GUI):**
1. Open Hyper-V Manager
2. Locate `training_1` VM
3. Check Status column - should show "Running"
4. If not running:
   - Right-click → Start
   - Wait for VM to fully boot

**Via PowerShell (requires Administrator):**
```powershell
# Run PowerShell as Administrator
Get-VM -Name training_1 | Select-Object Name, State, Uptime, Status

# If VM is off, start it:
Start-VM -Name training_1

# Verify network adapter:
Get-VMNetworkAdapter -VMName training_1 | Format-Table VMName, Name, SwitchName, MacAddress, IPAddresses
```

**Expected Result:**
- State: `Running`
- SwitchName: `training-vm-lan-new`
- Uptime: > 0

### Step 2: Check VM Network Configuration (Inside the VM)

**Connect to training_1 VM:**
1. Open Hyper-V Manager
2. Right-click `training_1` → Connect
3. Log into the VM

**Verify Network Configuration (Linux VM):**
```bash
# Check IP address
ip addr show

# Should show:
# - Interface with IP 192.168.50.20/24
# - Gateway 192.168.50.1

# Check gateway
ip route show default

# Should show:
# default via 192.168.50.1 dev <interface>

# Check DNS
cat /etc/resolv.conf

# Should contain nameservers like:
# nameserver 8.8.8.8
# nameserver 8.8.4.4
```

**Verify Network Configuration (Windows VM):**
```powershell
# Check IP configuration
ipconfig /all

# Should show:
# - IPv4 Address: 192.168.50.20
# - Subnet Mask: 255.255.255.0
# - Default Gateway: 192.168.50.1
# - DNS Servers: 8.8.8.8, 8.8.4.4 (or similar)
```

**If network is not configured, set it manually:**

**Linux:**
```bash
# Temporary configuration (lost on reboot)
sudo ip addr add 192.168.50.20/24 dev eth0
sudo ip route add default via 192.168.50.1
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf

# Test connectivity
ping -c 3 192.168.50.1    # Gateway
ping -c 3 8.8.8.8          # Internet
```

**Windows:**
```powershell
# Set static IP
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.50.20 -PrefixLength 24 -DefaultGateway 192.168.50.1

# Set DNS
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses ("8.8.8.8","8.8.4.4")

# Test connectivity
Test-Connection 192.168.50.1  # Gateway
Test-Connection 8.8.8.8       # Internet
```

### Step 3: Configure pfSense Outbound NAT

**NOTE:** The pfSense API v2.6.4 does NOT expose NAT configuration endpoints. You must configure NAT via the web UI.

**Access pfSense Web UI:**
1. Open browser: `http://192.168.10.1` or `https://192.168.10.1`
2. Login with: `admin` / `password`

**Check Current NAT Configuration:**
1. Navigate to: **Firewall → NAT → Outbound**
2. Check **Outbound NAT Mode**:
   - **Automatic outbound NAT rule generation** (recommended for most setups)
   - **Hybrid Outbound NAT** (automatic + manual rules)
   - **Manual Outbound NAT** (you control all rules)

**Recommended Configuration:**

**Option A: Automatic NAT (Easiest)**
1. Go to **Firewall → NAT → Outbound**
2. Select **"Automatic outbound NAT rule generation"**
3. Click **Save**
4. Click **Apply Changes**
5. This will automatically create NAT rules for all internal networks (including 192.168.50.0/24)

**Option B: Manual NAT Rule (More Control)**
1. Go to **Firewall → NAT → Outbound**
2. Select **"Hybrid Outbound NAT"** or **"Manual Outbound NAT"**
3. Click **Add** (up arrow to add rule to top)
4. Configure rule:
   - **Interface:** `WAN`
   - **Protocol:** `any`
   - **Source:**
     - Type: `Network`
     - Network: `192.168.50.0`
     - CIDR: `/24`
   - **Destination:** `any`
   - **Translation:**
     - Address: `Interface Address` (WAN address)
   - **Description:** `NAT Training LAN to Internet`
   - **NAT Reflection:** `Enable` (optional)
5. Click **Save**
6. Click **Apply Changes**

**Verify NAT Rule:**
- Look for rule matching source `192.168.50.0/24` with destination `any` on WAN interface
- Rule should be enabled (no disabled icon)

### Step 4: Test Connectivity

**From Hyper-V Host:**
```powershell
# Test each hop
ping 192.168.50.1         # pfSense gateway - should work
ping 192.168.50.20        # training_1 VM - should work after fixes
ping 8.8.8.8              # Internet via training LAN routing
```

**From training_1 VM:**
```bash
# Linux
ping -c 3 192.168.50.1    # Gateway
ping -c 3 8.8.8.8          # Internet DNS
ping -c 3 google.com       # Domain resolution

# Windows
Test-Connection 192.168.50.1
Test-Connection 8.8.8.8
Test-Connection google.com
```

**From Host - Check pfSense Firewall States:**
```powershell
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('admin:password'))
$h=@{Authorization="Basic $b64"}
$states = (Invoke-WebRequest -Uri 'http://192.168.10.1/api/v2/firewall/states' -Headers $h -UseBasicParsing).Content | ConvertFrom-Json

# Look for states from training_1 VM
$states.data | Where-Object { $_.src -like "192.168.50.20*" } | Format-Table src,dst,proto,state -AutoSize
```

### Step 5: Troubleshooting if Still Not Working

**If gateway ping fails (192.168.50.1):**
- Check Step 2 - VM network configuration likely wrong
- Verify VM is on correct virtual switch (`training-vm-lan-new`)
- Restart network service in VM

**If gateway works but internet fails:**
- NAT not configured (go to Step 3)
- DNS not set in VM (go to Step 2)
- Default gateway not set in VM (go to Step 2)
- WAN interface on pfSense not working (check pfSense Status → Interfaces)

**If ping to VM (192.168.50.20) fails from host:**
- VM powered off (Step 1)
- VM firewall blocking ICMP
  - Linux: `sudo iptables -L INPUT` (check for ICMP blocks)
  - Windows: Check Windows Defender Firewall settings
- Wrong IP address configured in VM

## Verification Checklist

Once configured, verify all these work:

- [ ] training_1 VM is powered on and running
- [ ] VM has network adapter connected to `training-vm-lan-new`
- [ ] VM has IP 192.168.50.20/24 configured
- [ ] VM has gateway 192.168.50.1 configured
- [ ] VM has DNS servers configured (8.8.8.8, 8.8.4.4, or pfSense IP)
- [ ] Host can ping 192.168.50.20
- [ ] VM can ping 192.168.50.1 (gateway)
- [ ] VM can ping 8.8.8.8 (internet)
- [ ] VM can resolve domain names (ping google.com)
- [ ] pfSense NAT is configured (Automatic or Manual rule)
- [ ] pfSense firewall shows active states from 192.168.50.20

## API Limitations

The pfSense API v2.6.4 has the following limitations for this task:

- **No NAT endpoints**: `/api/v2/firewall/nat/outbound` returns 404
- **No routing gateway endpoints**: `/api/v2/routing/gateway` returns 400
- **VM management requires elevation**: Cannot use Hyper-V cmdlets without Administrator privileges

**Workarounds:**
- NAT must be configured via pfSense web UI
- VM status must be checked via Hyper-V Manager GUI or elevated PowerShell
- Firewall states can be checked via `/api/v2/firewall/states` to see active connections

## Quick Reference Commands

**PowerShell (Host):**
```powershell
# Check connectivity
ping 192.168.50.1   # Gateway
ping 192.168.50.20  # VM

# Check pfSense firewall rules
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('admin:password'))
$h=@{Authorization="Basic $b64"}
(Invoke-WebRequest -Uri 'http://192.168.10.1/api/v2/firewall/rules' -Headers $h -UseBasicParsing).Content | ConvertFrom-Json | Select-Object -ExpandProperty data | Where-Object { $_.interface -eq 'opt1' } | Format-Table tracker,descr,source,destination,disabled

# Check active firewall states
(Invoke-WebRequest -Uri 'http://192.168.10.1/api/v2/firewall/states' -Headers $h -UseBasicParsing).Content | ConvertFrom-Json | Select-Object -ExpandProperty data | Where-Object { $_.src -like "192.168.50.*" }

# Check VM (requires Administrator)
Get-VM -Name training_1 | Select-Object Name,State,Uptime
Get-VMNetworkAdapter -VMName training_1 | Select-Object SwitchName,MacAddress,IPAddresses
```

## Next Steps

1. **Immediate:** Follow Steps 1-4 above to get training_1 VM online
2. **Document:** Once working, document the final configuration in this file
3. **Automate:** Consider creating PowerShell script to verify training_1 connectivity and NAT configuration
4. **Monitor:** Set up regular connectivity checks to detect issues early

## See Also

- [training-lan-firewall-apply-fix.md](training-lan-firewall-apply-fix.md) - How we fixed Training LAN gateway connectivity
- pfSense Documentation: https://docs.netgate.com/pfsense/en/latest/nat/outbound.html
