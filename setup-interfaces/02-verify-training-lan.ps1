param(
    [string]$VmName = "PFSenseVM",
    [string]$SwitchName = "training-vm-lan",
    [string]$HostInterfaceAlias = "vEthernet (training-vm-lan)"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$vmNic = Get-VMNetworkAdapter -VMName $VmName | Where-Object { $_.SwitchName -eq $SwitchName }
if (-not $vmNic) {
    throw "VM adapter on switch '$SwitchName' not found for VM '$VmName'."
}

$hostIps = Get-NetIPAddress -InterfaceAlias $HostInterfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Select-Object IPAddress, PrefixLength

$result = [pscustomobject]@{
    VmName = $VmName
    SwitchName = $SwitchName
    VmNicMac = $vmNic.MacAddress
    VmNicStatus = ($vmNic.Status -join ",")
    HostInterfaceAlias = $HostInterfaceAlias
    HostIPv4 = if ($hostIps) { ($hostIps | ForEach-Object { "$($_.IPAddress)/$($_.PrefixLength)" }) -join ", " } else { "NONE" }
}

$result | Format-List
