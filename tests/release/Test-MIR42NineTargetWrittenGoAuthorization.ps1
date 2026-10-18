# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [ValidateSet('4.2.1','4.2.2','4.2.3','4.3.0','4.5.2')][string]$MaintenanceSourceVersion='4.2.1')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/release/readiness/MIR42ReleaseAssets.ps1')
. (Join-Path $repo 'tests/support/MIR421ReleaseAssetControls.ps1')
$script:mir42WrittenGoControlAssertions=0

function Assert-MIR42WrittenGoTest {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code)
  if (-not $Condition) { throw "[mir42-written-go-test-$Code]" }
  $script:mir42WrittenGoControlAssertions++
}

function Assert-MIR42WrittenGoReject {
  param([Parameter(Mandatory)][scriptblock]$Action,[Parameter(Mandatory)][string]$Pattern,[Parameter(Mandatory)][string]$Code)
  $rejected = $false
  try { & $Action | Out-Null } catch { $rejected = $_.Exception.Message -match $Pattern }
  Assert-MIR42WrittenGoTest -Condition $rejected -Code $Code
}

$wrapper = Join-Path $repo 'tools/commands/release/Invoke-MIR42NineTargetReleaseAssets.ps1'
$wrapperText = Get-Content -Raw -LiteralPath $wrapper
Assert-MIR42WrittenGoTest -Condition ($wrapperText -match "'AuthorizePublication'" -and $wrapperText -match 'New-MIR42NineTargetPublicationAuthorization') -Code 'wrapper-exposes-bound-authorization-only'

