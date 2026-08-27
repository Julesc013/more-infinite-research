param([Parameter(Mandatory)][string]$InputPath,[Parameter(Mandatory)][string]$OutputPath,[Parameter(Mandatory)][string]$RepoRoot)
$ErrorActionPreference='Stop'
. (Join-Path $RepoRoot 'tools/mir/application/extensions/ModuleEcosystem.ps1')
$value=Get-Content -Raw -LiteralPath $InputPath|ConvertFrom-Json
$result=ConvertFrom-MIR4MepV0ToV1 -Envelope $value
Test-MIR4MepV1Envelope -Envelope $result -RepoRoot $RepoRoot|Out-Null
[IO.File]::WriteAllText($OutputPath,(ConvertTo-MIR4ModuleCanonicalJson $result)+"`n",[Text.UTF8Encoding]::new($false))