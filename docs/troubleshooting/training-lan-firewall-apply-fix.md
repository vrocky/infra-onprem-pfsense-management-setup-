# Training LAN Connectivity Issue - Resolution

**Date**: April 28, 2026  
**Issue**: pfSense OPT1 interface (192.168.50.1) not responding to pings  
**Status**: ✅ **RESOLVED**

---

## Problem Summary

The pfSense Training LAN interface (OPT1, 192.168.50.1/24) was not responding to ICMP ping requests from the host (192.168.50.254), even though:
- The interface was configured correctly
- VMs were on the correct virtual switch (`training-vm-lan-new`)
- Firewall rules existed and were enabled
- Packets were being received by the interface (inpkts counter increasing)

---

## Root Cause

**Firewall rules were not applied to the running configuration.**

When firewall rules are created or modified through the pfSense API (or Web UI), they exist in the configuration but are **not automatically applied** to the active firewall ruleset. The changes must be explicitly applied using the `/api/v2/firewall/apply` endpoint.

### Key Discovery

While diagnosing, we observed:
- OPT1 interface showing `enable: False` in runtime status (despite config showing enabled)
- Packets arriving at OPT1 (inpkts increasing) but no replies sent
- No ICMP firewall states being created
- Interface restart and VM restart did not resolve the issue

The breakthrough came when we enabled logging on the ICMP firewall rule and then **applied the firewall configuration**. This immediately resolved all connectivity issues.

---

## Solution

### API Commands Used

```powershell
# Setup authentication headers
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('admin:password'))
$headers = @{
    Authorization = "Basic $b64"
    Accept = 'application/json'
    'Content-Type' = 'application/json'
}

# Step 1: Enable logging on ICMP rule (optional, for debugging)
$body = @{id=2; log=$true} | ConvertTo-Json
Invoke-WebRequest -Uri 'http://192.168.10.1/api/v2/firewall/rule' `
    -Headers $headers -Method PATCH -Body $body

# Step 2: Apply firewall changes (CRITICAL FIX)
Invoke-WebRequest -Uri 'http://192.168.10.1/api/v2/firewall/apply' `
    -Headers $headers -Method POST -Body '{"async":false}'
```

### Result

Immediately after applying firewall changes:
```
Pinging 192.168.50.1 with 32 bytes of data:
Reply from 192.168.50.1: bytes=32 time<1ms TTL=64
Reply from 192.168.50.1: bytes=32 time=1ms TTL=64
Reply from 192.168.50.1: bytes=32 time<1ms TTL=64

Ping statistics for 192.168.50.1:
    Packets: Sent = 3, Received = 3, Lost = 0 (0% loss)
```

---

## Verification Steps

After applying the fix, we verified:

1. **✓ Ping to OPT1 gateway**: 5/5 packets successful (0% loss)
2. **✓ OPT1 packet counters**: Increasing (283 in, 21 out)
3. **✓ Firewall rules**: Active and enabled on OPT1
4. **✓ Interface status**: Operationally "up"

---

## Key Lessons Learned

### 1. Firewall Rule Application is Separate
- Creating/modifying firewall rules via API does not automatically apply them
- Always call `POST /api/v2/firewall/apply` after rule changes
- Use `{"async":false}` to wait for completion

### 2. Interface Apply vs Firewall Apply
- `/api/v2/interface/apply` - applies interface configuration changes
- `/api/v2/firewall/apply` - applies firewall rule changes
- These are **separate operations** for different subsystems

### 3. Status Fields Can Be Misleading
- OPT1 showed `enable: False` in runtime status but was actually configured correctly
- LAN interface also showed `enable: False` but worked fine
- The `enable` field may not indicate actual operational status

### 4. Diagnostic Indicators That Led to Solution
- Packets received (inpkts) but no replies sent
- No firewall states created for ICMP traffic
- DNS traffic from VMs working through OPT1 (showing interface functionally capable)
- Interface restart and VM restart had no effect (indicating config issue, not hardware)

