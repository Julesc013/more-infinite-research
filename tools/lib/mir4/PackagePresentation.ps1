function Get-MIR4CurrentPackagePresentationBaselineV1 {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $authorityPath = Join-Path $repo 'spec/distribution/mir4-package-presentation-baseline-v1.json'
  $schemaPath = Join-Path $repo 'spec/schemas/mir4-package-presentation-baseline-v1.schema.json'
  $authorityText = Get-Content -Raw -LiteralPath $authorityPath
  if (-not ($authorityText | Test-Json -SchemaFile $schemaPath)) {
    throw '[mir4-package-presentation-current-schema]'
  }

  $authority = $authorityText | ConvertFrom-Json -Depth 30
  if (
    [string]$authority.current.package_zip_content_sha256 -cne [string]$authority.current.package_source_sha256 -or
    (@($authority.current.package_visible_delta) -join '|') -cne 'README.md' -or
    -not [bool]$authority.invariants.player_executable_sources_unchanged -or
    -not [bool]$authority.invariants.one_emitter_preserved -or
    [bool]$authority.invariants.gameplay_difference_authorized -or
    [bool]$authority.invariants.source_freeze_authorized -or
    [bool]$authority.invariants.candidate_allocation_authorized -or
    [bool]$authority.invariants.signing_or_sealing_authorized -or
    [bool]$authority.invariants.promotion_authorized -or
    [bool]$authority.invariants.publication_authorized
  ) {
    throw '[mir4-package-presentation-current-boundary]'
  }
  return $authority
}

function Get-MIR4FrozenPackagePresentationV1SourceSha256 {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)

  return [string](Get-MIR4CurrentPackagePresentationBaselineV1 -RepoRoot $RepoRoot).current.package_source_sha256
}

function Assert-MIR4PackagePresentationV1 {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$PackageSourceSha256
  )
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $preT14='9EFA2BBF5D399CCB6CE78BC907C5051D48E2CDB3DE652BA423FAF95FCE67A24C'
  $t14='F9E3F19201B5D660B24883168BBC43B0F06760FA272E33F1380AB6967D42EB0E'
  $current = Get-MIR4CurrentPackagePresentationBaselineV1 -RepoRoot $repo
  $currentSha256 = [string]$current.current.package_source_sha256
  if($PackageSourceSha256-cne$preT14-and$PackageSourceSha256-cne$t14-and$PackageSourceSha256-cne$currentSha256){
    throw "[mir4-package-presentation-unknown] $PackageSourceSha256"
  }
  if($PackageSourceSha256-ceq$currentSha256){
    if([string]$current.predecessor.package_source_sha256-cne$t14){
      throw '[mir4-package-presentation-current-predecessor]'
    }
    return [pscustomobject][ordered]@{maturity='post-t14-readme-badge-presentation';package_source_sha256=$PackageSourceSha256;package_visible_delta=@('README.md');player_executable_sources_unchanged=$true;one_emitter_preserved=$true}
  }
  if($PackageSourceSha256-ceq$t14){
    & {
      param([string]$ScopedRepoRoot)
      . (Join-Path $ScopedRepoRoot 'tools/lib/mir4/PreFreezeRelease.ps1')
      Test-MIR4PreFreezeAuthorities -RepoRoot $ScopedRepoRoot|Out-Null
    } $repo
    $authorityText=Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Documentation-Continuity-T14V1.json')
    if(-not($authorityText|Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-documentation-continuity-t14-v1.schema.json'))){
      throw '[mir4-package-presentation-t14-schema]'
    }
    $authority=$authorityText|ConvertFrom-Json -Depth 100
    if((@($authority.package_visible_delta)-join'|')-cne'README.md'-or
      -not[bool]$authority.player_executable_sources_unchanged-or-not[bool]$authority.one_emitter_preserved-or
      [bool]$authority.source_freeze_authorized-or[bool]$authority.signing_or_sealing_authorized-or
      [bool]$authority.promotion_authorized-or[bool]$authority.publication_authorized){
      throw '[mir4-package-presentation-t14-boundary]'
    }
    return [pscustomobject][ordered]@{maturity='t14-readme-presentation';package_source_sha256=$PackageSourceSha256;package_visible_delta=@('README.md');player_executable_sources_unchanged=$true;one_emitter_preserved=$true}
  }
  return [pscustomobject][ordered]@{maturity='pre-t14';package_source_sha256=$PackageSourceSha256;package_visible_delta=@();player_executable_sources_unchanged=$true;one_emitter_preserved=$true}
}

