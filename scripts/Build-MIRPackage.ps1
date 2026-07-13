param([string]$OutputDir = "dist")

$ErrorActionPreference = "Stop"
& (Join-Path $PSScriptRoot "Build-MIRMuseumTarget.ps1") -FactorioVersion "0.11" -OutputDir $OutputDir -MaterializeRoot (Join-Path $PSScriptRoot "..")
