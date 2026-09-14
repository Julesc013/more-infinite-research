Set-StrictMode -Version Latest

# A08 is intentionally a proof-only adapter. It can create and push a
# candidate ref only when a separately persisted intention names a synthetic
# or protected remote. It never updates main, creates tags, or publishes.

function Invoke-MIR4A08Git {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string[]]$Arguments
  )
  $output = @(& git -C $RepoRoot @Arguments 2>&1)
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0) {
    throw "[mir4-a08-git] git $($Arguments -join ' ') :: $($output -join ' ')"
  }
  return @($output | ForEach-Object { [string]$_ })
}

function Resolve-MIR4A08Commit {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Revision)
  $value = ((Invoke-MIR4A08Git -RepoRoot $RepoRoot -Arguments @('rev-parse','--verify',"$Revision^{commit}")) -join '').Trim()
  if ($value -cnotmatch '^[0-9a-f]{40}$') { throw "[mir4-a08-commit] $Revision" }
  return $value
}

function Resolve-MIR4A08Tree {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Commit)
  $value = ((Invoke-MIR4A08Git -RepoRoot $RepoRoot -Arguments @('rev-parse','--verify',"$Commit^{tree}")) -join '').Trim()
  if ($value -cnotmatch '^[0-9a-f]{40}$') { throw "[mir4-a08-tree] $Commit" }
  return $value
}

function Get-MIR4A08OptionalRef {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Ref)
  $output = @(& git -C $RepoRoot rev-parse --verify $Ref 2>$null)
  if ($LASTEXITCODE -ne 0) { return $null }
  $value = ($output -join '').Trim()
  if ($value -cnotmatch '^[0-9a-f]{40}$') { throw "[mir4-a08-ref] $Ref" }
  return $value
}

function Get-MIR4A08RemoteRef {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Remote,[Parameter(Mandatory)][string]$Ref)
  if ($Ref -cnotmatch '^refs/heads/[A-Za-z0-9][A-Za-z0-9._/-]{0,180}$') { throw '[mir4-a08-remote-ref]' }
  $output = @(& git -C $RepoRoot ls-remote --refs $Remote $Ref 2>&1)
  if ($LASTEXITCODE -ne 0) { throw "[mir4-a08-remote-read] $($output -join ' ')" }
  if ($output.Count -eq 0) { return $null }
  if ($output.Count -ne 1 -or $output[0] -cnotmatch '^([0-9a-f]{40})\s+(.+)$' -or $Matches[2] -cne $Ref) {
    throw '[mir4-a08-remote-read]'
  }
  return $Matches[1]
}

function Get-MIR4A08CanonicalJson {
  param([Parameter(Mandatory)]$Value)
  return ($Value | ConvertTo-Json -Depth 100 -Compress)
}

function Get-MIR4A08Sha256 {
  param([Parameter(Mandatory)]$Value)
  $bytes = [Text.Encoding]::UTF8.GetBytes((Get-MIR4A08CanonicalJson $Value))
  return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
}

function Get-MIR4A08FileSha256 {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw '[mir4-a08-file-missing]' }
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Assert-MIR4A08PropertyNames {
  param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)][string[]]$Names,[Parameter(Mandatory)][string]$Code)
  $actual = @($Value.PSObject.Properties | ForEach-Object { [string]$_.Name })
  if ($actual.Count -ne $Names.Count -or @($actual | Where-Object { $_ -cnotin $Names }).Count -ne 0) { throw $Code }
}

function Assert-MIR4A08Boolean {
  param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)][bool]$Expected,[Parameter(Mandatory)][string]$Code)
  if ($Value -isnot [bool] -or [bool]$Value -ne $Expected) { throw $Code }
}

function Assert-MIR4A08Sha {
  param([Parameter(Mandatory)][string]$Value,[Parameter(Mandatory)][string]$Code)
  if ($Value -cnotmatch '^[A-F0-9]{64}$') { throw $Code }
}

function Get-MIR4A08PlanSha256 {
  param([Parameter(Mandatory)]$Plan)
  $copy = [ordered]@{}
  foreach ($property in $Plan.PSObject.Properties) {
    $copy[$property.Name] = if ($property.Name -ceq 'plan_sha256') { '' } else { $property.Value }
  }
  return Get-MIR4A08Sha256 ([pscustomobject]$copy)
}

