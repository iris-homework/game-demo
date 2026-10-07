param(
    [ValidateSet('menu', 'dialogue', 'map', 'place', 'battle', 'pile', 'cyberware')]
    [string]$Target = 'menu',
    [ValidateSet('capture', 'integration', 'interaction', 'drag', 'pile', 'story', 'combat')]
    [string]$Suite = 'capture',
    [string]$GodotPath = $env:GODOT_PATH,
    [string]$OutputDirectory = '',
    [ValidateRange(1, 600)][int]$TimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'
$taskProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$taskLocalPaths = Join-Path $PSScriptRoot 'local_paths.json'
if ([string]::IsNullOrWhiteSpace($GodotPath) -and (Test-Path -LiteralPath $taskLocalPaths)) {
    $GodotPath = (Get-Content -LiteralPath $taskLocalPaths -Raw | ConvertFrom-Json).godot
}
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $taskCommand = Get-Command godot -ErrorAction SilentlyContinue
    if ($null -eq $taskCommand) { throw 'Set GODOT_PATH, pass -GodotPath, or configure tools/local_paths.json.' }
    $GodotPath = $taskCommand.Source
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot executable does not exist: $GodotPath" }
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $taskProjectRoot ('artifacts\qa\' + [DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + $Suite + '-' + $Target)
}
$taskOutputRoot = (New-Item -ItemType Directory -Path $OutputDirectory -Force).FullName
$taskScreenshots = @()
$taskScenes = @{
    integration = 'res://tests/r1_visual.tscn'
    interaction = 'res://tests/interaction_visual.tscn'
    drag = 'res://tests/drag_visual.tscn'
    pile = 'res://tests/pile_visual.tscn'
    story = 'res://tests/run.tscn'
    combat = 'res://tests/combat_tests.tscn'
}
$taskSummaries = @{
    integration = 'VISUAL INTEGRATION: 0 failures'
    interaction = 'INTERACTION VISUAL: \d+ checks, 0 failures'
    drag = 'DRAG VISUAL: \d+ checks, 0 failures'
    pile = 'PILE VISUAL: \d+ checks, 0 failures'
    story = '\b0 failures\b'
    combat = '\b0 failures\b'
}
$taskArgs = @('--path', $taskProjectRoot)
if ($Suite -in @('story', 'combat')) { $taskArgs += '--headless' }
$taskWindowStyle = 'Hidden'
if ($Suite -in @('interaction', 'drag', 'pile')) {
    # Input.warp_mouse requires an on-screen window for real pointer coordinates.
    $taskWindowStyle = 'Normal'
    $taskArgs += @('--windowed', '--position', '40,40', '--resolution', '1280x800', '--always-on-top')
}
if ($Suite -eq 'capture') {
    $taskScreenshotPath = Join-Path $taskOutputRoot ($Target + '.png')
    $taskArgs += @('res://tools/qa_capture.tscn', '--', '--target', $Target, '--output', $taskScreenshotPath)
} else { $taskArgs += $taskScenes[$Suite] }
# Paths are separate native arguments; reject quotes/newlines rather than execute shell text.
foreach ($taskArgument in $taskArgs) {
    if ($taskArgument -match '["\r\n]') { throw 'QA arguments cannot contain quotes or newlines.' }
}
$taskArgumentLine = ($taskArgs | ForEach-Object { '"' + $_ + '"' }) -join ' '
$taskStdout = Join-Path $taskOutputRoot 'stdout.log'
$taskStderr = Join-Path $taskOutputRoot 'stderr.log'
$taskStarted = [DateTime]::UtcNow
$taskProcess = Start-Process -FilePath $GodotPath -ArgumentList $taskArgumentLine -WindowStyle $taskWindowStyle -PassThru -RedirectStandardOutput $taskStdout -RedirectStandardError $taskStderr
if (-not $taskProcess.WaitForExit($TimeoutSeconds * 1000)) {
    Stop-Process -Id $taskProcess.Id -ErrorAction SilentlyContinue
    throw "Godot QA timed out. Logs: $taskOutputRoot"
}
$taskProcess.Refresh()
$taskOutput = [string](Get-Content -LiteralPath $taskStdout -Raw -ErrorAction SilentlyContinue)
$taskErrors = [string](Get-Content -LiteralPath $taskStderr -Raw -ErrorAction SilentlyContinue)
if (-not [string]::IsNullOrWhiteSpace($taskOutput)) { Write-Output $taskOutput.TrimEnd() }
if (-not [string]::IsNullOrWhiteSpace($taskErrors)) { Write-Output $taskErrors.TrimEnd() }
$taskFailure = ''
if ($taskProcess.ExitCode -ne 0 -or ($taskOutput + "`n" + $taskErrors) -match '(?im)\bSCRIPT ERROR\b|\bParse Error\b|^\s*ERROR:|Assertion failed') { $taskFailure = 'Godot QA failed.' }
if ($Suite -eq 'capture') {
    if ($taskOutput -notmatch 'QA CAPTURE OK:' -or -not (Test-Path -LiteralPath $taskScreenshotPath)) { $taskFailure = 'QA screenshot or completion marker is missing.' }
    if (Test-Path -LiteralPath $taskScreenshotPath) { $taskScreenshots += $taskScreenshotPath }
} else {
    if ($taskOutput -notmatch $taskSummaries[$Suite] -and [string]::IsNullOrWhiteSpace($taskFailure)) { $taskFailure = 'Expected suite summary is missing.' }
    $taskPrefixes = @{ integration = 'midnight_r1_'; interaction = 'midnight_ui_'; drag = 'midnight_drag_'; pile = 'midnight_pile_' }
    if ($taskPrefixes.ContainsKey($Suite)) {
        Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Filter ($taskPrefixes[$Suite] + '*.png') | Where-Object { $_.LastWriteTimeUtc -ge $taskStarted.AddSeconds(-1) } | ForEach-Object {
            $taskDestination = Join-Path $taskOutputRoot $_.Name
            Copy-Item -LiteralPath $_.FullName -Destination $taskDestination
            $taskScreenshots += $taskDestination
        }
    }
}
[pscustomobject]@{
    Suite = $Suite; Target = $Target; ExitCode = $taskProcess.ExitCode
    Status = $(if ([string]::IsNullOrWhiteSpace($taskFailure)) { 'passed' } else { 'failed' })
    Screenshots = $taskScreenshots; Logs = $taskOutputRoot
} | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $taskOutputRoot 'result.json') -Encoding utf8
if (-not [string]::IsNullOrWhiteSpace($taskFailure)) { throw "$taskFailure Logs: $taskOutputRoot" }
Write-Output "QA OK: $taskOutputRoot"
