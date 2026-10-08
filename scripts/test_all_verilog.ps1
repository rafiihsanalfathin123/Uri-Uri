param([switch]$Legacy, [switch]$Questa)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    foreach ($script in @('test_v2.ps1','test_shake_v2.ps1','test_v2_buffers.ps1')) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $script)
        if ($LASTEXITCODE -ne 0) { throw "Regression failed: $script" }
    }
    if ($Legacy) {
        foreach ($script in @('test_expanda.ps1','test_integrated.ps1')) {
            & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $script)
            if ($LASTEXITCODE -ne 0) { throw "Legacy regression failed: $script" }
        }
    }
    if ($Questa) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_questa.ps1
        if ($LASTEXITCODE -ne 0) { throw 'Questa failed' }
    }
    py -3 scripts/analyze_v2.py
    if ($LASTEXITCODE -ne 0) { throw 'Packed output analysis failed' }
} finally { Pop-Location }
