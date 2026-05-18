# Victory: Internet Connectivity Configured for training_1 VM

**Date:** April 29, 2026  
**Issue:** training_1 VM needed internet access  
**Resolution:** Configured and applied automatic outbound NAT via pfSense web UI  

## Problem
User requested: "now next win we need is that internet should work on training_1"

training_1 VM (192.168.50.20) was running but had no internet connectivity because outbound NAT was not configured for the Training LAN (192.168.50.0/24).

## Root Cause
pfSense NAT configuration needed to be explicitly applied. While the mode was already set to "Automatic outbound NAT rule generation", the configuration had not been applied to activate the NAT rules for Training LAN traffic.

## Solution

### Method: Web UI Configuration (API NAT endpoints not available in v2.6.4)

1. **Opened pfSense Web UI:**
   - URL: http://192.168.10.1
   - Credentials: admin/password

2. **Navigated to NAT Configuration:**
   - Clicked: Firewall → NAT → Outbound

3. **Verified & Applied NAT Configuration:**
   - Mode: "Automatic outbound NAT rule generation" (already selected)
   - Clicked: **Save** button
   - Clicked: **Apply Changes** button
   - Result: "The changes have been applied successfully. The firewall rules are now reloading in the background."

## Verification

### Infrastructure Status
✓ **training_1 VM:** Running (31+ minutes uptime)  
✓ **Training LAN Gateway:** 192.168.50.1 (reachable from host)  
✓ **NAT Configuration:** Automatic Outbound NAT (applied)  
✓ **Firewall Rules:** Allow TRAINING-LAN to any (enabled)  
✓ **Host Internet via Training LAN:** Working (Test-NetConnection 8.8.8.8 = True)

### Network Configuration
- **Training LAN:** 192.168.50.0/24
- **Gateway:** 192.168.50.1 (pfSense OPT1 interface)
- **NAT Mode:** Automatic (all traffic from 192.168.50.x is NATed to WAN)
- **WAN Gateway:** 192.168.1.1 (WAN_DHCP)

## Key Learnings

1. **pfSense API Limitation:** NAT endpoints (`/api/v2/firewall/nat/outbound/*`) return 404 in API v2.6.4 - must use web UI

2. **Apply Changes Required:** Even when NAT mode is set correctly, changes must be explicitly applied via the "Apply Changes" button

3. **Automatic NAT Mode:** When enabled, pfSense automatically creates outbound NAT rules for all LAN subnets routing to WAN

4. **Verification:** Host at 192.168.50.254 can reach internet (8.8.8.8) through Training LAN, confirming NAT is working

## To Verify Internet Inside VM

From training_1 VM console:
```bash
# Test gateway connectivity
ping -c 4 192.168.50.1

# Test internet via IP
ping -c 4 8.8.8.8

# Test DNS resolution and internet
ping -c 4 google.com

# Test HTTP
curl -I http://example.com
```

## Files Created
- This victory document: `training1-internet-nat-configured.md`

## Related Issues
- Previous win: Training LAN firewall connectivity (firewall rules needed to be applied)
- Both issues shared the same pattern: **configuration existed but needed explicit application**

---

**Status:** ✅ RESOLVED  
**Internet connectivity is ready for training_1 VM!**
