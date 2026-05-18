# KUBERNETES_1 Subnet Setup — How We Did It

## Overview

Set up a dedicated isolated subnet for Kubernetes workloads (`KUBERNETES_1`) on pfSense using Hyper-V internal networking and pfSense API v2.

| Item | Value |
|---|---|
| Hyper-V switch | `kubernetes-1-lan` |
| pfSense interface | `hn3` → `opt2` → `KUBERNETES_1` |
| Subnet | `192.168.70.0/24` |
| pfSense gateway IP | `192.168.70.1` |
| Host adapter IP | `192.168.70.254` |
| DHCP range | `192.168.70.10 – 192.168.70.250` |

---

## Full Interface Map (after setup)

| NIC | pfSense name | Role | IP |
|---|---|---|---|
| hn0 | WAN | Uplink to external network | 192.168.1.10/24 |
| hn1 | LAN | Management / main LAN | 192.168.10.1/24 |
| hn2 | opt1 / TRAININGLAN | Training VMs subnet | 192.168.50.1/24 |
| hn3 | opt2 / KUBERNETES_1 | Kubernetes workloads subnet | 192.168.70.1/24 |

---

## Steps Performed

### 1. Create Hyper-V Internal Switch

```powershell
New-VMSwitch -Name "kubernetes-1-lan" -SwitchType Internal
```

Creates an isolated internal switch. VMs connected to it are isolated from the physical network but can reach the host and pfSense.

---

### 2. Assign Host Adapter IP

```powershell
$adapter = Get-NetAdapter | Where-Object { $_.Name -like "*kubernetes-1-lan*" }
New-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex `
    -IPAddress "192.168.70.254" -PrefixLength 24
```

The host gets `192.168.70.254` — useful for reaching VMs and for diagnostics without going through pfSense routing.

---

### 3. Attach pfSense VM to the Switch

```powershell
Add-VMNetworkAdapter -VMName "PFSenseVM" -SwitchName "kubernetes-1-lan"
```

This adds `hn3` to the pfSense VM. pfSense detects it as a new unassigned NIC.

---

### 4. Assign Interface in pfSense UI (manual step)

> This step must be done in the pfSense web UI because the interface assignment API is not reliably available.

1. Browse to `http://192.168.10.1` → **Interfaces → Assignments**
2. Under "Available network ports", select `hn3`
3. Click **+ Add** → this creates `OPT2`
4. Click on **OPT2** to configure:
   - **Enable**: checked
   - **Description**: `KUBERNETES_1`
   - **IPv4 Configuration Type**: Static IPv4
   - **IPv4 Address**: `192.168.70.1 / 24`
5. **Save** → **Apply Changes**

After this, pfSense recognises `hn3` as `opt2` / `KUBERNETES_1`.

---

### 5. Enable DHCP Server via API

```powershell
$pair = 'admin:password'
$b64  = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
$h    = @{
    Authorization  = "Basic $b64"
    Accept         = 'application/json'
    'Content-Type' = 'application/json'
}

$body = @{
    id         = "opt2"
    enable     = $true
    range_from = "192.168.70.10"
    range_to   = "192.168.70.250"
    gateway    = "192.168.70.1"
    dnsserver  = @("192.168.70.1")
} | ConvertTo-Json

Invoke-WebRequest -Uri 'http://192.168.10.1/api/v2/services/dhcp_server' `
    -Method PATCH -Headers $h -Body $body -UseBasicParsing
```

**Endpoint**: `PATCH /api/v2/services/dhcp_server`  
**Key field**: `id` must be the pfSense interface id (`opt2`), not the description name.  
Returns HTTP 200 with `enable: True` on success.

---

### 6. Create Firewall Allow Rule via API

Without a firewall rule, pfSense blocks all traffic from `opt2` by default.

```powershell
$rule = @{
    type        = "pass"
    interface   = @("opt2")
    protocol    = "tcp/udp"
    source      = "any"
    destination = "any"
    descr       = "Allow KUBERNETES_1 to any"
} | ConvertTo-Json

Invoke-WebRequest -Uri 'http://192.168.10.1/api/v2/firewall/rule' `
    -Method POST -Headers $h -Body $rule -UseBasicParsing
```

**Key field**: `interface` takes the internal id `opt2`, not the description `KUBERNETES_1`.  
**Key field**: `protocol` must be a known value — `tcp/udp` works; `any` returns an error.

---

### 7. Apply All Changes

```powershell
Invoke-WebRequest -Uri 'http://192.168.10.1/api/v2/firewall/apply' `
    -Method POST -Headers $h -Body '{"async":false}' -UseBasicParsing
```

Always call this after creating DHCP or firewall rules. Without it, changes are staged but not active.

---

### 8. Outbound NAT (manual step — API endpoint not available)

For VMs on KUBERNETES_1 to reach the internet, outbound NAT must be added manually:

1. pfSense → **Firewall → NAT → Outbound**
2. Switch to **Hybrid Outbound NAT**
3. **Add** a new mapping:
   - **Interface**: WAN
   - **Source**: `192.168.70.0/24` (KUBERNETES_1 subnet)
   - **Destination**: any
   - **Translation / Target**: Interface address (WAN)
4. **Save** → **Apply Changes**

> `PATCH /api/v2/firewall/nat/outbound` returns 404 on this pfSense version — cannot be automated.

---

## Automation Scripts

| Script | Purpose |
|---|---|
| [setup-interfaces-playbook/setup-kubernetes1-subnet.ps1](../setup-interfaces-playbook/setup-kubernetes1-subnet.ps1) | One-command wrapper with all defaults pre-filled |
| [setup-interfaces-playbook/setup-interface.ps1](../setup-interfaces-playbook/setup-interface.ps1) | Generic reusable setup script called by wrapper |

Run with:

```powershell
cd C:\Users\ws-user\Documents\project-9\pfsense-management\setup-interfaces-playbook
.\setup-kubernetes1-subnet.ps1
```

Use `-SkipHyperV` if running without Hyper-V admin rights (skips switch and adapter steps).

---

## Validation

```powershell
# Ping pfSense gateway from host
Test-Connection -ComputerName 192.168.70.1 -Count 4

# Verify interface is up via API
$status = ((Invoke-WebRequest -Uri 'http://192.168.10.1/api/v2/status/interfaces' -Headers $h -Method GET -UseBasicParsing).Content | ConvertFrom-Json).data
$status | Where-Object { $_.if -eq 'hn3' }

# Verify DHCP is enabled
$dhcp = ((Invoke-WebRequest -Uri 'http://192.168.10.1/api/v2/services/dhcp_servers' -Headers $h -Method GET -UseBasicParsing).Content | ConvertFrom-Json).data
$dhcp | Where-Object { $_.id -eq 'opt2' } | Select-Object id,enable,range_from,range_to
```

---

## Lessons Learned / Gotchas

| # | Issue | Resolution |
|---|---|---|
| 1 | Interface assignment must be done in UI | No reliable API for assigning new NIC → manual step required |
| 2 | DHCP `id` field must be `opt2` not `KUBERNETES_1` | Use the internal pfSense interface id, not the description |
| 3 | Firewall `interface` field must be `opt2` not description | Same rule — internal id only |
| 4 | Firewall `protocol: "any"` returns API error | Use `"tcp/udp"` or specific protocol strings |
| 5 | Outbound NAT API returns 404 | Must be done via pfSense web UI |
| 6 | Changes not active until applied | Always POST to `/api/v2/firewall/apply` after changes |
| 7 | pfSense VM name is `PFSenseVM` not `pfSense` | Exact VM name matters for `Add-VMNetworkAdapter` |
