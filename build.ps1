$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$env:GOCACHE = Join-Path $root ".gocache"

New-Item -ItemType Directory -Force -Path (Join-Path $root "bin") | Out-Null
go build -o (Join-Path $root "bin\CsAC-Terminal.exe") .

Write-Host "Built bin\CsAC-Terminal.exe"
