# Fix Training LAN Switch Mismatch
# Run this script as Administrator

$ErrorActionPreference = 'Stop'

Write-Host '=== Current Configuration ===' -ForegroundColor Cyan
Write-Host 'Host IP is on: vEthernet (training-vm-lan-new)'
Write-Host 'VMs are connected to: training-vm-lan switch'
Write-Host ''

# Check current VM connections
Write-Host '=== Current VM Network Adapters ===' -ForegroundColor Cyan
Get-VMNetworkAdapter -VMName PFSenseVM,training_1 | 
    Select-Object VMName,Name,SwitchName,MacAddress | 
    Format-Table -AutoSize

Write-Host ''
Write-Host '=== Applying Fix: Moving VMs to training-vm-lan-new ===' -ForegroundColor Yellow

# Move PFSense OPT1 adapter (MAC 00155D00A09C) to training-vm-lan-new
$pfOpt1 = Get-VMNetworkAdapter -VMName 'PFSenseVM' | 
    Where-Object { $_.MacAddress -eq '00155D00A09C' }

if ($pfOpt1) {
    Write-Host "Moving PFSense OPT1 (hn2) to training-vm-lan-new..."
    Connect-VMNetworkAdapter -VMNetworkAdapter $pfOpt1 -SwitchName 'training-vm-lan-new'
    Write-Host "  ✓ PFSense OPT1 moved" -ForegroundColor Green
} else {
    Write-Host "  ✗ PFSense OPT1 adapter not found by MAC" -ForegroundColor Red
}

# Move training_1 adapter to training-vm-lan-new
$tr1 = Get-VMNetworkAdapter -VMName 'training_1' | Select-Object -First 1

if ($tr1) {
    Write-Host "Moving training_1 to training-vm-lan-new..."
    Connect-VMNetworkAdapter -VMNetworkAdapter $tr1 -SwitchName 'training-vm-lan-new'
    Write-Host "  ✓ training_1 moved" -ForegroundColor Green
} else {
    Write-Host "  ✗ training_1 adapter not found" -ForegroundColor Red
}

Write-Host ''
Write-Host '=== Final VM Network Configuration ===' -ForegroundColor Cyan
Get-VMNetworkAdapter -VMName PFSenseVM,training_1 | 
    Select-Object VMName,Name,SwitchName,MacAddress | 
    Format-Table -AutoSize

Write-Host ''
Write-Host '=== Testing Connectivity ===' -ForegroundColor Cyan
Start-Sleep -Seconds 2
Write-Host 'Pinging 192.168.50.1 (PFSense OPT1)...'
ping -n 4 192.168.50.1

Write-Host ''
Write-Host 'Pinging 192.168.50.20 (training_1 expected IP)...'
ping -n 2 192.168.50.20

Write-Host ''
Write-Host '=== Script Complete ===' -ForegroundColor Green
Write-Host 'If pings still fail, check PFSense firewall rules and DHCP server on OPT1'