$root = Join-Path $repo ('build/test-results/mir42-written-go-' + [guid]::NewGuid().ToString('N'))
$inventoryReader = (Get-Item Function:Read-MIR42NineTargetReleaseAssetInventory).ScriptBlock
$liveMainReader = (Get-Item Function:Get-MIR42PrimaryMainSnapshot).ScriptBlock
try {
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  $source = [pscustomobject][ordered]@{commit=('a' * 40);tree=('c' * 40);package_source_sha256=('A' * 64)}
  $candidateBinding = [pscustomobject][ordered]@{sha256=('B' * 64);record_sha256=('C' * 64)}
  $sealBinding = [pscustomobject][ordered]@{sha256=('D' * 64);record_sha256=('E' * 64)}
  $targets = @(
    foreach ($index in 0..($script:MIR42ReleaseAssetTargets.Count - 1)) {
      $target = $script:MIR42ReleaseAssetTargets[$index]
      [pscustomobject][ordered]@{target=$target;distribution_version=('4.2.' + $target.Substring(1) + '00');archive_sha256=(([string]$index) * 64).Substring(0,64);content_sha256=(([string](($index + 1) % 10)) * 64);entry_count=10 + $index}
    }
  )
  $authorization = [pscustomobject][ordered]@{
    schema=1;kind='MIR42MaintainerWrittenReleaseAuthorizationHandoffV1';status='written-maintainer-authorization-recorded-awaiting-exact-candidate-and-technical-proof'
    recorded_from_user_turn_date='2026-10-02';timezone='Australia/Sydney'
    release=[ordered]@{source_version='4.2.0';tag='v4.2.0';selected_targets=@($script:MIR42ReleaseAssetTargets)}
    written_authorizations=[ordered]@{
      complete_mir_4_2='authorized-subject-to-required-technical-checks';protected_main_promotion='authorized-after-accepted-technical-seal-and-governed-restore'
      required_distribution_tags='authorized-after-protected-main-readback-and-candidate-bound-go';github_publication='authorized-after-final-byte-acceptance-and-tag-verification'
      nine_target_github_zip_assets='authorized-after-final-byte-acceptance';mod_portal_upload='not-claimed-by-this-github-release-authorization'
    }
    maintainer_decisions=[ordered]@{
      current_balance_direction='accepted';current_visual_direction='accepted';disclosed_limitations='accepted';additional_playtest_prompt='waived-for-this-release-decision'
      experimental_f210='qualified-experimental-consent-recorded';f210_f200_playtest_receipt='not-claimed-and-not-materialized';technical_acceptance='not-established'
      candidate_binding='deferred-until-one-exact-accepted-candidate';final_byte_hashes='not-yet-available'
    }
    nonnegotiable_constraints=@('fixture constraint')
    current_controller_state=[ordered]@{programme_path='.mir/releases/governance/mir4/MIR42-Nine-Target-Release-Cut-ProgrammeV1.json';programme_status='active-current-4.2-release-cut-pre-freeze-no-transition-authority';source_freeze=$false;candidate_allocation=$false;production_signing=$false;technical_seal=$false;promotion=$false;tagging=$false;publication=$false}
    required_external_inputs_before_technical_seal=@([ordered]@{name='fixture';required_path='external fixture';state='absent'})
    known_operator_inputs=[ordered]@{ssh_keygen_path='C:/Windows/System32/OpenSSH/ssh-keygen.exe';existing_signer_public_fingerprint='SHA256:McpdYUux7BcYmBkf75fGuHSn/lYkTHB6ngMOdUJ5ggQ';signer_continuity_policy='existing-MIR-dedicated-signer-continuity';signer_probe_disposition='automatic-review-rejected-no-retry-or-workaround';rejection_record='AUTOMATIC-REVIEW-REJECTION.txt'}
    final_byte_binding=[ordered]@{candidate_manifest_path='deferred';technical_seal_path='deferred';frozen_inventory_path='deferred';required_binding='fixture binds after exact proof'}
    secret_values_present=$false;warning='fixture only';record_sha256=''
  }
  $authorizationPath = Join-Path $root 'authorization.json'
  Write-MIR4BootstrapRecord -Record $authorization -Path $authorizationPath | Out-Null
  $authorizationIdentity = Read-MIR42NineTargetWrittenReleaseAuthorization -Path $authorizationPath
  Assert-MIR42WrittenGoTest -Condition ([string]$authorizationIdentity.record.maintainer_decisions.f210_f200_playtest_receipt -ceq 'not-claimed-and-not-materialized') -Code 'written-waiver-does-not-claim-gameplay-receipt'
  $authorization.written_authorizations.mod_portal_upload = 'authorized-after-final-byte-acceptance-using-identical-sealed-zips'
  $authorization.record_sha256 = ''
  $oldPortalScopePath = Join-Path $root 'old-portal-scope-authorization.json'
  Write-MIR4BootstrapRecord -Record $authorization -Path $oldPortalScopePath | Out-Null
  Assert-MIR42WrittenGoReject -Action { Read-MIR42NineTargetWrittenReleaseAuthorization -Path $oldPortalScopePath } -Pattern '\[mir42-release-go-schema\]' -Code 'portal-authority-not-in-github-go'
  $authorization.written_authorizations.mod_portal_upload = 'not-claimed-by-this-github-release-authorization'

  $mainReadback = [pscustomobject][ordered]@{
    schema=1;kind='MIR42NineTargetProtectedMainReadbackV1';status='MIR-4.2-NINE-TARGET-SEALED-ON-MAIN-AWAITING-HUMAN-PLAYTEST';scope='nine-target';source=$source
    primary_main=[ordered]@{commit=('b' * 40);tree=('c' * 40);package_source_sha256=('A' * 64);remote_commit=('b' * 40)}
    protected_pull_request='fixture';promotion_transport='fixture';source_rebinding=[ordered]@{qualified_tree=('c' * 40);promoted_main_tree=('c' * 40);package_source_sha256=('A' * 64);package_bytes_preserved=$true;explicit_commit_rebinding=$true}
    candidate_manifest=$candidateBinding;technical_seal=$sealBinding;current_programme='fixture';direct_predecessors='fixture';governed_offline_restore_drill='fixture';targets=@($script:MIR42ReleaseAssetTargets);target_assets=$targets;proofs='fixture'
    main_readback_verified=$true;remote_mutation_performed=$false;protected_main_promotion_authorized=$false;human_go_required_after_main_readback=$true;tagging_authorized=$false;publication_authorized=$false;record_sha256=''
  }
  $mainReadbackPath = Join-Path $root 'main-readback.json'
  Write-MIR4BootstrapRecord -Record $mainReadback -Path $mainReadbackPath | Out-Null
  $mainIdentity = Read-MIR42NineTargetProtectedMainReadbackForPublication -Path $mainReadbackPath
  Assert-MIR42WrittenGoTest -Condition ([bool]$mainIdentity.record.main_readback_verified -and -not [bool]$mainIdentity.record.tagging_authorized) -Code 'main-readback-pre-go-state-required'

  $inventoryRecord = [pscustomobject][ordered]@{
    release=[ordered]@{source_version='4.2.0';tag='v4.2.0'}
    source=$source;candidate_manifest=$candidateBinding;technical_seal=$sealBinding
    package_assets=@($targets | ForEach-Object { [pscustomobject][ordered]@{target=[string]$_.target;distribution_version=[string]$_.distribution_version;sha256=[string]$_.archive_sha256;content_sha256=[string]$_.content_sha256;entry_count=[int]$_.entry_count} })
    asset_root_file_set_sha256=('F' * 64);record_sha256=('9' * 64)
  }
  Set-Item Function:Read-MIR42NineTargetReleaseAssetInventory -Value { param($Path) return [pscustomobject][ordered]@{path=$Path;sha256=('8' * 64);record=$inventoryRecord} }
  Set-Item Function:Get-MIR42PrimaryMainSnapshot -Value { param($PrimaryRepoRoot) return [pscustomobject][ordered]@{branch='main';commit=('b' * 40);tree=('c' * 40);package_source_sha256=('A' * 64);remote_commit=('b' * 40);remote='origin';ref='refs/heads/main';working_tree_clean=$true} }
  $frozenInventoryPath = Join-Path $root 'frozen-inventory.json'
  [IO.File]::WriteAllText($frozenInventoryPath, '{}')
  $primary = Join-Path $root 'primary'
  New-Item -ItemType Directory -Force -Path $primary | Out-Null
  $output = Join-Path $primary 'build/release-authorization/written-go.json'
  $bound = New-MIR42NineTargetPublicationAuthorization -RepoRoot $repo -PrimaryRepoRoot $primary -MaintainerAuthorizationPath $authorizationPath -MainReadbackPath $mainReadbackPath -FrozenInventoryPath (Join-Path $root 'frozen-inventory.json') -OutputPath $output
  Assert-MIR42WrittenGoTest -Condition ([bool]$bound.record.tagging_authorized -and [bool]$bound.record.github_publication_authorized -and -not [bool]$bound.record.mod_portal_upload_authorized -and [string]$bound.record.publication_scope -ceq 'github-release-only' -and [string]$bound.record.mod_portal_upload_disposition -ceq 'not-claimed-by-this-github-release-authorization' -and -not [bool]$bound.record.written_maintainer_authorization.gameplay_receipt_claimed) -Code 'post-main-authorizes-github-only-without-synthetic-gameplay'
  $repeat = New-MIR42NineTargetPublicationAuthorization -RepoRoot $repo -PrimaryRepoRoot $primary -MaintainerAuthorizationPath $authorizationPath -MainReadbackPath $mainReadbackPath -FrozenInventoryPath (Join-Path $root 'frozen-inventory.json') -OutputPath $output
  Assert-MIR42WrittenGoTest -Condition ([string]$repeat.sha256 -ceq [string]$bound.sha256) -Code 'create-only-output-idempotent'

  $authorization.maintainer_decisions.technical_acceptance = 'accepted'
  $authorization.record_sha256 = ''
  $invalidAuthorizationPath = Join-Path $root 'invalid-authorization.json'
  Write-MIR4BootstrapRecord -Record $authorization -Path $invalidAuthorizationPath | Out-Null
  Assert-MIR42WrittenGoReject -Action { Read-MIR42NineTargetWrittenReleaseAuthorization -Path $invalidAuthorizationPath } -Pattern '\[mir42-release-go-schema\]' -Code 'synthetic-technical-acceptance-rejected'

  $maintenancePatch=([version]$MaintenanceSourceVersion).Build.ToString('D2')
  $waiverProperty=if($MaintenanceSourceVersion-cin@('4.2.2','4.2.3','4.3.0','4.5.2')){'inherit_predecessor_testing_waivers'}else{'inherit_420_testing_waivers'}
  $maintenanceConstraints=if($MaintenanceSourceVersion-ceq'4.5.2'){
    [ordered]@{preserve_published_442=$true;preserve_published_450=$true;preserve_published_451=$true;inherit_predecessor_testing_waivers=$false;fabricate_signatures_or_review=$false;mutable_github_release_required=$true;mod_portal_maintainer_managed=$true}
  }else{
    [ordered]@{preserve_published_420=$true;fabricate_signatures_or_review=$false;mutable_github_release_required=$true;mod_portal_maintainer_managed=$true}
  }
  $maintenanceConstraints[$waiverProperty]=$false
  if($MaintenanceSourceVersion-cin@('4.2.2','4.2.3','4.3.0')){$maintenanceConstraints.preserve_published_421=$true}
  if($MaintenanceSourceVersion-cin@('4.2.3','4.3.0')){$maintenanceConstraints.preserve_published_422=$true}
  $maintenanceWrittenAuthorizations=$authorization.written_authorizations | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
  if($MaintenanceSourceVersion-cin@('4.3.0','4.5.2')){
    $maintenanceWrittenAuthorizations.PSObject.Properties.Remove('complete_mir_4_2')
    $deliveryField=if($MaintenanceSourceVersion-ceq'4.5.2'){'deliver_qualified_mir_4_5_2'}else{'deliver_qualified_mir_4_3_0'}
    $maintenanceWrittenAuthorizations | Add-Member -NotePropertyName $deliveryField -NotePropertyValue 'authorized-subject-to-required-technical-checks'
  }
  $maintenanceAuthorization=[pscustomobject][ordered]@{
    schema=1;kind=('MIR'+$MaintenanceSourceVersion.Replace('.','')+'MaintainerWrittenReleaseAuthorizationV1');status='written-maintainer-authorization-awaiting-technical-acceptance'
    recorded_from_user_turn_date='2026-10-06';timezone='Australia/Sydney'
    release=[ordered]@{source_version=$MaintenanceSourceVersion;tag=('v'+$MaintenanceSourceVersion);selected_targets=@($script:MIR42ReleaseAssetTargets)}
    written_authorizations=$maintenanceWrittenAuthorizations
    constraints=$maintenanceConstraints
    technical_acceptance='not-established-by-this-authorization';final_byte_binding='required-before-publication'
    personal_playthrough='not-a-prerequisite-for-authorized-execution';secret_values_present=$false;record_sha256=''
  }
  $maintenanceAuthorizationPath=Join-Path $root 'maintenance-authorization.json'
  Write-MIR4BootstrapRecord -Record $maintenanceAuthorization -Path $maintenanceAuthorizationPath | Out-Null
  if($MaintenanceSourceVersion-ceq'4.3.0'){
    $mir430Schema=Join-Path $repo 'spec/schemas/mir430-maintainer-written-release-authorization-v1.schema.json'
    Assert-MIR42WrittenGoTest -Condition ([bool](Get-Content -Raw -LiteralPath $maintenanceAuthorizationPath | Test-Json -SchemaFile $mir430Schema)) -Code 'mir430-schema-accepts-scoped-qualified-delivery'
  }elseif($MaintenanceSourceVersion-ceq'4.5.2'){
    $mir452Schema=Join-Path $repo 'spec/schemas/mir452-maintainer-written-release-authorization-v1.schema.json'
    Assert-MIR42WrittenGoTest -Condition ([bool](Get-Content -Raw -LiteralPath $maintenanceAuthorizationPath | Test-Json -SchemaFile $mir452Schema)) -Code 'mir452-schema-accepts-scoped-qualified-delivery'
  }
  $maintenanceIdentity=Read-MIR42NineTargetWrittenReleaseAuthorization -Path $maintenanceAuthorizationPath
  Assert-MIR42WrittenGoTest -Condition ([string]$maintenanceIdentity.record.technical_acceptance -ceq 'not-established-by-this-authorization' -and [string]$maintenanceIdentity.record.final_byte_binding -ceq 'required-before-publication' -and -not $maintenanceIdentity.record.constraints.$waiverProperty -and -not $maintenanceIdentity.record.constraints.fabricate_signatures_or_review) -Code 'maintenance-conditional-authority-establishes-no-pass-or-waiver'
  if($MaintenanceSourceVersion-ceq'4.3.0'){
    Assert-MIR42WrittenGoTest -Condition ([string]$maintenanceIdentity.record.written_authorizations.deliver_qualified_mir_4_3_0 -ceq 'authorized-subject-to-required-technical-checks' -and $maintenanceIdentity.record.written_authorizations.PSObject.Properties.Name -notcontains 'complete_mir_4_2') -Code 'mir430-authorizes-scoped-qualified-delivery-only'
    $legacyScope=$maintenanceAuthorization | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
    $legacyScope.written_authorizations.PSObject.Properties.Remove('deliver_qualified_mir_4_3_0')
    $legacyScope.written_authorizations | Add-Member -NotePropertyName complete_mir_4_2 -NotePropertyValue 'authorized-subject-to-required-technical-checks'
    $legacyScopePath=Join-Path $root 'mir430-legacy-completion-scope.json'
    Write-MIR4BootstrapRecord -Record $legacyScope -Path $legacyScopePath | Out-Null
    Assert-MIR42WrittenGoReject -Action { Read-MIR42NineTargetWrittenReleaseAuthorization -Path $legacyScopePath } -Pattern '^\[mir42-release-go-schema\]$' -Code 'mir430-refuses-relabelled-mir42-completion-scope'
  }elseif($MaintenanceSourceVersion-ceq'4.5.2'){
    Assert-MIR42WrittenGoTest -Condition ([string]$maintenanceIdentity.record.written_authorizations.deliver_qualified_mir_4_5_2 -ceq 'authorized-subject-to-required-technical-checks' -and $maintenanceIdentity.record.written_authorizations.PSObject.Properties.Name -notcontains 'complete_mir_4_2') -Code 'mir452-authorizes-scoped-qualified-delivery-only'
    $legacyScope=$maintenanceAuthorization | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
    $legacyScope.written_authorizations.PSObject.Properties.Remove('deliver_qualified_mir_4_5_2')
    $legacyScope.written_authorizations | Add-Member -NotePropertyName complete_mir_4_2 -NotePropertyValue 'authorized-subject-to-required-technical-checks'
    $legacyScopePath=Join-Path $root 'mir452-legacy-completion-scope.json'
    Write-MIR4BootstrapRecord -Record $legacyScope -Path $legacyScopePath | Out-Null
    Assert-MIR42WrittenGoReject -Action { Read-MIR42NineTargetWrittenReleaseAuthorization -Path $legacyScopePath } -Pattern '^\[mir42-release-go-schema\]$' -Code 'mir452-refuses-relabelled-mir42-completion-scope'
  }
  $inventoryRecord.release.source_version=$MaintenanceSourceVersion;$inventoryRecord.release.tag='v'+$MaintenanceSourceVersion
  $custody=New-MIR421ReleaseAssetCustodyFixture -RepoRoot $repo -CandidateSourceVersion $MaintenanceSourceVersion
  $inventoryRecord | Add-Member -NotePropertyName published_maintenance_predecessor -NotePropertyValue $custody
  foreach ($row in $inventoryRecord.package_assets) { $row.distribution_version=$row.distribution_version.Substring(0,$row.distribution_version.Length - 2) + $maintenancePatch }
  $maintenanceMain=$mainReadback | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
  if($MaintenanceSourceVersion-ceq'4.5.2'){$maintenanceMain.status='MIR-4.5-NINE-TARGET-SEALED-ON-MAIN-AWAITING-HUMAN-PLAYTEST'}
  foreach ($row in $maintenanceMain.target_assets) { $row.distribution_version=$row.distribution_version.Substring(0,$row.distribution_version.Length - 2) + $maintenancePatch }
  $maintenanceMain | Add-Member -NotePropertyName published_maintenance_predecessor -NotePropertyValue $custody
  $maintenanceMainPath=Join-Path $root 'maintenance-main-readback.json'
  Write-MIR4BootstrapRecord -Record $maintenanceMain -Path $maintenanceMainPath | Out-Null
  $maintenanceOutput=Join-Path $primary 'build/release-authorization/maintenance-written-go.json'
  $maintenanceBound=New-MIR42NineTargetPublicationAuthorization -RepoRoot $repo -PrimaryRepoRoot $primary -MaintainerAuthorizationPath $maintenanceAuthorizationPath -MainReadbackPath $maintenanceMainPath -FrozenInventoryPath $frozenInventoryPath -OutputPath $maintenanceOutput
  Assert-MIR42WrittenGoTest -Condition ([string]$maintenanceBound.record.kind -ceq 'MIR42NineTargetMaintenancePublicationAuthorizationV1' -and [string]$maintenanceBound.record.release.source_version -ceq $MaintenanceSourceVersion -and [string]$maintenanceBound.record.release.tag -ceq ('v'+$MaintenanceSourceVersion) -and [bool]$maintenanceBound.record.github_publication_authorized -and -not [bool]$maintenanceBound.record.mod_portal_upload_authorized -and -not [bool]$maintenanceBound.record.written_maintainer_authorization.additional_playtest_prompt_waived -and -not [bool]$maintenanceBound.record.written_maintainer_authorization.gameplay_receipt_claimed) -Code 'maintenance-bound-authority-preserves-technical-acceptance-condition'
  Assert-MIR42WrittenGoTest -Condition ((ConvertTo-MIR4BootstrapCanonicalJson -Value $maintenanceBound.record.published_maintenance_predecessor) -ceq (ConvertTo-MIR4BootstrapCanonicalJson -Value $custody)) -Code 'maintenance-publication-custody-preserved'
  $forbiddenOutput=Join-Path $primary 'build/release-authorization/old-go-must-not-authorize-maintenance.json'
  Assert-MIR42WrittenGoReject -Action { New-MIR42NineTargetPublicationAuthorization -RepoRoot $repo -PrimaryRepoRoot $primary -MaintainerAuthorizationPath $authorizationPath -MainReadbackPath $maintenanceMainPath -FrozenInventoryPath $frozenInventoryPath -OutputPath $forbiddenOutput } -Pattern '^\[mir42-release-go-authorization-version-binding\]$' -Code 'old-go-cannot-authorize-maintenance'
  Assert-MIR42WrittenGoTest -Condition (-not (Test-Path -LiteralPath $forbiddenOutput)) -Code 'old-go-no-output'
  if($MaintenanceSourceVersion-ceq'4.5.2'){
    $wrongInventory=$inventoryRecord | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
    $wrongInventory.release.source_version='4.5.0';$wrongInventory.release.tag='v4.5.0'
    $savedInventory=$inventoryRecord;$inventoryRecord=$wrongInventory
    Assert-MIR42WrittenGoReject -Action { New-MIR42NineTargetPublicationAuthorization -RepoRoot $repo -PrimaryRepoRoot $primary -MaintainerAuthorizationPath $maintenanceAuthorizationPath -MainReadbackPath $maintenanceMainPath -FrozenInventoryPath $frozenInventoryPath -OutputPath $forbiddenOutput } -Pattern '^\[mir42-release-go-authorization-version-binding\]$' -Code 'mir452-inventory-version-cannot-authorize-current-go'
    Assert-MIR42WrittenGoTest (-not(Test-Path -LiteralPath $forbiddenOutput)) 'mir452-inventory-version-no-output'
    $inventoryRecord=$savedInventory
  }
  if($MaintenanceSourceVersion-cin@('4.2.2','4.2.3','4.3.0','4.5.2')){
    $prior=$maintenanceAuthorization | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
    $priorVersion=switch($MaintenanceSourceVersion){'4.2.2'{'4.2.1'};'4.2.3'{'4.2.2'};'4.3.0'{'4.2.3'};'4.5.2'{'4.5.1'}}
    $prior.kind=('MIR'+$priorVersion.Replace('.','')+'MaintainerWrittenReleaseAuthorizationV1')
    $prior.release.source_version=$priorVersion;$prior.release.tag=('v'+$priorVersion)
    if($MaintenanceSourceVersion-ceq'4.3.0'){
      $prior.written_authorizations.PSObject.Properties.Remove('deliver_qualified_mir_4_3_0')
      $prior.written_authorizations | Add-Member -NotePropertyName complete_mir_4_2 -NotePropertyValue 'authorized-subject-to-required-technical-checks'
    }elseif($MaintenanceSourceVersion-ceq'4.5.2'){
      $prior.written_authorizations.PSObject.Properties.Remove('deliver_qualified_mir_4_5_2')
      $prior.written_authorizations | Add-Member -NotePropertyName complete_mir_4_2 -NotePropertyValue 'authorized-subject-to-required-technical-checks'
    }
    if($MaintenanceSourceVersion-ceq'4.2.3'){
      $prior.constraints.PSObject.Properties.Remove('preserve_published_422')
    }elseif($MaintenanceSourceVersion-ceq'4.2.2'){
      $prior.constraints.PSObject.Properties.Remove('preserve_published_421')
      $prior.constraints.PSObject.Properties.Remove('inherit_predecessor_testing_waivers')
      $prior.constraints | Add-Member -NotePropertyName inherit_420_testing_waivers -NotePropertyValue $false
    }
    $priorPath=Join-Path $root 'prior-maintenance-authorization.json'
    Write-MIR4BootstrapRecord -Record $prior -Path $priorPath | Out-Null
    if($MaintenanceSourceVersion-ceq'4.5.2'){
      Assert-MIR42WrittenGoReject -Action { Read-MIR42NineTargetWrittenReleaseAuthorization -Path $priorPath } -Pattern '^\[mir42-release-go-schema\]$' -Code 'prior-451-authorization-is-not-current-mir452-authority'
    }else{
      $priorIdentity=Read-MIR42NineTargetWrittenReleaseAuthorization -Path $priorPath
      Assert-MIR42WrittenGoTest ($priorIdentity.record.release.source_version-ceq$priorVersion) 'prior-maintenance-authority-remains-readable'
    }
    $priorAuthorizationPattern=if($MaintenanceSourceVersion-ceq'4.5.2'){'^\[mir42-release-go-schema\]$'}else{'^\[mir42-release-go-authorization-version-binding\]$'}
    Assert-MIR42WrittenGoReject -Action { New-MIR42NineTargetPublicationAuthorization -RepoRoot $repo -PrimaryRepoRoot $primary -MaintainerAuthorizationPath $priorPath -MainReadbackPath $maintenanceMainPath -FrozenInventoryPath $frozenInventoryPath -OutputPath $forbiddenOutput } -Pattern $priorAuthorizationPattern -Code 'prior-authority-cannot-authorize-current-maintenance'
    Assert-MIR42WrittenGoTest (-not(Test-Path -LiteralPath $forbiddenOutput)) 'prior-authority-no-current-maintenance-output'
    $prior.release.source_version=$MaintenanceSourceVersion;$prior.release.tag=('v'+$MaintenanceSourceVersion)
    Write-MIR4BootstrapRecord -Record $prior -Path $priorPath | Out-Null
    Assert-MIR42WrittenGoReject -Action { Read-MIR42NineTargetWrittenReleaseAuthorization -Path $priorPath } -Pattern '^\[mir42-release-go-schema\]$' -Code 'prior-authority-cannot-be-relabelled-current-maintenance'
    $priorMain=$maintenanceMain | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
    $wrongPredecessorVersion=if($MaintenanceSourceVersion-ceq'4.3.0'){'4.2.2'}elseif($MaintenanceSourceVersion-ceq'4.5.2'){'4.5.0'}else{$priorVersion}
    $priorMain.published_maintenance_predecessor=New-MIR421ReleaseAssetCustodyFixture -RepoRoot $repo -CandidateSourceVersion $wrongPredecessorVersion
    $priorMainPath=Join-Path $root 'prior-predecessor-main.json'
    Write-MIR4BootstrapRecord -Record $priorMain -Path $priorMainPath | Out-Null
    Assert-MIR42WrittenGoReject -Action { New-MIR42NineTargetPublicationAuthorization -RepoRoot $repo -PrimaryRepoRoot $primary -MaintainerAuthorizationPath $maintenanceAuthorizationPath -MainReadbackPath $priorMainPath -FrozenInventoryPath $frozenInventoryPath -OutputPath $forbiddenOutput } -Pattern '^\[mir42-release-assets-maintenance-predecessor\]$' -Code 'wrong-published-predecessor-cannot-authorize-current-maintenance'
    Assert-MIR42WrittenGoTest (-not(Test-Path -LiteralPath $forbiddenOutput)) 'wrong-predecessor-no-current-maintenance-output'
  }
  if($MaintenanceSourceVersion-ceq'4.5.2'){
    foreach($relabelVersion in @('4.5.1','4.5.3')){
      $relabel=$maintenanceAuthorization | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
      $relabel.kind=('MIR'+$relabelVersion.Replace('.','')+'MaintainerWrittenReleaseAuthorizationV1')
      $relabel.release.source_version=$relabelVersion;$relabel.release.tag=('v'+$relabelVersion)
      $relabelPath=Join-Path $root ('mir452-relabel-'+$relabelVersion.Replace('.','-')+'.json')
      Write-MIR4BootstrapRecord -Record $relabel -Path $relabelPath | Out-Null
      Assert-MIR42WrittenGoReject -Action { Read-MIR42NineTargetWrittenReleaseAuthorization -Path $relabelPath } -Pattern '^\[mir42-release-go-schema\]$' -Code ('mir452-refuses-'+$relabelVersion+'-relabel')
    }
  }
  foreach ($case in @('inherited-waiver','synthetic-acceptance','stable-tag','wrong-source-version','fabricated-signature-review','missing-technical-acceptance','old-decisions')) {
    $invalid=$maintenanceAuthorization | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
    switch ($case) {
      'inherited-waiver' { $invalid.constraints.$waiverProperty=$true }
      'synthetic-acceptance' { $invalid.technical_acceptance='accepted' }
      'stable-tag' { $invalid.release.tag='v'+$MaintenanceSourceVersion+'-stable' }
      'wrong-source-version' { $invalid.release.source_version='4.2.0' }
      'fabricated-signature-review' { $invalid.constraints.fabricate_signatures_or_review=$true }
      'missing-technical-acceptance' { $invalid.PSObject.Properties.Remove('technical_acceptance') }
      'old-decisions' { $invalid | Add-Member -NotePropertyName maintainer_decisions -NotePropertyValue $authorization.maintainer_decisions }
    }
    $invalidPath=Join-Path $root ($case + '.json')
    Write-MIR4BootstrapRecord -Record $invalid -Path $invalidPath | Out-Null
    Assert-MIR42WrittenGoReject -Action { Read-MIR42NineTargetWrittenReleaseAuthorization -Path $invalidPath } -Pattern '^\[mir42-release-go-schema\]$' -Code ('maintenance-refuses-' + $case)
  }
  $driftMain=$maintenanceMain | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
  $driftMain.published_maintenance_predecessor.manifest.path='different-custody-location'
  $driftPath=Join-Path $root 'maintenance-main-custody-drift.json'
  Write-MIR4BootstrapRecord -Record $driftMain -Path $driftPath | Out-Null
  $forbiddenOutput=Join-Path $primary 'build/release-authorization/custody-drift-must-not-authorize.json'
  Assert-MIR42WrittenGoReject -Action { New-MIR42NineTargetPublicationAuthorization -RepoRoot $repo -PrimaryRepoRoot $primary -MaintainerAuthorizationPath $maintenanceAuthorizationPath -MainReadbackPath $driftPath -FrozenInventoryPath $frozenInventoryPath -OutputPath $forbiddenOutput } -Pattern '^\[mir42-release-go-maintenance-custody-binding\]$' -Code 'main-readback-custody-drift-refused'
  Assert-MIR42WrittenGoTest -Condition (-not (Test-Path -LiteralPath $forbiddenOutput)) -Code 'custody-drift-no-output'
  $candidateDriftMain=$maintenanceMain | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
  $candidateDriftMain.candidate_manifest.sha256=('F' * 64)
  $candidateDriftPath=Join-Path $root 'maintenance-main-candidate-drift.json'
  Write-MIR4BootstrapRecord -Record $candidateDriftMain -Path $candidateDriftPath | Out-Null
  $forbiddenOutput=Join-Path $primary 'build/release-authorization/candidate-drift-must-not-authorize.json'
  Assert-MIR42WrittenGoReject -Action { New-MIR42NineTargetPublicationAuthorization -RepoRoot $repo -PrimaryRepoRoot $primary -MaintainerAuthorizationPath $maintenanceAuthorizationPath -MainReadbackPath $candidateDriftPath -FrozenInventoryPath $frozenInventoryPath -OutputPath $forbiddenOutput } -Pattern '^\[mir42-release-go-inventory-binding\] candidate_manifest/sha256$' -Code 'candidate-drift-cannot-authorize-maintenance'
  Assert-MIR42WrittenGoTest -Condition (-not (Test-Path -LiteralPath $forbiddenOutput)) -Code 'candidate-drift-no-output'
} finally {
  Set-Item Function:Read-MIR42NineTargetReleaseAssetInventory -Value $inventoryReader
  Set-Item Function:Get-MIR42PrimaryMainSnapshot -Value $liveMainReader
  if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}

