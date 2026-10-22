param(
    [string]$GodotPath = $env:GODOT_PATH,
    [switch]$Check,
    [string]$Resolution = '1280x800'
)
$ErrorActionPreference = 'Stop'
$taskProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
$taskLocalPaths = Join-Path $taskProjectRoot 'tools/local_paths.json'
if ([string]::IsNullOrWhiteSpace($GodotPath) -and (Test-Path -LiteralPath $taskLocalPaths)) {
    $GodotPath = (Get-Content -LiteralPath $taskLocalPaths -Raw | ConvertFrom-Json).godot
}
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $taskGodotCommand = Get-Command godot -ErrorAction SilentlyContinue
    if ($null -eq $taskGodotCommand) { throw 'Pass -GodotPath, set GODOT_PATH, or configure tools/local_paths.json.' }
    $GodotPath = $taskGodotCommand.Source
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot not found: $GodotPath" }
if ($Resolution -notmatch '^\d{3,4}x\d{3,4}$') { throw 'Resolution must look like 1280x800.' }
$taskOutput = Join-Path $PSScriptRoot 'runtime'
New-Item -ItemType Directory -Force -Path $taskOutput | Out-Null
Set-Content -LiteralPath (Join-Path $taskOutput '.gdignore') -Value ''
$taskOldAppData = $env:APPDATA
$taskOldLocalAppData = $env:LOCALAPPDATA
$taskOldQaOutput = $env:QA_OUT_DIR
try {
    $env:APPDATA = $taskOutput
    $env:LOCALAPPDATA = $taskOutput
    $env:QA_OUT_DIR = Join-Path $taskOutput 'qa'
    $taskScene = if ($Check) { 'res://tests/combat/workbench/battle_background_preview_check.tscn' } else { 'res://tests/combat/workbench/battle_background_preview.tscn' }
    $taskArguments = @('--path', ('"' + $taskProjectRoot + '"'), '--windowed', '--resolution', $Resolution, $taskScene)
    if ($Check) {
        $taskProcess = Start-Process -FilePath $GodotPath -ArgumentList $taskArguments -WindowStyle Hidden -PassThru -Wait -RedirectStandardOutput (Join-Path $taskOutput 'check-stdout.log') -RedirectStandardError (Join-Path $taskOutput 'check-stderr.log')
        Get-Content -LiteralPath (Join-Path $taskOutput 'check-stdout.log')
        Get-Content -LiteralPath (Join-Path $taskOutput 'check-stderr.log')
    } else {
        # This is the user-facing interactive test window.
        $taskProcess = Start-Process -FilePath $GodotPath -ArgumentList $taskArguments -WindowStyle Normal -PassThru -Wait
    }
    exit $taskProcess.ExitCode
} finally {
    $env:APPDATA = $taskOldAppData
    $env:LOCALAPPDATA = $taskOldLocalAppData
    $env:QA_OUT_DIR = $taskOldQaOutput
}
