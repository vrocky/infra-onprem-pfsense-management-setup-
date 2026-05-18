# pfSense NAT Behavior - Implicit vs Manual Rules

**Category:** pfSense Networking  
**Last Updated:** April 29, 2026  
**Verified On:** pfSense v2.8.1-RELEASE, API v2.6.4

---

## Key Discovery: Implicit LAN NAT

pfSense has **built-in implicit NAT** for the primary LAN interface that works differently than additional interfaces.

### Primary LAN Interface (Implicit NAT)

**Behavior:**
- The primary LAN interface (typically 192.168.10.0/24 or similar) gets **automatic NAT** even in Manual mode
- This is a built-in behavior for backwards compatibility
- Works WITHOUT requiring a manual NAT rule
- Persists across reboots
- **NOT visible** in the "Automatic Rules" or "Mappings" table in the web UI

**Example:**
```
VM-LAN-2 (192.168.10.0/24)
  Interface: LAN
  NAT Status: ✅ Implicit/Automatic (always works)
  Manual Rule Required: ❌ No
```

### Additional Interfaces (Manual NAT Required)

**Behavior:**
- OPT1, OPT2, etc. (Training LAN, Guest networks, etc.) do **NOT** get automatic NAT
- Require **explicit manual NAT configuration** to reach the internet
- Will NOT work even if "Automatic" NAT mode is selected (unless automatic generation works)
- Must be configured in Firewall → NAT → Outbound

**Example:**
```
Training LAN (192.168.50.0/24)
  Interface: OPT1 (TRAININGLAN)
  NAT Status: ❌ No automatic NAT
  Manual Rule Required: ✅ Yes
```

---

## NAT Rule Configuration for Additional Interfaces

### Required Settings

When creating a manual NAT rule for an additional interface to reach the internet:

| Field | Value | Notes |
|-------|-------|-------|
| **Interface** | WAN | Exit interface to internet |
| **Address Family** | IPv4 | Or IPv4+IPv6 if needed |
| **Protocol** | Any | All protocols unless specific filtering needed |
| **Source** | **[Interface] subnets** | ⚠️ CRITICAL: Source = internal network |
| **Source Port** | * | Any |
| **Destination** | **Any** | ⚠️ CRITICAL: Destination = internet (any) |
| **Destination Port** | * | Any |
| **NAT Address** | WAN address | Translate to WAN interface IP |
| **NAT Port** | * | Dynamic port allocation |
| **Static Port** | No | Randomize for security |

### Common Mistake: Backwards Rule

❌ **WRONG:**
```
Source: Any
Destination: TRAININGLAN subnets
```
This matches traffic going **TO** the internal network (useless for outbound NAT).

✅ **CORRECT:**
```
Source: TRAININGLAN subnets
Destination: Any
```
This matches traffic **FROM** the internal network going to the internet.

---

## NAT Modes Explained

### Automatic Mode
- **Expected:** Auto-generate NAT rules for all WAN-connected interfaces
- **Reality:** May not generate rules for additional interfaces (OPT1, OPT2, etc.)
- **Display Issue:** "Automatic Rules" table in web UI can be empty even when rules exist
- **Use Case:** Simple single-LAN setups

### Hybrid Mode
- **Behavior:** Automatic rules + manual rules
- **Use Case:** Want automatic rules plus custom exceptions
- **Note:** Doesn't help if automatic generation isn't working

### Manual Mode (Recommended for Multi-LAN)
- **Behavior:** Complete manual control
- **Pros:** Explicit configuration, no surprises
- **Cons:** Must configure every interface manually
- **Use Case:** Multiple internal networks with different NAT requirements

---

## Troubleshooting NAT Issues

### Symptoms of Missing NAT
- ✅ VM can ping gateway (e.g., 192.168.50.1)
- ✅ Firewall rules allow outbound traffic
- ❌ VM cannot ping internet IPs (8.8.8.8)
- ❌ DNS resolution fails
- ❌ No firewall states showing traffic from VM

### Diagnostic Steps

