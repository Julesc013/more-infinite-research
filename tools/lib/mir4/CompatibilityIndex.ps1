if (-not (Get-Command New-MIR4CompatibilitySubjectLedger -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'SupportAssessment.ps1')
}

function Copy-MIR4W07InspectionData {
  param([AllowNull()]$Value,[Parameter(Mandatory)][string]$RepoRoot)
  $authority = Get-MIR4InspectorCompatibilityAuthority -RepoRoot $RepoRoot
  Test-MIR4W07ForbiddenValue -Value $Value -Forbidden @($authority.forbidden_import_fields)
  if ($null -eq $Value) { return $null }
  return (($Value | ConvertTo-Json -Depth 100 -Compress) | ConvertFrom-Json -Depth 100)
}

function Get-MIR4CompatibilityPage {
  param(
    [Parameter(Mandatory)]$Ledger,
    [Parameter(Mandatory)][string]$RepoRoot,
    [int]$Limit=25,
    [AllowNull()][string]$Cursor=$null,
    [string]$Availability='',
    [string]$Target=''
  )
  $authority = Get-MIR4InspectorCompatibilityAuthority -RepoRoot $RepoRoot
  $max = [int]$authority.inspection_bounds.max_page_items
  if ($Limit -lt 1 -or $Limit -gt $max) { throw "[mir4-w07-page-limit] $Limit" }
  $offset = 0
  if (-not [string]::IsNullOrWhiteSpace($Cursor) -and (-not [int]::TryParse($Cursor,[ref]$offset) -or $offset -lt 0)) {
    throw '[mir4-w07-page-cursor]'
  }
  $items = @($Ledger.subjects | Sort-Object subject_id)
  if (-not [string]::IsNullOrWhiteSpace($Availability)) { $items = @($items | Where-Object { [string]$_.availability.state -ceq $Availability }) }
  if (-not [string]::IsNullOrWhiteSpace($Target)) { $items = @($items | Where-Object { $Target -in @($_.target_bindings.target) }) }
  $pageItems = if ($offset -lt $items.Count) { @($items | Select-Object -Skip $offset -First $Limit) } else { @() }
  $next = if (($offset + $pageItems.Count) -lt $items.Count) { [string]($offset + $pageItems.Count) } else { $null }
  $record = [pscustomobject][ordered]@{
    schema=1;kind='MIR4CompatibilityIndexPageV1';maturity='developer-preview'
    filters=[ordered]@{availability=$(if($Availability){$Availability}else{$null});target=$(if($Target){$Target}else{$null})}
    page=[ordered]@{offset=$offset;limit=$Limit;returned=$pageItems.Count;total=$items.Count;next_cursor=$next}
    items=@(Copy-MIR4W07InspectionData -Value $pageItems -RepoRoot $RepoRoot)
    package_visible=$false;public_support_claim=$false;mutation_authorized=$false;digest=''
  }
  Import-MIR4W07CanonicalSupport -RepoRoot $RepoRoot
  Add-MIR4ModuleDigest $record | Out-Null
  return $record
}

