# Setup New pfSense Interface - Automated Script
# Based on playbook: README.md

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InterfaceName,

    [Parameter(Mandatory = $true)]
    [string]$SwitchName,

    [Parameter(Mandatory = $true)]
    [string]$NetworkSubnet,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$')]
    [string]$PfSenseIP,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$')]
    [string]$HostIP,

    [Parameter(Mandatory = $false)]
    [string]$DhcpRangeStart = "",

    [Parameter(Mandatory = $false)]
    [string]$DhcpRangeEnd = "",

    [Parameter(Mandatory = $false)]
    [string]$PfSenseVMName = "pfSense",

    [Parameter(Mandatory = $false)]
    [string]$PfSenseWebUI = "http://192.168.10.1",

    [Parameter(Mandatory = $false)]
    [string]$PfSenseUser = "admin",

    [Parameter(Mandatory = $false)]
    [string]$PfSensePassword = "password"

    ,
    [Parameter(Mandatory = $false)]
    [switch]$SkipHyperV
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:Colors = @{
    Header  = "Cyan"
    Success = "Green"
    Warning = "Yellow"
    Error   = "Red"
    Info    = "White"
    Step    = "Magenta"
}

function Write-Header {
    param([string]$Message)
    Write-Host "`n=== $Message ===" -ForegroundColor $Colors.Header
}

function Write-Step {
    param([string]$Message)
    Write-Host "`n> $Message" -ForegroundColor $Colors.Step
}

function Write-Success {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor $Colors.Success
}

function Write-Fail {
    param([string]$Message)
    Write-Host "  [X] $Message" -ForegroundColor $Colors.Error
}

function Write-Info {
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor $Colors.Info
}

function Invoke-PfSenseAPI {
    param(
        [string]$Endpoint,
        [string]$Method = "GET",
        [object]$Body = $null
    )

    $base64Auth = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${PfSenseUser}:${PfSensePassword}"))
    $headers = @{
        Authorization = "Basic $base64Auth"
        "Content-Type" = "application/json"
    }

    $uri = "${PfSenseWebUI}${Endpoint}"

    try {
        if ($null -ne $Body) {
            $jsonBody = $Body | ConvertTo-Json
            return Invoke-RestMethod -Uri $uri -Method $Method -Headers $headers -Body $jsonBody
        }
        return Invoke-RestMethod -Uri $uri -Method $Method -Headers $headers
    } catch {
        Write-Fail "API call failed: $($_.Exception.Message)"
        return $null
    }
}

if ($SkipHyperV) {
    Write-Header "Phase 1: Hyper-V Infrastructure Setup"
    Write-Info "Skipping Hyper-V operations as requested (-SkipHyperV)."
    Write-Info "Ensure switch '$SwitchName' exists, host IP '$HostIP' is configured, and pfSense is attached."
} else {
    Write-Header "Phase 1: Hyper-V Infrastructure Setup"

    Write-Step "Creating virtual switch: $SwitchName"
    try {
        $existingSwitch = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
        if ($existingSwitch) {
            Write-Info "Switch already exists, skipping creation"
        } else {
            New-VMSwitch -Name $SwitchName -SwitchType Internal | Out-Null
            Write-Success "Virtual switch created"
        }
    } catch {
        Write-Fail "Failed to create switch: $($_.Exception.Message)"
        Write-Info "Re-run from an elevated PowerShell session, or use -SkipHyperV if infra is already prepared."
        exit 1
    }

    Write-Step "Configuring host adapter IP: $HostIP"
    try {
        $adapter = Get-NetAdapter | Where-Object { $_.Name -like "*$SwitchName*" }
        if (-not $adapter) {
            Write-Fail "Cannot find adapter for switch $SwitchName"
            exit 1
        }

        $existingIP = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        if ($existingIP -and $existingIP.IPAddress -eq $HostIP) {
            Write-Info "IP already configured"
        } else {
            if ($existingIP) {
                Remove-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -Confirm:$false
            }

            $prefixLength = $NetworkSubnet.Split('/')[1]
            New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $HostIP -PrefixLength $prefixLength | Out-Null
            Write-Success "Host IP configured: $HostIP/$prefixLength"
        }
    } catch {
        Write-Fail "Failed to configure host IP: $($_.Exception.Message)"
        exit 1
    }

    Write-Step "Connecting pfSense VM to switch"
    try {
        $existingAdapter = Get-VMNetworkAdapter -VMName $PfSenseVMName | Where-Object { $_.SwitchName -eq $SwitchName }
        if ($existingAdapter) {
            Write-Info "pfSense already connected to switch"
        } else {
            Add-VMNetworkAdapter -VMName $PfSenseVMName -SwitchName $SwitchName
            Write-Success "pfSense VM connected to $SwitchName"
        }

        Write-Info "Current pfSense adapters:"
        Get-VMNetworkAdapter -VMName $PfSenseVMName | ForEach-Object {
            Write-Info "  - $($_.Name): $($_.SwitchName)"
        }
    } catch {
        Write-Fail "Failed to connect pfSense to switch: $($_.Exception.Message)"
        exit 1
    }
}

