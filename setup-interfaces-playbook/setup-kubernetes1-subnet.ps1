param(
    [string]$InterfaceName = "KUBERNETES_1",
    [string]$SwitchName = "kubernetes-1-lan",
    [string]$NetworkSubnet = "192.168.70.0/24",
    [string]$PfSenseIP = "192.168.70.1",
    [string]$HostIP = "192.168.70.254",
    [string]$DhcpRangeStart = "192.168.70.10",
    [string]$DhcpRangeEnd = "192.168.70.250",
    [string]$PfSenseVMName = "pfSense",
    [string]$PfSenseWebUI = "http://192.168.10.1",
    [string]$PfSenseUser = "admin",
    [string]$PfSensePassword = "password",
    [switch]$SkipHyperV
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$setupScript = Join-Path $PSScriptRoot "setup-interface.ps1"
if (-not (Test-Path $setupScript)) {
    throw "Cannot find setup script: $setupScript"
}

Write-Host "Starting kubernetes_1 subnet setup..." -ForegroundColor Cyan
Write-Host "InterfaceName : $InterfaceName"
Write-Host "SwitchName    : $SwitchName"
Write-Host "NetworkSubnet : $NetworkSubnet"
Write-Host "PfSenseIP     : $PfSenseIP"
Write-Host "HostIP        : $HostIP"

& $setupScript `
    -InterfaceName $InterfaceName `
    -SwitchName $SwitchName `
    -NetworkSubnet $NetworkSubnet `
    -PfSenseIP $PfSenseIP `
    -HostIP $HostIP `
    -DhcpRangeStart $DhcpRangeStart `
    -DhcpRangeEnd $DhcpRangeEnd `
    -PfSenseVMName $PfSenseVMName `
    -PfSenseWebUI $PfSenseWebUI `
    -PfSenseUser $PfSenseUser `
    -PfSensePassword $PfSensePassword `
    -SkipHyperV:$SkipHyperV
