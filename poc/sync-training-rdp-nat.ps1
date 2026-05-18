param(
    [string]$ConfigPath = ".\\training-rdp-sync.config.json",
    [switch]$DryRun,
    [switch]$GenerateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-PathFromFile {
    param(
        [string]$BaseFile,
        [string]$PathValue
    )

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return $PathValue
    }

    $baseDir = Split-Path -Parent $BaseFile
    return Join-Path $baseDir $PathValue
}

function Get-PropertyValue {
    param(
        [object]$InputObject,
        [string[]]$Names
    )

    if ($null -eq $InputObject) {
        return $null
    }

    foreach ($name in $Names) {
        $prop = $InputObject.PSObject.Properties[$name]
        if ($null -ne $prop) {
            return $prop.Value
        }
    }

    return $null
}

function Get-RuleArray {
    param([object]$Response)

    if ($null -eq $Response) {
        return @()
    }

    if ($Response -is [System.Array]) {
        return $Response
    }

    $candidates = @("items", "data", "rules", "nat", "result")
    foreach ($name in $candidates) {
        $value = Get-PropertyValue -InputObject $Response -Names @($name)
        if ($value -is [System.Array]) {
            return $value
        }
    }

    return @()
}

function Get-IpSuffix {
    param([string]$Ip)

    $parsed = $null
    if (-not [System.Net.IPAddress]::TryParse($Ip, [ref]$parsed)) {
        throw "Invalid IP address: $Ip"
    }

    $octets = $Ip.Split('.')
    if ($octets.Count -ne 4) {
        throw "Only IPv4 is supported for suffix mapping: $Ip"
    }

    return [int]$octets[3]
}

function Get-Token {
    param([pscustomobject]$Firewall)

    $envVar = [string]$Firewall.tokenEnvVar
    if ([string]::IsNullOrWhiteSpace($envVar)) {
        throw "firewall.tokenEnvVar is required."
    }

    $token = [Environment]::GetEnvironmentVariable($envVar)
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "Environment variable '$envVar' is empty or missing."
    }

    return $token
}

function Invoke-PfSenseApi {
    param(
        [pscustomobject]$Firewall,
        [string]$Token,
        [string]$Method,
        [string]$Endpoint,
        [object]$Body,
        [bool]$SkipCert,
        [bool]$IsDryRun
    )

    $baseUrl = ([string]$Firewall.baseUrl).TrimEnd('/')
    $normalizedEndpoint = if ($Endpoint.StartsWith('/')) { $Endpoint } else { "/$Endpoint" }
    $uri = "$baseUrl$normalizedEndpoint"

    $headers = @{
        Authorization = "Bearer $Token"
        Accept = "application/json"
    }

    $invokeParams = @{
        Uri = $uri
        Method = $Method
        Headers = $headers
    }

    if ($null -ne $Body) {
        $invokeParams["Body"] = ($Body | ConvertTo-Json -Depth 25)
        $invokeParams["ContentType"] = "application/json"
    }

    if ($IsDryRun) {
        Write-Host "DRY-RUN $Method $uri"
        if ($null -ne $Body) {
            Write-Host ($Body | ConvertTo-Json -Depth 25)
        }
        return $null
    }

    if ($SkipCert) {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    }

    Write-Host "Calling $Method $uri"
    return Invoke-RestMethod @invokeParams
}

function Build-DesiredMappings {
    param(
        [object[]]$Inventory,
        [pscustomobject]$MappingConfig
    )

    $portBase = [int]$MappingConfig.wanPortBase
    $targetPort = [int]$MappingConfig.targetPort
    $prefix = [string]$MappingConfig.descriptionPrefix

    $result = @()
    $usedPorts = @{}

    foreach ($vm in $Inventory) {
        $enabled = Get-PropertyValue -InputObject $vm -Names @("enabled")
        if ($null -eq $enabled) {
            $enabled = $true
        }

        if (-not [bool]$enabled) {
            continue
        }

        $name = [string](Get-PropertyValue -InputObject $vm -Names @("name"))
        $ip = [string](Get-PropertyValue -InputObject $vm -Names @("ip", "ipAddress"))

        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($ip)) {
            throw "Each inventory item must include 'name' and 'ip'."
        }

        $suffix = Get-IpSuffix -Ip $ip
        $wanPort = $portBase + $suffix

        if ($usedPorts.ContainsKey($wanPort)) {
            throw "Duplicate WAN port computed: $wanPort ($name and $($usedPorts[$wanPort]))."
        }

        $usedPorts[$wanPort] = $name

        $result += [pscustomobject]@{
            Name = $name
            Ip = $ip
            Suffix = $suffix
            WanPort = $wanPort
            TargetPort = $targetPort
            Description = "$prefix$name"
        }
    }

    return $result
}

