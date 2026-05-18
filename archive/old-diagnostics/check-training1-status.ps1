# Check training_1 VM status and write to output file
$outputFile = "$PSScriptRoot\training1-vm-status.txt"

try {
    $vm = Get-VM -Name training_1 -ErrorAction Stop
    
    $output = @"
VM Status Check - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
============================================
VM Name: $($vm.Name)
State: $($vm.State)
Uptime: $($vm.Uptime)
CPU Usage: $($vm.CPUUsage)%
Memory: $([math]::Round($vm.MemoryAssigned/1GB, 2)) GB

Network Adapters:
"@
    
    $adapters = Get-VMNetworkAdapter -VMName training_1
    foreach ($adapter in $adapters) {
        $output += "`n  - Name: $($adapter.Name)"
        $output += "`n    Switch: $($adapter.SwitchName)"
        $output += "`n    MAC: $($adapter.MacAddress)"
        $output += "`n    IP Addresses: $($adapter.IPAddresses -join ', ')"
    }
    
    $output | Out-File -FilePath $outputFile -Encoding UTF8
    Write-Host "Status written to: $outputFile" -ForegroundColor Green
    
} catch {
    "ERROR: $($_.Exception.Message)" | Out-File -FilePath $outputFile -Encoding UTF8
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
