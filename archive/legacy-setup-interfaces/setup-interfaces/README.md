# Interface Setup Runbook (API First)

Purpose: make training-vm-lan setup repeatable with minimal operator error using pfSense API.

Use this folder to assign subnet and DHCP for training VMs behind pfSense on Hyper-V.

## Files

- 01-set-host-training-vswitch-ip.ps1
  - Idempotent host-side IPv4 setup for vEthernet (training-vm-lan).
- 02-verify-training-lan.ps1
  - Verifies PFSenseVM binding, MAC, NIC status, and host IPv4 state.
- configure_training_interface_api.py
  - API workflow to discover training interface, set IPv4, enable DHCP range, and apply changes.
- api-config.sample.json
  - Endpoint/payload templates for your pfSense API package.
- requirements.txt
  - Python dependency list for API scripts.
- 03-configure-pfsense-training-interface.md
  - Console fallback procedure if API package endpoints are unavailable.
- EXECUTION-LOG.md
  - Historical run evidence and observations.

## Standard Target State

- VM: PFSenseVM
- Switches: WAN, VM-LAN-2, training-vm-lan
- pfSense training interface IP: 192.168.50.1/24
- Host vEthernet (training-vm-lan): 192.168.50.254/24
- DHCP pool for training clients: 192.168.50.20-192.168.50.199

## Prerequisites

- Run commands from elevated PowerShell (Administrator).
- Hyper-V role available on host.
- VM name is PFSenseVM.
- You have a pfSense API token.
- Python available on host.

## Safe Execution Order

1. Pre-check current state:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-interfaces\02-verify-training-lan.ps1
```

Expected:
- SwitchName is training-vm-lan
- VmNicStatus is Ok

2. Set host-side training interface subnet:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-interfaces\01-set-host-training-vswitch-ip.ps1
```

Expected:
- Host interface shows 192.168.50.254/24

3. Configure pfSense training interface and DHCP via API:

```powershell
pip install -r .\setup-interfaces\requirements.txt
Copy-Item .\setup-interfaces\api-config.sample.json .\setup-interfaces\api-config.json
$env:PFSENSE_FW1_TOKEN = "<FW1_API_TOKEN>"
python .\setup-interfaces\configure_training_interface_api.py --config .\setup-interfaces\api-config.json --dry-run
python .\setup-interfaces\configure_training_interface_api.py --config .\setup-interfaces\api-config.json
```

Required target values in api-config.json:
- desired.interfaceIp: 192.168.50.1
- desired.subnetBits: 24
- desired.dhcpEnabled: true
- desired.dhcpRangeStart: 192.168.50.20
- desired.dhcpRangeEnd: 192.168.50.199

4. Post-check from host:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-interfaces\02-verify-training-lan.ps1
Test-NetConnection 192.168.50.1 -Port 443 | Select-Object ComputerName,RemotePort,TcpTestSucceeded
```

Expected:
- HostIPv4 includes 192.168.50.254/24
- TcpTestSucceeded = True (after pfSense interface is correctly configured)

## If Something Fails

- If HostIPv4 is 169.254.x.x:
  - Re-run 01-set-host-training-vswitch-ip.ps1 in elevated shell.
- If test to 192.168.50.1:443 fails:
  - Confirm correct API endpoints for your pfSense API package in api-config.json.
  - Confirm interface.discover matchField/matchValue correctly identifies training-vm-lan.
  - Confirm desired.interfaceIp and DHCP range values are correct.
  - If needed, use 03-configure-pfsense-training-interface.md as fallback.
- If VM NIC is not attached to training-vm-lan:
  - Fix Hyper-V adapter switch mapping before any pfSense changes.

## Re-run and Maintenance Rules

- Script 01 is intended to be idempotent and safe to re-run.
- Always run script 02 before and after changes.
- Record each run result in EXECUTION-LOG.md.
- If changing subnet in future, change both:
  - Script 01 parameters (host-side IP/prefix)
  - pfSense interface IP and DHCP range values

## One-Command Quick Start (Host Side)

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-interfaces\01-set-host-training-vswitch-ip.ps1; powershell -ExecutionPolicy Bypass -File .\setup-interfaces\02-verify-training-lan.ps1
```

If API endpoints differ in your environment, adjust only api-config.json templates.