$manualWaiverTest = Join-Path $repo 'tests/release/Test-MIRManualReleaseReview.ps1'
$manualWaiverFailure = $null
try { & $manualWaiverTest -RepoRoot $repo -SelfTest } catch { $manualWaiverFailure = $_ }
Assert-MIR42WrittenGoTest -Condition ($null -eq $manualWaiverFailure) -Code 'manual-written-waiver-negative-contract'

Write-Output "MIR42-NINE-TARGET-WRITTEN-GO-AUTHORIZATION-PASSED maintenance=$MaintenanceSourceVersion assertions=$script:mir42WrittenGoControlAssertions structural-only engines=0 signing=0 publication=0"
if($MaintenanceSourceVersion-ceq'4.2.1'){
  & (Get-Process -Id $PID).Path -NoProfile -File $PSCommandPath -RepoRoot $repo -MaintenanceSourceVersion '4.2.2'
  if($LASTEXITCODE-ne0){throw '[mir422-written-go-controls-failed]'}
}elseif($MaintenanceSourceVersion-ceq'4.2.2'){
  & (Get-Process -Id $PID).Path -NoProfile -File $PSCommandPath -RepoRoot $repo -MaintenanceSourceVersion '4.2.3'
  if($LASTEXITCODE-ne0){throw '[mir423-written-go-controls-failed]'}
}elseif($MaintenanceSourceVersion-ceq'4.2.3'){
  & (Get-Process -Id $PID).Path -NoProfile -File $PSCommandPath -RepoRoot $repo -MaintenanceSourceVersion '4.3.0'
  if($LASTEXITCODE-ne0){throw '[mir430-written-go-controls-failed]'}
}elseif($MaintenanceSourceVersion-ceq'4.3.0'){
  & (Get-Process -Id $PID).Path -NoProfile -File $PSCommandPath -RepoRoot $repo -MaintenanceSourceVersion '4.5.2'
  if($LASTEXITCODE-ne0){throw '[mir452-written-go-controls-failed]'}
}
