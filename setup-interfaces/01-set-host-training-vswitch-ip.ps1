param(
    [string]$InterfaceAlias = "vEthernet (training-vm-lan)",
    [string]$HostIp = "192.168.50.254",
    [int]$PrefixLength = 24,
    [string]$Gateway = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-Admin {
    $current = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $current.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this script from an elevated PowerShell session."
    }
}

Assert-Admin

$adapter = Get-NetAdapter -Name $InterfaceAlias -ErrorAction SilentlyContinue
if (-not $adapter) {
    throw "Adapter not found: $InterfaceAlias"
}

Set-NetIPInterface -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -Dhcp Disabled

$existingV4 = Get-NetIPAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue
$alreadyPresent = $false

foreach ($ip in $existingV4) {
    if ($ip.IPAddress -eq $HostIp -and $ip.PrefixLength -eq $PrefixLength) {
        $alreadyPresent = $true
        continue
    }

    Remove-NetIPAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -IPAddress $ip.IPAddress -Confirm:$false
}

if (-not $alreadyPresent) {
    $newParams = @{
        InterfaceAlias = $InterfaceAlias
        IPAddress = $HostIp
        PrefixLength = $PrefixLength
        AddressFamily = "IPv4"
    }

    if (-not [string]::IsNullOrWhiteSpace($Gateway)) {
        $newParams["DefaultGateway"] = $Gateway
    }

    New-NetIPAddress @newParams | Out-Null
}

$final = Get-NetIPAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 |
    Select-Object InterfaceAlias, IPAddress, PrefixLength

Write-Host "Host interface configured:"
$final | Format-Table -AutoSize
