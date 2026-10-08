param([switch]$Gui, [string]$Simulator = 'C:\intelFPGA_lite\23.1std\questa_fse\win64\vsim.exe')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    py -3 scripts/generate_integrated_vectors.py
    if ($LASTEXITCODE -ne 0) { throw 'Golden generation failed' }
    py -3 scripts/generate_packed_vectors.py
    if ($LASTEXITCODE -ne 0) { throw 'Packed generation failed' }
    New-Item -ItemType Directory -Force results/questa,results/v2_fast | Out-Null
    if ($Gui) {
        # Explicit -Gui is an interactive request; normal runs remain console-only.
        & $Simulator -do scripts/questa_gui.do
    } else {
        & $Simulator -c -do scripts/questa_batch.do
        if ($LASTEXITCODE -ne 0) { throw 'Questa simulation failed; inspect transcript/license messages' }
    }
} finally { Pop-Location }