function Test-MIR4CompatibilityProvenance {
  param([Parameter(Mandatory)]$Ledger,[Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4W07RepoRoot $RepoRoot
  $paths = [ordered]@{
    w07_authority='.mir/releases/waves/mir4-r0/MIR4-Inspector-Compatibility-ProgrammeV1.json'
    sol07='.mir/releases/waves/mir4-r0/MIR4-Compatibility-Campaign-SOL07V1.json'
    target_registry='.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV6.json'
    terminal_compatibility='.mir/compatibility.yml'
    terminal_claims='spec/compatibility/claims.json'
  }
  $rows = @(
    foreach ($key in $paths.Keys) {
      $path = Join-Path $repo $paths[$key]
      $actual = if (Test-Path -LiteralPath $path -PathType Leaf) { Get-MIR4W07FileSha256 $path } else { $null }
      $expected = [string]$Ledger.input_digests.$key
      [ordered]@{id=$key;path=$paths[$key];expected_sha256=$expected;actual_sha256=$actual;status=$(if($actual -and $actual -ceq $expected){'current'}else{'stale'})}
    }
  )
  $record = [pscustomobject][ordered]@{
    schema=1;kind='MIR4CompatibilityProvenanceCheckV1';status=$(if(@($rows | Where-Object status -ne 'current').Count){'stale'}else{'current'});rows=$rows
    actual_claim_revocation_performed=$false;public_claim_authority=$false;digest=''
  }
  Import-MIR4W07CanonicalSupport -RepoRoot $repo
  Add-MIR4ModuleDigest $record | Out-Null
  return $record
}

function New-MIR4InspectionSection {
  param([Parameter(Mandatory)][string]$Id,[Parameter(Mandatory)][string]$Label,[object[]]$Items=@(),[int]$MaxItems=100)
  $all = @($Items)
  return [ordered]@{
    id=$Id;label=$Label;item_count=$all.Count;returned=[Math]::Min($all.Count,$MaxItems);truncated=($all.Count -gt $MaxItems)
    items=@($all | Select-Object -First $MaxItems)
  }
}

function Resolve-MIR4W07ProcessIRComparison {
  param([Parameter(Mandatory)][string]$RepoRoot,[AllowNull()]$Comparison=$null)
  $value=$Comparison;$path='embedded:T12/process-ir-comparison'
  if($null-eq$value){
    $relative='sdk/preview/mir4/reference/t12/comparisons/f210-base--f210-official.json'
    $candidate=Join-Path $RepoRoot $relative
    if(-not(Test-Path -LiteralPath $candidate -PathType Leaf)){return $null}
    $value=Get-Content -Raw -LiteralPath $candidate|ConvertFrom-Json -Depth 100;$path=$relative
  }
  if([int]$value.schema-ne 1-or[string]$value.kind-cne'MIR4ProcessIRComparisonV1'-or[string]$value.work_package-cne'T12'-or
     -not[bool]$value.offline-or[bool]$value.network_or_upload_authorized-or[bool]$value.mutation_authorized-or
     [bool]$value.public_support_claim-or[bool]$value.package_visible-or@($value.process_changes).Count-gt 100-or
     [string]$value.digest-cnotmatch'^sha256:[0-9a-f]{64}$') { throw '[mir4-w07-processir-comparison]' }
  [pscustomobject][ordered]@{value=$value;path=$path}
}

function New-MIR4InspectionBundleV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Ledger,[AllowNull()]$SourceIdentity=$null,[AllowNull()]$ProcessIRComparison=$null)
  $repo = Get-MIR4W07RepoRoot $RepoRoot
  Import-MIR4W07CanonicalSupport -RepoRoot $repo
  $authority = Get-MIR4InspectorCompatibilityAuthority -RepoRoot $repo
  Test-MIR4CompatibilitySubjectLedger -Ledger $Ledger -RepoRoot $repo | Out-Null
  $max = [int]$authority.inspection_bounds.max_items_per_section
  $files = [ordered]@{
    compilation='sdk/preview/mir4/reference/compilation-runs.json'
    runtime='sdk/preview/mir4/reference/runtime-state-inventory.json'
    migration='sdk/preview/mir4/reference/migration-graph-matrix.json'
    continuity='sdk/preview/mir4/reference/continuity-bundle-template.json'
    extension='sdk/preview/mir4/reference/extension-closure-v1.json'
    process_ir='sdk/preview/mir4/reference/process-ir-parity-result.json'
    effect_channels='sdk/preview/mir4/reference/effect-channel-registry-v1.json'
    synthesis='sdk/preview/mir4/reference/synthesis-maturity-matrix-v1.json'
  }
  $imported = @{}; $inputDigests = [ordered]@{}
  foreach ($key in $files.Keys) {
    $path = Join-Path $repo $files[$key]
    $inputDigests[$key] = [ordered]@{path=$files[$key];sha256=(Get-MIR4W07FileSha256 $path)}
    $imported[$key] = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100
  }
  $exactComparison=Resolve-MIR4W07ProcessIRComparison -RepoRoot $repo -Comparison $ProcessIRComparison
  if($null-ne$exactComparison){$inputDigests.process_ir=[ordered]@{path=[string]$exactComparison.path;sha256=([string]$exactComparison.value.digest).Substring(7)}}
  $capabilities = @(
    foreach ($subject in @($Ledger.subjects | Sort-Object subject_id)) {
      foreach ($capability in @($subject.capabilities_or_streams | Sort-Object)) {
        [ordered]@{subject_id=[string]$subject.subject_id;capability=[string]$capability;availability=[string]$subject.availability.state;claim_eligible=$false}
      }
    }
  )
  $coverage = @(
    foreach ($subject in @($Ledger.subjects | Sort-Object subject_id)) {
      [ordered]@{subject_id=[string]$subject.subject_id;qualified_surface=[string]$subject.availability.qualified_surface;excluded_surface=@($subject.availability.excluded_surface);automatic_mutation=$false}
    }
  )
  $comparisonRows=@()
  if($null-ne$exactComparison){
    $comparisonRows=@($exactComparison.value.process_changes|Select-Object -First ([Math]::Max(0,$max-$coverage.Count))|ForEach-Object{
      [ordered]@{subject_id='process-ir';process=[string]$_.process;change=[string]$_.status;before=$(if($null-ne$_.before){[ordered]@{certainty=[string]$_.before.certainty;disposition=[string]$_.before.disposition;digest=[string]$_.before.digest}}else{$null});after=$(if($null-ne$_.after){[ordered]@{certainty=[string]$_.after.certainty;disposition=[string]$_.after.disposition;digest=[string]$_.after.digest}}else{$null});automatic_mutation=$false}
    })
  }
  $diagnostics = @(
    foreach ($subject in @($Ledger.subjects | Sort-Object subject_id)) {
      foreach ($blocker in @($subject.blockers)) { [ordered]@{subject_id=[string]$subject.subject_id;severity='review';code='mir4-w07-bounded-blocker';message=[string]$blocker} }
    }
    if($null-eq$exactComparison){[ordered]@{subject_id='process-ir';severity='review';code=[string]$imported.process_ir.exact_target_status;message=[string]$imported.process_ir.exact_target_reason}}
    else{[ordered]@{subject_id='process-ir';severity='information';code='mir4-t12-exact-comparison-captured';message="Exact bounded comparison $($exactComparison.value.a.capture_id) to $($exactComparison.value.b.capture_id); changes=$($exactComparison.value.process_change_count); truncated=$($exactComparison.value.truncated)."}}
  )
  $proof = @(
    foreach ($subject in @($Ledger.subjects | Sort-Object subject_id)) {
      [ordered]@{subject_id=[string]$subject.subject_id;state=[string]$subject.proof.state;evidence_count=@($subject.proof.evidence).Count;claim_eligible=$false}
    }
  )
  if($null-ne$exactComparison){$proof+= [ordered]@{subject_id='process-ir';state='exact-target-preview-captured';evidence_count=2;claim_eligible=$false;comparison_digest=[string]$exactComparison.value.digest}}
  $overview=[ordered]@{programme_id=[string]$authority.programme_id;maturity='developer-preview';subject_count=[int]$Ledger.subject_count;target_count=@($Ledger.target_dispositions).Count;read_only=$true}
  if($null-ne$exactComparison){$overview['exact_processir']=[ordered]@{status='captured-bounded-preview';a=$exactComparison.value.a;b=$exactComparison.value.b;change_count=[int]$exactComparison.value.process_change_count;truncated=[bool]$exactComparison.value.truncated;digest=[string]$exactComparison.value.digest}}
  $sections = @(
    New-MIR4InspectionSection -Id overview -Label 'Overview' -MaxItems $max -Items @($overview)
    New-MIR4InspectionSection -Id capabilities -Label 'Capabilities' -MaxItems $max -Items $capabilities
    New-MIR4InspectionSection -Id research-streams -Label 'Research streams' -MaxItems $max -Items @([ordered]@{authority='.mir/streams.yml';mode='digest-bound-reference-only';sha256=(Get-MIR4W07FileSha256 (Join-Path $repo '.mir/streams.yml'))})
    New-MIR4InspectionSection -Id recipe-productivity-coverage -Label 'Recipe/productivity coverage' -MaxItems $max -Items @($coverage+$comparisonRows)
    New-MIR4InspectionSection -Id compatibility -Label 'Compatibility' -MaxItems $max -Items @($Ledger.subjects | Sort-Object subject_id)
    New-MIR4InspectionSection -Id diagnostics -Label 'Diagnostics' -MaxItems $max -Items $diagnostics
    New-MIR4InspectionSection -Id settings-profile -Label 'Settings/profile' -MaxItems $max -Items @([ordered]@{maturity='developer-preview';network='denied';upload='denied';mutation='denied';factory='data-only'})
    New-MIR4InspectionSection -Id target-dispositions -Label 'Target dispositions' -MaxItems $max -Items @($Ledger.target_dispositions | Sort-Object target)
    New-MIR4InspectionSection -Id migration-status -Label 'Migration status' -MaxItems $max -Items @([ordered]@{kind=[string]$imported.migration.kind;edge_count=@($imported.migration.edges).Count;complete_for_public_release=[bool]$imported.migration.complete_for_public_release;execution_authorized=$false;source_digest=[string]$imported.migration.digest})
    New-MIR4InspectionSection -Id proof-status -Label 'Proof status' -MaxItems $max -Items $proof
    New-MIR4InspectionSection -Id export -Label 'Export' -MaxItems $max -Items @([ordered]@{formats=@('MIR4InspectionBundleV1','MIR4CompatibilityFactoryDataBundleV1');upload=$false;network=$false;executable_content=$false})
  )
  $record = [pscustomobject][ordered]@{
    schema=1;kind='MIR4InspectionBundleV1';programme_id=[string]$authority.programme_id;source_identity=$SourceIdentity;maturity='developer-preview'
    authority='W07-copied-bounded-read-only-DTOs';input_digests=$inputDigests;bounds=$authority.inspection_bounds;sections=$sections
    section_count=$sections.Count;local_file_api_only=$true;network_or_upload_authorized=$false;raw_mutable_compiler_objects=$false
    idle_runtime_work=$false;package_visible=$false;public_release_proof=$false;player_mutation_authorized=$false;digest=''
  }
  Test-MIR4W07ForbiddenValue -Value $record -Forbidden @($authority.forbidden_import_fields)
  Add-MIR4ModuleDigest $record | Out-Null
  return $record
}

