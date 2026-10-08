$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    py -3 scripts/generate_integrated_vectors.py
    if ($LASTEXITCODE -ne 0) { throw 'Golden generation failed' }
    py -3 scripts/generate_packed_vectors.py
    if ($LASTEXITCODE -ne 0) { throw 'Packed generation failed' }
    $sources = @('rtl/expanda_controller.v','rtl/expanda_seed_absorb.v','rtl/expanda_shake128.v',
        'rtl/expanda_xof_buffer.v','rtl/expanda_rej_ntt_poly.v','rtl/expanda_output_packer.v','rtl/expanda_top.v')
    New-Item -ItemType Directory -Force results/v2_units | Out-Null
    & iverilog -g2001 -Wall -s tb_expanda_units -o results/v2_units/test.vvp @sources tb/tb_expanda_units.v
    if ($LASTEXITCODE -ne 0) { throw 'Units compile failed' }
    $output = & vvp results/v2_units/test.vvp
    $output | Set-Content -Encoding UTF8 results/v2_units/simulation.log
    $output | Write-Output
    if ($LASTEXITCODE -ne 0 -or ($output -match 'FAIL:') -or -not ($output -match 'PASS:')) { throw 'Units failed' }
    foreach ($rows in @(1,4)) {
        $name = if ($rows -eq 1) { 'v2_row' } else { 'v2_full' }
        New-Item -ItemType Directory -Force "results/$name" | Out-Null
        & iverilog -g2001 -Wall "-DBUFFER_ROWS=$rows" -s tb_expanda_buffered -o "results/$name/test.vvp" @sources rtl/expanda_matrix_buffer.v rtl/expanda_buffered_top.v tb/tb_expanda_buffered.v
        if ($LASTEXITCODE -ne 0) { throw "Buffer compile failed: $name" }
        $output = & vvp "results/$name/test.vvp"
        $code = $LASTEXITCODE
        $output | Set-Content -Encoding UTF8 "results/$name/simulation.log"
        $output | Write-Output
        if ($code -ne 0 -or ($output -match 'FAIL:') -or -not ($output -match 'PASS:')) { throw "Buffer simulation failed: $name" }
    }
} finally { Pop-Location }