function Get-MIR4CurrentPackagePresentationV2 {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  . (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1'); . (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
  $text=Get-Content -Raw (Join-Path $repo 'spec/distribution/mir4-current-package-presentation-v2.json')
  if(-not($text|Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-current-package-presentation-v2.schema.json'))){throw '[mir4-package-presentation-v2-schema]'}
  $v2=$text|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4CurrentPackagePresentationV2Record -Record $v2
  $v1Path=Join-Path $repo ([string]$v2.predecessor.path);$v1Text=Get-Content -Raw -LiteralPath $v1Path
  if(-not($v1Text|Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-package-presentation-baseline-v1.schema.json'))){throw '[mir4-package-presentation-v2-predecessor-schema]'}
  $v1=$v1Text|ConvertFrom-Json -Depth 100 -DateKind String
  if([string]$v1.kind-cne[string]$v2.predecessor.kind-or[string]$v2.predecessor.hash_mode-cne'canonical-text-v1'-or(Get-MIR4BootstrapTextSha256 $v1Path)-cne[string]$v2.predecessor.sha256){throw '[mir4-package-presentation-v2-predecessor-binding]'}
  $v1Invariants = [ordered]@{
    one_emitter_preserved = $true
    gameplay_difference_authorized = $false
    source_freeze_authorized = $false
    candidate_allocation_authorized = $false
    signing_or_sealing_authorized = $false
    promotion_authorized = $false
    publication_authorized = $false
  }
  foreach ($name in $v1Invariants.Keys) {
    if ([bool]$v1.invariants.PSObject.Properties[$name].Value -ne [bool]$v1Invariants[$name] -or
        [bool]$v2.authority_invariants.PSObject.Properties[$name].Value -ne [bool]$v1Invariants[$name]) {
      throw '[mir4-package-presentation-v2-predecessor-invariants]'
    }
  }
  $executableEquality = $v2.player_executable_source_equality
  $frozenV1CurrentRelation = $v2.frozen_v1_current_package_fingerprint_relation
  $documentationCutoverPath = Join-Path $repo 'releases/migrations/MIR4-M41-05B-Documentation-CutoverV1.json'
  $documentationCutover = Get-Content -Raw -LiteralPath $documentationCutoverPath | ConvertFrom-Json -Depth 100 -DateKind String
  if (
    [string]$executableEquality.scope -cne 'm41-05b-documentation-cutover-only' -or
    [string]$executableEquality.cutover_source_identity.commit -cne [string]$documentationCutover.base.commit -or
    [string]$executableEquality.cutover_source_identity.tree -cne [string]$documentationCutover.base.tree -or
    [string]$executableEquality.cutover_source_identity.package_source_sha256 -cne [string]$documentationCutover.package_source_sha256 -or
    -not [bool]$executableEquality.player_executable_sources_equal -or
    [string]$executableEquality.evidence.path -cne 'releases/migrations/MIR4-M41-05B-Documentation-CutoverV1.json' -or
    [string]$executableEquality.evidence.kind -cne 'MIR4M4105BDocumentationCutoverV1' -or
    [string]$executableEquality.evidence.hash_mode -cne 'record-self-hash' -or
    [string]$executableEquality.evidence.sha256 -cne '41DA3E5346D719AB36279EDA535ACD9E193E03F4C9DC64B7903B6594654B3C5B' -or
    [string]$executableEquality.evidence.invariant -cne 'invariants.player_executable_sources_unchanged' -or
    -not (Test-MIR4BootstrapRecordHash -Record $documentationCutover) -or
    [string](Get-MIR4BootstrapRecordSha256 -Record $documentationCutover) -cne [string]$executableEquality.evidence.sha256 -or
    -not [bool]$documentationCutover.invariants.player_executable_sources_unchanged -or
    [string]$frozenV1CurrentRelation.frozen_v1_package_source_sha256 -cne [string]$v1.current.package_source_sha256 -or
    [string]$frozenV1CurrentRelation.current_package_source_sha256 -cne [string]$v2.package_source.fingerprint_sha256 -or
    [bool]$frozenV1CurrentRelation.package_source_fingerprints_equal -or
    [bool]$frozenV1CurrentRelation.player_executable_sources_equality_claimed
  ) {
    throw '[mir4-package-presentation-v2-executable-source-equality]'
  }
  $a=Get-MIR4CanonicalPackageAuthority -RepoRoot $repo;$m=Get-Content -Raw (Join-Path $repo 'src/mod/package-source.json')|ConvertFrom-Json -Depth 100 -DateKind String;$liveFingerprint=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
  if([string]$a.record_sha256-cne[string]$v2.package_authority.record_sha256-or[string]$m.record_sha256-cne[string]$v2.source_manifest.record_sha256-or[string]$a.source_manifest.path-cne[string]$v2.source_manifest.path-or[string]$a.source_manifest.record_sha256-cne[string]$v2.source_manifest.record_sha256-or[string]$m.materializer_abi-cne'mir4-target-materializer/1'-or(@(Get-MIR4CanonicalPackageSourceRoots)-join'|')-cne'src/mod|targets'-or[string]$a.writer.implementation-cne'tools/mir/application/package/TargetMaterializer.ps1'-or[string]$a.legacy_root_projection.compatibility_state-cne'retired-historical-read-only'-or[string]$v2.package_source.fingerprint_sha256-cne$liveFingerprint){throw '[mir4-package-presentation-v2-binding]'}
  foreach($r in @($v2.receipts)){$path=Join-Path $repo $r.path;$actual=Get-Content -Raw $path|ConvertFrom-Json -Depth 100 -DateKind String;if([string]$r.hash_mode-ceq'record-self-hash'){if(-not(Test-MIR4BootstrapRecordHash $actual)){throw '[mir4-package-presentation-v2-receipt-self-hash]'};$hash=Get-MIR4BootstrapRecordSha256 $actual}else{$hash=Get-MIR4BootstrapTextSha256 $path};if([string]$actual.kind-cne[string]$r.kind-or[string]$actual.status-cne[string]$r.status-or$hash-cne[string]$r.sha256){throw '[mir4-package-presentation-v2-receipt]'}}
  if('README.md'-in@(Get-MIR4CanonicalPackageSourceFiles $repo)){throw '[mir4-package-presentation-v2-root-readme-source]'}
  foreach($target in @('f210','f200','f110','f100')){$rows=@($m.bindings|Where-Object{[string]$_.source_path-ceq"targets/$target/generation/README.md.template"-and[string]$_.output_path-ceq'README.md'-and[string]$_.semantic_class-ceq'package-documentation'-and[string]$_.transform-ceq'exact-template-v1'-and(@($_.target_scope)-join'|')-ceq$target});if($rows.Count-ne1){throw "[mir4-package-presentation-v2-readme-binding] $target"}}
  return $v2
}

function Assert-MIR4CurrentPackagePresentationV2Record {
  [CmdletBinding()] param([Parameter(Mandatory)]$Record)
  if(-not(Test-MIR4BootstrapRecordHash $Record)){throw '[mir4-package-presentation-v2-record-hash]'}
  $expectedInvariants = [ordered]@{
    one_emitter_preserved = $true
    gameplay_difference_authorized = $false
    source_freeze_authorized = $false
    candidate_allocation_authorized = $false
    signing_or_sealing_authorized = $false
    promotion_authorized = $false
    publication_authorized = $false
    player_package_mutation_authorized = $false
    prototype_write_authorized = $false
    public_support_authorized = $false
  }
  foreach ($name in $expectedInvariants.Keys) {
    if ([bool]$Record.authority_invariants.PSObject.Properties[$name].Value -ne [bool]$expectedInvariants[$name]) {
      throw "[mir4-package-presentation-v2-record-authority] $name"
    }
  }
  if ($Record.authority_invariants.PSObject.Properties['player_executable_sources_unchanged']) {
    throw '[mir4-package-presentation-v2-record-unscoped-executable-source-assertion]'
  }
  if (
    [string]$Record.player_executable_source_equality.scope -cne 'm41-05b-documentation-cutover-only' -or
    [string]$Record.player_executable_source_equality.cutover_source_identity.commit -cne 'fed9ae76cdb99b1dcfacfaf263f612d9c6f01a31' -or
    [string]$Record.player_executable_source_equality.cutover_source_identity.tree -cne '15b2df204cac33121000c36b741738ebfc611237' -or
    [string]$Record.player_executable_source_equality.cutover_source_identity.package_source_sha256 -cne '632E71A660AB5DEE4C3286E21AAA348BA7162674DFB15AEEECEFEF4B2525948E' -or
    -not [bool]$Record.player_executable_source_equality.player_executable_sources_equal -or
    [string]$Record.player_executable_source_equality.evidence.path -cne 'releases/migrations/MIR4-M41-05B-Documentation-CutoverV1.json' -or
    [string]$Record.player_executable_source_equality.evidence.sha256 -cne '41DA3E5346D719AB36279EDA535ACD9E193E03F4C9DC64B7903B6594654B3C5B' -or
    [string]$Record.frozen_v1_current_package_fingerprint_relation.frozen_v1_package_source_sha256 -cne '8D59F97AC6A42917A22E160E492ED94854D3D377C57D22C3FE27AE6A9C77A336' -or
    [string]$Record.frozen_v1_current_package_fingerprint_relation.current_package_source_sha256 -cne '2BE9A0C5510F6369DBE239746BB525F77952DC5E64C0C0D2DCD9E002B059779E' -or
    [bool]$Record.frozen_v1_current_package_fingerprint_relation.package_source_fingerprints_equal -or
    [bool]$Record.frozen_v1_current_package_fingerprint_relation.player_executable_sources_equality_claimed
  ) {
    throw '[mir4-package-presentation-v2-record-executable-source-equality]'
  }
  if([string]$Record.predecessor.path-cne'spec/distribution/mir4-package-presentation-baseline-v1.json'-or[string]$Record.predecessor.kind-cne'MIR4PackagePresentationBaselineV1'-or[string]$Record.predecessor.hash_mode-cne'canonical-text-v1'-or[string]$Record.predecessor.sha256-cne'9E30907A2D6B8AE949FA0FA64CD28A4246B504177187FC22AB064989388AA0A8'-or-not[bool]$Record.predecessor.retired_for_current_checkout-or[string]$Record.package_authority.record_sha256-cne'BC0D254E4BA34B9B4B8E87995F9817B19B1D64B077331B58DE5A1822BEB1943F'-or[string]$Record.source_manifest.record_sha256-cne'B0ADB772013A1BEB3B25E999BBF0235956497294455B164B1C1C4BF998496D3B'-or[string]$Record.package_source.fingerprint_sha256-cne'2BE9A0C5510F6369DBE239746BB525F77952DC5E64C0C0D2DCD9E002B059779E'-or[string]$Record.package_source.sole_writer-cne'tools/mir/application/package/TargetMaterializer.ps1'-or(@($Record.package_source.roots)-join'|')-cne'src/mod|targets'-or-not[bool]$Record.presentation.repository_readme_package_excluded){throw '[mir4-package-presentation-v2-record-binding]'}
  foreach($name in @('version_allocation','tagging','signing','sealing','publication')){if([bool]$Record.transition_gate.$name){throw "[mir4-package-presentation-v2-record-gate] $name"}}
  $expected=@('releases/migrations/MIR4-M41-05B-Documentation-CutoverV1.json','releases/migrations/MIR4-M41-F2E-Package-Authority-CutoverV1.json','releases/migrations/MIR4-M41-Current-Product-Bridge-RetirementV1.json');if((@($Record.receipts|ForEach-Object path)-join'|')-cne($expected-join'|')){throw '[mir4-package-presentation-v2-record-receipts]'}
}

function Assert-MIR4CurrentPackagePresentationV2FingerprintTriplet {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$StoredPackageSourceSha256,
    [Parameter(Mandatory)][string]$RequiredPackageSourceSha256,
    [Parameter(Mandatory)][string]$RecomputedPackageSourceSha256
  )

  if (
    $StoredPackageSourceSha256 -notmatch '^[A-F0-9]{64}$' -or
    $RequiredPackageSourceSha256 -notmatch '^[A-F0-9]{64}$' -or
    $RecomputedPackageSourceSha256 -notmatch '^[A-F0-9]{64}$' -or
    $StoredPackageSourceSha256 -cne $RequiredPackageSourceSha256 -or
    $RequiredPackageSourceSha256 -cne $RecomputedPackageSourceSha256
  ) {
    throw '[mir4-package-presentation-v2-live-fingerprint]'
  }
  return $StoredPackageSourceSha256
}

function Assert-MIR4CurrentPackagePresentationV2LiveFingerprint {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$StoredPackageSourceSha256,
    [Parameter(Mandatory)][string]$RequiredPackageSourceSha256
  )

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  . (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
  $recomputedPackageSourceSha256 = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
  return Assert-MIR4CurrentPackagePresentationV2FingerprintTriplet -StoredPackageSourceSha256 $StoredPackageSourceSha256 -RequiredPackageSourceSha256 $RequiredPackageSourceSha256 -RecomputedPackageSourceSha256 $recomputedPackageSourceSha256
}

function Assert-MIR4CurrentPackagePresentationV2 {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$PackageSourceSha256)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path;$v2=Get-MIR4CurrentPackagePresentationV2 $repo
  . (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
  $liveFingerprint=Assert-MIR4CurrentPackagePresentationV2LiveFingerprint -RepoRoot $repo -StoredPackageSourceSha256 ([string]$v2.package_source.fingerprint_sha256) -RequiredPackageSourceSha256 $PackageSourceSha256
  if(-not[bool]$v2.presentation.repository_readme_package_excluded){throw '[mir4-package-presentation-v2-root-readme]'}
  foreach($target in @('f210','f200','f110','f100')){if(-not(Test-Path (Join-Path $repo "targets/$target/generation/README.md.template") -PathType Leaf)){throw "[mir4-package-presentation-v2-target-readme] $target"}}
  foreach($name in @('version_allocation','tagging','signing','sealing','publication')){if([bool]$v2.transition_gate.$name){throw "[mir4-package-presentation-v2-gate] $name"}}
  $v2
}

function Get-MIR4CurrentPackageSourceSha256 {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $v2=Get-MIR4CurrentPackagePresentationV2 -RepoRoot $repo
  return [string](Assert-MIR4CurrentPackagePresentationV2LiveFingerprint -RepoRoot $repo -StoredPackageSourceSha256 ([string]$v2.package_source.fingerprint_sha256) -RequiredPackageSourceSha256 ([string]$v2.package_source.fingerprint_sha256))
}
