param(
  [Parameter(Mandatory)][ValidateSet('baseline','baseline-check')][string]$Command,
  [Parameter(Mandatory)][string]$RepoRoot,
  [string]$OutputPath = 'spec/distribution/mir4-golden-four-target-baseline-v1.json'
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/package/GoldenTargetBaselines.ps1')
Write-MIR4GoldenTargetBaseline -RepoRoot $repo -OutputPath $OutputPath -Check:($Command -ceq 'baseline-check') | ConvertTo-Json -Depth 12