function Test-MIR4InspectionBundleV1 {
  param([Parameter(Mandatory)]$Bundle,[Parameter(Mandatory)][string]$RepoRoot)
  $authority = Get-MIR4InspectorCompatibilityAuthority -RepoRoot $RepoRoot
  Test-MIR4W07ForbiddenValue -Value $Bundle -Forbidden @($authority.forbidden_import_fields)
  if ([int]$Bundle.schema -ne 1 -or [string]$Bundle.kind -cne 'MIR4InspectionBundleV1' -or [int]$Bundle.section_count -ne 11 -or
      @($Bundle.sections).Count -ne 11 -or -not [bool]$Bundle.local_file_api_only -or [bool]$Bundle.network_or_upload_authorized -or
      [bool]$Bundle.raw_mutable_compiler_objects -or [bool]$Bundle.idle_runtime_work -or [bool]$Bundle.package_visible -or
      [bool]$Bundle.public_release_proof -or [bool]$Bundle.player_mutation_authorized) { throw '[mir4-w07-inspection-bundle-header]' }
  if ((@($Bundle.sections.label) -join '|') -cne (@($authority.inspector_sections) -join '|')) { throw '[mir4-w07-inspection-sections]' }
  foreach ($section in @($Bundle.sections)) {
    if ([int]$section.returned -gt [int]$authority.inspection_bounds.max_items_per_section -or @($section.items).Count -ne [int]$section.returned) {
      throw "[mir4-w07-inspection-bound] $($section.id)"
    }
  }
  Import-MIR4W07CanonicalSupport -RepoRoot $RepoRoot
  if ([string]$Bundle.digest -cne (Get-MIR4ModuleDigest $Bundle)) { throw '[mir4-w07-inspection-digest]' }
  return $true
}
