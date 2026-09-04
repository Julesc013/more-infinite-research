Set-StrictMode -Version Latest

if (-not (Get-Command New-MIR4TargetPackage -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot '../../package/TargetMaterializer.ps1')
}

function New-MIR441FourTargetCandidate {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$WorkRoot,
    [Parameter(Mandatory)][string]$EvidenceRoot
  )
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  Assert-MIR441CleanTrackedSource -RepoRoot $repo
  $contract=Get-MIR441ReleaseReadinessContract -RepoRoot $repo
  $work=Assert-MIR441ExternalRoot -RepoRoot $repo -Path $WorkRoot -Name WorkRoot
  $evidence=Assert-MIR441ExternalRoot -RepoRoot $repo -Path $EvidenceRoot -Name EvidenceRoot
  if((Test-MIR441PathContained -Root $work -Path $evidence -AllowEqual)-or(Test-MIR441PathContained -Root $evidence -Path $work -AllowEqual)){throw '[mir441-build-root-overlap]'}
  foreach($root in @($work,$evidence)){if(-not(Test-Path -LiteralPath $root)){New-Item -ItemType Directory -Force -Path $root|Out-Null}}
  $snapshot=Assert-MIR441ResourceAdmission -Policy $contract.resource_policy -WorkRoot $work -EstimatedPeakBytes 2GB
  $assets=Join-Path $evidence 'assets';if(-not(Test-Path -LiteralPath $assets)){New-Item -ItemType Directory -Force -Path $assets|Out-Null}
  $rows=[Collections.Generic.List[object]]::new()
  foreach($target in @($contract.targets)){
    $id=[string]$target.target;$receiptPath=Join-Path $evidence "candidate/$id.json"
    if(Test-Path -LiteralPath $receiptPath -PathType Leaf){
      $existing=Get-Content -Raw -LiteralPath $receiptPath|ConvertFrom-Json -Depth 100
      $asset=Join-Path $assets ([string]$existing.asset.path)
      if((Get-FileHash -LiteralPath $asset -Algorithm SHA256).Hash -cne [string]$existing.asset.sha256){throw "[mir441-build-resume-asset] $id"}
      $rows.Add($existing);continue
    }
    $targetRoot=Join-Path $work $id
    if(Test-Path -LiteralPath $targetRoot){Remove-MIR441ContainedTree -AdmittedRoot $work -Path $targetRoot}
    New-Item -ItemType Directory -Force -Path $targetRoot|Out-Null
    $a=New-MIR4TargetPackage -RepoRoot $repo -Target $id -CandidateId "MIR410-$($id.ToUpperInvariant())-A" -SourceVersion '4.1.0' -OutputRoot $targetRoot
    $aIdentity=Get-MIR441FileIdentity -Path ([string]$a.archive_path)
    Remove-MIR441ContainedTree -AdmittedRoot $targetRoot -Path (Split-Path -Parent ([string]$a.tree_path))
    $b=New-MIR4TargetPackage -RepoRoot $repo -Target $id -CandidateId "MIR410-$($id.ToUpperInvariant())-B" -SourceVersion '4.1.0' -OutputRoot $targetRoot
    $bIdentity=Get-MIR441FileIdentity -Path ([string]$b.archive_path)
    if($aIdentity.sha256-cne$bIdentity.sha256-or[string]$a.content_sha256-cne[string]$b.content_sha256-or[int]$a.entry_count-ne[int]$b.entry_count){throw "[mir441-build-nondeterministic] $id"}
    $assetName=[string]$bIdentity.path;$assetPath=Join-Path $assets $assetName
    Copy-Item -LiteralPath ([string]$b.archive_path) -Destination $assetPath
    $accepted=Get-MIR441FileIdentity -Path $assetPath -RelativePath $assetName
    if($accepted.sha256-cne$bIdentity.sha256){throw "[mir441-build-custody-copy] $id"}
    $row=[pscustomobject][ordered]@{
      schema=1;kind='MIR441TargetCandidateBuildV1';status='built-private-deterministic-unqualified';target=$id
      source_version='4.1.0';distribution_version=[string]$target.distribution_version
      source=(Get-MIR441GitIdentity -RepoRoot $repo);package_source_sha256=[string]$b.package_source_sha256
      asset=$accepted;content_sha256=[string]$b.content_sha256;entry_count=[int]$b.entry_count
      build_a_sha256=[string]$aIdentity.sha256;build_b_sha256=[string]$bIdentity.sha256;deterministic_archive_bytes=$true
      expanded_success_roots='removed';qualification='pending';technical_seal='pending';publication_authorized=$false
    }
    Write-MIR441Json -Value $row -Path $receiptPath
    Remove-MIR441ContainedTree -AdmittedRoot $work -Path $targetRoot
    $rows.Add($row)
  }
  $manifest=[pscustomobject][ordered]@{
    schema=1;kind='MIR441FourTargetCandidateManifestV1';status='MIR-4.1.0-PRIVATE-FOUR-TARGET-CANDIDATE-BUILT-UNQUALIFIED'
    candidate_id=[string]$contract.release.candidate_id;source=(Get-MIR441GitIdentity -RepoRoot $repo);targets=@($rows)
    resource_admission=$snapshot;publisher_can_build=$false;tagging_authorized=$false;publication_authorized=$false
  }
  Write-MIR441Json -Value $manifest -Path (Join-Path $evidence 'candidate-manifest.json')
  return $manifest
}
