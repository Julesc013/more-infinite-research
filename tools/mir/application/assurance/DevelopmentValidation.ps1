function ConvertTo-MIR4DevelopmentRelativePath {
  param([Parameter(Mandatory)][string]$Path)
  $value=$Path.Trim().Replace('\','/')
  if([string]::IsNullOrWhiteSpace($value) -or [IO.Path]::IsPathRooted($value) -or $value.StartsWith('../') -or $value.Contains('/../')) { throw '[mir4-development-path]' }
  return $value
}

function Test-MIR4DevelopmentCatalogInputMatch {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$CatalogInput)
  $pattern=$CatalogInput.Trim().Replace('\','/')
  if($pattern.StartsWith('source:')) { $pattern=$pattern.Substring(7) }
  # Symbolic inputs are covered by their assurance class, not filename matching.
  if([string]::IsNullOrWhiteSpace($pattern) -or $pattern -notmatch '/') { return $false }
  $escaped=[regex]::Escape($pattern).Replace('\*\*','.*').Replace('\*','[^/]*')
  return $Path -match ('^'+$escaped+'$')
}

function Assert-MIR4DevelopmentHostedCheckoutClean {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $entries=@(& git -C $repo status --porcelain=v1 --untracked-files=all --)
  if($LASTEXITCODE -ne 0) { throw '[mir4-development-hosted-status]' }
  if($entries.Count -ne 0) { throw '[mir4-development-hosted-dirty-checkout]' }
}

function Get-MIR4DevelopmentSelectorInputHashes {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $inputs=[ordered]@{
    assurance_policy_sha256=(Get-FileHash -LiteralPath (Join-Path $repo '.mir/assurance.json') -Algorithm SHA256).Hash.ToUpperInvariant()
    test_catalog_sha256=(Get-FileHash -LiteralPath (Join-Path $repo 'validation/tests.yml') -Algorithm SHA256).Hash.ToUpperInvariant()
    development_epoch_sha256=(Get-FileHash -LiteralPath (Join-Path $repo 'governance/repository/development-epoch-v1.json') -Algorithm SHA256).Hash.ToUpperInvariant()
    selector_sha256=(Get-FileHash -LiteralPath (Join-Path $repo 'tools/mir/application/assurance/DevelopmentValidation.ps1') -Algorithm SHA256).Hash.ToUpperInvariant()
    classifier_sha256=(Get-FileHash -LiteralPath (Join-Path $repo 'tools/lib/assurance/Core.ps1') -Algorithm SHA256).Hash.ToUpperInvariant()
    package_authority_sha256=(Get-FileHash -LiteralPath (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1') -Algorithm SHA256).Hash.ToUpperInvariant()
  }
  foreach($hash in $inputs.Values) { if([string]$hash -cnotmatch '^[A-F0-9]{64}$') { throw '[mir4-development-selector-input-hash]' } }
  return $inputs
}

function Get-MIR4DevelopmentStaticProfileRows {
  param([Parameter(Mandatory)]$Catalog,[Parameter(Mandatory)]$Assurance,[Parameter(Mandatory)][string]$Profile)
  $property=$Assurance.profiles.PSObject.Properties[$Profile]
  if($null -eq $property) { throw "[mir4-development-profile-missing] $Profile" }
  $rows=@()
  foreach($idValue in @($property.Value)) {
    $id=[string]$idValue;$matches=@($Catalog.tests|Where-Object {[string]$_.id -ceq $id})
    if($matches.Count -ne 1 -or [bool]$matches[0].requires_factorio -or [string]$matches[0].kind -cne 'static') { throw "[mir4-development-static-selection] $id" }
    $rows += $matches[0]
  }
  return @($rows)
}

function Select-MIR4DevelopmentAffectedStaticRows {
  param(
    [Parameter(Mandatory)]$Classification,
    [Parameter(Mandatory)]$Catalog,[Parameter(Mandatory)]$Assurance,[Parameter(Mandatory)][string]$Profile
  )
  $profileRows=@(Get-MIR4DevelopmentStaticProfileRows -Catalog $Catalog -Assurance $Assurance -Profile $Profile)
  if([bool]$Classification.escalated) { return @($profileRows|Sort-Object {[string]$_.id}) }
  $selected=@{}
  foreach($id in @($Classification.tests)) { $selected[[string]$id]=$true }
  foreach($row in $profileRows) {
    foreach($input in @($row.inputs)) {
      foreach($path in @($Classification.paths)) {
        if(Test-MIR4DevelopmentCatalogInputMatch -Path $path -CatalogInput ([string]$input)) { $selected[[string]$row.id]=$true;break }
      }
    }
  }
  $rows=@($profileRows|Where-Object {$selected.ContainsKey([string]$_.id)}|Sort-Object {[string]$_.id})
  # Never make an incompletely mapped but known change a zero-test green.
  if($rows.Count -eq 0) { return @($profileRows|Sort-Object {[string]$_.id}) }
  return $rows
}

function Get-MIR4DevelopmentSelectionIdentity {
  param(
    [Parameter(Mandatory)][string]$Mode,[Parameter(Mandatory)][string]$EventName,[Parameter(Mandatory)][string]$Baseline,
    [Parameter(Mandatory)][string]$SourceCommit,[Parameter(Mandatory)][string]$SourceTree,[Parameter(Mandatory)][string]$PackageSourceSha256,
    [Parameter(Mandatory)]$InputHashes,[Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Paths,[Parameter(Mandatory)][AllowEmptyCollection()][string[]]$TestIds
  )
  $material=[ordered]@{schema=1;mode=$Mode;event_name=$EventName;baseline=$Baseline;source_commit=$SourceCommit;source_tree=$SourceTree;package_source_sha256=$PackageSourceSha256;input_hashes=$InputHashes;paths=@($Paths|Sort-Object -Unique);test_ids=@($TestIds|Sort-Object -Unique)}
  return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes(($material|ConvertTo-Json -Depth 8 -Compress))))
}

function Get-MIR4DevelopmentCISelection {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][ValidateSet('hosted-development-affected','local-current-profile')][string]$Mode,
    [string]$EventName='local',[string]$Baseline='',[string]$ExpectedHead=''
  )
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $epoch=Get-Content -Raw (Join-Path $repo 'governance/repository/development-epoch-v1.json')|ConvertFrom-Json
  if($epoch.schema -ne 1 -or $epoch.current_profile -cne 'mir4-development' -or $epoch.release_authority) { throw '[mir4-development-profile-authority]' }
  $catalog=Get-Content -Raw (Join-Path $repo 'validation/tests.yml')|ConvertFrom-Json
  $assurance=Get-Content -Raw (Join-Path $repo '.mir/assurance.json')|ConvertFrom-Json
  # Assurance owns path classification and unknown-path escalation.  This
  # selector only intersects that result with the hosted development profile.
  . (Join-Path $repo 'tools/lib/assurance/Core.ps1')
  $sourceCommit=(@(& git -C $repo rev-parse HEAD)-join '').Trim().ToLowerInvariant();$sourceTree=(@(& git -C $repo rev-parse 'HEAD^{tree}')-join '').Trim().ToLowerInvariant()
  if($LASTEXITCODE -ne 0 -or $sourceCommit -cnotmatch '^[0-9a-f]{40}$' -or $sourceTree -cnotmatch '^[0-9a-f]{40}$') { throw '[mir4-development-static-source-identity]' }
  if(-not [string]::IsNullOrWhiteSpace($ExpectedHead) -and $sourceCommit -cne $ExpectedHead.Trim().ToLowerInvariant()) { throw '[mir4-development-head-identity]' }
  if($Mode -eq 'hosted-development-affected') { Assert-MIR4DevelopmentHostedCheckoutClean -RepoRoot $repo }
  . (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
  $packageSourceSha256=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
  if($packageSourceSha256 -cnotmatch '^[A-F0-9]{64}$') { throw '[mir4-development-static-package-source-identity]' }
  $inputHashes=Get-MIR4DevelopmentSelectorInputHashes -RepoRoot $repo
  $baselineValue=$Baseline.Trim().ToLowerInvariant();$baselineState='resolved';$classification=$null;$rows=@()
  if($Mode -eq 'hosted-development-affected') {
    if([string]::IsNullOrWhiteSpace($baselineValue)) {
      $baselineState='unavailable';$classification=[ordered]@{paths=@();classes=@('unknown');tests=@();unknown_paths=@('baseline-unavailable');escalated=$true}
      $rows=@(Select-MIR4DevelopmentAffectedStaticRows -Classification $classification -Catalog $catalog -Assurance $assurance -Profile $epoch.current_profile)
    } else {
      if($baselineValue -cnotmatch '^[0-9a-f]{40}$') { throw '[mir4-development-baseline-shape]' }
      & git -C $repo cat-file -e ($baselineValue+'^{commit}');if($LASTEXITCODE -ne 0) { throw '[mir4-development-baseline-unavailable]' }
      $paths=@(& git -C $repo diff --name-only ($baselineValue+'...'+$sourceCommit) --|ForEach-Object {ConvertTo-MIR4DevelopmentRelativePath -Path ([string]$_)}|Sort-Object -Unique)
      if($LASTEXITCODE -ne 0) { throw '[mir4-development-baseline-diff]' }
      $classification=Get-MIRAssuranceClassification -Paths $paths -Config $assurance
      $rows=@(Select-MIR4DevelopmentAffectedStaticRows -Classification $classification -Catalog $catalog -Assurance $assurance -Profile $epoch.current_profile)
    }
  } else {
    $baselineState='local-profile';$classification=[ordered]@{paths=@();classes=@();tests=@();unknown_paths=@();escalated=$false}
    $rows=@(Get-MIR4DevelopmentStaticProfileRows -Catalog $catalog -Assurance $assurance -Profile $epoch.current_profile)
  }
  $testIds=@($rows|ForEach-Object {[string]$_.id}|Sort-Object -Unique);if($testIds.Count -eq 0) { throw '[mir4-development-empty-static-selection]' }
  $identity=Get-MIR4DevelopmentSelectionIdentity -Mode $Mode -EventName $EventName -Baseline $(if($baselineState -eq 'resolved'){$baselineValue}else{$baselineState}) -SourceCommit $sourceCommit -SourceTree $sourceTree -PackageSourceSha256 $packageSourceSha256 -InputHashes $inputHashes -Paths @($classification.paths) -TestIds $testIds
  return [ordered]@{schema=1;kind='MIR4DevelopmentCISelectionV1';mode=$Mode;event_name=$EventName;baseline=$baselineValue;baseline_state=$baselineState;source_commit=$sourceCommit;source_tree=$sourceTree;package_source_sha256=$packageSourceSha256;input_hashes=$inputHashes;classification=$classification;tests=$testIds;selection_identity=$identity;evaluator='MIR4-development-static-selector-v1';trust_scope=$(if($Mode -eq 'hosted-development-affected'){'hosted-development-authoring'}else{'local-development-authoring'});release_qualification=$false;release_readiness_gate=$false;reuse_allowed=$false}
}

function Invoke-MIR4DevelopmentStaticChecks {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [ValidateSet('hosted-development-affected','local-current-profile')][string]$Mode='local-current-profile',
    [string]$EventName='local',[string]$Baseline='',[string]$ExpectedHead='',[string]$OutputPath=''
  )
  $selection=Get-MIR4DevelopmentCISelection -RepoRoot $RepoRoot -Mode $Mode -EventName $EventName -Baseline $Baseline -ExpectedHead $ExpectedHead
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path;$catalog=Get-Content -Raw (Join-Path $repo 'validation/tests.yml')|ConvertFrom-Json;$outcomes=@()
  foreach($id in @($selection.tests)) {
    $row=@($catalog.tests|Where-Object {[string]$_.id -ceq $id})
    if($row.Count -ne 1 -or [bool]$row[0].requires_factorio -or [string]$row[0].kind -cne 'static') { throw "[mir4-development-static-selection] $id" }
    $parts=([string]$row[0].command).Split(' ',[StringSplitOptions]::RemoveEmptyEntries)
    if($parts[0] -notmatch '^\./(?:tests|scripts)/[A-Za-z0-9/.-]+[.]ps1$') { throw "[mir4-development-static-command] $id" }
    $testOutput='';if('<test-output>' -in $parts) { $testOutput=Join-Path $repo "build/results/assurance/evidence/$id/$($selection.selection_identity)/work/$([guid]::NewGuid().ToString('N'))/test-output.json" }
    $replacements=@{'<source-commit>'=[string]$selection.source_commit;'<source-tree>'=[string]$selection.source_tree;'<package-source-sha256>'=[string]$selection.package_source_sha256;'<test-output>'=$testOutput}
    for($index=1;$index-lt$parts.Count;$index++) {
      if($replacements.ContainsKey([string]$parts[$index])) { $replacement=[string]$replacements[[string]$parts[$index]];if([string]::IsNullOrWhiteSpace($replacement)) { throw "[mir4-development-static-placeholder] $id/$($parts[$index])" };$parts[$index]=$replacement }
      elseif([string]$parts[$index] -match '<[^>]+>') { throw "[mir4-development-static-unresolved-placeholder] $id/$($parts[$index])" }
    }
    $parts[0]=Join-Path $repo $parts[0];Write-Host "[current-development] $id selection=$($selection.selection_identity)";& pwsh -NoProfile -File @parts
    if($LASTEXITCODE -ne 0) { throw "[mir4-development-static-failed] $id" };$outcomes += [ordered]@{id=$id;status='passed';test_output=$testOutput}
  }
  & git -C $repo diff --check;if($LASTEXITCODE -ne 0) { throw '[mir4-development-whitespace]' }
  $result=[ordered]@{};foreach($property in $selection.GetEnumerator()){$result[$property.Key]=$property.Value};$result['status']='passed';$result['outcomes']=$outcomes
  if(-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $path=[IO.Path]::GetFullPath((Join-Path $repo $OutputPath));if(-not $path.StartsWith((Join-Path $repo 'build')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw '[mir4-development-output-path]' }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path)|Out-Null;[IO.File]::WriteAllText($path,(($result|ConvertTo-Json -Depth 20)+"`n"),[Text.UTF8Encoding]::new($false))
  }
  return [pscustomobject]$result
}