Write-Header "Phase 2: pfSense Interface Configuration"
Write-Host ""
Write-Host "The following steps must be done in the pfSense Web UI:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Open pfSense Web UI: $PfSenseWebUI" -ForegroundColor Cyan
Write-Host "2. Navigate to: Interfaces -> Assignments" -ForegroundColor Cyan
Write-Host "3. Look for new unassigned interface and click Add" -ForegroundColor Cyan
Write-Host "4. Click on the new interface (OPT1 or similar)" -ForegroundColor Cyan
Write-Host "5. Configure:" -ForegroundColor Cyan
Write-Host "   - Enable: interface enabled" -ForegroundColor White
Write-Host "   - Description: $InterfaceName" -ForegroundColor White
Write-Host "   - IPv4 Configuration Type: Static IPv4" -ForegroundColor White
Write-Host "   - IPv4 Address: $PfSenseIP / $(($NetworkSubnet -split '/')[1])" -ForegroundColor White
Write-Host "6. Click Save then Apply Changes" -ForegroundColor Cyan
Write-Host ""

$null = Read-Host "Press Enter when pfSense interface is configured..."

Write-Header "Phase 3: DHCP Server Configuration"
Write-Host ""
Write-Host "Configure DHCP in pfSense Web UI:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Navigate to: Services -> DHCP Server -> $InterfaceName" -ForegroundColor Cyan
Write-Host "2. Configure:" -ForegroundColor Cyan
Write-Host "   - Enable DHCP server on $InterfaceName interface" -ForegroundColor White
if ($DhcpRangeStart -and $DhcpRangeEnd) {
    Write-Host "   - Range From: $DhcpRangeStart" -ForegroundColor White
    Write-Host "   - Range To: $DhcpRangeEnd" -ForegroundColor White
} else {
    Write-Host "   - Range From: (e.g., $($PfSenseIP -replace '\.\d+$', '.10'))" -ForegroundColor White
    Write-Host "   - Range To: (e.g., $($PfSenseIP -replace '\.\d+$', '.250'))" -ForegroundColor White
}
Write-Host "   - DNS Servers: 8.8.8.8, 8.8.4.4" -ForegroundColor White
Write-Host "3. Click Save" -ForegroundColor Cyan
Write-Host ""

$null = Read-Host "Press Enter when DHCP is configured..."

Write-Header "Phase 4: Firewall Rules Configuration"
Write-Host ""
Write-Host "Create firewall rule in pfSense Web UI:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Navigate to: Firewall -> Rules -> $InterfaceName" -ForegroundColor Cyan
Write-Host "2. Click Add (add to top)" -ForegroundColor Cyan
Write-Host "3. Configure:" -ForegroundColor Cyan
Write-Host "   - Action: Pass" -ForegroundColor White
Write-Host "   - Interface: $InterfaceName" -ForegroundColor White
Write-Host "   - Address Family: IPv4" -ForegroundColor White
Write-Host "   - Protocol: Any" -ForegroundColor White
Write-Host "   - Source: $InterfaceName subnets" -ForegroundColor White
Write-Host "   - Destination: Any" -ForegroundColor White
Write-Host "   - Description: Allow $InterfaceName to any" -ForegroundColor White
Write-Host "4. Click Save then Apply Changes" -ForegroundColor Cyan
Write-Host ""

