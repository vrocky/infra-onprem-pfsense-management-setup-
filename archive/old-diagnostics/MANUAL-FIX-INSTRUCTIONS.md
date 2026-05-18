# Manual Fix Instructions for Training LAN Issue

## Problem Summary
Your VMs (PFSenseVM OPT1 and training_1) are connected to the **`training-vm-lan`** Hyper-V switch, but your host IP (192.168.50.254) is configured on the **`training-vm-lan-new`** switch. These are two separate isolated networks.

## Solution: Move VMs to the Correct Switch

### Option 1: Run the Diagnostic Script (Recommended)

1. **Right-click** on `diagnose-and-fix-training-lan.ps1`
2. Select **"Run with PowerShell as Administrator"**
3. Follow the prompts - it will:
   - Show you the current configuration
   - Confirm the problem
   - Ask if you want to fix it
   - Move both VMs to the correct switch
   - Test connectivity

### Option 2: Manual Fix via Hyper-V Manager (GUI)

1. Open **Hyper-V Manager** (run as Administrator if needed)

2. **For PFSenseVM:**
   - Right-click **PFSenseVM** → Settings
   - Find the network adapter with MAC **00-15-5D-00-A0-9C** (OPT1/hn2)
   - Change **Virtual switch** from `training-vm-lan` to **`training-vm-lan-new`**
   - Click OK

3. **For training_1:**
   - Right-click **training_1** → Settings
   - Select the network adapter
   - Change **Virtual switch** from `training-vm-lan` to **`training-vm-lan-new`**
   - Click OK

4. **Test connectivity:**
   - Open PowerShell
   - Run: `ping 192.168.50.1`
   - Should now get replies

### Option 3: PowerShell Commands (Run as Administrator)

```powershell
# Move PFSense OPT1 to training-vm-lan-new
$pfOpt1 = Get-VMNetworkAdapter -VMName 'PFSenseVM' | Where-Object { $_.MacAddress -eq '00155D00A09C' }
Connect-VMNetworkAdapter -VMNetworkAdapter $pfOpt1 -SwitchName 'training-vm-lan-new'

# Move training_1 to training-vm-lan-new
$tr1 = Get-VMNetworkAdapter -VMName 'training_1' | Select-Object -First 1
Connect-VMNetworkAdapter -VMNetworkAdapter $tr1 -SwitchName 'training-vm-lan-new'

# Verify
Get-VMNetworkAdapter -VMName PFSenseVM,training_1 | Select-Object VMName,SwitchName,MacAddress | Format-Table

# Test
ping 192.168.50.1
```

## Why This Fixes the Problem

### Current (Broken) State:
```
Host:       192.168.50.254 on vEthernet (training-vm-lan-new)
                    ↓ (same switch)
            training-vm-lan-new switch
                    
                    X (NO CONNECTION)
                    
            training-vm-lan switch (different switch!)
                    ↓
PFSenseVM:  192.168.50.1 on training-vm-lan
training_1: on training-vm-lan
```

### After Fix:
```
Host:       192.168.50.254 on vEthernet (training-vm-lan-new)
                    ↓ (same switch)
            training-vm-lan-new switch
                    ↓
PFSenseVM:  192.168.50.1 on training-vm-lan-new  ← MOVED
training_1: on training-vm-lan-new               ← MOVED
            
            ✓ All on same switch = connectivity works!
```

## Verification After Fix

After applying the fix, verify with these commands:

```powershell
# 1. Check VM switch assignments
Get-VMNetworkAdapter -VMName PFSenseVM,training_1 | Select-Object VMName,SwitchName,MacAddress

# Expected output: All should show "training-vm-lan-new"

# 2. Test connectivity
ping -n 4 192.168.50.1

# Expected output: Replies from 192.168.50.1

# 3. Check PFSense sees the traffic
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('admin:password'))
$h=@{Authorization="Basic $b64";Accept='application/json'}
$r=(Invoke-WebRequest -Uri 'http://192.168.10.1/api/v2/status/interfaces' -Headers $h -Method GET -UseBasicParsing).Content | ConvertFrom-Json
$r.data | Where-Object { $_.name -eq 'opt1' } | Select-Object name,ipaddr,inpkts,outpkts

# Expected: inpkts and outpkts should be increasing
```

## If Still Not Working After Fix

If you've moved the VMs to the correct switch and ping still fails:

1. **Check PFSense interface status** via web UI (http://192.168.10.1)
   - Go to Interfaces → OPT1 (TRAINING-LAN)
   - Verify "Enable interface" is checked
   - Click Save, then Apply Changes

2. **Check firewall rules** on OPT1:
   - Go to Firewall → Rules → OPT1
   - Ensure there's at least one "pass" rule allowing traffic

3. **Try restarting pfSense VM:**
   - Sometimes pfSense needs a restart after network adapter changes
   - Restart-VM -Name PFSenseVM (as admin)
   - Or via pfSense web UI: Diagnostics → Reboot

4. **Check if training_1 VM is powered on:**
   - Get-VM -Name training_1

## Additional Notes

- **Don't delete the old switch:** The `training-vm-lan` switch can remain, it's just not being used
- **Host IP stays where it is:** No need to move the host IP 192.168.50.254 - it's already on the right switch
- **Other VMs unaffected:** This only moves PFSenseVM OPT1 and training_1 adapters
