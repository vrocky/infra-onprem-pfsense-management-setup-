# pfSense API PoC (PowerShell)

This is a small proof-of-concept to test pfSense API access from your Hyper-V host.

## Prerequisites

- pfSense API is installed/enabled on `PFSenseVM`
- You have a valid API token
- You can reach pfSense WebGUI from this machine

## Files

- `pfsense-api-poc.ps1`: Generic API caller
- `request-sample.json`: Example request body
- `apply-rdp-chain.ps1`: Automation runner for chained Firewall-1/Firewall-2 RDP forwards
- `rdp-chain-manifest.sample.json`: Environment and mapping inventory for automation
- `templates/fw1-port-forward.template.json`: Firewall-1 NAT payload template
- `templates/fw2-port-forward.template.json`: Firewall-2 NAT payload template

## Quick Start

1. Set variables in PowerShell:

```powershell
$baseUrl = "https://<PFSENSE_LAN_IP>"
$token = "<API_TOKEN>"
```

2. Test an endpoint (adjust endpoint to your pfSense API docs):

```powershell
.\pfsense-api-poc.ps1 -BaseUrl $baseUrl -ApiToken $token -Endpoint "/api/v1/system/status" -Method GET -SkipCertificateCheck
```

3. Test a request with JSON body:

```powershell
.\pfsense-api-poc.ps1 -BaseUrl $baseUrl -ApiToken $token -Endpoint "/api/v1/example" -Method POST -BodyFile .\request-sample.json -SkipCertificateCheck
```

## Notes

- `-SkipCertificateCheck` is intended for lab/self-signed cert use only.
- If you get `401/403`, verify token and API permissions.
- If endpoint returns `404`, verify the correct path in your installed pfSense API package/docs.

## Chained RDP Port Forward Automation

This automates the two-firewall path:

WAN -> Firewall-1 -> VM-LAN-2 -> Firewall-2 -> training-vm-lan -> Training VMs

1. Copy and edit the sample manifest values:

```powershell
Copy-Item .\rdp-chain-manifest.sample.json .\rdp-chain-manifest.json
```

2. Set API tokens in environment variables:

```powershell
$env:PFSENSE_FW1_TOKEN = "<FW1_API_TOKEN>"
$env:PFSENSE_FW2_TOKEN = "<FW2_API_TOKEN>"
```

3. Dry-run first (shows payloads and endpoints, no changes made):

```powershell
.\apply-rdp-chain.ps1 -ManifestPath .\rdp-chain-manifest.json -DryRun
```

4. Apply changes:

```powershell
.\apply-rdp-chain.ps1 -ManifestPath .\rdp-chain-manifest.json
```

5. Validate from WAN side:

```powershell
Test-NetConnection <FIREWALL1_WAN_IP> -Port 53389
mstsc /v:<FIREWALL1_WAN_IP>:53389
```

Important:

- JSON field names in template files may differ depending on your pfSense API package. If your API expects different keys, update only the template files and keep the runner unchanged.

## Maintained NAT Table For Training VMs (Recommended)

For the simpler single-firewall design, maintain all training RDP NAT rules from one inventory file.

### Files

- `training-vm-inventory.sample.json`: Source-of-truth VM list (name + IP + enabled)
- `training-rdp-sync.config.sample.json`: Firewall/API and mapping settings
- `sync-training-rdp-nat.ps1`: Generates NAT mapping table and syncs rules

### Mapping Logic

- WAN port = `wanPortBase + VM_IP_suffix`
- Example with base `40000`: VM `192.168.50.21` gets WAN port `40021`

### Setup

1. Copy sample files:

```powershell
Copy-Item .\training-vm-inventory.sample.json .\training-vm-inventory.json
Copy-Item .\training-rdp-sync.config.sample.json .\training-rdp-sync.config.json
```

2. Edit both copied files with your real IPs/endpoints.

3. Set token:

```powershell
$env:PFSENSE_FW1_TOKEN = "<FW1_API_TOKEN>"
```

### Safe Run Order

1. Generate mapping table only:

```powershell
.\sync-training-rdp-nat.ps1 -ConfigPath .\training-rdp-sync.config.json -GenerateOnly
```

2. Dry-run API calls:

```powershell
.\sync-training-rdp-nat.ps1 -ConfigPath .\training-rdp-sync.config.json -DryRun
```

3. Apply changes:

```powershell
.\sync-training-rdp-nat.ps1 -ConfigPath .\training-rdp-sync.config.json
```

### Output

Generated files in `generated` folder:

- `training-rdp-nat-table.csv`
- `training-rdp-nat-table.md`

These files are your maintained NAT table for trainer operations.