function Assert-MIR4A08Plan {
  param([Parameter(Mandatory)]$Plan)
  Assert-MIR4A08PropertyNames $Plan @('schema','kind','strategy','main_before','source','reconciliation','candidate','qualification','promotion','readback','tag_creation_authority','main_mutation_authority','release_authority','publication_authority','plan_sha256') '[mir4-a08-plan-invalid]'
  Assert-MIR4A08PropertyNames $Plan.main_before @('ref','commit','tree') '[mir4-a08-plan-invalid]'
  Assert-MIR4A08PropertyNames $Plan.source @('ref','commit','tree') '[mir4-a08-plan-invalid]'
  Assert-MIR4A08PropertyNames $Plan.reconciliation @('merge_base','main_unique_commit_count','patch_equivalent_main_commit_count','all_main_changes_integrated') '[mir4-a08-plan-invalid]'
  Assert-MIR4A08PropertyNames $Plan.candidate @('ref','parent_commit','source_commit','tree','construction','created') '[mir4-a08-plan-invalid]'
  Assert-MIR4A08PropertyNames $Plan.qualification @('exact_candidate_commit_required','exact_candidate_tree_required','exact_package_bytes_required','qualification_before_promotion','independent_record_required') '[mir4-a08-plan-invalid]'
  Assert-MIR4A08PropertyNames $Plan.promotion @('branch','merge_method','pull_request_required','required_status_checks','linear_history_required','ruleset_mutation_authorized','force_push_authorized','deletion_authorized') '[mir4-a08-plan-invalid]'
  Assert-MIR4A08PropertyNames $Plan.readback @('final_commit_may_differ','exact_tree_required','exact_package_bytes_required','main_base_ancestry_required','source_ref_unchanged_required','fresh_remote_ref_readback_required','direct_main_child_required','commit_message_binding_required','commit_rebinding_receipt_required') '[mir4-a08-plan-invalid]'
  if ([int]$Plan.schema -ne 1 -or
      [string]$Plan.kind -cne 'MIR42ProtectedMainPromotionTopologyPlanV1' -or
      [string]$Plan.strategy -cne 'main-based-tree-transplant-protected-pr' -or
      [string]$Plan.main_before.ref -cnotmatch '^refs/' -or [string]$Plan.source.ref -cnotmatch '^refs/' -or
      [string]$Plan.candidate.ref -cnotmatch '^refs/heads/candidate/[a-z0-9][a-z0-9._-]{2,80}$' -or
      [string]$Plan.promotion.branch -cne 'main' -or [string]$Plan.promotion.merge_method -cne 'squash' -or
      [string]$Plan.candidate.construction -cne 'single-parent commit carrying the exact frozen dev tree') { throw '[mir4-a08-plan-invalid]' }
  foreach ($commit in @([string]$Plan.main_before.commit,[string]$Plan.source.commit,[string]$Plan.reconciliation.merge_base,[string]$Plan.candidate.parent_commit,[string]$Plan.candidate.source_commit)) {
    if ($commit -cnotmatch '^[0-9a-f]{40}$') { throw '[mir4-a08-plan-invalid]' }
  }
  foreach ($tree in @([string]$Plan.main_before.tree,[string]$Plan.source.tree,[string]$Plan.candidate.tree)) {
    if ($tree -cnotmatch '^[0-9a-f]{40}$') { throw '[mir4-a08-plan-invalid]' }
  }
  foreach ($check in @($Plan.promotion.required_status_checks)) {
    if ([string]$check -notin @('branch-policy','verification-gate')) { throw '[mir4-a08-plan-invalid]' }
  }
  if (@($Plan.promotion.required_status_checks | Sort-Object -Unique).Count -ne 2 -or
      @($Plan.promotion.required_status_checks | Where-Object { $_ -notin @('branch-policy','verification-gate') }).Count -ne 0) { throw '[mir4-a08-plan-invalid]' }
  foreach ($assertion in @(
      @($Plan.reconciliation.all_main_changes_integrated,$true),@($Plan.candidate.created,$false),
      @($Plan.qualification.exact_candidate_commit_required,$true),@($Plan.qualification.exact_candidate_tree_required,$true),@($Plan.qualification.exact_package_bytes_required,$true),@($Plan.qualification.qualification_before_promotion,$true),@($Plan.qualification.independent_record_required,$true),
      @($Plan.promotion.pull_request_required,$true),@($Plan.promotion.linear_history_required,$true),@($Plan.promotion.ruleset_mutation_authorized,$false),@($Plan.promotion.force_push_authorized,$false),@($Plan.promotion.deletion_authorized,$false),
      @($Plan.readback.final_commit_may_differ,$true),@($Plan.readback.exact_tree_required,$true),@($Plan.readback.exact_package_bytes_required,$true),@($Plan.readback.main_base_ancestry_required,$true),@($Plan.readback.source_ref_unchanged_required,$true),@($Plan.readback.fresh_remote_ref_readback_required,$true),@($Plan.readback.direct_main_child_required,$true),@($Plan.readback.commit_message_binding_required,$true),@($Plan.readback.commit_rebinding_receipt_required,$true),
      @($Plan.tag_creation_authority,$false),@($Plan.main_mutation_authority,$false),@($Plan.release_authority,$false),@($Plan.publication_authority,$false)
    )) { Assert-MIR4A08Boolean -Value $assertion[0] -Expected $assertion[1] -Code '[mir4-a08-plan-invalid]' }
  if ([int]$Plan.reconciliation.main_unique_commit_count -lt 0 -or [int]$Plan.reconciliation.patch_equivalent_main_commit_count -lt 0 -or
      [string]$Plan.plan_sha256 -cnotmatch '^[A-F0-9]{64}$' -or [string]$Plan.plan_sha256 -cne (Get-MIR4A08PlanSha256 $Plan)) { throw '[mir4-a08-plan-invalid]' }
  return $Plan
}

function Get-MIR4A08CandidateMessage {
  param([Parameter(Mandatory)]$Plan)
  return "MIR 4.2 protected candidate`n`nMIR-Source-Commit: $($Plan.source.commit)`nMIR-Source-Tree: $($Plan.source.tree)`nMIR-Main-Base: $($Plan.main_before.commit)`nMIR-Promotion-Plan: $($Plan.plan_sha256)"
}

function Assert-MIR4A08CandidateAgainstPlan {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Plan,[Parameter(Mandatory)][string]$CandidateRef,[Parameter(Mandatory)][string]$CandidateCommit)
  if ($CandidateRef -cne [string]$Plan.candidate.ref) { throw '[mir4-a08-candidate-ref-conflict]' }
  $tree = Resolve-MIR4A08Tree -RepoRoot $RepoRoot -Commit $CandidateCommit
  $parents = @(((Invoke-MIR4A08Git -RepoRoot $RepoRoot -Arguments @('show','-s','--format=%P',$CandidateCommit)) -join '').Trim() -split '\s+' | Where-Object { $_ })
  $message = ((Invoke-MIR4A08Git -RepoRoot $RepoRoot -Arguments @('show','-s','--format=%B',$CandidateCommit)) -join "`n").TrimEnd()
  if ($tree -cne [string]$Plan.source.tree -or $parents.Count -ne 1 -or $parents[0] -cne [string]$Plan.main_before.commit -or
      $message -cne (Get-MIR4A08CandidateMessage $Plan)) { throw '[mir4-a08-candidate-ref-conflict]' }
  return [pscustomobject][ordered]@{
    schema=1;kind='MIR42ProtectedMainCandidateV1';ref=$CandidateRef;commit=$CandidateCommit;tree=$tree
    parent_commit=$parents[0];source_commit=[string]$Plan.source.commit;plan_sha256=[string]$Plan.plan_sha256
    candidate_message_sha256=Get-MIR4A08Sha256 $message
  }
}

