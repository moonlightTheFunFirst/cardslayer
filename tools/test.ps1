param([string]$Godot = $env:GODOT_EXE)
$ErrorActionPreference = 'Stop'
if (-not $Godot) { $Godot = 'F:\tools\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' }
$projectRoot = Split-Path $PSScriptRoot -Parent
& $Godot --headless --path $projectRoot --script res://tests/run.gd
exit $LASTEXITCODE
