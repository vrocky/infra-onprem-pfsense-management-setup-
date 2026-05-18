# kubernetes_1 Subnet Setup

This guide sets up a dedicated subnet for kubernetes_1 using the existing interface playbook automation.

## Default Network Plan

- Interface name: KUBERNETES_1
- Switch name: kubernetes-1-lan
- Subnet: 192.168.70.0/24
- pfSense interface IP: 192.168.70.1
- Host adapter IP: 192.168.70.254
- DHCP range: 192.168.70.10 to 192.168.70.250

## One-Command Run

From setup-interfaces-playbook folder:

```powershell
.\setup-kubernetes1-subnet.ps1
```

The script will:

1. Create internal Hyper-V switch.
2. Configure host adapter IP.
3. Attach pfSense VM adapter.
4. Pause and guide manual pfSense UI steps.
5. Continue with DHCP, firewall, NAT, and tests.

## If You Need Different Subnet Values

```powershell
.\setup-kubernetes1-subnet.ps1 `
  -NetworkSubnet "192.168.71.0/24" `
  -PfSenseIP "192.168.71.1" `
  -HostIP "192.168.71.254" `
  -DhcpRangeStart "192.168.71.10" `
  -DhcpRangeEnd "192.168.71.250"
```

## Validation After Setup

From Hyper-V host:

```powershell
Test-Connection -ComputerName 192.168.70.1 -Count 4
```

From kubernetes_1 VM:

```powershell
ping 192.168.70.1 -n 4
ping 8.8.8.8 -n 4
ping google.com -n 2
```

## Notes

- Keep outbound NAT source as KUBERNETES_1 subnets and destination as Any.
- Always apply changes after firewall/NAT edits.
- If 192.168.70.0/24 conflicts in your environment, use a different /24.
