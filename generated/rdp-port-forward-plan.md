# RDP Port Forwarding Plan (Simple Single-Firewall Model)

## Goal
Keep design simple with one firewall doing all inbound WAN RDP NAT to training VMs.

Topology:

WAN -> Firewall-1 (pfSense on PFSenseVM) -> VM-LAN-2 (different subnet)

WAN -> Firewall-1 (pfSense on PFSenseVM) -> training-vm-lan -> Training VMs (different subnet)

## Core Idea
Use deterministic port mapping based on VM IP suffix so WAN RDP port is predictable.

Example rule formula:

- Training VM IP: 192.168.50.X
- WAN RDP port: 40000 + X
- Destination: 192.168.50.X:3389

Examples:

- 192.168.50.21 -> WAN TCP 40021 -> 192.168.50.21:3389
- 192.168.50.35 -> WAN TCP 40035 -> 192.168.50.35:3389
- 192.168.50.109 -> WAN TCP 40109 -> 192.168.50.109:3389

## Why This Is Simple
1. No second firewall NAT chain.
2. Port mapping can be generated automatically from IP list.
3. Trainers can infer RDP port directly from VM suffix.
4. Easy troubleshooting: one firewall, one NAT table.

## Assumptions to Confirm
1. Firewall-1 has interface in `training-vm-lan` and can route to training VMs.
2. Training VMs use static or DHCP-reserved IP addresses.
3. Training VMs allow inbound TCP 3389 in Windows Firewall.
4. pfSense API token has permission to manage NAT and rules.

## Implementation Plan
1. Define training subnet and allowed suffix range (example 20-199).
2. Reserve VM IPs to avoid suffix drift.
3. Generate NAT rules using formula `WAN port = 40000 + suffix`.
4. Create associated WAN pass rules automatically.
5. Apply pfSense changes once after batch rule creation.
6. Export a mapping table for trainer operations.

## Automation Inputs
1. Firewall-1 base URL and API token.
2. Training subnet (example 192.168.50.0/24).
3. VM list (name + IP).
4. Base WAN port prefix (default 40000).

## Validation Checklist
1. `Test-NetConnection <WAN_IP> -Port 40021` succeeds for VM suffix 21.
2. `mstsc /v:<WAN_IP>:40021` opens VM with IP suffix 21.
3. No duplicate WAN ports are generated.
4. NAT + WAN pass rule exists per VM.

## Rollback Plan
1. Disable auto-created NAT rules by description prefix (example `AUTO_RDP_`).
2. Disable/remove associated WAN pass rules with same prefix.
3. Re-test that mapped WAN ports no longer respond.

## Next Action
Generate a VM inventory file and run one script to create all NAT/pass rules from IP suffix automatically.