function New-MIR4ProtectedPromotionTopologyPlan {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [string]$MainRef = 'refs/remotes/origin/main',
    [string]$SourceRef = 'refs/remotes/origin/dev',
    [Parameter(Mandatory)][string]$CandidateRef,
    [Parameter(Mandatory)]$EffectivePolicy
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  if ($CandidateRef -cnotmatch '^refs/heads/candidate/[a-z0-9][a-z0-9._-]{2,80}$') { throw '[mir4-a08-candidate-ref]' }
  $requiredChecks = @($EffectivePolicy.required_status_checks | ForEach-Object { [string]$_ } | Sort-Object -CaseSensitive -Unique)
  if (-not [bool]$EffectivePolicy.pull_request_required -or -not [bool]$EffectivePolicy.linear_history_required -or
      -not [bool]$EffectivePolicy.non_fast_forward_blocked -or -not [bool]$EffectivePolicy.deletion_blocked -or
      [int]$EffectivePolicy.bypass_actor_count -ne 0 -or -not [bool]$EffectivePolicy.squash_merge_enabled -or
      @('branch-policy','verification-gate' | Where-Object { $_ -notin $requiredChecks }).Count -ne 0) { throw '[mir4-a08-policy-incompatible]' }
  $mainCommit = Resolve-MIR4A08Commit -RepoRoot $repo -Revision $MainRef
  $sourceCommit = Resolve-MIR4A08Commit -RepoRoot $repo -Revision $SourceRef
  $sourceTree = Resolve-MIR4A08Tree -RepoRoot $repo -Commit $sourceCommit
  $mainTree = Resolve-MIR4A08Tree -RepoRoot $repo -Commit $mainCommit
  $mergeBase = ((Invoke-MIR4A08Git -RepoRoot $repo -Arguments @('merge-base',$mainCommit,$sourceCommit)) -join '').Trim()
  $cherry = @(Invoke-MIR4A08Git -RepoRoot $repo -Arguments @('cherry',$sourceCommit,$mainCommit))
  $unintegrated = @($cherry | Where-Object { $_ -match '^\+\s+[0-9a-f]{40}$' })
  if ($unintegrated.Count -ne 0) { throw '[mir4-a08-main-change-not-integrated]' }
  $mainUniqueCount = [int](((Invoke-MIR4A08Git -RepoRoot $repo -Arguments @('rev-list','--count',"$mergeBase..$mainCommit")) -join '').Trim())
  if ($cherry.Count -ne $mainUniqueCount) { throw '[mir4-a08-main-history-not-linear-patch-set]' }
  $plan = [pscustomobject][ordered]@{
    schema=1;kind='MIR42ProtectedMainPromotionTopologyPlanV1';strategy='main-based-tree-transplant-protected-pr'
    main_before=[pscustomobject][ordered]@{ref=$MainRef;commit=$mainCommit;tree=$mainTree}
    source=[pscustomobject][ordered]@{ref=$SourceRef;commit=$sourceCommit;tree=$sourceTree}
    reconciliation=[pscustomobject][ordered]@{merge_base=$mergeBase;main_unique_commit_count=$mainUniqueCount;patch_equivalent_main_commit_count=@($cherry | Where-Object { $_ -match '^-\s+[0-9a-f]{40}$' }).Count;all_main_changes_integrated=$true}
    candidate=[pscustomobject][ordered]@{ref=$CandidateRef;parent_commit=$mainCommit;source_commit=$sourceCommit;tree=$sourceTree;construction='single-parent commit carrying the exact frozen dev tree';created=$false}
    qualification=[pscustomobject][ordered]@{exact_candidate_commit_required=$true;exact_candidate_tree_required=$true;exact_package_bytes_required=$true;qualification_before_promotion=$true;independent_record_required=$true}
    promotion=[pscustomobject][ordered]@{branch='main';merge_method='squash';pull_request_required=$true;required_status_checks=$requiredChecks;linear_history_required=$true;ruleset_mutation_authorized=$false;force_push_authorized=$false;deletion_authorized=$false}
    readback=[pscustomobject][ordered]@{final_commit_may_differ=$true;exact_tree_required=$true;exact_package_bytes_required=$true;main_base_ancestry_required=$true;source_ref_unchanged_required=$true;fresh_remote_ref_readback_required=$true;direct_main_child_required=$true;commit_message_binding_required=$true;commit_rebinding_receipt_required=$true}
    tag_creation_authority=$false;main_mutation_authority=$false;release_authority=$false;publication_authority=$false;plan_sha256=''
  }
  $plan.plan_sha256 = Get-MIR4A08PlanSha256 $plan
  return Assert-MIR4A08Plan $plan
}

