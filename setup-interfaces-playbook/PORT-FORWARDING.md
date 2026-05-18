# Port Forwarding for Training LAN

**Purpose:** Forward external ports to VMs on Training LAN (192.168.50.x)  
**Created:** April 29, 2026

---

## Port Forwarding vs Outbound NAT

### Already Configured ✅
**Outbound NAT** (Internet Access)
- Direction: Internal → Internet
- Purpose: Allow VMs to reach internet
- What we did: Created NAT rule for TRAININGLAN subnets → WAN
- Status: ✅ Working

### New Configuration 📝
**Port Forwarding (Inbound NAT)**
- Direction: Internet → Internal VM
- Purpose: Allow external connections to reach specific VM services
- Example: RDP to training_1 VM from outside network

---

## Web UI Method (Recommended for Manual Setup)

### Step 1: Navigate to Port Forward

1. Open pfSense Web UI: `http://192.168.10.1`
2. Go to: **Firewall → NAT → Port Forward**
3. Click **Add ↑** (add to top)

### Step 2: Configure Port Forward Rule

**Basic Settings:**

| Field | Value | Example |
|-------|-------|---------|
| **Disabled** | Unchecked | Rule is active |
| **No RDR** | Unchecked | Normal NAT behavior |
| **Interface** | **WAN** | Where traffic comes from |
| **Address Family** | IPv4 | |
| **Protocol** | TCP | (or UDP, or TCP/UDP) |

**Source (External):**

| Field | Value | Notes |
|-------|-------|-------|
| **Source** | Any | Allow from anywhere (or restrict to specific IP) |
| **Source Port Range** | Any | Leave as "any" |

**Destination (Your WAN):**

| Field | Value | Notes |
|-------|-------|-------|
| **Destination** | WAN address | Traffic to your public IP |
| **Destination Port Range** | Custom → **3389** | External port to forward |

**Redirect Target (Internal VM):**

| Field | Value | Example |
|-------|-------|---------|
| **Redirect Target IP** | **192.168.50.20** | training_1 VM IP |
| **Redirect Target Port** | **3389** | Port on the VM |

**Other Settings:**

| Field | Value | Notes |
|-------|-------|-------|
| **Description** | `RDP to training_1` | Clear description |
| **NAT Reflection** | Use system default | Usually "enabled" |
| **Filter Rule Association** | Add associated filter rule | Auto-creates firewall rule |

### Step 3: Save and Apply

1. Click **Save**
2. Click **Apply Changes**

---

## Configuration Examples

### Example 1: RDP to training_1

```
Interface: WAN
Protocol: TCP
Source: Any
Destination: WAN address
Destination Port: 3389 (or custom like 33891)
Redirect Target: 192.168.50.20
Redirect Port: 3389
Description: RDP to training_1
```

**Access from outside:**
```
mstsc /v:192.168.1.10:3389
```

### Example 2: Multiple VMs with Different Ports

**training_1 (RDP):**
```
Destination Port: 33891
Redirect Target: 192.168.50.20:3389
```

**training_2 (RDP):**
```
Destination Port: 33892
Redirect Target: 192.168.50.21:3389
```

**Access:**
```
mstsc /v:192.168.1.10:33891  (connects to training_1)
mstsc /v:192.168.1.10:33892  (connects to training_2)
```

### Example 3: HTTP/HTTPS Web Server

```
Destination Port: 80
Redirect Target: 192.168.50.30:80
Description: HTTP to web server
```

---

## Using port-forward-sync Tool (Bulk Operations)

### Step 1: Create Inventory File

Create `training-vms-inventory.json`:

```json
{
  "vms": [
    {
      "name": "training_1",
      "ip": "192.168.50.20",
      "hostname": "training-vm-1"
    },
    {
      "name": "training_2",
      "ip": "192.168.50.21",
      "hostname": "training-vm-2"
    }
  ]
}
```

### Step 2: Create Port Mapping Rules

Create `training-rdp-mappings.json`:

```json
{
  "port_forwards": [
    {
      "vm_name": "training_1",
      "external_port": 33891,
      "internal_port": 3389,
      "protocol": "tcp",
      "description": "RDP to training_1"
    },
    {
      "vm_name": "training_2",
      "external_port": 33892,
      "internal_port": 3389,
      "protocol": "tcp",
      "description": "RDP to training_2"
    }
  ]
}
```

### Step 3: Configure Sync Tool

Edit `port-forward-sync/config.json`:

```json
{
  "pfsense": {
    "url": "http://192.168.10.1",
    "username": "admin",
    "password": "password"
  },
  "inventory_file": "../training-vms-inventory.json",
  "mappings_file": "../training-rdp-mappings.json",
  "wan_interface": "wan"
}
```

### Step 4: Run Sync

```powershell
cd port-forward-sync
python sync_port_forward.py
```

---

## PowerShell API Method (Advanced)

### Create Single Port Forward Rule

```powershell
# Setup credentials
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('admin:password'))
$headers = @{
    Authorization = "Basic $b64"
    "Content-Type" = "application/x-www-form-urlencoded"
}

# Build form data for port forward
$formData = @(
    "disabled=no"
    "interface=wan"
    "protocol=tcp"
    "src=any"              # Source: any
    "dst=(wan)"            # Destination: WAN address
    "dstbeginport=3389"    # External port
    "dstendport=3389"      # External port end
    "target=192.168.50.20" # Internal VM IP
    "local-port=3389"      # Internal port
    "descr=RDP+to+training_1"
    "natreflection=default"
    "associated-rule-id=add-associated"  # Auto-create firewall rule
    "Save=Save"
) -join "&"

# Submit port forward rule
Invoke-WebRequest -Uri 'http://192.168.10.1/firewall_nat_edit.php' `
    -Method POST -Headers $headers -Body $formData -UseBasicParsing

