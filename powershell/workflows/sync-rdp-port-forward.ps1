param(
    [ValidateSet("Validate", "DryRun", "GenerateOnly", "Apply")]
    [string]$Mode = "Validate",
    [string]$ConfigPath = ".\\config.json",
    [string]$PythonExe = "python"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path $ConfigPath)) {
    throw "Config file not found: $ConfigPath. Copy config.sample.json to config.json first."
}

$scriptPath = Join-Path $PSScriptRoot "sync_training_vm_port_forward.py"
if (-not (Test-Path $scriptPath)) {
    throw "Python script not found: $scriptPath"
}

$args = @($scriptPath, "--config", $ConfigPath)

switch ($Mode) {
    "Validate" {
        $args += "--validate-config"
    }
    "DryRun" {
        $args += "--dry-run"
    }
    "GenerateOnly" {
        $args += "--generate-only"
    }
    "Apply" {
        # default mode applies reconciliation
    }
}

Write-Host "Running mode: $Mode" -ForegroundColor Cyan
Write-Host "$PythonExe $($args -join ' ')" -ForegroundColor DarkGray

& $PythonExe @args
if ($LASTEXITCODE -ne 0) {
    throw "Sync run failed with exit code $LASTEXITCODE"
}

Write-Host "Completed mode: $Mode" -ForegroundColor Green