---

## Network Topology

```
Host (Windows)
├── vEthernet (VM-LAN-2): 192.168.10.101/24
│   └── Connected to: pfSense LAN (hn1: 192.168.10.1/24) ✓ WORKING
│
└── vEthernet (training-vm-lan-new): 192.168.50.254/24
    └── Connected to: pfSense OPT1 (hn2: 192.168.50.1/24) ✓ FIXED

PFSenseVM
├── WAN (hn0): 192.168.1.10/24 (External NIC)
├── LAN (hn1): 192.168.10.1/24 (VM-LAN-2 switch)
└── OPT1 (hn2): 192.168.50.1/24 (training-vm-lan-new switch)

training_1 VM
└── NIC: 00-15-5d-00-a0-9a (training-vm-lan-new switch)
    └── IP: 192.168.50.20/24
```

---

## pfSense API Endpoints Used

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v2/interface` | GET | Retrieve interface configuration |
| `/api/v2/interface` | PATCH | Modify interface settings |
| `/api/v2/interface/apply` | POST | Apply interface configuration changes |
| `/api/v2/status/interfaces` | GET | Get runtime interface status |
| `/api/v2/firewall/rules` | GET | List firewall rules |
| `/api/v2/firewall/rule` | PATCH | Modify specific firewall rule |
| `/api/v2/firewall/apply` | POST | **Apply firewall rule changes** ⭐ |
| `/api/v2/firewall/states` | GET | View active firewall states |

---

## Troubleshooting Commands Used

### Check Interface Status
```powershell
$r = (Invoke-WebRequest -Uri 'http://192.168.10.1/api/v2/status/interfaces' `
    -Headers $headers -Method GET).Content | ConvertFrom-Json
$r.data | Where-Object { $_.name -eq 'opt1' } | Format-List
```

### Check Firewall Rules
```powershell
$r = (Invoke-WebRequest -Uri 'http://192.168.10.1/api/v2/firewall/rules' `
    -Headers $headers -Method GET).Content | ConvertFrom-Json
$r.data | Where-Object { $_.interface -eq 'opt1' } | Format-Table
```

### Check Firewall States
```powershell
$states = (Invoke-WebRequest -Uri 'http://192.168.10.1/api/v2/firewall/states' `
    -Headers $headers -Method GET).Content | ConvertFrom-Json
$states.data | Where-Object { $_.interface -eq 'hn2' } | Format-Table
```

### Test Connectivity
```powershell
ping -n 5 192.168.50.1
```

---

## Timeline of Diagnosis

1. **Initial Hypothesis**: VMs on wrong virtual switch
   - **Result**: Confirmed VMs already on correct switch
   
2. **Second Hypothesis**: Interface not properly enabled
   - **Attempted**: API calls to enable interface, pfSense VM restart
   - **Result**: No change - issue persisted
   
3. **Third Hypothesis**: Firewall rules blocking traffic
   - **Observation**: Rules existed and were enabled, but no states created
   - **Action**: Enabled logging on ICMP rule
   
4. **Final Discovery**: Firewall configuration not applied
   - **Action**: Called `/api/v2/firewall/apply` endpoint
   - **Result**: ✅ **Immediate success** - connectivity restored

---

## References

- pfSense REST API v2.6.4 Documentation
- Repository memory: `/memories/repo/pfsense-api-v264.md`

---

## Related Files

- `setup-interfaces/configure_training_interface_api.py` - Initial OPT1 interface setup
- `setup-interfaces/EXECUTION-LOG.md` - Original interface configuration log
- `TRAINING-LAN-DIAGNOSIS.md` - Initial diagnostic report (outdated theory)
- `MANUAL-FIX-INSTRUCTIONS.md` - Manual fix instructions (outdated)

---

**Resolution Date**: April 28, 2026  
**Total Troubleshooting Time**: ~2 hours  
**Final Status**: Training LAN fully operational ✅
