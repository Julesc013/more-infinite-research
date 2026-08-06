param(
  [Parameter(Mandatory)][ValidateSet("manual", "protected", "seal", "backport", "promotion", "tag", "publication", "public-byte")][string]$Obligation,
  [Parameter(Mandatory)][string]$ContextPath,
  [string]$EvidenceRoot = "build/results/evidence",
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path
)
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
foreach ($module in @("Core", "Records", "Planner", "Scenario", "Observation", "Evidence", "Views", "Context")) {
  . (Join-Path $repo "tools/lib/control/$module.ps1")
}
$context = Assert-MIRCPVerificationContext -Path $ContextPath
$manifest = Get-Content -Raw -LiteralPath (Join-Path $context.path "context-manifest.json") | ConvertFrom-Json
$descriptor = Get-Content -Raw -LiteralPath (Join-Path $context.path "candidate-descriptor.json") | ConvertFrom-Json
$release = Get-MIRCPReleaseByVersion -Release ([string]$manifest.release) -RepoRoot $repo

function Get-ReleaseProofRows {
  param([Parameter(Mandatory)][string]$Name)
  $property = $release.proofs.PSObject.Properties[$Name]
  if ($null -eq $property) { return @() }
  return @($property.Value)
}

function Assert-ProofFile {
  param([Parameter(Mandatory)]$Proof)
  if ($null -eq $Proof.PSObject.Properties["path"] -or [string]::IsNullOrWhiteSpace([string]$Proof.path)) { throw "$Obligation proof has no governed path." }
  $path = Join-Path $repo ([string]$Proof.path)
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "$Obligation proof is missing: $($Proof.path)" }
  $sha = Get-MIRCPSha256File -Path $path
  if ($null -ne $Proof.PSObject.Properties["sha256"] -and -not [string]::IsNullOrWhiteSpace([string]$Proof.sha256) -and $sha -ne [string]$Proof.sha256) {
    throw "$Obligation proof hash changed: $($Proof.path)"
  }
  return [pscustomobject][ordered]@{path=[string]$Proof.path;sha256=$sha;record=(Get-Content -Raw -LiteralPath $path | ConvertFrom-Json)}
}

$proofs = [Collections.Generic.List[object]]::new()
switch ($Obligation) {
  "manual" {
    $rows = @(Get-ReleaseProofRows -Name "manual_acceptance")
    if ($rows.Count -eq 0) { throw "Release $($release.release) has no maintainer-authored exact-candidate manual attestation." }
    foreach ($row in $rows) {
      $proof = Assert-ProofFile -Proof $row
      $record = $proof.record
      if ([string]$record.status -ne "passed" -or [string]$record.candidate_sha256 -ne [string]$descriptor.archive_sha256 -or
          [string]$record.candidate_content_sha256 -ne [string]$descriptor.content_sha256 -or [string]$record.source_commit -ne [string]$descriptor.source_commit -or
          [string]::IsNullOrWhiteSpace([string]$record.reviewer)) {
        throw "Manual attestation is not passed and bound to the exact context candidate."
      }
      $proofs.Add($proof)
    }
  }
  "protected" {
    $index = Update-MIRCPEvidenceIndex -RepoRoot $repo -Root $EvidenceRoot
    $matches = @($index.index.objects | Where-Object {
      [string]$_.kind -eq "execution-manifest" -and [string]$_.context_digest -eq [string]$context.context_id -and
      [string]$_.status -eq "passed" -and [string]$_.trust_class -eq "protected-release" -and -not [bool]$_.revoked
    })
    if ($matches.Count -ne 1) { throw "Protected qualification requires exactly one unrevoked protected-release execution manifest for this context." }
    $proofs.Add($matches[0])
  }
  "seal" {
    $rows = @(Get-ReleaseProofRows -Name "seal")
    if ($rows.Count -eq 0) { throw "Release $($release.release) has no exact candidate seal." }
    foreach ($row in $rows) {
      $proof = Assert-ProofFile -Proof $row
      $record = $proof.record
      $sealedSha = if ($null -ne $record.PSObject.Properties["candidate"]) { [string]$record.candidate.sha256 } else { [string]$record.candidate_sha256 }
      if ($sealedSha -ne [string]$descriptor.archive_sha256) { throw "Candidate seal is not bound to the context archive." }
      $proofs.Add($proof)
    }
  }
  "backport" {
    $rows = @(Get-ReleaseProofRows -Name "backport_reconstruction")
    if ($rows.Count -eq 0) { throw "Release $($release.release) has no deterministic dual-parent reconstruction proof." }
    foreach ($row in $rows) { $proofs.Add((Assert-ProofFile -Proof $row)) }
  }
  default {
    $stateOrder = @("planned", "source-frozen", "package-built", "focused-qualified", "candidate-qualified", "manually-accepted", "protected-qualified", "sealed", "promoted", "tagged", "published", "publicly-verified")
    $requiredState = @{promotion="promoted";tag="tagged";publication="published";"public-byte"="publicly-verified"}[$Obligation]
    if ([Array]::IndexOf($stateOrder, [string]$release.state) -lt [Array]::IndexOf($stateOrder, $requiredState)) {
      throw "Release $($release.release) is $($release.state); $Obligation requires $requiredState."
    }
    $proofs.Add([pscustomobject][ordered]@{release=[string]$release.release;state=[string]$release.state})
  }
}

[pscustomobject][ordered]@{schema=1;status="passed";obligation=$Obligation;release=[string]$release.release;candidate_sha256=[string]$descriptor.archive_sha256;context_digest=[string]$context.context_id;proofs=@($proofs)} | ConvertTo-Json -Depth 12
