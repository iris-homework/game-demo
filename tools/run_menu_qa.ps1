param(
    [ValidateSet('baseline','import','capture','input','performance')][string]$Suite = 'input',
    [string]$Resolution = '1280x800',
    [string]$OutputDirectory = '',
    [string]$GodotPath = '',
    [switch]$VerboseEngine,
    [ValidateRange(10,300)][int]$TimeoutSeconds = 150
)
$ErrorActionPreference = 'Stop'
$menuQaRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (-not $GodotPath) { $GodotPath = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'local_paths.json') -Raw | ConvertFrom-Json).godot }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw 'Godot executable missing.' }
if ($Resolution -notmatch '^\d+x\d+$') { throw 'Use WIDTHxHEIGHT for Resolution.' }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $menuQaRoot ('artifacts/qa/menu-gif-2026-10-07/' + $Suite + '-' + $Resolution) }
$menuQaOutput = [IO.Path]::GetFullPath($OutputDirectory)
$menuQaData = Join-Path $menuQaRoot 'artifacts/qa/menu-gif-2026-10-07/engine-userdata'
New-Item -ItemType Directory -Force -Path $menuQaOutput,$menuQaData | Out-Null
$menuQaStdout = Join-Path $menuQaOutput 'stdout.log'
$menuQaStderr = Join-Path $menuQaOutput 'stderr.log'
$menuQaArgs = @('--path',$menuQaRoot,'--log-file',(Join-Path $menuQaOutput 'engine.log'))
if ($VerboseEngine) { $menuQaArgs += '--verbose' }
if ($Suite -eq 'import') { $menuQaArgs += @('--headless','--editor','--import','--quit') }
elseif ($Suite -eq 'baseline') { $menuQaArgs += @('--windowed','--resolution',$Resolution,'res://tools/qa_capture.tscn','--','--target','menu','--output',(Join-Path $menuQaOutput 'menu.png')) }
else { $menuQaArgs += @('--windowed','--position','40,40','--resolution',$Resolution,'--always-on-top','res://tests/menu_visual.tscn','--','--output-dir',$menuQaOutput,'--suite',$Suite) }
foreach ($menuQaArg in $menuQaArgs) { if ($menuQaArg -match '["\r\n]') { throw 'Unsafe command-line path.' } }
$menuQaCommandLine = ($menuQaArgs | ForEach-Object { '"' + $_ + '"' }) -join ' '
$menuQaPriorAppData = $env:APPDATA
$menuQaPriorLocalAppData = $env:LOCALAPPDATA
$menuQaStart = [DateTime]::UtcNow
try {
    $env:APPDATA = $menuQaData
    $env:LOCALAPPDATA = $menuQaData
    $menuQaWindow = 'Hidden'
    if ($Suite -in @('input','performance')) { $menuQaWindow = 'Normal' }
    $menuQaProcess = Start-Process -FilePath $GodotPath -ArgumentList $menuQaCommandLine -WorkingDirectory $menuQaRoot -WindowStyle $menuQaWindow -RedirectStandardOutput $menuQaStdout -RedirectStandardError $menuQaStderr -PassThru
    $menuQaFocusRequest = Join-Path $menuQaOutput 'focus-request.json'
    $menuQaFocusAttempted = $false
    while (-not $menuQaProcess.WaitForExit(1000)) {
        if (-not $menuQaFocusAttempted -and (Test-Path -LiteralPath $menuQaFocusRequest)) {
            $menuQaFocusAttempted = $true
            $menuQaShell = New-Object -ComObject WScript.Shell
            $menuQaActivated = $menuQaShell.AppActivate($menuQaProcess.Id)
            [pscustomobject]@{processId=$menuQaProcess.Id;activated=$menuQaActivated;reason='Re-select restored QA window'} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $menuQaOutput 'focus-activation.json') -Encoding utf8
            [Runtime.InteropServices.Marshal]::ReleaseComObject($menuQaShell) | Out-Null
        }
        if (([DateTime]::UtcNow - $menuQaStart).TotalSeconds -gt $TimeoutSeconds) { Stop-Process -Id $menuQaProcess.Id; throw ('Menu QA timed out; evidence retained: ' + $menuQaOutput) }
    }
    $menuQaProcess.Refresh()
    $menuQaText = [string](Get-Content -LiteralPath $menuQaStdout -Raw)
    $menuQaError = [string](Get-Content -LiteralPath $menuQaStderr -Raw)
    $menuQaPass = $menuQaProcess.ExitCode -eq 0 -and ($menuQaText + $menuQaError) -notmatch 'SCRIPT ERROR|Parse Error|SHADER ERROR|(?m)^\s*ERROR:'
    if ($Suite -notin @('import','baseline') -and $menuQaText -notmatch 'MENU QA: \d+ checks, 0 failures') { $menuQaPass = $false }
    [pscustomobject]@{suite=$Suite;resolution=$Resolution;exitCode=$menuQaProcess.ExitCode;passed=$menuQaPass;stdout=$menuQaStdout;stderr=$menuQaStderr;screenshots=@(Get-ChildItem -LiteralPath $menuQaOutput -Filter '*.png' | Select-Object -ExpandProperty FullName)} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $menuQaOutput 'result.json') -Encoding utf8
    Write-Output $menuQaText.Trim()
    if (-not [string]::IsNullOrWhiteSpace($menuQaError)) { Write-Output $menuQaError.Trim() }
    if (-not $menuQaPass) { throw ('Menu QA failed; evidence retained: ' + $menuQaOutput) }
    Write-Output ('MENU QA OK: ' + $menuQaOutput)
} finally {
    $env:APPDATA = $menuQaPriorAppData
    $env:LOCALAPPDATA = $menuQaPriorLocalAppData
}