# Apply changes
Start-Sleep -Seconds 2
$applyHeaders = @{
    Authorization = "Basic $b64"
    "Content-Type" = "application/json"
}
Invoke-WebRequest -Uri 'http://192.168.10.1/api/v2/firewall/apply' `
    -Method POST -Headers $applyHeaders `
    -Body '{"async":false}' -UseBasicParsing
```

---

## Automatic Firewall Rule

When you create a port forward rule with **"Add associated filter rule"**, pfSense automatically creates a matching firewall rule on the WAN interface.

**What it creates:**
- Interface: WAN
- Action: Pass
- Protocol: TCP (matching port forward)
- Source: Any (or your restriction)
- Destination: Redirected IP (192.168.50.20)
- Port: Redirected port (3389)

**You can verify:**
- Go to: **Firewall → Rules → WAN**
- Look for auto-created rule with description matching port forward

---

## Port Planning Strategy

### Use Sequential Ports

```
Base Port: 33800

training_1 RDP: 33891 → 192.168.50.20:3389
training_2 RDP: 33892 → 192.168.50.21:3389
training_3 RDP: 33893 → 192.168.50.22:3389

training_1 SSH: 22201 → 192.168.50.20:22
training_2 SSH: 22202 → 192.168.50.21:22
```

### Document Mappings

Create `TRAINING-PORT-MAPPINGS.md`:

```markdown
# Training LAN Port Forwards

| External Port | Internal VM | Internal Port | Service | Notes |
|---------------|-------------|---------------|---------|-------|
| 33891 | training_1 (192.168.50.20) | 3389 | RDP | Main training VM |
| 33892 | training_2 (192.168.50.21) | 3389 | RDP | Secondary VM |
| 8081 | training_web (192.168.50.30) | 80 | HTTP | Web server |
```

---

## Testing Port Forwards

### From External Network

```powershell
# Test port is open
Test-NetConnection -ComputerName 192.168.1.10 -Port 3389

# If successful:
ComputerName     : 192.168.1.10
RemoteAddress    : 192.168.1.10
RemotePort       : 3389
TcpTestSucceeded : True

# Connect via RDP
mstsc /v:192.168.1.10:3389
```

### From Hyper-V Host (NAT Reflection)

If NAT reflection is enabled, you can test from internal network:

```powershell
# Test from host
Test-NetConnection -ComputerName 192.168.1.10 -Port 3389

# Should also work (reflected back to internal VM)
```

---

## Troubleshooting

### Port Forward Not Working

**Check 1: Port forward rule exists**
```
Firewall → NAT → Port Forward
Verify rule is enabled (not grayed out)
```

**Check 2: Firewall rule exists**
```
Firewall → Rules → WAN
Should see auto-created rule for the port
```

**Check 3: Service is running on VM**
```powershell
# On the VM
Get-NetTCPConnection -LocalPort 3389
# Should show LISTENING state
```

**Check 4: Changes were applied**
```powershell
# Apply via API
Invoke-RestMethod -Uri 'http://192.168.10.1/api/v2/firewall/apply' `
    -Method POST -Headers @{Authorization="Basic $b64"; "Content-Type"="application/json"} `
    -Body '{"async":false}'
```

**Check 5: Test from outside network**
- Port forwards only work from external network
- From internal network, connect directly: `mstsc /v:192.168.50.20`

---

## Security Considerations

### Restrict Source IPs

Instead of allowing from "Any", restrict to specific IPs:

```
Source: Single host or alias
IP: 203.0.113.50 (your office IP)
```

### Use Non-Standard Ports

Instead of 3389 (standard RDP), use custom:

```
External Port: 33891 (custom)
Internal Port: 3389 (standard on VM)
```

Reduces automated attacks on standard ports.

### Firewall Logging

Enable logging on port forward rules:

```
Firewall → Rules → WAN
Edit auto-created rule
Check "Log packets that are handled by this rule"
```

Monitor: **Status → System Logs → Firewall**

---

## Common Patterns

### 1. RDP Access to Multiple Training VMs

```
WAN:33891 → 192.168.50.20:3389 (training_1)
WAN:33892 → 192.168.50.21:3389 (training_2)
WAN:33893 → 192.168.50.22:3389 (training_3)
```

### 2. Web Server Hosting

```
WAN:80 → 192.168.50.30:80 (HTTP)
WAN:443 → 192.168.50.30:443 (HTTPS)
```

### 3. Remote Access to Services

```
WAN:2222 → 192.168.50.20:22 (SSH)
WAN:3306 → 192.168.50.25:3306 (MySQL)
WAN:8080 → 192.168.50.30:8080 (App server)
```

---

## Quick Reference

### Web UI Path
```
Firewall → NAT → Port Forward → Add ↑
```

### Key Fields
```
Interface: WAN
Destination: WAN address
Destination Port: [external port]
Redirect Target: [VM IP]
Redirect Port: [internal port]
```

### Apply Changes
```
Click "Apply Changes" button
OR
POST /api/v2/firewall/apply
```

### Test Connection
```powershell
Test-NetConnection -ComputerName <WAN_IP> -Port <EXTERNAL_PORT>
```

---

## Related Documentation

- [Setup Interfaces Playbook](../setup-interfaces-playbook/README.md) - Interface setup
- [Port Forward Sync Tool](../port-forward-sync/README.md) - Bulk operations
- [POC Scripts](../poc/apply-rdp-chain.ps1) - RDP chain example

---

**Last Updated:** April 29, 2026  
**Applies to:** Training LAN (192.168.50.0/24) and any other pfSense interface
