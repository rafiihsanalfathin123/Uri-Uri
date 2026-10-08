$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    py -3 scripts/generate_expanda_vectors.py
    if ($LASTEXITCODE -ne 0) { throw 'Vector generation failed' }
    New-Item -ItemType Directory -Force results | Out-Null
    $rtlFiles = @('rtl/expanda_rejection_sampler.v', 'rtl/expanda_row_buffer.v', 'rtl/expanda_stream_top.v', 'rtl/expanda_word_to_byte.v', 'rtl/expanda_shake64_top.v', 'third_party/ML-DSA-OSH/ref_combined/src/rejection_a.v')
    foreach ($testName in @('sampler', 'stream', 'benchmark', 'shake64_msb', 'shake64_lsb')) {
        $topName = "tb_expanda_$testName"
        $outputPath = "results/expanda_$testName.vvp"
        $defines = @()
        if ($testName -like 'shake64_*') {
            $topName = 'tb_expanda_stream'
            $byteOrder = if ($testName -eq 'shake64_msb') { 1 } else { 0 }
            $defines = @('-DSHAKE64', "-DBYTE_MSB_FIRST=$byteOrder")
        }
        & iverilog -g2001 -Wall @defines -s $topName -o $outputPath @rtlFiles "tb/$topName.v"
        if ($LASTEXITCODE -ne 0) { throw "Compilation failed: $testName" }
        $testOutput = & vvp $outputPath
        $testExitCode = $LASTEXITCODE
        $testOutput | Set-Content -Encoding UTF8 "results/expanda_$testName.log"
        $testOutput | Write-Output
        if ($testExitCode -ne 0 -or ($testOutput -match 'FAIL:') -or -not ($testOutput -match 'PASS:')) { throw "Simulation failed: $testName" }
    }
} finally { Pop-Location }
