# Configure Network Settings for training_1 VM
# Run this script INSIDE the training_1 VM

Write-Host "`n=== Configuring Network for training_1 VM ===" -ForegroundColor Cyan

# Get network adapter name
$adapter = Get-NetAdapter | Where-Object {$_.Status -eq 'Up'} | Select-Object -First 1
$adapterName = $adapter.Name

Write-Host "`nNetwork Adapter: $adapterName" -ForegroundColor Yellow

# Configure static IP with gateway and DNS
Write-Host "`n1. Setting IP Address: 192.168.50.20/24" -ForegroundColor Cyan
New-NetIPAddress -InterfaceAlias $adapterName -IPAddress 192.168.50.20 -PrefixLength 24 -DefaultGateway 192.168.50.1 -ErrorAction SilentlyContinue

Write-Host "`n2. Setting DNS Server: 8.8.8.8" -ForegroundColor Cyan
Set-DnsClientServerAddress -InterfaceAlias $adapterName -ServerAddresses 8.8.8.8,8.8.4.4

Write-Host "`n3. Verifying configuration..." -ForegroundColor Cyan
Get-NetIPAddress -InterfaceAlias $adapterName -AddressFamily IPv4 | Select-Object IPAddress, PrefixLength
Get-NetRoute -InterfaceAlias $adapterName -DestinationPrefix "0.0.0.0/0" | Select-Object DestinationPrefix, NextHop
Get-DnsClientServerAddress -InterfaceAlias $adapterName -AddressFamily IPv4 | Select-Object ServerAddresses

Write-Host "`n4. Testing connectivity..." -ForegroundColor Cyan
Write-Host "   Testing gateway (192.168.50.1)..." -ForegroundColor Yellow
$gw = Test-Connection -ComputerName 192.168.50.1 -Count 2 -Quiet
Write-Host "   Gateway: $(if($gw){'✓ OK'}else{'✗ FAILED'})" -ForegroundColor $(if($gw){'Green'}else{'Red'})

Write-Host "   Testing Internet (8.8.8.8)..." -ForegroundColor Yellow
$inet = Test-Connection -ComputerName 8.8.8.8 -Count 2 -Quiet
Write-Host "   Internet: $(if($inet){'✓ OK'}else{'✗ FAILED'})" -ForegroundColor $(if($inet){'Green'}else{'Red'})

Write-Host "   Testing DNS (google.com)..." -ForegroundColor Yellow
$dns = Test-Connection -ComputerName google.com -Count 1 -Quiet -ErrorAction SilentlyContinue
Write-Host "   DNS: $(if($dns){'✓ OK'}else{'✗ FAILED'})" -ForegroundColor $(if($dns){'Green'}else{'Red'})

if($gw -and $inet -and $dns) {
    Write-Host "`n✓✓✓ SUCCESS! Internet is working on training_1! ✓✓✓" -ForegroundColor Green
} else {
    Write-Host "`n⚠️ Some tests failed - check configuration" -ForegroundColor Yellow
}
