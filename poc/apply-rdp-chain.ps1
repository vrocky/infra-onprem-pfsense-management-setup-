param(
    [string]$ManifestPath = ".\\rdp-chain-manifest.sample.json",
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-PathSafe {
    param([string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return $PathValue
    }

    return Join-Path (Split-Path -Parent $ManifestPath) $PathValue
}

function Get-AuthToken {
    param([pscustomobject]$Firewall)

    if ($Firewall.PSObject.Properties.Name -contains "token") {
        if (-not [string]::IsNullOrWhiteSpace($Firewall.token)) {
            return $Firewall.token
        }
    }

    if (-not ($Firewall.PSObject.Properties.Name -contains "tokenEnvVar")) {
        throw "Firewall config must include token or tokenEnvVar."
    }

    $token = [Environment]::GetEnvironmentVariable([string]$Firewall.tokenEnvVar)
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "Environment variable '$($Firewall.tokenEnvVar)' is empty or missing."
    }

    return $token
}

function Expand-TemplateText {
    param(
        [string]$TemplateText,
        [hashtable]$Values
    )

    $expanded = $TemplateText
    foreach ($key in $Values.Keys) {
        $expanded = $expanded.Replace("{{$key}}", [string]$Values[$key])
    }

    return $expanded
}

function Invoke-PfSenseApi {
    param(
        [pscustomobject]$Firewall,
        [string]$Method,
        [string]$Endpoint,
        [string]$Token,
        [object]$Body,
        [bool]$SkipCert
    )

    $base = ([string]$Firewall.baseUrl).TrimEnd('/')
    $ep = if ($Endpoint.StartsWith('/')) { $Endpoint } else { "/$Endpoint" }
    $uri = "$base$ep"

    $headers = @{
        Authorization = "Bearer $Token"
        Accept = "application/json"
    }

    $params = @{
        Uri = $uri
        Method = $Method
        Headers = $headers
    }

    if ($null -ne $Body) {
        $params["Body"] = ($Body | ConvertTo-Json -Depth 30)
        $params["ContentType"] = "application/json"
    }

    if ($DryRun) {
        Write-Host "DRY-RUN $Method $uri"
        if ($null -ne $Body) {
            Write-Host (($Body | ConvertTo-Json -Depth 30))
        }
        return $null
    }

    if ($SkipCert) {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    }

    Write-Host "Calling $Method $uri"
    return Invoke-RestMethod @params
}

if (-not (Test-Path $ManifestPath)) {
    throw "Manifest file not found: $ManifestPath"
}

$manifest = Get-Content -Path $ManifestPath -Raw | ConvertFrom-Json

if (-not $manifest.mappings -or $manifest.mappings.Count -eq 0) {
    throw "Manifest must contain at least one mapping."
}

$fw1 = $manifest.firewalls.firewall1
$fw2 = $manifest.firewalls.firewall2
if ($null -eq $fw1 -or $null -eq $fw2) {
    throw "Manifest must define firewalls.firewall1 and firewalls.firewall2."
}

$fw1TemplatePath = Resolve-PathSafe -PathValue ([string]$fw1.templatePath)
$fw2TemplatePath = Resolve-PathSafe -PathValue ([string]$fw2.templatePath)
$fw1Template = Get-Content -Path $fw1TemplatePath -Raw
$fw2Template = Get-Content -Path $fw2TemplatePath -Raw

$fw1Token = Get-AuthToken -Firewall $fw1
$fw2Token = Get-AuthToken -Firewall $fw2
$skipCert = [bool]$manifest.skipCertificateCheck

foreach ($mapping in $manifest.mappings) {
    $values = @{
        MAPPING_NAME = [string]$mapping.name
        PUBLIC_PORT = [int]$mapping.publicPort
        FW2_WAN_IP = [string]$manifest.firewall2WanIp
        TARGET_VM_IP = [string]$mapping.targetVmIp
        TARGET_VM_PORT = [int]$mapping.targetVmPort
    }

    $fw1Expanded = Expand-TemplateText -TemplateText $fw1Template -Values $values
    $fw2Expanded = Expand-TemplateText -TemplateText $fw2Template -Values $values

    $fw1Body = $fw1Expanded | ConvertFrom-Json
    $fw2Body = $fw2Expanded | ConvertFrom-Json

    Write-Host "Processing mapping: $($mapping.name)" -ForegroundColor Cyan

    [void](Invoke-PfSenseApi -Firewall $fw1 -Method ([string]$fw1.natCreateMethod) -Endpoint ([string]$fw1.natCreateEndpoint) -Token $fw1Token -Body $fw1Body -SkipCert $skipCert)
    [void](Invoke-PfSenseApi -Firewall $fw2 -Method ([string]$fw2.natCreateMethod) -Endpoint ([string]$fw2.natCreateEndpoint) -Token $fw2Token -Body $fw2Body -SkipCert $skipCert)
}

if ([bool]$manifest.applyAfterEachFirewall) {
    if ($fw1.applyEndpoint) {
        [void](Invoke-PfSenseApi -Firewall $fw1 -Method ([string]$fw1.applyMethod) -Endpoint ([string]$fw1.applyEndpoint) -Token $fw1Token -Body $null -SkipCert $skipCert)
    }

    if ($fw2.applyEndpoint) {
        [void](Invoke-PfSenseApi -Firewall $fw2 -Method ([string]$fw2.applyMethod) -Endpoint ([string]$fw2.applyEndpoint) -Token $fw2Token -Body $null -SkipCert $skipCert)
    }
}

Write-Host "Done."
