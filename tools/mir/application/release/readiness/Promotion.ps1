Set-StrictMode -Version Latest

function Invoke-MIR441CaptureCommand {
  param([Parameter(Mandatory)][string]$File,[Parameter(Mandatory)][string[]]$Arguments)
  $output=@(& $File @Arguments 2>&1);$code=$LASTEXITCODE
  if($code-ne0){throw "[mir441-command-failed] $File $($Arguments-join' ') :: $($output-join' ')"}
  return @($output|ForEach-Object{[string]$_})
}

function Get-MIR441RemoteBranchOid {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Branch)
  $lines=Invoke-MIR441CaptureCommand -File 'git' -Arguments @('-C',$RepoRoot,'ls-remote','--heads','origin',"refs/heads/$Branch")
  if($lines.Count-ne1-or$lines[0]-notmatch'^([a-f0-9]{40})\s+'){throw "[mir441-remote-ref] $Branch"}
  return [string]$Matches[1]
}

function ConvertTo-MIR441RulesetPayload {
  param([Parameter(Mandatory)]$Ruleset,[switch]$WithoutPullRequest)
  $rules=@($Ruleset.rules)
  if($WithoutPullRequest){$rules=@($rules|Where-Object{[string]$_.type-cne'pull_request'})}
  return [ordered]@{name=[string]$Ruleset.name;target=[string]$Ruleset.target;enforcement=[string]$Ruleset.enforcement;bypass_actors=@($Ruleset.bypass_actors);conditions=$Ruleset.conditions;rules=$rules}
}

function Test-MIR441RulesetAppliesToMain {
  param([Parameter(Mandatory)]$Ruleset)
  if([string]$Ruleset.target-cne'branch'-or[string]$Ruleset.enforcement-ceq'disabled'-or@($Ruleset.rules|Where-Object type -eq 'pull_request').Count-eq0){return $false}
  $include=@($Ruleset.conditions.ref_name.include);$exclude=@($Ruleset.conditions.ref_name.exclude)
  $included=(@('~ALL','~DEFAULT_BRANCH','refs/heads/main')|Where-Object{$_-in$include}).Count-gt0
  $excluded=(@('~ALL','~DEFAULT_BRANCH','refs/heads/main')|Where-Object{$_-in$exclude}).Count-gt0
  return $included-and-not$excluded
}

function Invoke-MIR441RulesetUpdate {
  param([Parameter(Mandatory)][string]$Repository,[Parameter(Mandatory)][int64]$Id,[Parameter(Mandatory)]$Payload,[Parameter(Mandatory)][string]$Path)
  Write-MIR441Json -Value $Payload -Path $Path
  Invoke-MIR441CaptureCommand -File 'gh' -Arguments @('api','--method','PUT',"repos/$Repository/rulesets/$Id",'--input',$Path)|Out-Null
}