function New-MIR4ProtectedMainCandidate {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Plan)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $null = Assert-MIR4A08Plan $Plan
  if ((Resolve-MIR4A08Commit -RepoRoot $repo -Revision ([string]$Plan.main_before.ref)) -cne [string]$Plan.main_before.commit) { throw '[mir4-a08-main-ref-drift]' }
  if ((Resolve-MIR4A08Commit -RepoRoot $repo -Revision ([string]$Plan.source.ref)) -cne [string]$Plan.source.commit) { throw '[mir4-a08-source-ref-drift]' }
  $candidateRef = [string]$Plan.candidate.ref
  $candidateCommit = Get-MIR4A08OptionalRef -RepoRoot $repo -Ref $candidateRef
  $created = $false
  if ($null -eq $candidateCommit) {
    $candidateCommit = ((Invoke-MIR4A08Git -RepoRoot $repo -Arguments @('commit-tree',[string]$Plan.source.tree,'-p',[string]$Plan.main_before.commit,'-m',(Get-MIR4A08CandidateMessage $Plan))) -join '').Trim()
    if ($candidateCommit -cnotmatch '^[0-9a-f]{40}$') { throw '[mir4-a08-candidate-commit]' }
    $null = Invoke-MIR4A08Git -RepoRoot $repo -Arguments @('update-ref',$candidateRef,$candidateCommit,('0'*40))
    $created = $true
  }
  $candidate = Assert-MIR4A08CandidateAgainstPlan -RepoRoot $repo -Plan $Plan -CandidateRef $candidateRef -CandidateCommit $candidateCommit
  $candidate | Add-Member -NotePropertyName created -NotePropertyValue $created
  $candidate | Add-Member -NotePropertyName remote_push_performed -NotePropertyValue $false
  $candidate | Add-Member -NotePropertyName main_mutation_performed -NotePropertyValue $false
  $candidate | Add-Member -NotePropertyName tag_created -NotePropertyValue $false
  $candidate | Add-Member -NotePropertyName publication_authorized -NotePropertyValue $false
  return $candidate
}

function Resolve-MIR4A08ContainedFile {
  param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$RelativePath,[Parameter(Mandatory)][string]$Code)
  $rootPath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Root).Path).TrimEnd('\','/')
  if ([IO.Path]::IsPathRooted($RelativePath) -or $RelativePath -match '(^|[\\/])\.\.([\\/]|$)') { throw $Code }
  $candidate = [IO.Path]::GetFullPath((Join-Path $rootPath $RelativePath))
  $prefix = $rootPath + [IO.Path]::DirectorySeparatorChar
  if (-not $candidate.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $candidate -PathType Leaf)) { throw $Code }
  $current = $rootPath
  foreach ($segment in ($RelativePath -split '[\\/]')) {
    $current = Join-Path $current $segment
    if (((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw $Code }
  }
  return $candidate
}

function Get-MIR4A08PackageObservation {
  param([Parameter(Mandatory)][string]$PackagePath,[Parameter(Mandatory)][string]$Target,[Parameter(Mandatory)][string]$RelativePath)
  try { $archive = [IO.Compression.ZipFile]::OpenRead($PackagePath) } catch { throw '[mir4-a08-package-archive]' }
  try {
    $entries = @($archive.Entries | Sort-Object -Property FullName -CaseSensitive)
    if ($entries.Count -eq 0 -or @($entries.FullName | Sort-Object -Unique).Count -ne $entries.Count) { throw '[mir4-a08-package-archive]' }
    $content = [Text.StringBuilder]::new()
    foreach ($entry in $entries) {
      $stream = $entry.Open(); $hash = [Security.Cryptography.SHA256]::Create()
      try { $entrySha = [Convert]::ToHexString($hash.ComputeHash($stream)) } finally { $hash.Dispose(); $stream.Dispose() }
      [void]$content.Append($entry.FullName).Append([char]0).Append([string]$entry.Length).Append([char]0).Append($entrySha).Append("`n")
    }
    $contentSha = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($content.ToString())))
    return [pscustomobject][ordered]@{target=$Target;relative_path=$RelativePath;archive_sha256=(Get-MIR4A08FileSha256 $PackagePath);content_sha256=$contentSha;bytes=[long](Get-Item -LiteralPath $PackagePath).Length;entry_count=$entries.Count}
  } finally { $archive.Dispose() }
}

function Get-MIR4A08PackageSetSha256 {
  param([Parameter(Mandatory)][object[]]$Packages)
  $normalized = @(foreach ($package in @($Packages | Sort-Object { [string]$_.target })) {
    [pscustomobject][ordered]@{target=[string]$package.target;archive_sha256=[string]$package.archive_sha256;content_sha256=[string]$package.content_sha256;bytes=[long]$package.bytes;entry_count=[int]$package.entry_count}
  })
  if ($normalized.Count -eq 0 -or @($normalized.target | Sort-Object -Unique).Count -ne $normalized.Count) { throw '[mir4-a08-package-set]' }
  foreach ($package in $normalized) {
    Assert-MIR4A08Sha $package.archive_sha256 '[mir4-a08-package-set]'; Assert-MIR4A08Sha $package.content_sha256 '[mir4-a08-package-set]'
    if ($package.bytes -lt 1 -or $package.entry_count -lt 1) { throw '[mir4-a08-package-set]' }
  }
  return Get-MIR4A08Sha256 $normalized
}

