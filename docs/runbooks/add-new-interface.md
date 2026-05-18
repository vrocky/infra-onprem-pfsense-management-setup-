# pfSense Interface Setup Playbook

**Purpose:** Step-by-step guide to add a new interface to pfSense with full internet connectivity  
**Last Updated:** April 29, 2026  
**Validated On:** pfSense v2.8.1-RELEASE, Hyper-V environment

---

## Overview

This playbook covers the complete process of:
1. Setting up the physical/virtual network layer
2. Configuring the pfSense interface
3. Creating firewall rules
4. Configuring NAT for internet access
5. Testing and validation

**Time Required:** 30-45 minutes  
**Difficulty:** Intermediate  
**Prerequisites:** pfSense admin access, Hyper-V management access

---

## Phase 1: Network Infrastructure Setup

### 1.1 Create Hyper-V Virtual Switch

**On Hyper-V Host:**

```powershell
# Create new internal virtual switch
$switchName = "training-vm-lan-new"  # Choose meaningful name
New-VMSwitch -Name $switchName -SwitchType Internal

# Verify creation
Get-VMSwitch -Name $switchName
```

**Expected Output:**
```
Name                  SwitchType NetAdapterInterfaceDescription
----                  ---------- ------------------------------
training-vm-lan-new   Internal   Microsoft Hyper-V Network Adapter
```

### 1.2 Configure Host IP on Virtual Switch

**Assign IP to host adapter:**

```powershell
# Find the adapter index
$adapter = Get-NetAdapter | Where-Object { $_.Name -like "*$switchName*" }

# Assign IP address (must be in same subnet as planned pfSense interface)
New-NetIPAddress -InterfaceIndex $adapter.ifIndex `
    -IPAddress "192.168.50.254" `
    -PrefixLength 24

# Verify
Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4
```

**IP Planning:**
- pfSense interface: `.1` (e.g., 192.168.50.1)
- Host adapter: `.254` (e.g., 192.168.50.254)
- DHCP range: `.10-.250` (e.g., 192.168.50.10-192.168.50.250)

### 1.3 Connect pfSense VM to New Switch

```powershell
# Add network adapter to pfSense VM
Add-VMNetworkAdapter -VMName "pfSense" -SwitchName $switchName

# Verify
Get-VMNetworkAdapter -VMName "pfSense"
```

---

## Phase 2: pfSense Interface Configuration

### 2.1 Detect New Interface

**Web UI: Interfaces → Assignments**

1. Navigate to **Interfaces → Assignments**
2. Look for new unassigned interface (e.g., `hn2`)
3. Click **Add** to assign it to OPT1 (or next available OPT)
4. Click **Save**

**Or via API:**

```powershell
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('admin:password'))
$headers = @{
    Authorization = "Basic $b64"
    "Content-Type" = "application/json"
}

# Get available interfaces
Invoke-RestMethod -Uri 'http://192.168.10.1/api/v2/interface/available' `
    -Headers $headers
```

### 2.2 Configure Interface Settings

**Web UI: Interfaces → OPT1** (or your assigned interface)

Configure:
- ✅ **Enable:** Check "Enable interface"
- **Description:** `TRAININGLAN` (or descriptive name)
- **IPv4 Configuration Type:** Static IPv4
- **IPv4 Address:** `192.168.50.1` / `24`
- **IPv4 Upstream Gateway:** None (it's a LAN interface)

Click **Save** then **Apply Changes**

**Via API (if available):**

```powershell
$body = @{
    enable = $true
    descr = "TRAININGLAN"
    type = "staticv4"
    ipaddr = "192.168.50.1"
    subnet = "24"
} | ConvertTo-Json

Invoke-RestMethod -Uri 'http://192.168.10.1/api/v2/interface?name=opt1' `
    -Method POST -Headers $headers -Body $body
```

### 2.3 Verify Interface Status

```powershell
# Check interface is UP
Invoke-RestMethod -Uri 'http://192.168.10.1/api/v2/interface?name=opt1' `
    -Headers $headers

# Should show: enable=true, status=up
```

---

## Phase 3: DHCP Server Configuration

### 3.1 Enable DHCP Server

**Web UI: Services → DHCP Server → TRAININGLAN**

Configure:
- ✅ **Enable:** Check "Enable DHCP server on TRAININGLAN interface"
- **Range:** 
  - From: `192.168.50.10`
  - To: `192.168.50.250`
- **DNS Servers:** `8.8.8.8`, `8.8.8.4` (or your preferred DNS)
- **Gateway:** `192.168.50.1` (auto-filled)
- **Domain name:** (optional)

Click **Save**

### 3.2 Verify DHCP Leases

**After VMs connect:**

**Web UI: Status → DHCP Leases**

Should show leases for connected VMs with:
- IP Address
- MAC Address
- Hostname
- Lease expiration

---

## Phase 4: Firewall Rules Setup

### 4.1 Create Allow Rule

**Web UI: Firewall → Rules → TRAININGLAN**

Click **Add ↑** (add to top):

Configure:
- **Action:** Pass
- **Interface:** TRAININGLAN
- **Address Family:** IPv4
- **Protocol:** Any
- **Source:** TRAININGLAN subnets
- **Destination:** Any
- **Description:** `Allow TRAINING-LAN to any`
- **Log:** Optional (check for troubleshooting)

Click **Save** then **Apply Changes**

**⚠️ CRITICAL:** Must click "Apply Changes" or use API to apply!

### 4.2 Apply Firewall Changes via API

```powershell
# Apply pending firewall changes immediately
$applyBody = @{ async = $false } | ConvertTo-Json