function Export-MappingTable {
    param(
        [object[]]$Mappings,
        [string]$OutputDir,
        [string]$ConfigPathValue
    )

    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir | Out-Null
    }

    $csvPath = Join-Path $OutputDir "training-rdp-nat-table.csv"
    $mdPath = Join-Path $OutputDir "training-rdp-nat-table.md"

    $Mappings |
        Select-Object Name, Ip, Suffix, WanPort, TargetPort, Description |
        Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

    $lines = @()
    $lines += "# Training RDP NAT Table"
    $lines += ""
    $lines += "Generated from: $ConfigPathValue"
    $lines += ""
    $lines += "| VM Name | VM IP | Suffix | WAN Port | Target Port | Description |"
    $lines += "| --- | --- | ---: | ---: | ---: | --- |"

    foreach ($item in $Mappings) {
        $lines += "| $($item.Name) | $($item.Ip) | $($item.Suffix) | $($item.WanPort) | $($item.TargetPort) | $($item.Description) |"
    }

    Set-Content -Path $mdPath -Value $lines -Encoding UTF8

    Write-Host "Exported mapping table:"
    Write-Host "- $csvPath"
    Write-Host "- $mdPath"
}

if (-not (Test-Path $ConfigPath)) {
    throw "Config file not found: $ConfigPath"
}

$config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
$inventoryPath = Resolve-PathFromFile -BaseFile $ConfigPath -PathValue ([string]$config.inventoryFile)
if (-not (Test-Path $inventoryPath)) {
    throw "Inventory file not found: $inventoryPath"
}

$inventory = Get-Content -Path $inventoryPath -Raw | ConvertFrom-Json
$mappings = Build-DesiredMappings -Inventory $inventory -MappingConfig $config.mapping
if ($mappings.Count -eq 0) {
    throw "No enabled VMs found in inventory."
}

$outputDir = Resolve-PathFromFile -BaseFile $ConfigPath -PathValue ([string]$config.outputDir)
Export-MappingTable -Mappings $mappings -OutputDir $outputDir -ConfigPathValue $ConfigPath

if ($GenerateOnly) {
    Write-Host "GenerateOnly mode complete."
    exit 0
}

$firewall = $config.firewall
$token = Get-Token -Firewall $firewall
$skipCert = [bool]$config.skipCertificateCheck

$existingByDescription = @{}
if ($firewall.natListEndpoint) {
    $listResponse = Invoke-PfSenseApi -Firewall $firewall -Token $token -Method "GET" -Endpoint ([string]$firewall.natListEndpoint) -Body $null -SkipCert $skipCert -IsDryRun ([bool]$DryRun)
    foreach ($rule in (Get-RuleArray -Response $listResponse)) {
        $desc = [string](Get-PropertyValue -InputObject $rule -Names @("description", "descr"))
        if (-not [string]::IsNullOrWhiteSpace($desc)) {
            $existingByDescription[$desc] = $rule
        }
    }
}

$desiredDescriptions = @{}
foreach ($mapping in $mappings) {
    $desiredDescriptions[$mapping.Description] = $true

    if ($existingByDescription.ContainsKey($mapping.Description)) {
        Write-Host "Exists, skip create: $($mapping.Description)"
        continue
    }

    $payload = [pscustomobject]@{
        interface = [string]$config.mapping.wanInterface
        protocol = [string]$config.mapping.protocol
        description = [string]$mapping.Description
        destination = [pscustomobject]@{
            address = [string]$config.mapping.destinationAddress
            port = [int]$mapping.WanPort
        }
        target = [pscustomobject]@{
            address = [string]$mapping.Ip
            port = [int]$mapping.TargetPort
        }
        associated_rule = [string]$config.mapping.associatedRule
    }

    [void](Invoke-PfSenseApi -Firewall $firewall -Token $token -Method "POST" -Endpoint ([string]$firewall.natCreateEndpoint) -Body $payload -SkipCert $skipCert -IsDryRun ([bool]$DryRun)
    )
}

if ([bool]$config.removeStaleAutoRules -and $firewall.natDeleteEndpointTemplate) {
    foreach ($kv in $existingByDescription.GetEnumerator()) {
        $desc = [string]$kv.Key
        if (-not $desc.StartsWith([string]$config.mapping.descriptionPrefix)) {
            continue
        }

        if ($desiredDescriptions.ContainsKey($desc)) {
            continue
        }

        $rule = $kv.Value
        $id = [string](Get-PropertyValue -InputObject $rule -Names @("id", "uuid", "tracker"))
        if ([string]::IsNullOrWhiteSpace($id)) {
            Write-Warning "Cannot delete stale rule '$desc' because no id/uuid/tracker field was found."
            continue
        }

        $endpoint = ([string]$firewall.natDeleteEndpointTemplate).Replace("{id}", $id)
        [void](Invoke-PfSenseApi -Firewall $firewall -Token $token -Method "DELETE" -Endpoint $endpoint -Body $null -SkipCert $skipCert -IsDryRun ([bool]$DryRun)
        )
    }
}

if ($firewall.applyEndpoint) {
    [void](Invoke-PfSenseApi -Firewall $firewall -Token $token -Method "POST" -Endpoint ([string]$firewall.applyEndpoint) -Body $null -SkipCert $skipCert -IsDryRun ([bool]$DryRun)
    )
}

Write-Host "NAT maintenance sync completed."
