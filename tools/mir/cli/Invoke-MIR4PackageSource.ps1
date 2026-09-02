param(
  [Parameter(Mandatory)][ValidateSet('baseline','baseline-check','shadow','shadow-check','model','model-check','materialize','materialize-check','runtime-replay','runtime-replay-check')][string]$Command,
  [Parameter(Mandatory)][string]$RepoRoot,
  [string]$OutputPath,
  [ValidatePattern('^[A-Z0-9][A-Z0-9.-]*$')][string]$CandidateId = 'M41-EDITABLE-SOURCE',
  [string]$SourceVersion,
  [string]$DistributionVersion,
  [string]$FactorioBin,
  [string]$WorkRoot,
  [string]$EvidenceRoot,
  [ValidateSet('OnFailure','Always','Never')][string]$Retention = 'OnFailure',
  [ValidateSet('f210','f200','f110','f100')][string]$Target='f210'
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
if ($Command -eq 'runtime-replay') {
  foreach ($required in @(@{name='FactorioBin';value=$FactorioBin},@{name='WorkRoot';value=$WorkRoot},@{name='EvidenceRoot';value=$EvidenceRoot})) {
    if ([string]::IsNullOrWhiteSpace([string]$required.value)) { throw "runtime-replay requires $($required.name)." }
  }
  if ($CandidateId -eq 'M41-EDITABLE-SOURCE') { $CandidateId = "M41-F2D-$((& git -C $repo rev-parse --short=8 HEAD).Trim().ToUpperInvariant())-$($Target.ToUpperInvariant())" }
  . (Join-Path $repo 'tools/mir/application/package/RuntimeReplay.ps1')
  Invoke-MIR4TargetRuntimeReplay -RepoRoot $repo -Target $Target -FactorioBin $FactorioBin -WorkRoot $WorkRoot -EvidenceRoot $EvidenceRoot -CandidateId $CandidateId -Retention $Retention | ConvertTo-Json -Depth 20
  return
}
if ($Command -eq 'runtime-replay-check') {
  if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) { throw 'runtime-replay-check requires EvidenceRoot.' }
  $verifierArguments = @{RepoRoot=$repo;Target=$Target;EvidenceRoot=$EvidenceRoot}
  if (-not [string]::IsNullOrWhiteSpace($OutputPath)) { $verifierArguments.OutputPath=$OutputPath }
  & (Join-Path $repo 'tools/mir/application/package/RuntimeReplayVerifier.ps1') @verifierArguments
  return
}
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
if ($Command -in @('materialize','materialize-check')) {
  . (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
  if ($Command -ceq 'materialize') {
    if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = 'build/packages' }
    New-MIR4TargetPackage -RepoRoot $repo -Target $Target -CandidateId $CandidateId -SourceVersion $SourceVersion -DistributionVersion $DistributionVersion -OutputRoot $OutputPath | ConvertTo-Json -Depth 12
    return
  }
  if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = 'build/reports/package-source/mir4-editable-source-materializer-v1.json' }
  Invoke-MIR4TargetMaterializerParity -RepoRoot $repo -ReportPath $OutputPath -Check | ConvertTo-Json -Depth 12
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
