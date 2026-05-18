# Configure pfSense training-vm-lan Subnet

Objective: assign a real IPv4 subnet to pfSense interface connected to training-vm-lan.

Recommended subnet:
- Interface IP: 192.168.50.1/24
- Training subnet: 192.168.50.0/24
- DHCP range: 192.168.50.20 to 192.168.50.199

## Console Steps (pfSense VM)

1. Open Hyper-V console for PFSenseVM.
2. In pfSense menu, choose option 2 (Set interface IP address).
3. Select interface mapped to training-vm-lan (often OPTx).
4. Enter static IPv4 address: 192.168.50.1
5. Enter subnet bit count: 24
6. Enter upstream gateway: leave blank for LAN type interface.
7. Enable DHCP server on this interface: y
8. Enter DHCP start: 192.168.50.20
9. Enter DHCP end: 192.168.50.199
10. Save and apply.

## Verify From pfSense Console

1. Choose option 1 (Assign Interfaces) only if interface mapping is wrong.
2. Choose option 8 (Shell), then run:

ifconfig
netstat -rn

Expected:
- Interface for training-vm-lan has 192.168.50.1/24
- Route includes connected network 192.168.50.0/24

## Verify From Hyper-V Host

Run:

.\\setup-interfaces\\02-verify-training-lan.ps1

Then test reachability to pfSense training interface:

Test-NetConnection 192.168.50.1 -Port 443
