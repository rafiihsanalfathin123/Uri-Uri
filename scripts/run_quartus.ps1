param(
    [ValidateSet('row','full','stream')][string]$Variant = 'row',
    [ValidateSet('synthesis','fit')][string]$Stage = 'fit',
    [switch]$Isolated,
    [string]$QuartusBin = 'C:\intelFPGA_lite\23.1std\quartus\bin64'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$revision = "expanda_$Variant"
$projectDirectory = Join-Path $projectRoot "quartus\$revision"
if ($Isolated) {
    if ($Variant -eq 'stream') { throw 'Isolated evaluation is available for row/full only.' }
    $revision = "evaluation_$Variant"
    $projectDirectory = Join-Path $projectRoot "quartus\evaluation\$Variant"
}
if (-not (Test-Path -LiteralPath (Join-Path $projectDirectory "$revision.qpf"))) {
    $generator = if ($Isolated) { 'create_quartus_evaluation.py' } else { 'create_quartus_projects.py' }
    throw "Project missing. Run py -3 scripts/$generator first."
}
$stages = @(@{Tool='quartus_map.exe';Arguments=@($revision,'--read_settings_files=on','--write_settings_files=off');Log='map.log'})
if ($Stage -eq 'fit') {
    $stages += @{Tool='quartus_fit.exe';Arguments=@($revision,'--read_settings_files=on','--write_settings_files=off');Log='fit.log'}
    $stages += @{Tool='quartus_sta.exe';Arguments=@($revision,'--do_report_timing');Log='sta.log'}
}
Push-Location $projectDirectory
try {
    New-Item -ItemType Directory -Force run_logs | Out-Null
    foreach ($step in $stages) {
        $executable = Join-Path $QuartusBin $step.Tool
        if (-not (Test-Path -LiteralPath $executable)) { throw "Missing Quartus executable: $executable" }
        $arguments = $step.Arguments
        # Quartus emits a nonfatal allocator message on stderr on this machine.
        # Capture both streams and use the tool exit code to decide success.
        $savedPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & $executable @arguments 2>&1 | Tee-Object -FilePath (Join-Path run_logs $step.Log)
        $code = $LASTEXITCODE
        $ErrorActionPreference = $savedPreference
        if ($code -ne 0) { throw "$($step.Tool) failed with exit code $code. Inspect $projectDirectory/run_logs/$($step.Log)." }
    }
    Write-Output "Completed $Stage for $revision. Reports: $projectDirectory/output_files"
    if ($Stage -eq 'fit') {
        Write-Output 'Inspect setup/hold slack and unconstrained paths: a successful tool exit does not imply timing closure.'
        Write-Output 'Virtual-pin IP evaluation; no assembler/programming image or board pin mapping was created.'
    }
} finally { Pop-Location }