function Read-MIR4A08QualificationRecord {
  param([Parameter(Mandatory)]$Plan,[Parameter(Mandatory)]$Candidate,[Parameter(Mandatory)][string]$RecordPath,[Parameter(Mandatory)][string]$PackageRoot,[Parameter(Mandatory)][string]$TrustedRecordSha256)
  $recordFullPath = (Resolve-Path -LiteralPath $RecordPath).Path
  Assert-MIR4A08Sha $TrustedRecordSha256 '[mir4-a08-qualification-record]'
  if ((Get-MIR4A08FileSha256 $recordFullPath) -cne $TrustedRecordSha256) { throw '[mir4-a08-qualification-record-hash]' }
  try { $record = (Get-Content -Raw -LiteralPath $recordFullPath | ConvertFrom-Json -Depth 100 -DateKind String) } catch { throw '[mir4-a08-qualification-record]' }
  Assert-MIR4A08PropertyNames $record @('schema','kind','status','candidate','packages','release_authority','publication_authority') '[mir4-a08-qualification-record]'
  Assert-MIR4A08PropertyNames $record.candidate @('ref','commit','tree') '[mir4-a08-qualification-record]'
  if ([int]$record.schema -ne 1 -or [string]$record.kind -cne 'MIR42ProtectedMainQualificationV1' -or [string]$record.status -cne 'independently-qualified' -or
      [string]$record.candidate.ref -cne [string]$Candidate.ref -or [string]$record.candidate.commit -cne [string]$Candidate.commit -or [string]$record.candidate.tree -cne [string]$Candidate.tree) { throw '[mir4-a08-qualification-record]' }
  Assert-MIR4A08Boolean $record.release_authority $false '[mir4-a08-qualification-record]'; Assert-MIR4A08Boolean $record.publication_authority $false '[mir4-a08-qualification-record]'
  $observed = @()
  foreach ($package in @($record.packages)) {
    Assert-MIR4A08PropertyNames $package @('target','relative_path','archive_sha256','content_sha256','bytes','entry_count') '[mir4-a08-qualification-record]'
    Assert-MIR4A08Sha ([string]$package.archive_sha256) '[mir4-a08-qualification-record]'; Assert-MIR4A08Sha ([string]$package.content_sha256) '[mir4-a08-qualification-record]'
    $path = Resolve-MIR4A08ContainedFile -Root $PackageRoot -RelativePath ([string]$package.relative_path) -Code '[mir4-a08-qualification-record]'
    $actual = Get-MIR4A08PackageObservation -PackagePath $path -Target ([string]$package.target) -RelativePath ([string]$package.relative_path)
    foreach ($field in @('archive_sha256','content_sha256','bytes','entry_count')) {
      if ([string]$actual.$field -cne [string]$package.$field) { throw '[mir4-a08-qualified-package-mismatch]' }
    }
    $observed += $actual
  }
  $setSha = Get-MIR4A08PackageSetSha256 $observed
  return [pscustomobject][ordered]@{record_path=$recordFullPath;record_sha256=$TrustedRecordSha256;package_root=([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $PackageRoot).Path));candidate=[pscustomobject][ordered]@{ref=[string]$Candidate.ref;commit=[string]$Candidate.commit;tree=[string]$Candidate.tree};package_set_sha256=$setSha;packages=@($observed | Sort-Object target)}
}

function Get-MIR4A08SelfSha256 {
  param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)][string]$Property)
  $copy = [ordered]@{}
  foreach ($item in $Value.PSObject.Properties) { $copy[$item.Name] = if ($item.Name -ceq $Property) { '' } else { $item.Value } }
  return Get-MIR4A08Sha256 ([pscustomobject]$copy)
}

function Write-MIR4A08ImmutableJson {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Value,[Parameter(Mandatory)][string]$Code)
  $text = (Get-MIR4A08CanonicalJson $Value) + "`n"
  $directory = Split-Path -Parent $Path
  [IO.Directory]::CreateDirectory($directory) | Out-Null
  if (Test-Path -LiteralPath $Path) {
    if ((Get-Content -Raw -LiteralPath $Path) -cne $text) { throw $Code }
    return $Path
  }
  try {
    $stream = [IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $bytes = [Text.Encoding]::UTF8.GetBytes($text); $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
  } catch [IO.IOException] {
    if (-not (Test-Path -LiteralPath $Path) -or (Get-Content -Raw -LiteralPath $Path) -cne $text) { throw $Code }
  }
  return $Path
}

function Read-MIR4A08Intention {
  param([Parameter(Mandatory)][string]$Path)
  try { $value = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -Depth 100 -DateKind String } catch { throw '[mir4-a08-intention-invalid]' }
  Assert-MIR4A08PropertyNames $value @('schema','kind','plan','candidate','qualification','remote','intention_sha256') '[mir4-a08-intention-invalid]'
  if ([int]$value.schema -ne 1 -or [string]$value.kind -cne 'MIR42ProtectedMainPromotionIntentionV1' -or [string]$value.intention_sha256 -cnotmatch '^[A-F0-9]{64}$' -or [string]$value.intention_sha256 -cne (Get-MIR4A08SelfSha256 $value 'intention_sha256')) { throw '[mir4-a08-intention-invalid]' }
  $null = Assert-MIR4A08Plan $value.plan
  Assert-MIR4A08PropertyNames $value.candidate @('schema','kind','ref','commit','tree','parent_commit','source_commit','plan_sha256','candidate_message_sha256') '[mir4-a08-intention-invalid]'
  Assert-MIR4A08PropertyNames $value.qualification @('record_path','record_sha256','package_root','candidate','package_set_sha256','packages') '[mir4-a08-intention-invalid]'
  Assert-MIR4A08PropertyNames $value.remote @('url','main_ref','source_ref','candidate_ref') '[mir4-a08-intention-invalid]'
  if ([int]$value.candidate.schema -ne 1 -or [string]$value.candidate.kind -cne 'MIR42ProtectedMainCandidateV1' -or [string]$value.candidate.ref -cne [string]$value.plan.candidate.ref -or [string]$value.candidate.commit -cnotmatch '^[0-9a-f]{40}$' -or
      [string]$value.candidate.tree -cne [string]$value.plan.source.tree -or [string]$value.candidate.parent_commit -cne [string]$value.plan.main_before.commit -or
      [string]$value.candidate.source_commit -cne [string]$value.plan.source.commit -or [string]$value.candidate.plan_sha256 -cne [string]$value.plan.plan_sha256 -or
      [string]$value.remote.candidate_ref -cne [string]$value.candidate.ref -or [string]$value.remote.main_ref -cnotmatch '^refs/heads/' -or [string]$value.remote.source_ref -cnotmatch '^refs/heads/' -or
      [string]$value.remote.url -eq '') { throw '[mir4-a08-intention-invalid]' }
  Assert-MIR4A08Sha ([string]$value.qualification.record_sha256) '[mir4-a08-intention-invalid]'; Assert-MIR4A08Sha ([string]$value.qualification.package_set_sha256) '[mir4-a08-intention-invalid]'
  return $value
}

