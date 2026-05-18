# Training LAN Connectivity Issue - Diagnosis Report

## Issue Summary
192.168.10.1 (VM-LAN-2) works fine, but 192.168.50.1 (Training LAN / OPT1) cannot be reached from the host.

## Root Cause
**Virtual Switch Mismatch**

- **VMs are connected to:** `training-vm-lan` Hyper-V switch
- **Host IP (192.168.50.254) is configured on:** `vEthernet (training-vm-lan-new)` switch
- **Result:** Two separate isolated layer 2 networks with no connectivity

## Diagnostic Evidence

### 1. VM Configuration (from earlier session)
```
VMName     Name            SwitchName      MacAddress
PFSenseVM  Network Adapter training-vm-lan 00155D00A09C (OPT1/hn2)
training_1 Network Adapter training-vm-lan 00155D00A09A
```

### 2. Host Network Interfaces
```
Name                            Status      IPAddress
vEthernet (training-vm-lan-new) Up          192.168.50.254
vEthernet (training-vm-lan)     Not Present (no IP)
```

### 3. PFSense OPT1 Status
- **Interface:** hn2
- **IP Address:** 192.168.50.1/24
- **Physical Status:** up
- **Config Enable:** True
- **Packet Counters:** inpkts=1, outpkts=5 (minimal traffic, no responses)
- **Firewall Rules:** 2 rules present (Allow all + ICMP)
- **Firewall States:** 0 states on hn2 (no traffic being processed)

### 4. Connectivity Tests
- **ping 192.168.50.1:** 100% packet loss (4/4 timeouts)
- **ARP resolution:** Returns MAC 00-15-5d-00-a0-9c but no ping response
- **OPT1 packet counters:** No change during ping tests (0 delta)

## Why VM-LAN-2 Works But Training LAN Doesn't

### VM-LAN-2 (192.168.10.x) - WORKING
- VMs connected to: `VM-LAN-2` switch
- Host IP configured on: `vEthernet (VM-LAN-2)` interface
- **Match:** ✓ Same virtual switch = connectivity works

### Training LAN (192.168.50.x) - NOT WORKING
- VMs connected to: `training-vm-lan` switch  
- Host IP configured on: `vEthernet (training-vm-lan-new)` interface
- **Mismatch:** ✗ Different switches = isolated networks

## Solution

### Option 1: Move VMs to training-vm-lan-new (Recommended)
**Run as Administrator:**
```powershell
.\fix-training-lan-switch.ps1
```

This script will:
1. Move PFSense OPT1 adapter to `training-vm-lan-new` switch
2. Move training_1 VM adapter to `training-vm-lan-new` switch
3. Test connectivity

### Option 2: Move Host IP to training-vm-lan
**Run as Administrator:**
```powershell
# Remove IP from training-vm-lan-new
Remove-NetIPAddress -InterfaceAlias "vEthernet (training-vm-lan-new)" -IPAddress 192.168.50.254 -Confirm:$false

# Find training-vm-lan ifIndex
$if = Get-NetAdapter | Where-Object { $_.Name -eq 'vEthernet (training-vm-lan)' }

# Add IP to training-vm-lan (if interface is present)
if ($if -and $if.Status -eq 'Up') {
    New-NetIPAddress -InterfaceIndex $if.ifIndex -IPAddress 192.168.50.254 -PrefixLength 24
}
```

**Note:** This option only works if `vEthernet (training-vm-lan)` interface exists and is operational.

## Additional Findings

### PFSense Interface "Enable" Field Confusion
- Configuration shows: `enable: True`
- Runtime status shows: `enable: False`
- **Note:** LAN interface also shows `enable: False` but works fine
- This field may indicate something other than "interface enabled"
- The actual operational status is indicated by `status: up`

### Permission Issues
Current PowerShell session does not have permissions to:
- Modify VM network adapters (Get-VMNetworkAdapter works, Connect-VMNetworkAdapter fails)
- Modify network IP addresses (New-NetIPAddress fails with "Access denied")
- These operations require Administrator elevation

## Verification Steps After Fix

1. **Check VM connections:**
   ```powershell
   Get-VMNetworkAdapter -VMName PFSenseVM,training_1 | Select-Object VMName,SwitchName,MacAddress
   ```

2. **Test connectivity:**
   ```powershell
   ping -n 4 192.168.50.1
   ping -n 2 192.168.50.20
   ```

3. **Check PFSense firewall states:**
   ```powershell
   $b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('admin:password'))
   $h=@{Authorization="Basic $b64";Accept='application/json'}
   $r=(Invoke-WebRequest -Uri 'http://192.168.10.1/api/v2/firewall/states' -Headers $h -Method GET -UseBasicParsing).Content | ConvertFrom-Json
   $r.data | Where-Object { $_.interface -eq 'hn2' }
   ```

4. **Verify OPT1 packet counters increase:**
   ```powershell
   $r=(Invoke-WebRequest -Uri 'http://192.168.10.1/api/v2/status/interfaces' -Headers $h -Method GET -UseBasicParsing).Content | ConvertFrom-Json
   $r.data | Where-Object { $_.name -eq 'opt1' } | Select-Object inpkts,outpkts
   ```

## Timeline of Issue
The issue likely occurred when:
1. The `training-vm-lan` switch was renamed or recreated as `training-vm-lan-new`
2. The host IP was migrated to the new switch
3. The VMs remained connected to the old `training-vm-lan` switch
4. The old switch's host-side virtual adapter went to "Not Present" status

## Summary
This is a **networking infrastructure issue**, not a pfSense configuration issue. The pfSense OPT1 interface is properly configured with IP 192.168.50.1/24, firewall rules are in place, and the interface is operationally "up". The problem is purely the layer 2 switch mismatch preventing any traffic from reaching the interface.