1. **Check NAT rules exist**
   ```
   Web UI: Firewall → NAT → Outbound
   Look at: "Mappings" table (for manual rules)
            "Automatic Rules" table (for automatic rules)
   ```

2. **Verify NAT rule configuration**
   - Source should be the INTERNAL subnet
   - Destination should be "Any" for internet access
   - Interface should be WAN

3. **Check firewall rules allow traffic**
   ```
   Web UI: Firewall → Rules → [Interface Name]
   Should have: Pass rule from interface subnet to any destination
   ```

4. **Test from VM**
   ```powershell
   # Test gateway (should work even without NAT)
   ping 192.168.50.1
   
   # Test internet (requires working NAT)
   ping 8.8.8.8
   ping google.com
   ```

5. **Check firewall states**
   ```
   Web UI: Diagnostics → States
   Filter by: Source IP of your VM
   Should show: NAT translated connections to internet
   ```

---

## API Limitations

pfSense API v2.6.4 **does NOT support** NAT configuration:
- ❌ `/api/v2/firewall/nat/*` endpoints return 404
- ❌ Cannot read NAT rules via API
- ❌ Cannot create/modify NAT rules via API
- ✅ Must use web UI for NAT configuration
- ✅ Can use `/api/v2/firewall/apply` to apply changes after manual web UI config

**Alternative:** Use web form POST directly:
```powershell
$formData = @(
    "interface=wan"
    "ipprotocol=inet"
    "protocol=any"
    "source_type=opt1"  # For TRAININGLAN
    "destination_type=any"
    "descr=Training+LAN+NAT"
    "Save=Save"
) -join "&"

Invoke-WebRequest -Uri 'http://192.168.10.1/firewall_nat_out_edit.php' `
  -Method POST -Headers $headers -Body $formData
```

---

## Real-World Example: Training LAN Setup

### Initial State (Not Working)
- Training LAN interface: OPT1, 192.168.50.0/24
- Firewall rules: ✅ Allow all from Training LAN
- NAT Mode: Automatic
- NAT Rules: ❌ Empty (no rules generated)
- Result: VMs can ping gateway, cannot reach internet

### Solution Applied
1. Switch to Manual NAT mode
2. Create manual NAT rule:
   - Interface: WAN
   - Source: TRAININGLAN subnets (192.168.50.0/24)
   - Destination: Any
   - NAT Address: WAN address
3. Apply changes
4. Result: ✅ Internet works

### Why Primary LAN Wasn't Affected
- VM-LAN-2 (192.168.10.0/24) is primary LAN interface
- Has implicit NAT built into pfSense
- Continued working even when NAT mode was "Manual"
- No manual rule required

---

## Best Practices

1. **Document your NAT configuration**
   - Keep track of which interfaces need manual NAT
   - Document the purpose of each NAT rule

2. **Use descriptive rule names**
   - Example: "Training LAN to Internet NAT"
   - Makes troubleshooting easier

3. **Test after pfSense restarts**
   - Ensure NAT rules persist across reboots
   - Primary LAN will work, but additional interfaces need manual rules

4. **Monitor firewall states**
   - Check Diagnostics → States regularly
   - Verify NAT translations are occurring

5. **Use Manual NAT mode for multi-LAN setups**
   - More explicit and predictable
   - Automatic mode may not generate rules for all interfaces

---

## Related Knowledge

- **Firewall Rules vs NAT Rules:** Firewall rules control what traffic is ALLOWED. NAT rules control how IP addresses are TRANSLATED. Both must be configured correctly for internet access.

- **Outbound vs Inbound NAT:** 
  - Outbound NAT (this document): Internal devices → Internet
  - Inbound NAT (Port Forwarding): Internet → Internal devices

- **Apply Changes:** Always click "Apply Changes" after modifying NAT or firewall rules. Or use API: `POST /api/v2/firewall/apply`

---

## References

- pfSense Documentation: https://docs.netgate.com/pfsense/en/latest/nat/
- Issue Resolution: [training-lan-internet-nat-fix.md](../issue-wins/training-lan-internet-nat-fix.md)
- Repository Memory: [pfsense-api-v264.md](../memories/repo/pfsense-api-v264.md)