function New-MIR4A08PromotionIntention {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Plan,[Parameter(Mandatory)]$Candidate,
    [Parameter(Mandatory)][string]$QualificationRecordPath,[Parameter(Mandatory)][string]$TrustedQualificationRecordSha256,[Parameter(Mandatory)][string]$PackageRoot,
    [Parameter(Mandatory)][string]$Remote,[Parameter(Mandatory)][string]$RemoteMainRef,[Parameter(Mandatory)][string]$RemoteSourceRef,[Parameter(Mandatory)][string]$StateRoot
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path; $null = Assert-MIR4A08Plan $Plan
  $localCandidate = Assert-MIR4A08CandidateAgainstPlan -RepoRoot $repo -Plan $Plan -CandidateRef ([string]$Candidate.ref) -CandidateCommit ([string]$Candidate.commit)
  if ([string]$Candidate.tree -cne [string]$localCandidate.tree -or [string]$Candidate.parent_commit -cne [string]$localCandidate.parent_commit) { throw '[mir4-a08-candidate-caller-forged]' }
  if ((Get-MIR4A08RemoteRef -RepoRoot $repo -Remote $Remote -Ref $RemoteMainRef) -cne [string]$Plan.main_before.commit) { throw '[mir4-a08-remote-main-ref-drift]' }
  if ((Get-MIR4A08RemoteRef -RepoRoot $repo -Remote $Remote -Ref $RemoteSourceRef) -cne [string]$Plan.source.commit) { throw '[mir4-a08-remote-source-ref-drift]' }
  $qualification = Read-MIR4A08QualificationRecord -Plan $Plan -Candidate $localCandidate -RecordPath $QualificationRecordPath -PackageRoot $PackageRoot -TrustedRecordSha256 $TrustedQualificationRecordSha256
  $intention = [pscustomobject][ordered]@{
    schema=1;kind='MIR42ProtectedMainPromotionIntentionV1';plan=$Plan;candidate=$localCandidate;qualification=$qualification
    remote=[pscustomobject][ordered]@{url=$Remote;main_ref=$RemoteMainRef;source_ref=$RemoteSourceRef;candidate_ref=[string]$localCandidate.ref}
    intention_sha256=''
  }
  $intention.intention_sha256 = Get-MIR4A08SelfSha256 $intention 'intention_sha256'
  $path = Join-Path ([IO.Path]::GetFullPath($StateRoot)) ("$($intention.intention_sha256.ToLowerInvariant()).promotion-intention.json")
  $null = Write-MIR4A08ImmutableJson -Path $path -Value $intention -Code '[mir4-a08-intention-conflict]'
  return [pscustomobject][ordered]@{path=$path;intention_sha256=$intention.intention_sha256;candidate_commit=$localCandidate.commit;package_set_sha256=$qualification.package_set_sha256;remote_push_performed=$false;main_mutation_performed=$false;tag_created=$false;publication_authorized=$false}
}

function Invoke-MIR4A08CreateOnlyCandidatePush {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$IntentionPath,[Parameter(Mandatory)][string]$StateRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path; $intention = Read-MIR4A08Intention -Path $IntentionPath
  $candidate = Assert-MIR4A08CandidateAgainstPlan -RepoRoot $repo -Plan $intention.plan -CandidateRef ([string]$intention.candidate.ref) -CandidateCommit ([string]$intention.candidate.commit)
  if ((Get-MIR4A08RemoteRef -RepoRoot $repo -Remote ([string]$intention.remote.url) -Ref ([string]$intention.remote.main_ref)) -cne [string]$intention.plan.main_before.commit) { throw '[mir4-a08-remote-main-ref-drift]' }
  if ((Get-MIR4A08RemoteRef -RepoRoot $repo -Remote ([string]$intention.remote.url) -Ref ([string]$intention.remote.source_ref)) -cne [string]$intention.plan.source.commit) { throw '[mir4-a08-remote-source-ref-drift]' }
  $remoteCandidate = Get-MIR4A08RemoteRef -RepoRoot $repo -Remote ([string]$intention.remote.url) -Ref ([string]$intention.remote.candidate_ref)
  $created = $false
  if ($null -eq $remoteCandidate) {
    $pushOutput = @(& git -C $repo push --porcelain "--force-with-lease=$($intention.remote.candidate_ref):" $intention.remote.url "$($intention.candidate.ref):$($intention.remote.candidate_ref)" 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "[mir4-a08-create-only-push] $($pushOutput -join ' ')" }
    $created = $true
  } elseif ($remoteCandidate -cne [string]$candidate.commit) { throw '[mir4-a08-remote-candidate-conflict]' }
  $remoteAfter = Get-MIR4A08RemoteRef -RepoRoot $repo -Remote ([string]$intention.remote.url) -Ref ([string]$intention.remote.candidate_ref)
  if ($remoteAfter -cne [string]$candidate.commit) { throw '[mir4-a08-remote-candidate-readback]' }
  $receipt = [pscustomobject][ordered]@{schema=1;kind='MIR42ProtectedMainCandidatePushReceiptV1';intention_sha256=[string]$intention.intention_sha256;candidate_ref=[string]$candidate.ref;candidate_commit=[string]$candidate.commit;remote_candidate_ref=[string]$intention.remote.candidate_ref;remote_candidate_commit=$remoteAfter;create_only_verified=$true;main_mutation_performed=$false;tag_created=$false;publication_performed=$false}
  $path = Join-Path ([IO.Path]::GetFullPath($StateRoot)) ("$($intention.intention_sha256.ToLowerInvariant()).candidate-push-receipt.json")
  $null = Write-MIR4A08ImmutableJson -Path $path -Value $receipt -Code '[mir4-a08-candidate-push-receipt-conflict]'
  return [pscustomobject][ordered]@{path=$path;created=$created;candidate_commit=$candidate.commit;remote_candidate_commit=$remoteAfter;main_mutation_performed=$false;tag_created=$false;publication_authorized=$false}
}

