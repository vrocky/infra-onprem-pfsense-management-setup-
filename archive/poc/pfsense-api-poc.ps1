param(
    [Parameter(Mandatory = $true)]
    [string]$BaseUrl,

    [Parameter(Mandatory = $true)]
    [string]$ApiToken,

    [Parameter(Mandatory = $true)]
    [string]$Endpoint,

    [ValidateSet("GET", "POST", "PUT", "PATCH", "DELETE")]
    [string]$Method = "GET",

    [string]$BodyFile,

    [switch]$SkipCertificateCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($SkipCertificateCheck) {
    # Useful in labs where pfSense uses a self-signed cert.
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
}

$normalizedBaseUrl = $BaseUrl.TrimEnd('/')
$normalizedEndpoint = if ($Endpoint.StartsWith('/')) { $Endpoint } else { "/$Endpoint" }
$uri = "$normalizedBaseUrl$normalizedEndpoint"

$headers = @{
    "Authorization" = "Bearer $ApiToken"
    "Accept" = "application/json"
}

$invokeParams = @{
    Uri = $uri
    Method = $Method
    Headers = $headers
}

if ($BodyFile) {
    if (-not (Test-Path $BodyFile)) {
        throw "Body file not found: $BodyFile"
    }

    $rawBody = Get-Content -Path $BodyFile -Raw
    if (-not [string]::IsNullOrWhiteSpace($rawBody)) {
        $bodyObject = $rawBody | ConvertFrom-Json
        $jsonBody = $bodyObject | ConvertTo-Json -Depth 20
        $invokeParams["Body"] = $jsonBody
        $invokeParams["ContentType"] = "application/json"
    }
}

try {
    Write-Host "Calling $Method $uri"
    $response = Invoke-RestMethod @invokeParams

    if ($null -eq $response) {
        Write-Host "Request completed (empty response)."
    }
    else {
        $response | ConvertTo-Json -Depth 20
    }
}
catch {
    Write-Error "API call failed: $($_.Exception.Message)"

    if ($_.Exception.Response -and $_.Exception.Response.GetResponseStream()) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $errorBody = $reader.ReadToEnd()
        if (-not [string]::IsNullOrWhiteSpace($errorBody)) {
            Write-Host "Response body:"
            Write-Host $errorBody
        }
    }

    exit 1
}
