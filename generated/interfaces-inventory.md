# PFSenseVM Interface Inventory

Date: 2026-04-28
Source: Hyper-V host observations

## VM Interface Assignments

| Interface (Switch) | MAC | Assigned IPs (Observed) | Subnet Info |
| --- | --- | --- | --- |
| WAN | 00:15:5D:00:A0:33 | 192.168.1.10, fe80::215:5dff:fe00:a033 | IPv4 appears on 192.168.1.0/24 |
| VM-LAN-2 | 00:15:5D:00:A0:35 | 192.168.10.1, fe80::215:5dff:fe00:a035 | IPv4 appears on 192.168.10.0/24 |
| training-vm-lan | 00:15:5D:00:A0:9C | None observed from host integration data | Subnet not directly observed from VM integration data |

## Host vEthernet Prefix Evidence

| Host Interface Alias | Host IPv4 | Prefix |
| --- | --- | --- |
| vEthernet (WAN) | 192.168.1.12 | /24 |
| vEthernet (VM-LAN-2) | 192.168.10.101 | /24 |
| vEthernet (training-vm-lan) | 169.254.152.26 | /16 (APIPA, not reliable for training subnet design) |

## Notes

- WAN and VM-LAN-2 subnets are consistent between VM-assigned addresses and host-side prefixes.
- training-vm-lan currently has no VM-reported IPv4 assignment in Hyper-V integration output.
- To confirm the intended training subnet (for example 192.168.50.0/24), verify inside pfSense interface settings or via pfSense API interface endpoint.