function Invoke-MIR441ExactMainPromotion {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$EvidenceRoot,[switch]$Plan)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path;$evidence=Assert-MIR441ExternalRoot -RepoRoot $repo -Path $EvidenceRoot -Name EvidenceRoot;$window=Join-Path $evidence 'release-window'
  if(@(& git -C $repo status --porcelain).Count-ne0){throw '[mir441-promotion-working-tree-dirty]'}
  $seal=Get-Content -Raw -LiteralPath (Join-Path $window 'technical-seal.json')|ConvertFrom-Json -Depth 100 -DateKind String
  $prepared=Get-Content -Raw -LiteralPath (Join-Path $window 'prepared-tag.json')|ConvertFrom-Json -Depth 50 -DateKind String
  $source=[string]$seal.source.commit;$tag=[string]$seal.release.tag
  if([string]$seal.status-cne'MIR41-TECHNICALLY-SEALED-AWAITING-EXACT-MAIN-PROMOTION'-or[string]$prepared.source_commit-cne$source-or-not[bool]$prepared.signature_verified){throw '[mir441-promotion-seal-or-tag]'}
  Invoke-MIR441CaptureCommand -File 'git' -Arguments @('-C',$repo,'fetch','--prune','origin')|Out-Null
  $dev=Get-MIR441RemoteBranchOid -RepoRoot $repo -Branch dev;$main=Get-MIR441RemoteBranchOid -RepoRoot $repo -Branch main
  if($dev-cne$source){throw '[mir441-promotion-dev-drift]'}
  Invoke-MIR441CaptureCommand -File 'git' -Arguments @('-C',$repo,'merge-base','--is-ancestor',$main,$source)|Out-Null
  $remoteTag=@(Invoke-MIR441CaptureCommand -File 'git' -Arguments @('-C',$repo,'ls-remote','--tags','origin',"refs/tags/$tag"));if($remoteTag.Count-ne0){throw '[mir441-promotion-tag-present]'}
  $repository=((Invoke-MIR441CaptureCommand -File 'gh' -Arguments @('repo','view','--json','nameWithOwner','--jq','.nameWithOwner'))-join'').Trim()
  $list=((Invoke-MIR441CaptureCommand -File 'gh' -Arguments @('api',"repos/$repository/rulesets?includes_parents=true"))-join"`n")|ConvertFrom-Json -Depth 100
  $applicable=[Collections.Generic.List[object]]::new()
  foreach($summary in @($list)){
    $detail=((Invoke-MIR441CaptureCommand -File 'gh' -Arguments @('api',"repos/$repository/rulesets/$([int64]$summary.id)"))-join"`n")|ConvertFrom-Json -Depth 100
    if(Test-MIR441RulesetAppliesToMain -Ruleset $detail){$applicable.Add($detail)}
  }
  $planRecord=[pscustomobject][ordered]@{schema=1;kind='MIR441ExactMainPromotionPlanV1';status=$(if($Plan){'planned'}else{'authorized'});repository=$repository;source_commit=$source;main_before=$main;dev_before=$dev;fast_forward=$true;force_push=$false;pull_request_rules_to_suspend=@($applicable|ForEach-Object{[ordered]@{id=[int64]$_.id;name=[string]$_.name}});post_promotion_tests=$false}
  if($Plan){return $planRecord}
  $root=Join-Path $evidence 'promotion';if(-not(Test-Path -LiteralPath $root)){New-Item -ItemType Directory -Force -Path $root|Out-Null}
  $changed=[Collections.Generic.List[object]]::new();$pushSucceeded=$false
  try {
    foreach($ruleset in @($applicable)){
      $original=ConvertTo-MIR441RulesetPayload -Ruleset $ruleset;$modified=ConvertTo-MIR441RulesetPayload -Ruleset $ruleset -WithoutPullRequest
      $originalPath=Join-Path $root "ruleset-$([int64]$ruleset.id)-original.json";$modifiedPath=Join-Path $root "ruleset-$([int64]$ruleset.id)-promotion.json"
      Write-MIR441Json -Value $original -Path $originalPath;Invoke-MIR441RulesetUpdate -Repository $repository -Id ([int64]$ruleset.id) -Payload $modified -Path $modifiedPath
      $changed.Add([pscustomobject][ordered]@{id=[int64]$ruleset.id;name=[string]$ruleset.name;original=$original;original_path=$originalPath})
    }
    Invoke-MIR441CaptureCommand -File 'git' -Arguments @('-C',$repo,'push','origin',"${source}:refs/heads/main")|Out-Null;$pushSucceeded=$true
  } finally {
    $restoreEntries=@($changed);[array]::Reverse($restoreEntries)
    foreach($entry in $restoreEntries){
      $restorePath=Join-Path $root "ruleset-$([int64]$entry.id)-restore.json"
      try{Invoke-MIR441RulesetUpdate -Repository $repository -Id ([int64]$entry.id) -Payload $entry.original -Path $restorePath}catch{Write-Error "[mir441-promotion-ruleset-restore] $([int64]$entry.id): $($_.Exception.Message)"}
    }
  }
  if(-not$pushSucceeded){throw '[mir441-promotion-push-incomplete]'}
  $devAfter=Get-MIR441RemoteBranchOid -RepoRoot $repo -Branch dev;$mainAfter=Get-MIR441RemoteBranchOid -RepoRoot $repo -Branch main
  if($devAfter-cne$source-or$mainAfter-cne$source){throw '[mir441-promotion-readback]'}
  foreach($entry in @($changed)){
    $readback=((Invoke-MIR441CaptureCommand -File 'gh' -Arguments @('api',"repos/$repository/rulesets/$([int64]$entry.id)"))-join"`n")|ConvertFrom-Json -Depth 100
    $expected=(ConvertTo-MIR441CanonicalJson -Value $entry.original -Compress).Trim();$actual=(ConvertTo-MIR441CanonicalJson -Value (ConvertTo-MIR441RulesetPayload -Ruleset $readback) -Compress).Trim()
    if($actual-cne$expected){throw "[mir441-promotion-ruleset-readback] $([int64]$entry.id)"}
  }
  $receipt=[ordered]@{schema=1;kind='MIR441ExactMainPromotionV1';status='MIR41-SEALED-ON-MAIN-AWAITING-HUMAN-PLAYTEST';repository=$repository;source_commit=$source;source_tree=[string]$seal.source.tree;main_before=$main;main_after=$mainAfter;dev_after=$devAfter;fast_forward=$true;force_push=$false;rulesets_restored=$true;post_promotion_tests=$false;tag_remote_absent=$true;human_playtest='pending';publication_authorized=$false;promoted_at=[DateTimeOffset]::UtcNow.ToString('o')}
  Write-MIR441Json -Value $receipt -Path (Join-Path $window 'main-promotion.json')
  $finalCustody=[ordered]@{schema=1;kind='MIR441FinalReleaseWindowCustodyV1';status='sealed-on-main-awaiting-human-playtest';source=$seal.source;objects=@(Get-MIR441DirectoryIdentities -Root $window -Exclude @('final-custody-manifest.json'));human_playtest='pending';publication_authorized=$false};Write-MIR441Json -Value $finalCustody -Path (Join-Path $window 'final-custody-manifest.json')
  $capsule=New-MIR441DeterministicDirectoryArchive -SourceRoot $window -ArchivePath (Join-Path $evidence 'MIR4_4.1.0_RELEASE_WINDOW.zip')
  $ready=[ordered]@{schema=1;kind='MIR441FinalReadinessV1';status='READY-FOR-ONE-MINUTE-PLAYTEST-GATE';state='MIR41-SEALED-ON-MAIN-AWAITING-HUMAN-PLAYTEST';source=$seal.source;technical_seal=(Get-MIR441FileIdentity -Path (Join-Path $window 'technical-seal.json') -RelativePath 'release-window/technical-seal.json');promotion=(Get-MIR441FileIdentity -Path (Join-Path $window 'main-promotion.json') -RelativePath 'release-window/main-promotion.json');prepared_tag=(Get-MIR441FileIdentity -Path (Join-Path $window 'prepared-tag.json') -RelativePath 'release-window/prepared-tag.json');final_custody=(Get-MIR441FileIdentity -Path (Join-Path $window 'final-custody-manifest.json') -RelativePath 'release-window/final-custody-manifest.json');capsule=$capsule;automated_work_remaining=@();human_playtest='sole-pending-gate';tag_remote_absent=$true;publication_authorized=$false}
  Write-MIR441Json -Value $ready -Path (Join-Path $evidence 'READY-FOR-ONE-MINUTE-PLAYTEST-GATE.json')
  return [pscustomobject]$ready
}
