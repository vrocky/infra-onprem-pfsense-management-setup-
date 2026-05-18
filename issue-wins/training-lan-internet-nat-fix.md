# Training LAN Internet Access - NAT Configuration Fix

**Date:** April 29, 2026  
**Status:** ✅ RESOLVED  
**VM Affected:** training_1 (192.168.50.20)

---

## Problem Statement

After successfully establishing Training LAN connectivity (192.168.50.x network), VMs on the Training LAN could ping the gateway (192.168.50.1) but could **not reach the internet** (e.g., ping 8.8.8.8 timed out).

### Symptoms
- ✅ VM has correct IP configuration (192.168.50.20, gateway 192.168.50.1, DNS 8.8.8.8)
- ✅ VM can ping gateway: `ping 192.168.50.1` → Success
- ✅ pfSense gateway operational and can reach internet
- ✅ Firewall rules allow traffic from Training LAN
- ❌ VM cannot ping internet: `ping 8.8.8.8` → Request timed out
- ❌ DNS resolution fails

---

## Root Cause

**pfSense NAT automatic rule generation was not working.** Despite being set to "Automatic" mode, the NAT "Automatic Rules" table was **completely empty** - no NAT rules were being generated for any interface.

**Secondary Issue:** When manually creating a NAT rule, it was initially configured **backwards**:
- Source: `*` (Any)
- Destination: `TRAININGLAN subnets` ❌ **WRONG**

This matched traffic going **TO** Training LAN instead of **FROM** Training LAN to the internet.

---

## Solution

### 1. Switch NAT Mode to Manual
Since automatic NAT rule generation failed, switched pfSense to **Manual Outbound NAT** mode:
- Navigate to: **Firewall → NAT → Outbound**
- Select: "Manual Outbound NAT rule generation (AON - Advanced Outbound NAT)"
- Click **Save**
- Click **Apply Changes**

### 2. Create Manual NAT Rule (Corrected)
Created outbound NAT rule with **correct configuration**:

| Field | Value | Description |
|-------|-------|-------------|
| **Interface** | WAN | Exit interface for internet traffic |
| **Address Family** | IPv4 | Only IPv4 traffic |
| **Protocol** | Any | All protocols (TCP, UDP, ICMP, etc.) |
| **Source** | **TRAININGLAN subnets** | Traffic **FROM** 192.168.50.0/24 |
| **Source Port** | * | Any source port |
| **Destination** | **Any** | Traffic going **TO** internet |
| **Destination Port** | * | Any destination port |
| **NAT Address** | WAN address | Translate to WAN IP (192.168.1.10) |
| **NAT Port** | * | Dynamic port allocation |
| **Static Port** | No | Randomize source ports |
| **Description** | Training LAN to Internet NAT | |

### 3. Applied Configuration
- Click **Save** on NAT rule
- Click **Apply Changes** to activate
- API call to ensure immediate application:
  ```powershell
  Invoke-WebRequest -Uri 'http://192.168.10.1/api/v2/firewall/apply' `
    -Method POST -Headers @{Authorization="Basic $b64"; "Content-Type"="application/json"} `
    -Body '{"async":false}' -UseBasicParsing
  ```

---

## Verification

### Test from training_1 VM Console
```
C:\Users\globql-local>ping 8.8.8.8 -n 4

Pinging 8.8.8.8 with 32 bytes of data:
Reply from 8.8.8.8: bytes=32 time=<10ms TTL=116
Reply from 8.8.8.8: bytes=32 time=<10ms TTL=116
Reply from 8.8.8.8: bytes=32 time=<10ms TTL=116
Reply from 8.8.8.8: bytes=32 time=<10ms TTL=116

Ping statistics for 8.8.8.8:
    Packets: Sent = 4, Received = 4, Lost = 0 (0% loss)
```

**Result:** ✅ **SUCCESS** - Internet connectivity fully operational!

### Additional Validation
- ✅ DNS resolution working: `ping google.com` succeeds
- ✅ HTTP/HTTPS traffic working
- ✅ NAT translation visible in pfSense firewall states
- ✅ Firewall rule shows traffic: 12 states / 21.58 MiB processed

---

## Key Learnings

1. **pfSense Automatic NAT Can Fail**
   - "Automatic" mode does not guarantee NAT rules will be generated
   - Always verify NAT rules exist in the "Automatic Rules" table
   - If empty, switch to Manual or Hybrid mode

2. **NAT Rule Direction is Critical**
   - **Source** = where traffic originates (internal network)
   - **Destination** = where traffic is going (internet = any)
   - Common mistake: reversing source/destination

3. **NAT Rule Configuration Pattern**
   - For internet access from internal network:
     - Source: Internal subnet (e.g., TRAININGLAN subnets)
     - Destination: Any
     - Interface: WAN (exit interface)
     - NAT Address: WAN address (or interface address)

4. **Verification Steps**
   - Check firewall rules allow outbound traffic (Firewall → Rules)
   - Check NAT rules exist and are enabled (Firewall → NAT → Outbound)
   - Check firewall states show traffic from source IPs (Diagnostics → States)
   - Test from actual VM, not just pfSense console

---

## Related Issues

- **Previous:** [training-lan-firewall-apply-fix.md](training-lan-firewall-apply-fix.md) - Training LAN connectivity established
- **Next:** Training LAN fully operational with internet access

---

## Configuration Summary

### Network Topology
```
Internet (8.8.8.8)
    ↓
192.168.1.1 (ISP Gateway)
    ↓
192.168.1.10 (pfSense WAN)
    ↓
pfSense (NAT Translation)
    ↓
192.168.50.1 (pfSense OPT1/Training-LAN)
    ↓
192.168.50.20 (training_1 VM)
```

### Active NAT Rule
```
WAN | * | * | TRAININGLAN subnets | * | WAN address | * | [randomize ports]
```

This rule translates all traffic from 192.168.50.0/24 → WAN interface IP (192.168.1.10) for internet access.

---

## Status: COMPLETE ✅

Training LAN VMs now have:
- ✅ Local network connectivity (can reach 192.168.50.1 gateway)
- ✅ Internet connectivity (can reach 8.8.8.8 and beyond)
- ✅ DNS resolution working
- ✅ Full network functionality

**All Training LAN networking issues resolved.**
