param(
    [ValidateSet('import','logic','input','story','combat','capture')]
    [string]$Suite = 'logic',
    [string]$Resolution = '1280x800',
    [string]$OutputDirectory = '',
    [string]$GodotPath = '',
    [ValidateRange(10,300)][int]$TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
$mapQaRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (-not $GodotPath) {
    $GodotPath = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'local_paths.json') -Raw | ConvertFrom-Json).godot
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw 'Godot executable missing.' }
if ($Resolution -notmatch '^\d+x\d+$') { throw 'Use WIDTHxHEIGHT for Resolution.' }
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $mapQaRoot ('artifacts/qa/map-build-2026-10-07/' + $Suite + '-' + $Resolution)
}
$mapQaOutput = [IO.Path]::GetFullPath($OutputDirectory)
$mapQaRuntime = Join-Path $mapQaRoot 'artifacts/qa/map-build-2026-10-07/engine-userdata'
New-Item -ItemType Directory -Force -Path $mapQaOutput,$mapQaRuntime | Out-Null
$mapQaLog = Join-Path $mapQaOutput 'engine.log'
$mapQaStdout = Join-Path $mapQaOutput 'stdout.log'
$mapQaStderr = Join-Path $mapQaOutput 'stderr.log'
$mapQaArgs = @('--path',$mapQaRoot,'--log-file',$mapQaLog)
switch ($Suite) {
    'import' { $mapQaArgs += @('--headless','--editor','--import','--quit') }
    'logic' { $mapQaArgs += @('--headless','res://tests/map_model_tests.tscn') }
    'story' { $mapQaArgs += @('--headless','res://tests/run.tscn') }
    'combat' { $mapQaArgs += @('--headless','res://tests/combat_tests.tscn') }
    'input' { $mapQaArgs += @('--windowed','--position','40,40','--resolution',$Resolution,'--always-on-top','res://tests/map_visual.tscn','--','--output-dir',$mapQaOutput) }
    'capture' { $mapQaArgs += @('--windowed','--resolution',$Resolution,'res://tests/map_visual.tscn','--','--output-dir',$mapQaOutput,'--capture-only') }
}
foreach ($mapQaArg in $mapQaArgs) {
    if ($mapQaArg -match '["\r\n]') { throw 'Unsafe command-line path.' }
}
$mapQaCommandLine = ($mapQaArgs | ForEach-Object { '"' + $_ + '"' }) -join ' '
$mapQaPreviousAppData = $env:APPDATA
$mapQaStarted = [DateTime]::UtcNow
try {
    # Autoload runs before the scene disables saving; isolate its reads and caches too.
    $env:APPDATA = $mapQaRuntime
    $mapQaWindowStyle = 'Hidden'
    if ($Suite -eq 'input') { $mapQaWindowStyle = 'Normal' }
    $mapQaProcess = Start-Process -FilePath $GodotPath -ArgumentList $mapQaCommandLine -WorkingDirectory $mapQaRoot -WindowStyle $mapQaWindowStyle -RedirectStandardOutput $mapQaStdout -RedirectStandardError $mapQaStderr -PassThru
    while (-not $mapQaProcess.WaitForExit(1000)) {
        if (([DateTime]::UtcNow - $mapQaStarted).TotalSeconds -gt $TimeoutSeconds) {
            Stop-Process -Id $mapQaProcess.Id
            throw ('Map QA timed out; evidence retained: ' + $mapQaOutput)
        }
    }
    $mapQaProcess.Refresh()
    $mapQaText = [string](Get-Content -LiteralPath $mapQaStdout -Raw)
    $mapQaErrors = [string](Get-Content -LiteralPath $mapQaStderr -Raw)
    $mapQaPassed = $mapQaProcess.ExitCode -eq 0 -and ($mapQaText + $mapQaErrors) -notmatch 'SCRIPT ERROR|Parse Error|(?m)^\s*ERROR:'
    $mapQaExpected = @{logic='MAP MODEL: \d+ checks, 0 failures';input='MAP VISUAL: \d+ checks, 0 failures';capture='MAP CAPTURE OK';story='\b0 failures\b';combat='\b0 failures\b'}
    if ($mapQaExpected.ContainsKey($Suite) -and $mapQaText -notmatch $mapQaExpected[$Suite]) { $mapQaPassed = $false }
    [pscustomobject]@{suite=$Suite; resolution=$Resolution; exitCode=$mapQaProcess.ExitCode; passed=$mapQaPassed; stdout=$mapQaStdout; stderr=$mapQaStderr; screenshots=@(Get-ChildItem -LiteralPath $mapQaOutput -Filter '*.png' | Select-Object -ExpandProperty FullName)} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $mapQaOutput 'result.json') -Encoding utf8
    Write-Output $mapQaText.Trim()
    if (-not [string]::IsNullOrWhiteSpace($mapQaErrors)) { Write-Output $mapQaErrors.Trim() }
    if (-not $mapQaPassed) { throw ('Map QA failed; evidence retained: ' + $mapQaOutput) }
    Write-Output ('MAP QA OK: ' + $mapQaOutput)
} finally {
    $env:APPDATA = $mapQaPreviousAppData
}