$null = Read-Host "Press Enter when firewall rule is configured..."

Write-Step "Applying firewall changes via API"
$applyResult = Invoke-PfSenseAPI -Endpoint "/api/v2/firewall/apply" -Method POST -Body @{ async = $false }
if ($applyResult) {
    Write-Success "Firewall changes applied"
} else {
    Write-Fail "Failed to apply firewall changes via API - click Apply Changes in Web UI"
}

Write-Header "Phase 5: NAT Configuration (Internet Access)"
Write-Host ""
Write-Host "Configure NAT in pfSense Web UI:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Navigate to: Firewall -> NAT -> Outbound" -ForegroundColor Cyan
Write-Host "2. If needed, switch to Manual Outbound NAT rule generation" -ForegroundColor Cyan
Write-Host "3. Click Add to create new NAT rule" -ForegroundColor Cyan
Write-Host "4. Configure:" -ForegroundColor Cyan
Write-Host "   - Interface: WAN" -ForegroundColor White
Write-Host "   - Address Family: IPv4" -ForegroundColor White
Write-Host "   - Protocol: Any" -ForegroundColor White
Write-Host "   - Source: $InterfaceName subnets (NOT Any)" -ForegroundColor White
Write-Host "   - Destination: Any" -ForegroundColor White
Write-Host "   - NAT Address: WAN address" -ForegroundColor White
Write-Host "   - Static Port: unchecked" -ForegroundColor White
Write-Host "   - Description: $InterfaceName to Internet NAT" -ForegroundColor White
Write-Host "5. Click Save then Apply Changes" -ForegroundColor Cyan
Write-Host ""
Write-Host "CRITICAL: Source must be '$InterfaceName subnets', NOT Any." -ForegroundColor Red
Write-Host ""

$null = Read-Host "Press Enter when NAT is configured..."

Write-Header "Phase 6: Testing and Validation"

Write-Step "Testing host to pfSense gateway connectivity"
$pingResult = Test-Connection -ComputerName $PfSenseIP -Count 2 -Quiet
if ($pingResult) {
    Write-Success "Host can reach pfSense gateway ($PfSenseIP)"
} else {
    Write-Fail "Cannot reach pfSense gateway - check interface configuration"
}

Write-Host ""
Write-Host "VM Testing Instructions:" -ForegroundColor Yellow
Write-Host ""
Write-Host ("1. Connect VM to virtual switch {0}:" -f $SwitchName) -ForegroundColor Cyan
Write-Host ("   Connect-VMNetworkAdapter -VMName VM_NAME -SwitchName {0}" -f $SwitchName) -ForegroundColor White
Write-Host ""
Write-Host "2. From VM console, test:" -ForegroundColor Cyan
Write-Host "   ping $PfSenseIP -n 4" -ForegroundColor White
Write-Host "   ping 8.8.8.8 -n 4" -ForegroundColor White
Write-Host "   ping google.com -n 2" -ForegroundColor White
Write-Host ""

Write-Header "Setup Complete"
Write-Host ""
Write-Host "Interface Summary:" -ForegroundColor Cyan
Write-Host "  Name: $InterfaceName" -ForegroundColor White
Write-Host "  Network: $NetworkSubnet" -ForegroundColor White
Write-Host "  pfSense IP: $PfSenseIP" -ForegroundColor White
Write-Host "  Host IP: $HostIP" -ForegroundColor White
Write-Host "  Virtual Switch: $SwitchName" -ForegroundColor White
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Connect VMs to switch: $SwitchName" -ForegroundColor White
Write-Host "  2. Test connectivity from VMs" -ForegroundColor White
Write-Host "  3. Check DHCP leases: Status -> DHCP Leases" -ForegroundColor White
Write-Host "  4. Monitor firewall states: Diagnostics -> States" -ForegroundColor White
Write-Host ""
Write-Host "Troubleshooting:" -ForegroundColor Yellow
Write-Host "  - No gateway: Check interface is UP in pfSense" -ForegroundColor White
Write-Host "  - No internet: Check NAT rule (Source = $InterfaceName subnets)" -ForegroundColor White
Write-Host "  - See knowledge-book/pfsense-nat-behavior.md" -ForegroundColor White
Write-Host ""