function Get-MIR4A08PromotionMessage {
  param([Parameter(Mandatory)]$Intention)
  return "MIR 4.2 protected promotion`n`nMIR-Candidate-Commit: $($Intention.candidate.commit)`nMIR-Candidate-Tree: $($Intention.candidate.tree)`nMIR-Source-Commit: $($Intention.plan.source.commit)`nMIR-Source-Tree: $($Intention.plan.source.tree)`nMIR-Main-Base: $($Intention.plan.main_before.commit)`nMIR-Qualification-Record-SHA256: $($Intention.qualification.record_sha256)`nMIR-Qualification-Package-Set-SHA256: $($Intention.qualification.package_set_sha256)`nMIR-Promotion-Intention-SHA256: $($Intention.intention_sha256)"
}

function New-MIR4A08ProtectedPromotionRequest {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$IntentionPath,[Parameter(Mandatory)][string]$StateRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path; $intention = Read-MIR4A08Intention -Path $IntentionPath
  $remoteCandidate = Get-MIR4A08RemoteRef -RepoRoot $repo -Remote ([string]$intention.remote.url) -Ref ([string]$intention.remote.candidate_ref)
  if ($remoteCandidate -cne [string]$intention.candidate.commit) { throw '[mir4-a08-remote-candidate-readback]' }
  if ((Get-MIR4A08RemoteRef -RepoRoot $repo -Remote ([string]$intention.remote.url) -Ref ([string]$intention.remote.main_ref)) -cne [string]$intention.plan.main_before.commit) { throw '[mir4-a08-remote-main-ref-drift]' }
  $request = [pscustomobject][ordered]@{
    schema=1;kind='MIR42ProtectedMainPromotionRequestV1';intention_sha256=[string]$intention.intention_sha256
    remote=[pscustomobject][ordered]@{url=[string]$intention.remote.url;candidate_ref=[string]$intention.remote.candidate_ref;candidate_commit=[string]$intention.candidate.commit;main_ref=[string]$intention.remote.main_ref;main_before=[string]$intention.plan.main_before.commit}
    protected_pull_request=[pscustomobject][ordered]@{required=$true;merge_method='squash';required_status_checks=@($intention.plan.promotion.required_status_checks);expected_commit_message=(Get-MIR4A08PromotionMessage $intention);external_execution_required=$true}
    main_mutation_performed=$false;tag_created=$false;publication_performed=$false;request_sha256=''
  }
  $request.request_sha256 = Get-MIR4A08SelfSha256 $request 'request_sha256'
  $path = Join-Path ([IO.Path]::GetFullPath($StateRoot)) ("$($intention.intention_sha256.ToLowerInvariant()).protected-pr-request.json")
  $null = Write-MIR4A08ImmutableJson -Path $path -Value $request -Code '[mir4-a08-pr-request-conflict]'
  return [pscustomobject][ordered]@{path=$path;request_sha256=$request.request_sha256;candidate_commit=$intention.candidate.commit;protected_pr_required=$true;main_mutation_performed=$false;tag_created=$false;publication_authorized=$false}
}

function Read-MIR4A08PromotionRequest {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Intention)
  try { $request = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -Depth 100 -DateKind String } catch { throw '[mir4-a08-pr-request-invalid]' }
  Assert-MIR4A08PropertyNames $request @('schema','kind','intention_sha256','remote','protected_pull_request','main_mutation_performed','tag_created','publication_performed','request_sha256') '[mir4-a08-pr-request-invalid]'
  Assert-MIR4A08PropertyNames $request.remote @('url','candidate_ref','candidate_commit','main_ref','main_before') '[mir4-a08-pr-request-invalid]'
  Assert-MIR4A08PropertyNames $request.protected_pull_request @('required','merge_method','required_status_checks','expected_commit_message','external_execution_required') '[mir4-a08-pr-request-invalid]'
  if ([int]$request.schema -ne 1 -or [string]$request.kind -cne 'MIR42ProtectedMainPromotionRequestV1' -or [string]$request.intention_sha256 -cne [string]$Intention.intention_sha256 -or
      [string]$request.request_sha256 -cnotmatch '^[A-F0-9]{64}$' -or [string]$request.request_sha256 -cne (Get-MIR4A08SelfSha256 $request 'request_sha256') -or
      [string]$request.remote.url -cne [string]$Intention.remote.url -or [string]$request.remote.candidate_ref -cne [string]$Intention.remote.candidate_ref -or
      [string]$request.remote.candidate_commit -cne [string]$Intention.candidate.commit -or [string]$request.remote.main_ref -cne [string]$Intention.remote.main_ref -or [string]$request.remote.main_before -cne [string]$Intention.plan.main_before.commit -or
      [string]$request.protected_pull_request.merge_method -cne 'squash' -or [string]$request.protected_pull_request.expected_commit_message -cne (Get-MIR4A08PromotionMessage $Intention)) { throw '[mir4-a08-pr-request-invalid]' }
  Assert-MIR4A08Boolean $request.protected_pull_request.required $true '[mir4-a08-pr-request-invalid]'; Assert-MIR4A08Boolean $request.protected_pull_request.external_execution_required $true '[mir4-a08-pr-request-invalid]'
  Assert-MIR4A08Boolean $request.main_mutation_performed $false '[mir4-a08-pr-request-invalid]'; Assert-MIR4A08Boolean $request.tag_created $false '[mir4-a08-pr-request-invalid]'; Assert-MIR4A08Boolean $request.publication_performed $false '[mir4-a08-pr-request-invalid]'
  if (@($request.protected_pull_request.required_status_checks | Sort-Object -Unique).Count -ne 2 -or @($request.protected_pull_request.required_status_checks | Where-Object { $_ -notin @('branch-policy','verification-gate') }).Count -ne 0) { throw '[mir4-a08-pr-request-invalid]' }
  return $request
}

