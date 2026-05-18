# Diagnose and Fix Training LAN - Run as Administrator
# Right-click this file and select "Run with PowerShell as Administrator"

$ErrorActionPreference = 'Continue'

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "TRAINING LAN DIAGNOSTIC AND FIX" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Check if running as admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Right-click the script and select 'Run with PowerShell as Administrator'" -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "✓ Running as Administrator`n" -ForegroundColor Green

# Step 1: Show current VM connections
Write-Host "STEP 1: Current VM Network Configuration" -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor Yellow
try {
    $vmAdapters = Get-VMNetworkAdapter -VMName PFSenseVM,training_1 -ErrorAction Stop
    $vmAdapters | Select-Object VMName,Name,SwitchName,MacAddress | Format-Table -AutoSize
    
    $pfOpt1 = $vmAdapters | Where-Object { $_.VMName -eq 'PFSenseVM' -and $_.MacAddress -eq '00155D00A09C' }
    $training1 = $vmAdapters | Where-Object { $_.VMName -eq 'training_1' }
    
    if ($pfOpt1) {
        Write-Host "PFSense OPT1 is on switch: $($pfOpt1.SwitchName)" -ForegroundColor Cyan
    }
    if ($training1) {
        Write-Host "training_1 is on switch: $($training1.SwitchName)" -ForegroundColor Cyan
    }
} catch {
    Write-Host "ERROR: Could not get VM network adapters: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Step 2: Show host IP configuration
Write-Host "`nSTEP 2: Host IP Configuration" -ForegroundColor Yellow
Write-Host "==============================" -ForegroundColor Yellow
$hostIPs = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like '192.168.50.*' }
if ($hostIPs) {
    $hostIPs | Select-Object InterfaceAlias,IPAddress,PrefixLength | Format-Table -AutoSize
} else {
    Write-Host "No 192.168.50.x IPs found on host!" -ForegroundColor Red
}

# Step 3: Identify the problem
Write-Host "`nSTEP 3: Problem Identification" -ForegroundColor Yellow
Write-Host "===============================" -ForegroundColor Yellow
$hostSwitch = $hostIPs[0].InterfaceAlias -replace 'vEthernet \((.+)\)', '$1'
$vmSwitch = $pfOpt1.SwitchName

Write-Host "Host IP 192.168.50.254 is on: $($hostIPs[0].InterfaceAlias) (switch: $hostSwitch)" -ForegroundColor White
Write-Host "PFSense OPT1 is connected to: $vmSwitch" -ForegroundColor White

if ($hostSwitch -ne $vmSwitch) {
    Write-Host "`n✗ PROBLEM FOUND: Switch mismatch!" -ForegroundColor Red
    Write-Host "  VMs are on '$vmSwitch' but host is on '$hostSwitch'" -ForegroundColor Red
    Write-Host "  These are two separate isolated networks.`n" -ForegroundColor Red
} else {
    Write-Host "`n✓ Switches match - this is not the problem" -ForegroundColor Green
    Write-Host "  The issue must be elsewhere (firewall, interface config, etc.)`n" -ForegroundColor Yellow
}

# Step 4: Offer to fix
Write-Host "STEP 4: Apply Fix?" -ForegroundColor Yellow
Write-Host "===================" -ForegroundColor Yellow
Write-Host "This will move VMs to the '$hostSwitch' switch where the host IP is configured.`n"

$response = Read-Host "Do you want to apply the fix? (yes/no)"
if ($response -ne 'yes') {
    Write-Host "`nFix not applied. Exiting." -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 0
}

# Step 5: Apply the fix
Write-Host "`nSTEP 5: Applying Fix" -ForegroundColor Yellow
Write-Host "====================" -ForegroundColor Yellow

try {
    # Move PFSense OPT1
    if ($pfOpt1) {
        Write-Host "Moving PFSense OPT1 (MAC: $($pfOpt1.MacAddress)) to '$hostSwitch'..." -ForegroundColor Cyan
        Connect-VMNetworkAdapter -VMNetworkAdapter $pfOpt1 -SwitchName $hostSwitch -ErrorAction Stop
        Write-Host "  ✓ PFSense OPT1 moved successfully" -ForegroundColor Green
    }
    
    # Move training_1
    if ($training1) {
        Write-Host "Moving training_1 (MAC: $($training1.MacAddress)) to '$hostSwitch'..." -ForegroundColor Cyan
        Connect-VMNetworkAdapter -VMNetworkAdapter $training1 -SwitchName $hostSwitch -ErrorAction Stop
        Write-Host "  ✓ training_1 moved successfully" -ForegroundColor Green
    }
    
} catch {
    Write-Host "  ✗ ERROR during move: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Step 6: Verify fix
Write-Host "`nSTEP 6: Verification" -ForegroundColor Yellow
Write-Host "====================" -ForegroundColor Yellow
Start-Sleep -Seconds 2

$vmAdaptersAfter = Get-VMNetworkAdapter -VMName PFSenseVM,training_1
$vmAdaptersAfter | Select-Object VMName,Name,SwitchName,MacAddress | Format-Table -AutoSize

# Step 7: Test connectivity
Write-Host "`nSTEP 7: Testing Connectivity" -ForegroundColor Yellow
Write-Host "=============================" -ForegroundColor Yellow
Write-Host "Pinging 192.168.50.1 (PFSense OPT1)..."
$pingResult = Test-Connection -ComputerName 192.168.50.1 -Count 4 -Quiet

if ($pingResult) {
    Write-Host "✓ SUCCESS! 192.168.50.1 is now reachable!" -ForegroundColor Green
} else {
    Write-Host "✗ Ping still failing" -ForegroundColor Red
    Write-Host "`nPossible remaining issues:" -ForegroundColor Yellow
    Write-Host "  1. PFSense OPT1 interface might need to be enabled in pfSense web UI"
    Write-Host "  2. Firewall rules on OPT1 might be blocking traffic"
    Write-Host "  3. PFSense might need a reboot to recognize the switch change"
    Write-Host "`nTry accessing pfSense console and check interface status."
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "DIAGNOSTIC AND FIX COMPLETE" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Read-Host "Press Enter to exit"
