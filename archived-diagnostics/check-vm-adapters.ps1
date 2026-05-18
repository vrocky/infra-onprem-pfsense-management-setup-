# Check VM Network Configuration
# This will output to a file

$ErrorActionPreference = 'Continue'

try {
    $vmAdapters = Get-VMNetworkAdapter -VMName PFSenseVM,training_1 -ErrorAction Stop
    
    Write-Output "=== VM Network Adapter Configuration ==="
    Write-Output ""
    $vmAdapters | Select-Object VMName,Name,SwitchName,MacAddress | Format-Table -AutoSize | Out-String
    
    Write-Output "=== PFSense Adapters Detail ==="
    $vmAdapters | Where-Object { $_.VMName -eq 'PFSenseVM' } | Format-List VMName,Name,SwitchName,MacAddress
    
    Write-Output "=== training_1 Adapters Detail ==="
    $vmAdapters | Where-Object { $_.VMName -eq 'training_1' } | Format-List VMName,Name,SwitchName,MacAddress
    
    Write-Output "=== Summary ==="
    foreach($adapter in $vmAdapters) {
        Write-Output "$($adapter.VMName) - $($adapter.MacAddress) is on switch: $($adapter.SwitchName)"
    }
    
} catch {
    Write-Output "ERROR: $($_.Exception.Message)"
}
