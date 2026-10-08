$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    py -3 scripts/prepare_shake_regression.py
    if ($LASTEXITCODE -ne 0) { throw 'Testbench preparation failed' }
    foreach ($lanes in @(5,1)) {
        $name = if ($lanes -eq 5) { 'v2_fast' } else { 'v2_serial' }
        New-Item -ItemType Directory -Force "results/$name" | Out-Null
        & iverilog -g2001 -Wall "-DSHAKE_LANES=$lanes" -s tb_expanda_shake128 -o "results/$name/shake.vvp" rtl/expanda_shake128.v tb/tb_expanda_shake128.v
        if ($LASTEXITCODE -ne 0) { throw "SHAKE compile failed: $name" }
        $output = & vvp "results/$name/shake.vvp" '+VECTORS=third_party/shake128_package/shake128_memory/tests/vectors.txt'
        $code = $LASTEXITCODE
        $output | Set-Content -Encoding UTF8 "results/$name/shake.log"
        $output | Write-Output
        if ($code -ne 0 -or ($output -match 'FAIL:') -or -not ($output -match 'PASS ALL 81')) { throw "SHAKE vectors failed: $name" }
    }
} finally { Pop-Location }
