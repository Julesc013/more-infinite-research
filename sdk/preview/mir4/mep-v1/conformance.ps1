param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path)
$ErrorActionPreference='Stop'
. (Join-Path $RepoRoot 'tools/lib/mir4/PlatformPreview.ps1')
$value=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'sdk/preview/mir4/reference-extension-v1/extension.json')|ConvertFrom-Json
Test-MIR4MepV1Envelope -Envelope $value -RepoRoot $RepoRoot|Out-Null
Resolve-MIR4ExtensionClosureV1 -RepoRoot $RepoRoot -Extensions @($value) -Target f210|Out-Null
[pscustomobject]@{status='passed';maturity='developer-preview';production_consumer='BLOCKED-INDEPENDENT-PRODUCTION-CONSUMER'}|ConvertTo-Json