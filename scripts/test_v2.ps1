$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    py -3 scripts/generate_integrated_vectors.py
    if ($LASTEXITCODE -ne 0) { throw 'Golden generation failed' }
    py -3 scripts/generate_packed_vectors.py
    if ($LASTEXITCODE -ne 0) { throw 'Packed golden generation failed' }
    $sources = @('rtl/expanda_controller.v','rtl/expanda_seed_absorb.v','rtl/expanda_shake128.v',
        'rtl/expanda_xof_buffer.v','rtl/expanda_rej_ntt_poly.v','rtl/expanda_output_packer.v','rtl/expanda_top.v')
    foreach ($lanes in @(5,1)) {
        $name = if ($lanes -eq 5) { 'v2_fast' } else { 'v2_serial' }
        New-Item -ItemType Directory -Force "results/$name" | Out-Null
        & iverilog -g2001 -Wall "-DSHAKE_LANES=$lanes" -s tb_expanda_v2 -o "results/$name/test.vvp" @sources tb/tb_expanda_v2.v
        if ($LASTEXITCODE -ne 0) { throw "Verilog-2001 compile failed: $name" }
        $output = & vvp "results/$name/test.vvp"
        $code = $LASTEXITCODE
        $output | Set-Content -Encoding UTF8 "results/$name/simulation.log"
        $output | Write-Output
        if ($code -ne 0 -or ($output -match 'FAIL:') -or -not ($output -match 'PASS: V2')) { throw "Simulation failed: $name" }
    }
} finally { Pop-Location }
