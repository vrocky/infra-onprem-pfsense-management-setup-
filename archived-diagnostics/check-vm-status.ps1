$vm = Get-VM -Name training_1 -ErrorAction Stop
$adapter = Get-VMNetworkAdapter -VMName training_1
Write-Output "=== VM Status ==="
Write-Output "Name: $($vm.Name)"
Write-Output "State: $($vm.State)"
Write-Output "Uptime: $($vm.Uptime)"
Write-Output "`n=== Network Adapter ==="
Write-Output "Switch: $($adapter.SwitchName)"
Write-Output "MacAddress: $($adapter.MacAddress)"
Write-Output "Status: $($adapter.Status)"
Write-Output "Connected: $($adapter.Connected)"
