param(
    [ValidateSet('board', 'sizes', 'map')][string]$Mode = 'board',
    [string]$GodotPath = '',
    [string]$OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'
$iconProjectRoot = Split-Path -Parent $PSScriptRoot
if (-not $GodotPath) {
    $iconLocalPaths = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'local_paths.json') -Raw | ConvertFrom-Json
    $GodotPath = $iconLocalPaths.godot
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw 'Godot executable not found; pass -GodotPath.'
}
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $iconProjectRoot 'artifacts\icon-previews\all-locations'
}
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
# 预览输出与日志都留在 artifacts 下，不重建用户已删除的美术资产目录。
$iconEvidence = Join-Path $iconProjectRoot 'artifacts\qa\icons-all-locations'
$iconRuntimeData = Join-Path $iconEvidence 'engine-userdata'
New-Item -ItemType Directory -Force -Path $OutputDirectory, $iconEvidence, $iconRuntimeData | Out-Null
$iconStdout = Join-Path $iconEvidence ($Mode + '.stdout.log')
$iconStderr = Join-Path $iconEvidence ($Mode + '.stderr.log')
$iconEngineLog = Join-Path $iconEvidence ($Mode + '.engine.log')
$iconArguments = @('--path', ('"' + $iconProjectRoot + '"'), '--log-file', ('"' + $iconEngineLog + '"'),
    '--resolution', '1280x800', 'res://tools/icon_sample_preview.tscn', '--',
    '--icon-preview-mode', $Mode, '--icon-preview-output', ('"' + $OutputDirectory + '"'))
$iconPreviousAppData = $env:APPDATA
try {
    # Isolate engine logs, shader cache and autoload reads without changing system settings.
    $env:APPDATA = $iconRuntimeData
    $iconProcess = Start-Process -FilePath $GodotPath -ArgumentList $iconArguments -WorkingDirectory $iconProjectRoot -WindowStyle Hidden -RedirectStandardOutput $iconStdout -RedirectStandardError $iconStderr -PassThru
    if (-not $iconProcess.WaitForExit(45000)) {
        Stop-Process -Id $iconProcess.Id -Force
        throw ('Icon preview timed out; logs preserved in ' + $iconEvidence)
    }
    $iconProcess.Refresh()
    $iconOutput = Get-Content -LiteralPath $iconStdout -Raw
    $iconErrors = Get-Content -LiteralPath $iconStderr -Raw
    $iconScreenshot = Join-Path $OutputDirectory ('icon_preview_' + $Mode + '.png')
    if ($iconProcess.ExitCode -ne 0 -or ($iconOutput + $iconErrors) -match 'SCRIPT ERROR|Parse Error|ERROR:|ICON PREVIEW:.*(缺图|无法)' -or $iconOutput -notmatch 'ICON PREVIEW OK:' -or -not (Test-Path -LiteralPath $iconScreenshot)) {
        throw ('Icon preview failed; inspect ' + $iconStdout + ' and ' + $iconStderr)
    }
    Write-Output $iconOutput.Trim()
} finally {
    $env:APPDATA = $iconPreviousAppData
}
