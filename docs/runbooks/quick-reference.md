# Quick Reference Card - pfSense Interface Setup

## Common Commands

### Hyper-V Virtual Switch Management

```powershell
# Create internal switch
New-VMSwitch -Name "training-vm-lan-new" -SwitchType Internal

# List all switches
Get-VMSwitch

# Delete switch
Remove-VMSwitch -Name "switch-name"

# Show VM network adapters
Get-VMNetworkAdapter -VMName "pfSense"

# Add adapter to VM
Add-VMNetworkAdapter -VMName "pfSense" -SwitchName "switch-name"

# Connect VM to switch
Connect-VMNetworkAdapter -VMName "VM_NAME" -SwitchName "switch-name"
```

### Host Network Configuration

```powershell
# List network adapters
Get-NetAdapter

# Set IP address on adapter
$adapter = Get-NetAdapter | Where-Object { $_.Name -like "*switch-name*" }
New-NetIPAddress -InterfaceIndex $adapter.ifIndex `
    -IPAddress "192.168.50.254" -PrefixLength 24

# Check IP configuration
Get-NetIPAddress -AddressFamily IPv4

# Remove IP address
Remove-NetIPAddress -InterfaceIndex $adapter.ifIndex -Confirm:$false
```

### pfSense API Commands

```powershell
# Setup credentials
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('admin:password'))
$headers = @{
    Authorization = "Basic $b64"
    "Content-Type" = "application/json"
}

# Get interfaces
Invoke-RestMethod -Uri 'http://192.168.10.1/api/v2/interface' -Headers $headers

# Get specific interface
Invoke-RestMethod -Uri 'http://192.168.10.1/api/v2/interface?name=opt1' -Headers $headers

# Apply firewall changes (CRITICAL!)
$body = @{ async = $false } | ConvertTo-Json
Invoke-RestMethod -Uri 'http://192.168.10.1/api/v2/firewall/apply' `
    -Method POST -Headers $headers -Body $body

# Get firewall rules
Invoke-RestMethod -Uri 'http://192.168.10.1/api/v2/firewall/rules' -Headers $headers

# Get NAT rules (v2.6.4+)
Invoke-RestMethod -Uri 'http://192.168.10.1/api/v2/firewall/nat/outbound' -Headers $headers

# Get firewall states
Invoke-RestMethod -Uri 'http://192.168.10.1/api/v2/firewall/states' -Headers $headers

# Get gateways
Invoke-RestMethod -Uri 'http://192.168.10.1/api/v2/routing/gateways' -Headers $headers
```

### VM Network Testing

```powershell
# Inside VM - check IP configuration
ipconfig /all

# Restart network adapter
Restart-NetAdapter -Name "Ethernet"

# Renew DHCP
ipconfig /release
ipconfig /renew

# Test connectivity
ping 192.168.50.1 -n 4      # Gateway
ping 8.8.8.8 -n 4            # Internet
ping google.com -n 2         # DNS

# Trace route
tracert 8.8.8.8

# Check DNS
nslookup google.com
```

## pfSense Web UI Quick Paths

### Interface Configuration
```
Interfaces → Assignments → Add
Interfaces → [OPT1] → Configure → Save → Apply Changes
```

### DHCP Server
```
Services → DHCP Server → [Interface Name] → Enable → Configure Range → Save
```

### Firewall Rules
```
Firewall → Rules → [Interface Name] → Add ↑
  Action: Pass
  Protocol: Any
  Source: [Interface] subnets
  Destination: Any
  Save → Apply Changes
```

### NAT Configuration
```
Firewall → NAT → Outbound
  Mode: Manual Outbound NAT
  Add ↑
    Interface: WAN
    Source: [Interface] subnets
    Destination: Any
    Save → Apply Changes
```

### Diagnostics
```
Status → DHCP Leases            (Check VM leases)
Diagnostics → States            (Check firewall states)
Diagnostics → States → Filter   (Filter by source IP)
Firewall → Rules → [Interface]  (Check traffic counters)
```

## Common NAT Rule Configuration

### Correct Outbound NAT Rule
```
Interface: WAN
Address Family: IPv4
Protocol: Any
Source: TRAININGLAN subnets (or specific interface)
Destination: Any
NAT Address: WAN address
Static Port: No
```

### What Each Field Means
- **Interface**: Where traffic EXITS (usually WAN)
- **Source**: Where traffic comes FROM (internal subnet)
- **Destination**: Where traffic goes TO (Any = internet)
- **NAT Address**: What IP to translate TO (WAN = router's public IP)

## Troubleshooting Flowchart

```
Can ping gateway (192.168.50.1)?
  ├─ NO → Check Layer 1/2
  │       - VM on correct switch?
  │       - Interface enabled in pfSense?
  │       - DHCP working?
  │
  └─ YES → Can ping 8.8.8.8?
            ├─ NO → Check NAT
            │       - NAT rule exists?
            │       - Source = interface subnets?
            │       - Destination = Any?
            │       - Rule enabled (not disabled)?
            │
            └─ YES → Can ping google.com?
                      ├─ NO → DNS issue
                      │       - Check DNS servers in DHCP
                      │       - Try: nslookup google.com
                      │
                      └─ YES → Everything working! ✓
```

## IP Planning Template

```
Network:          192.168.X.0/24
pfSense Gateway:  192.168.X.1
Host Adapter:     192.168.X.254
DHCP Range:       192.168.X.10 - 192.168.X.250
Reserved Static:  192.168.X.2 - 192.168.X.9
Broadcast:        192.168.X.255
```

## Checklist

Before declaring success, verify:

- [ ] Host can ping pfSense gateway
- [ ] VM has DHCP lease (check Status → DHCP Leases)
- [ ] VM can ping gateway
- [ ] VM can ping 8.8.8.8 (tests NAT)
- [ ] VM can ping google.com (tests DNS)
- [ ] Firewall rule shows traffic/states
- [ ] NAT rule configured correctly (Source = subnets, NOT Any)

## Time Estimates

| Phase | Time | Can Skip If |
|-------|------|-------------|
| Hyper-V Setup | 5 min | Switch exists |
| pfSense Interface | 5 min | Already configured |
| DHCP Setup | 3 min | Using static IPs |
| Firewall Rules | 5 min | - |
| NAT Configuration | 5 min | Primary LAN only |
| Testing | 5 min | - |
| **Total** | **~30 min** | - |

## Common Mistakes

1. ❌ Forgetting to click "Apply Changes"
   → Always use API apply or click button

2. ❌ NAT rule backwards (Source=Any, Dest=Subnets)
   → Source should be the INTERNAL subnet

3. ❌ VM on wrong virtual switch
   → Check: `Get-VMNetworkAdapter -VMName "VM"`

4. ❌ Assuming Automatic NAT works for all interfaces
   → Only primary LAN has implicit NAT

5. ❌ Not testing incrementally
   → Test each phase before moving to next

## Files in This Playbook

- `README.md` - Complete step-by-step playbook
- `setup-interface.ps1` - Automated setup script
- `quick-reference.md` - This file (command reference)

## Related Resources

- Knowledge Book: `../knowledge-book/pfsense-nat-behavior.md`
- Issue Wins: `../issue-wins/training-lan-internet-nat-fix.md`
- API Docs: `../memories/repo/pfsense-api-v264.md`