function Test-MIR4ProtectedPromotionReadback {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$IntentionPath,[Parameter(Mandatory)][string]$PromotionRequestPath,[Parameter(Mandatory)][string]$StateRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path; $intention = Read-MIR4A08Intention -Path $IntentionPath; $request = Read-MIR4A08PromotionRequest -Path $PromotionRequestPath -Intention $intention
  $candidateRemote = Get-MIR4A08RemoteRef -RepoRoot $repo -Remote ([string]$intention.remote.url) -Ref ([string]$intention.remote.candidate_ref)
  if ($candidateRemote -cne [string]$intention.candidate.commit) { throw '[mir4-a08-remote-candidate-readback]' }
  if ((Get-MIR4A08RemoteRef -RepoRoot $repo -Remote ([string]$intention.remote.url) -Ref ([string]$intention.remote.source_ref)) -cne [string]$intention.plan.source.commit) { throw '[mir4-a08-remote-source-ref-drift-after-promotion]' }
  $mainRemote = Get-MIR4A08RemoteRef -RepoRoot $repo -Remote ([string]$intention.remote.url) -Ref ([string]$intention.remote.main_ref)
  if ($null -eq $mainRemote -or $mainRemote -ceq [string]$intention.plan.main_before.commit) { throw '[mir4-a08-readback-no-promotion]' }
  $null = Invoke-MIR4A08Git -RepoRoot $repo -Arguments @('fetch','--no-tags',[string]$intention.remote.url,[string]$intention.remote.main_ref)
  $mainAfter = Resolve-MIR4A08Commit -RepoRoot $repo -Revision 'FETCH_HEAD'
  if ($mainAfter -cne $mainRemote) { throw '[mir4-a08-remote-main-fetch-mismatch]' }
  $tree = Resolve-MIR4A08Tree -RepoRoot $repo -Commit $mainAfter
  $parents = @(((Invoke-MIR4A08Git -RepoRoot $repo -Arguments @('show','-s','--format=%P',$mainAfter)) -join '').Trim() -split '\s+' | Where-Object { $_ })
  $message = ((Invoke-MIR4A08Git -RepoRoot $repo -Arguments @('show','-s','--format=%B',$mainAfter)) -join "`n").TrimEnd()
  if ($tree -cne [string]$intention.candidate.tree) { throw '[mir4-a08-readback-tree-mismatch]' }
  if ($parents.Count -ne 1 -or $parents[0] -cne [string]$intention.plan.main_before.commit) { throw '[mir4-a08-readback-not-direct-main-child]' }
  if ($message -cne [string]$request.protected_pull_request.expected_commit_message) { throw '[mir4-a08-readback-message-mismatch]' }
  $candidate = Assert-MIR4A08CandidateAgainstPlan -RepoRoot $repo -Plan $intention.plan -CandidateRef ([string]$intention.candidate.ref) -CandidateCommit ([string]$intention.candidate.commit)
  $qualification = Read-MIR4A08QualificationRecord -Plan $intention.plan -Candidate $candidate -RecordPath ([string]$intention.qualification.record_path) -PackageRoot ([string]$intention.qualification.package_root) -TrustedRecordSha256 ([string]$intention.qualification.record_sha256)
  if ([string]$qualification.package_set_sha256 -cne [string]$intention.qualification.package_set_sha256) { throw '[mir4-a08-readback-package-mismatch]' }
  $receipt = [pscustomobject][ordered]@{schema=1;kind='MIR42ProtectedMainPromotionReadbackV2';status='qualified-tree-on-main-awaiting-maintainer-playtest';intention_sha256=[string]$intention.intention_sha256;request_sha256=[string]$request.request_sha256;main_before=[string]$intention.plan.main_before.commit;qualified_candidate_commit=[string]$candidate.commit;main_after=$mainAfter;tree=$tree;commit_rewritten=($mainAfter -cne [string]$candidate.commit);source_ref=[string]$intention.remote.source_ref;source_commit=[string]$intention.plan.source.commit;package_set_sha256=[string]$qualification.package_set_sha256;checks=@('fresh-remote-ref-readback','protected-pr-request','exact-direct-main-child','exact-qualified-tree','exact-package-bytes','source-ref-unchanged','commit-message-binding');ruleset_mutation_performed=$false;force_push_performed=$false;tag_created=$false;publication_performed=$false;publication_authorized=$false}
  $path = Join-Path ([IO.Path]::GetFullPath($StateRoot)) ("$($intention.intention_sha256.ToLowerInvariant()).commit-rebinding-receipt.json")
  $null = Write-MIR4A08ImmutableJson -Path $path -Value $receipt -Code '[mir4-a08-rebinding-receipt-conflict]'
  $receipt | Add-Member -NotePropertyName path -NotePropertyValue $path
  return $receipt
}