Invoke-RestMethod -Uri 'http://192.168.10.1/api/v2/firewall/apply' `
    -Method POST -Headers $headers -Body $applyBody
```

**Without this step, firewall rules exist but are NOT active!**

### 4.3 Verify Firewall Rules

```powershell
# Check rules for OPT1
$rules = Invoke-RestMethod -Uri 'http://192.168.10.1/api/v2/firewall/rules' `
    -Headers $headers

$rules.data | Where-Object { $_.interface -eq 'opt1' } | Format-Table
```

---

## Phase 5: NAT Configuration (Internet Access)

### 5.1 Check NAT Mode

**Web UI: Firewall → NAT → Outbound**

Current mode options:
- **Automatic:** May not generate rules for additional interfaces ❌
- **Hybrid:** Automatic + manual rules
- **Manual:** Full control (recommended) ✅

**Choose Manual for predictability**

### 5.2 Create Outbound NAT Rule

**If in Automatic mode:** Switch to Manual mode first:
1. Select "Manual Outbound NAT rule generation"
2. Click **Save**
3. Click **Apply Changes**

**Create NAT Rule:**

Click **Add ↑** to create new rule:

Configure:
- **Interface:** WAN
- **Address Family:** IPv4
- **Protocol:** Any
- **Source Type:** TRAININGLAN subnets (⚠️ NOT "Any"!)
- **Source Network:** (auto-filled: 192.168.50.0/24)
- **Destination:** Any
- **NAT Address:** WAN address
- **Static Port:** No (unchecked)
- **Description:** `Training LAN to Internet NAT`

Click **Save** then **Apply Changes**

### 5.3 Common Mistake: Backwards Rule

❌ **WRONG Configuration:**
```
Source: Any
Destination: TRAININGLAN subnets
```
This matches traffic going TO the training LAN (inbound).

✅ **CORRECT Configuration:**
```
Source: TRAININGLAN subnets
Destination: Any
```
This matches traffic FROM training LAN to internet (outbound).

### 5.4 Verify NAT Rule

**Web UI: Firewall → NAT → Outbound → Mappings**

Should show:
```
Interface: WAN
Source: TRAININGLAN subnets
Destination: *
NAT Address: WAN address
Status: ✓ (enabled)
```

---

## Phase 6: VM Configuration

### 6.1 Connect VMs to Virtual Switch

```powershell
# For each VM that needs access to the new network
$vmName = "training_1"

# Check current network adapter
Get-VMNetworkAdapter -VMName $vmName

# Connect to new switch
Connect-VMNetworkAdapter -VMName $vmName -SwitchName $switchName

# Verify
Get-VMNetworkAdapter -VMName $vmName | Select-Object VMName, SwitchName, MacAddress
```

### 6.2 Configure VM Network Settings

**If using DHCP (recommended):**

In VM:
```powershell
# Restart network adapter to get new DHCP lease
Restart-NetAdapter -Name "Ethernet"

# Check IP configuration
ipconfig /all
```

**Expected:**
```
IPv4 Address: 192.168.50.x (from DHCP range)
Subnet Mask: 255.255.255.0
Default Gateway: 192.168.50.1
DNS Servers: 8.8.8.8, 8.8.8.4
```

**If using Static IP:**

```powershell
$adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }

New-NetIPAddress -InterfaceIndex $adapter.ifIndex `
    -IPAddress "192.168.50.20" `
    -PrefixLength 24 `
    -DefaultGateway "192.168.50.1"

Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex `
    -ServerAddresses @("8.8.8.8", "8.8.8.4")
```

---

## Phase 7: Testing & Validation

### 7.1 Layer 1: Physical Connectivity

**From Hyper-V Host:**

```powershell
# Ping pfSense gateway
Test-Connection -ComputerName 192.168.50.1 -Count 4
```

**Expected:** ✅ Replies from 192.168.50.1

**If fails:**
- Check virtual switch exists
- Check host adapter has IP in same subnet
- Check pfSense interface is UP

### 7.2 Layer 2: VM Connectivity

**From VM Console:**

```powershell
# Ping gateway
ping 192.168.50.1 -n 4
```

**Expected:** ✅ Replies from gateway

**If fails:**
- Check VM is connected to correct virtual switch
- Check VM has IP in correct subnet (ipconfig)
- Check DHCP server is running on pfSense

### 7.3 Layer 3: Internet Connectivity

**From VM Console:**

```powershell
# Ping public DNS (tests NAT)
ping 8.8.8.8 -n 4

