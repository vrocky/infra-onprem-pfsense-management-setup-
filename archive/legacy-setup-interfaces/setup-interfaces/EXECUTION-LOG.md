# Execution Log

Date: 2026-04-28
Scope: prepare training-vm-lan subnet setup runbook and scripts for repeatable execution.

## Created

- setup-interfaces/README.md
- setup-interfaces/01-set-host-training-vswitch-ip.ps1
- setup-interfaces/02-verify-training-lan.ps1
- setup-interfaces/03-configure-pfsense-training-interface.md

## Verification Run

Command:

powershell -ExecutionPolicy Bypass -File .\\setup-interfaces\\02-verify-training-lan.ps1

Observed output:

- VmName: PFSenseVM
- SwitchName: training-vm-lan
- VmNicMac: 00155D00A09C
- VmNicStatus: Ok
- HostInterfaceAlias: vEthernet (training-vm-lan)
- HostIPv4: 169.254.152.26/16

Interpretation:

- Adapter binding is healthy.
- Host interface is currently APIPA (169.254.x.x), so explicit subnet assignment is still pending.
- Run 01-set-host-training-vswitch-ip.ps1, then complete pfSense interface configuration using 03-configure-pfsense-training-interface.md.

## Follow-up Run

Date: 2026-04-28

Completed:

- Executed `setup-interfaces/01-set-host-training-vswitch-ip.ps1` successfully.
- Host interface now: `vEthernet (training-vm-lan) = 192.168.50.254/24`.
- Opened Hyper-V console for `PFSenseVM` using `vmconnect` to enable DHCP on training interface.

Verification after host-side change:

- `setup-interfaces/02-verify-training-lan.ps1` shows host IP `192.168.50.254/24` and VM NIC status `Ok`.
- `Test-NetConnection 192.168.50.1 -Port 443` failed at this moment, indicating pfSense training interface IP/DHCP still needs to be finalized inside pfSense console.

## API Automation Added

Date: 2026-04-28

Implemented:

- Added API-first configuration script: `setup-interfaces/configure_training_interface_api.py`
- Added endpoint/payload template config: `setup-interfaces/api-config.sample.json`
- Added Python dependency file: `setup-interfaces/requirements.txt`
- Updated runbook to use API as primary path: `setup-interfaces/README.md`

Intent:

- Discover training interface via API.
- Set interface IPv4 (target 192.168.50.1/24).
- Enable/configure DHCP range (192.168.50.20-192.168.50.199).
- Apply configuration via API endpoint.
