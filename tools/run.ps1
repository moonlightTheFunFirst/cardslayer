param([string]$Godot = $env:GODOT_EXE, [switch]$Headless)
$ErrorActionPreference = 'Stop'
if (-not $Godot) { $Godot = 'F:\tools\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' }
if (-not (Test-Path -LiteralPath $Godot)) { throw 'Godotが見つかりません。-Godot または GODOT_EXE で指定してください。' }
$projectRoot = Split-Path $PSScriptRoot -Parent
if ($Headless) { & $Godot --headless --path $projectRoot --quit-after 3 } else { & $Godot --path $projectRoot }
exit $LASTEXITCODE
