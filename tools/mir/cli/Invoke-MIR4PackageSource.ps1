param(
  [Parameter(Mandatory)][ValidateSet('baseline','baseline-check','shadow','shadow-check','model','model-check')][string]$Command,
  [Parameter(Mandatory)][string]$RepoRoot,
  [string]$OutputPath,
  [ValidateSet('f210','f200','f110','f100')][string]$Target='f210'
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
if ($Command -in @('baseline','baseline-check')) {
  . (Join-Path $repo 'tools/mir/application/package/GoldenTargetBaselines.ps1')
  if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = 'spec/distribution/mir4-golden-four-target-baseline-v1.json' }
  Write-MIR4GoldenTargetBaseline -RepoRoot $repo -OutputPath $OutputPath -Check:($Command -ceq 'baseline-check') | ConvertTo-Json -Depth 12
  return
}
if ($Command -in @('model','model-check')) {
  . (Join-Path $repo 'tools/mir/application/package/ShadowSourceModel.ps1')
  if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = 'build/reports/package-source/mir4-shadow-source-model-v1.json' }
  $model = Write-MIR4ShadowSourceModel -RepoRoot $repo -OutputPath $OutputPath -Check:($Command -ceq 'model-check')
  [pscustomobject][ordered]@{
    status=[string]$model.status
    bindings=@($model.bindings).Count
    targets=@($model.target_overlays).Count
    omissions=@($model.target_overlays.operations | Where-Object semantic_class -ceq 'target-omission').Count
    output=$OutputPath
    record_sha256=[string]$model.record_sha256
  } | ConvertTo-Json -Depth 6
  return
}
. (Join-Path $repo 'tools/mir/application/package/ShadowTargetMaterializer.ps1')
if ($Command -ceq 'shadow') {
  if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = 'build/mir4/package-source/shadow-materializer-v1' }
  New-MIR4ShadowTargetMaterialization -RepoRoot $repo -Target $Target -Construction 'CLI' -OutputRoot $OutputPath | ConvertTo-Json -Depth 12
  return
}
$arguments = @{RepoRoot=$repo}
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) { $arguments.ReportPath = $OutputPath }
Invoke-MIR4ShadowTargetParity @arguments | ConvertTo-Json -Depth 12
