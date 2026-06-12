$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$env:GOCACHE = Join-Path $root ".gocache"

New-Item -ItemType Directory -Force -Path (Join-Path $root "bin") | Out-Null
go build -o (Join-Path $root "bin\HGSC-Terminal.exe") .
Copy-Item -Force (Join-Path $root "bin\HGSC-Terminal.exe") (Join-Path $root "hgsc-terminal.exe")

Write-Host "Built bin\HGSC-Terminal.exe"
Write-Host "Updated hgsc-terminal.exe"
