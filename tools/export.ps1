param([string]$Godot = $env:GODOT_EXE, [switch]$Release)
$ErrorActionPreference = 'Stop'
if (-not $Godot) { $Godot = 'F:\tools\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' }
$projectRoot = Split-Path $PSScriptRoot -Parent
New-Item -ItemType Directory -Force (Join-Path $projectRoot 'build') | Out-Null
# Optional project-local templates keep global Godot installations untouched.
$presetPath = Join-Path $projectRoot 'export_presets.cfg'
$originalPreset = [System.IO.File]::ReadAllText($presetPath)
$debugTemplate = Join-Path $projectRoot '.godot/templates/windows_debug_x86_64.exe'
$releaseTemplate = Join-Path $projectRoot '.godot/templates/windows_release_x86_64.exe'
if ((Test-Path -LiteralPath $debugTemplate) -and (Test-Path -LiteralPath $releaseTemplate)) {
    $patched = $originalPreset.Replace('custom_template/debug=""', 'custom_template/debug="' + $debugTemplate.Replace('\','/') + '"').Replace('custom_template/release=""', 'custom_template/release="' + $releaseTemplate.Replace('\','/') + '"')
    [System.IO.File]::WriteAllText($presetPath, $patched)
}
try {
if ($Release) { & $Godot --headless --path $projectRoot --export-release 'Windows Development' 'build/CardSlayer.exe' }
else { & $Godot --headless --path $projectRoot --export-debug 'Windows Development' 'build/CardSlayer.exe' }
    $exportExit = $LASTEXITCODE
} finally { [System.IO.File]::WriteAllText($presetPath, $originalPreset) }
exit $exportExit
