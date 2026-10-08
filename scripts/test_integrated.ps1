$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    py -3 scripts/generate_integrated_vectors.py
    if ($LASTEXITCODE -ne 0) { throw 'Vector generation failed' }
    New-Item -ItemType Directory -Force results | Out-Null
    $sourceFiles = @(
        'rtl/expanda_rejection_sampler.v', 'rtl/expanda_row_buffer.v',
        'rtl/expanda_stream_top.v', 'rtl/expanda_word_to_byte.v',
        'rtl/expanda_integrated_top.v',
        'third_party/shake128_package/shake128_memory/shared_shake128_mem.v',
        'tb/tb_expanda_integrated.v'
    )
    & iverilog -g2001 -Wall -s tb_expanda_integrated -o results/expanda_integrated.vvp @sourceFiles
    if ($LASTEXITCODE -ne 0) { throw 'Integrated compilation failed' }
    $testOutput = & vvp results/expanda_integrated.vvp
    $testExitCode = $LASTEXITCODE
    $testOutput | Set-Content -Encoding UTF8 results/expanda_integrated.log
    $testOutput | Write-Output
    if ($testExitCode -ne 0 -or ($testOutput -match 'FAIL:') -or -not ($testOutput -match 'PASS:')) { throw 'Integrated simulation failed' }
} finally { Pop-Location }