# Test DNS resolution
ping google.com -n 2
```

**Expected:** 
- ✅ Replies from 8.8.8.8
- ✅ DNS resolution works

**If fails:**
- Check NAT rule exists and is correct (Source = TRAININGLAN subnets)
- Check NAT rule is enabled (not disabled)
- Check firewall rule allows outbound traffic
- Check firewall states show VM traffic (Diagnostics → States)

### 7.4 Diagnostic Commands

**Check firewall states:**

```powershell
# Get states from VM IP
$states = Invoke-RestMethod -Uri 'http://192.168.10.1/api/v2/firewall/states' `
    -Headers $headers

$states.data | Where-Object { $_.src -like "192.168.50.20*" } | Format-Table
```

**Check NAT rules:**

```powershell
# List all NAT rules
$nat = Invoke-RestMethod -Uri 'http://192.168.10.1/api/v2/firewall/nat/outbound' `
    -Headers $headers

$nat.data | Format-Table interface, source, destination
```

---

## Troubleshooting Guide

### Issue: Gateway Pingable but No Internet

**Symptoms:**
- ✅ `ping 192.168.50.1` works
- ❌ `ping 8.8.8.8` times out

**Root Cause:** Missing or incorrect NAT rule

**Solution:**
1. Navigate to Firewall → NAT → Outbound
2. Verify NAT rule exists with:
   - Source: TRAININGLAN subnets (NOT "Any"!)
   - Destination: Any
3. If missing, create rule per Phase 5.2
4. Click Apply Changes

### Issue: No Connectivity at All

**Symptoms:**
- ❌ Cannot ping gateway from VM
- ❌ No DHCP lease

**Root Cause:** VM on wrong virtual switch or interface misconfigured

**Solution:**
1. Check VM switch: `Get-VMNetworkAdapter -VMName "VM_NAME"`
2. Should match the switch pfSense is connected to
3. Check pfSense interface is UP: Web UI → Interfaces → OPT1
4. Check DHCP is enabled: Services → DHCP Server

### Issue: Firewall Rules Don't Work

**Symptoms:**
- Rules show in web UI
- Traffic still blocked

**Root Cause:** Firewall changes not applied

**Solution:**
```powershell
# Apply pending changes
$body = @{ async = $false } | ConvertTo-Json
Invoke-RestMethod -Uri 'http://192.168.10.1/api/v2/firewall/apply' `
    -Method POST -Headers $headers -Body $body
```

Always click "Apply Changes" in web UI or use this API call!

---

## Checklist

Use this checklist to verify each phase:

### Infrastructure
- [ ] Virtual switch created in Hyper-V
- [ ] Host adapter has IP in correct subnet
- [ ] pfSense VM connected to switch

### pfSense Interface
- [ ] Interface assigned (OPT1, OPT2, etc.)
- [ ] Interface enabled
- [ ] Static IP configured
- [ ] Interface status shows UP
- [ ] DHCP server enabled
- [ ] DHCP range configured

### Firewall Rules
- [ ] Allow rule created for new interface
- [ ] Rule permits source = interface subnets → destination = any
- [ ] Firewall changes APPLIED
- [ ] Rule shows traffic/states in web UI

### NAT Configuration
- [ ] NAT mode set (Manual recommended)
- [ ] Outbound NAT rule created
- [ ] Source = interface subnets (NOT backwards!)
- [ ] Destination = Any
- [ ] Interface = WAN
- [ ] NAT changes APPLIED

### VM Configuration
- [ ] VM connected to correct virtual switch
- [ ] VM has IP in correct subnet
- [ ] VM gateway points to pfSense interface
- [ ] VM DNS configured

### Testing
- [ ] Host can ping pfSense gateway
- [ ] VM can ping pfSense gateway
- [ ] VM can ping internet (8.8.8.8)
- [ ] VM can resolve DNS (ping google.com)

---

## Time-Saving Tips

1. **Use API for firewall apply**
   - Don't rely on "Apply Changes" button
   - Use `POST /api/v2/firewall/apply` after every change

2. **Name interfaces descriptively**
   - Use names like "TRAININGLAN", "GUESTNET", etc.
   - Makes troubleshooting much easier

3. **Use Manual NAT mode**
   - More predictable than Automatic
   - Primary LAN has implicit NAT regardless

4. **Test incrementally**
   - Test each phase before moving to next
   - Don't configure everything then test

5. **Check firewall states**
   - Diagnostics → States shows real-time traffic
   - Best way to verify rules are working

---

## Related Documentation

- [pfSense NAT Behavior](../knowledge-book/pfsense-nat-behavior.md) - Understanding implicit vs manual NAT
- [Training LAN NAT Fix](../issue-wins/training-lan-internet-nat-fix.md) - Real-world troubleshooting example
- [pfSense API v2.6.4](../memories/repo/pfsense-api-v264.md) - API capabilities and limitations

---

## Version History

| Date | Version | Changes |
|------|---------|---------|
| 2026-04-29 | 1.0 | Initial playbook based on Training LAN implementation |

---

**Last Validated:** April 29, 2026 on pfSense v2.8.1-RELEASE (Hyper-V)
