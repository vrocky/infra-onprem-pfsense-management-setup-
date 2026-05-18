# training_1 Internet Connectivity - Root Cause & Solution

**Date**: 2026-04-29  
**Issue**: training_1 VM at 192.168.50.20 has no internet connectivity despite NAT being configured

---

## ✅ What's Working

1. **VM Hardware**: Running correctly on training-vm-lan-new switch
2. **pfSense Gateway**: 192.168.50.1 is up and reachable from host
3. **pfSense NAT**: Automatic outbound NAT configured and applied
4. **pfSense Firewall Rules**: Allow TRAINING-LAN to any (configured)
5. **VM IP Address**: 192.168.50.20 detected by Integration Services

---

## ❌ ROOT CAUSE IDENTIFIED

**The VM has NO default gateway configured inside the guest OS.**

### Evidence:
- VM doesn't respond to ping from host
- pfSense shows ZERO firewall states from 192.168.50.20
- No traffic from VM reaching pfSense gateway

This means the VM has an IP address (192.168.50.20) but no routing configuration to send traffic to the gateway (192.168.50.1).

---

## 🔧 Solution

### Inside the training_1 VM, configure:

```powershell
# Find network adapter name
$adapter = (Get-NetAdapter | Where-Object {$_.Status -eq 'Up'}).Name

# Configure IP with gateway
New-NetIPAddress -InterfaceAlias $adapter -IPAddress 192.168.50.20 -PrefixLength 24 -DefaultGateway 192.168.50.1

# Configure DNS
Set-DnsClientServerAddress -InterfaceAlias $adapter -ServerAddresses 8.8.8.8,8.8.4.4

# Test
ping 192.168.50.1  # Should work - gateway
ping 8.8.8.8       # Should work - internet
ping google.com    # Should work - DNS resolution
```

### OR use the provided script:

1. VM console is now open (vmconnect)
2. Inside the VM, run: `C:\configure-training1-network.ps1`
3. Or manually copy the script content from: `configure-training1-network.ps1`

---

## 📋 Required Configuration

| Setting | Value |
|---------|-------|
| IP Address | 192.168.50.20 |
| Subnet Mask | 255.255.255.0 (/24) |
| Default Gateway | 192.168.50.1 |
| DNS Server | 8.8.8.8, 8.8.4.4 |
| Network | Training LAN (192.168.50.0/24) |

---

## ✅ Verification Steps

After configuration, verify:

1. **Gateway connectivity**: `ping 192.168.50.1` → Should respond
2. **Internet connectivity**: `ping 8.8.8.8` → Should respond  
3. **DNS resolution**: `ping google.com` → Should respond
4. **From host**: `ping 192.168.50.20` → Should respond (if Windows Firewall allows)

---

## 📊 Infrastructure Status

### pfSense Configuration ✓
- WAN: 192.168.1.10 (upstream internet)
- LAN: 192.168.10.1/24 (management)
- OPT1 (TRAINING-LAN): 192.168.50.1/24 ✓
- NAT: Automatic outbound (applied) ✓
- Firewall Rules: Allow TRAINING-LAN to any ✓

### Hyper-V Configuration ✓
- VM: training_1 (Running, 30+ min uptime) ✓
- Switch: training-vm-lan-new ✓
- Host IP: 192.168.50.254 ✓
- Status: Connected, MAC 00:15:5D:00:A0:9A ✓

### The Missing Piece ❌
- **VM Guest OS**: No default gateway configured
- **This is why**: VM can't route traffic to internet

---

## 🎯 Next Action

**Open the VM console (already launched) and configure the gateway inside the VM.**

Once configured, internet will work immediately - no pfSense changes needed!
