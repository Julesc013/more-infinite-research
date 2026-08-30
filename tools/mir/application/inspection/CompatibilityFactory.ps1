if (-not (Get-Command Get-MIR4CompatibilityPage -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'CompatibilityIndex.ps1')
}
. (Join-Path $PSScriptRoot '../assurance/EnvironmentEvidence.ps1')

function New-MIR4SupportBundleV1 {
  param([Parameter(Mandatory)]$Request,[Parameter(Mandatory)]$Ledger,[Parameter(Mandatory)][string]$RepoRoot)
  $authority = Get-MIR4InspectorCompatibilityAuthority -RepoRoot $RepoRoot
  Test-MIR4W07ForbiddenValue -Value $Request -Forbidden @($authority.forbidden_import_fields)
  if ([int]$Request.schema -ne 1 -or [string]$Request.kind -cne 'MIR4CompatibilityFactoryRequestV1' -or
      [string]$Request.target -cnotmatch '^f[0-9]{3}$' -or @($Request.subjects).Count -lt 1 -or @($Request.subjects).Count -gt 10) {
    throw '[mir4-w07-support-request]'
  }
  $seen = @{}
  $subjects = @(
    foreach ($selection in @($Request.subjects | Sort-Object subject_id)) {
      $id = [string]$selection.subject_id
      if ($seen.ContainsKey($id)) { throw "[mir4-w07-support-duplicate-subject] $id" }; $seen[$id] = $true
      $subject = @($Ledger.subjects | Where-Object subject_id -eq $id)
      if ($subject.Count -ne 1 -or [string]$Request.target -notin @($subject[0].target_bindings.target) -or
          [string]$selection.safe_choice -cne [string]$subject[0].implementation.preferred_safe_choice) {
        throw "[mir4-w07-support-subject] $id"
      }
      [ordered]@{subject_id=$id;safe_choice=[string]$selection.safe_choice}
    }
  )
  $references = New-MIR4ReferenceEnvironmentEvidenceV1 -RepoRoot $RepoRoot
  $lock = if ([string]$Request.target -ceq 'f200') { $references.f200 } elseif ([string]$Request.target -ceq 'f210') { $references.f210 } else {
    throw "[mir4-w07-support-environment-unavailable] $($Request.target)"
  }
  $evidence = @(
    [pscustomobject][ordered]@{
      id='compatibility.subject-ledger';kind='authority';summary='The bounded compatibility subject ledger selected by this bundle.'
      dependencies=@();required_by_reproducer=$true
    }
  )
  $record = New-MIR4EnvironmentSupportBundleV1 -EnvironmentLock $lock -BundleId 'org.more-infinite-research.w07.reference' -Subjects $subjects -SourceLedgerDigest ([string]$Ledger.digest) -EvidenceItems $evidence
  Test-MIR4W07ForbiddenValue -Value $record -Forbidden @($authority.forbidden_import_fields)
  return $record
}

function New-MIR4ReferenceSupportBundleV1 {
  param([Parameter(Mandatory)]$Ledger,[Parameter(Mandatory)][string]$RepoRoot,[string]$Target='f210')
  $request = [pscustomobject][ordered]@{
    schema=1;kind='MIR4CompatibilityFactoryRequestV1';target=$Target
    subjects=@(
      foreach ($subject in @($Ledger.subjects | Sort-Object subject_id)) {
        if ($Target -in @($subject.target_bindings.target)) {
          [ordered]@{subject_id=[string]$subject.subject_id;safe_choice=[string]$subject.implementation.preferred_safe_choice}
        }
      }
    )
  }
  return New-MIR4SupportBundleV1 -Request $request -Ledger $Ledger -RepoRoot $RepoRoot
}

function New-MIR4CompatibilityFactoryPlanV1 {
  param([Parameter(Mandatory)]$SupportBundle,[Parameter(Mandatory)]$Ledger,[Parameter(Mandatory)][string]$RepoRoot,[AllowNull()]$SourceIdentity=$null)
  $repo = Get-MIR4W07RepoRoot $RepoRoot
  Import-MIR4W07CanonicalSupport -RepoRoot $repo
  $authority = Get-MIR4InspectorCompatibilityAuthority -RepoRoot $repo
  Test-MIR4CompatibilitySubjectLedger -Ledger $Ledger -RepoRoot $repo | Out-Null
  Test-MIR4W07ForbiddenValue -Value $SupportBundle -Forbidden @($authority.forbidden_import_fields)
  if ([int]$SupportBundle.schema -ne 1 -or [string]$SupportBundle.kind -cne 'MIR4SupportBundleV1' -or
      [string]$SupportBundle.target -cnotmatch '^f[0-9]{3}$' -or @($SupportBundle.subjects).Count -lt 1 -or
      @($SupportBundle.subjects).Count -gt 10 -or [bool]$SupportBundle.claim_eligible -or [bool]$SupportBundle.arbitrary_code -or
      [bool]$SupportBundle.package_visible -or [string]$SupportBundle.source_ledger_digest -cne [string]$Ledger.digest -or
      [string]$SupportBundle.digest -cne (Get-MIR4ModuleDigest $SupportBundle)) { throw '[mir4-w07-support-bundle]' }
  $priority = @($authority.safe_choice_priority | ForEach-Object { [string]$_ })
  $seen = @{}
  $rows = @(
    foreach ($selection in @($SupportBundle.subjects | Sort-Object subject_id)) {
      $id = [string]$selection.subject_id
      if ($seen.ContainsKey($id)) { throw "[mir4-w07-factory-duplicate-subject] $id" }; $seen[$id] = $true
      $subject = @($Ledger.subjects | Where-Object subject_id -eq $id)
      if ($subject.Count -ne 1) { throw "[mir4-w07-factory-subject] $id" }
      $subject = $subject[0]
      if ([string]$SupportBundle.target -notin @($subject.target_bindings.target)) { throw "[mir4-w07-factory-portability] $id" }
      $selected = [string]$selection.safe_choice
      $selectedIndex = [Array]::IndexOf($priority,$selected)
      $preferred = [string]$subject.implementation.preferred_safe_choice
      if ($selectedIndex -lt 0 -or $selected -cne $preferred) { throw "[mir4-w07-factory-unsafe-choice] ${id}:$selected" }
      $choicePath = @(
        for ($i=0; $i -lt $priority.Count; $i++) {
          [ordered]@{
            choice=$priority[$i]
            state=$(if($i -lt $selectedIndex){'rejected-with-reason'}elseif($i -eq $selectedIndex){'selected'}else{'not-considered'})
            reason=$(if($i -lt $selectedIndex){'The subject ledger does not contain the independently complete authority and evidence required for this higher-priority option.'}elseif($i -eq $selectedIndex){'Selected by the governed subject assessment.'}else{'A lower-priority fallback is not evaluated after a safe governed choice is selected.'})
          }
        }
      )
      $disposition = if ([string]$subject.availability.state -ceq 'extension-required') {'RequireExtension'} elseif ([string]$subject.proof.state -ceq 'review-required/no-governed-exact-archive-closure') {'RequestReview'} else {'Preserve'}
      $targetBinding = @($subject.target_bindings | Where-Object target -eq ([string]$SupportBundle.target))[0]
      [ordered]@{
        subject_id=$id;selected_choice=$selected;choice_path=$choicePath;terminal_disposition=$disposition
        target=[string]$SupportBundle.target;provider_identity_digest=[string]$targetBinding.provider_identity_digest
        claim_eligible=$false;automatic_mutation=$false;executable_operations=@();evidence_state=[string]$subject.proof.state
      }
    }
  )
  $record = [pscustomobject][ordered]@{
    schema=1;kind='MIR4CompatibilityFactoryPlanV1';programme_id=[string]$authority.programme_id;source_identity=$SourceIdentity;maturity='developer-preview'
    support_bundle_digest=[string]$SupportBundle.digest;subject_ledger_digest=[string]$Ledger.digest;target=[string]$SupportBundle.target
    pipeline=@($authority.factory_pipeline);priority=@($priority);subject_inventory_count=$rows.Count;plans=$rows
    portability_preview=[ordered]@{target=[string]$SupportBundle.target;all_subjects_target_bound=$true;cross_target_transfer_authorized=$false}
    explanation=[ordered]@{mode='data-only';arbitrary_code_generation=$false;automatic_player_mutation=$false;public_claim=$false;notes=@('Every selected fallback retains the higher-priority rejection reasons.','The ZIP is a package-excluded evidence/data bundle, not a Factorio mod or executable adapter.')}
    zip_contract=[ordered]@{allowlist=@($authority.factory_zip_allowlist);forbidden_extensions=@($authority.factory_zip_forbidden_extensions);executable_content=$false}
    passed=$true;package_visible=$false;public_release_proof=$false;player_mutation_authorized=$false;digest=''
  }
  Add-MIR4ModuleDigest $record | Out-Null
  Test-MIR4CompatibilityFactoryPlanV1 -Plan $record -RepoRoot $repo | Out-Null
  return $record
}

function Test-MIR4CompatibilityFactoryPlanV1 {
  param([Parameter(Mandatory)]$Plan,[Parameter(Mandatory)][string]$RepoRoot)
  $authority = Get-MIR4InspectorCompatibilityAuthority -RepoRoot $RepoRoot
  Test-MIR4W07ForbiddenValue -Value $Plan -Forbidden @($authority.forbidden_import_fields)
  if ([int]$Plan.schema -ne 1 -or [string]$Plan.kind -cne 'MIR4CompatibilityFactoryPlanV1' -or
      [string]$Plan.maturity -cne 'developer-preview' -or -not [bool]$Plan.passed -or [bool]$Plan.package_visible -or
      [bool]$Plan.public_release_proof -or [bool]$Plan.player_mutation_authorized -or [bool]$Plan.explanation.arbitrary_code_generation -or
      [bool]$Plan.explanation.automatic_player_mutation -or [bool]$Plan.explanation.public_claim -or
      (@($Plan.pipeline) -join '|') -cne (@($authority.factory_pipeline) -join '|') -or
      (@($Plan.priority) -join '|') -cne (@($authority.safe_choice_priority) -join '|') -or
      @($Plan.plans).Count -ne [int]$Plan.subject_inventory_count) { throw '[mir4-w07-factory-plan-header]' }
  foreach ($row in @($Plan.plans)) {
    $selectedIndex = [Array]::IndexOf(@($Plan.priority),[string]$row.selected_choice)
    if ($selectedIndex -lt 0 -or @($row.choice_path).Count -ne 7 -or @($row.executable_operations).Count -ne 0 -or
        [bool]$row.claim_eligible -or [bool]$row.automatic_mutation -or [string]$row.provider_identity_digest -cnotmatch '^sha256:[0-9a-f]{64}$') {
      throw "[mir4-w07-factory-plan-row] $($row.subject_id)"
    }
    for ($i=0; $i -lt $selectedIndex; $i++) {
      if ([string]$row.choice_path[$i].state -cne 'rejected-with-reason' -or [string]::IsNullOrWhiteSpace([string]$row.choice_path[$i].reason)) {
        throw "[mir4-w07-factory-priority-reason] $($row.subject_id)"
      }
    }
  }
  Import-MIR4W07CanonicalSupport -RepoRoot $RepoRoot
  if ([string]$Plan.digest -cne (Get-MIR4ModuleDigest $Plan)) { throw '[mir4-w07-factory-plan-digest]' }
  return $true
}

function Export-MIR4CompatibilityFactoryDataBundleV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$SupportBundle,[Parameter(Mandatory)]$Ledger,
    [Parameter(Mandatory)]$Plan,[Parameter(Mandatory)][string]$OutputPath
  )
  $repo = Get-MIR4W07RepoRoot $RepoRoot
  Import-MIR4W07CanonicalSupport -RepoRoot $repo
  $authority = Get-MIR4InspectorCompatibilityAuthority -RepoRoot $repo
  Test-MIR4CompatibilityFactoryPlanV1 -Plan $Plan -RepoRoot $repo | Out-Null
  $full = [IO.Path]::GetFullPath((Join-Path $repo $OutputPath))
  $allowedRoot = [IO.Path]::GetFullPath((Join-Path $repo 'build/mir4')).TrimEnd('\') + '\'
  if (-not ($full.StartsWith($allowedRoot,[StringComparison]::OrdinalIgnoreCase))) { throw "[mir4-w07-factory-output-boundary] $full" }
  $parent = Split-Path -Parent $full
  if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
  $portability = [pscustomobject][ordered]@{schema=1;kind='MIR4CompatibilityPortabilityPreviewV1';target=[string]$Plan.target;subjects=@($Plan.plans | ForEach-Object {[ordered]@{subject_id=[string]$_.subject_id;provider_identity_digest=[string]$_.provider_identity_digest;cross_target_transfer_authorized=$false}});digest=''}; Add-MIR4ModuleDigest $portability | Out-Null
  $explanation = [pscustomobject][ordered]@{schema=1;kind='MIR4CompatibilityExplanationV1';plan_digest=[string]$Plan.digest;subject_explanations=@($Plan.plans | ForEach-Object {[ordered]@{subject_id=[string]$_.subject_id;selected_choice=[string]$_.selected_choice;terminal_disposition=[string]$_.terminal_disposition;higher_priority_rejections=@($_.choice_path | Where-Object state -eq 'rejected-with-reason')}});arbitrary_code=$false;digest=''}; Add-MIR4ModuleDigest $explanation | Out-Null
  $provenance = Test-MIR4CompatibilityProvenance -Ledger $Ledger -RepoRoot $repo
  if ([string]$provenance.status -cne 'current') { throw '[mir4-w07-factory-stale-provenance]' }
  $manifest = [pscustomobject][ordered]@{
    schema=1;kind='MIR4CompatibilityFactoryDataBundleManifestV1';programme_id=[string]$authority.programme_id;maturity='developer-preview'
    support_bundle_digest=[string]$SupportBundle.digest;subject_ledger_digest=[string]$Ledger.digest;plan_digest=[string]$Plan.digest
    entries=@($authority.factory_zip_allowlist);executable_content=$false;factorio_mod=$false;package_visible=$false;public_support_claim=$false;digest=''
  }; Add-MIR4ModuleDigest $manifest | Out-Null
  $values = [ordered]@{
    'manifest.json'=$manifest
    'support-bundle.json'=$SupportBundle
    'subject-ledger.json'=$Ledger
    'portability-preview.json'=$portability
    'plan.json'=$Plan
    'explanation.json'=$explanation
    'provenance.json'=$provenance
  }
  $textEntries = [ordered]@{}
  foreach ($entry in $values.GetEnumerator()) { $textEntries[$entry.Key] = (ConvertTo-MIR4ModuleCanonicalJson $entry.Value) + "`n" }
  foreach ($schema in @('mir4-compatibility-subject-ledger-v1.schema.json','mir4-compatibility-factory-plan-v1.schema.json')) {
    $textEntries["schemas/$schema"] = (Get-Content -Raw -LiteralPath (Join-Path $repo "spec/schemas/$schema")).Replace("`r`n","`n")
  }
  if ((@($textEntries.Keys | Sort-Object) -join '|') -cne (@($authority.factory_zip_allowlist | Sort-Object) -join '|')) { throw '[mir4-w07-factory-entry-set]' }
  Add-Type -AssemblyName System.IO.Compression
  $stream = [IO.File]::Open($full,[IO.FileMode]::Create,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  try {
    $zip = [IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
    try {
      foreach ($name in @($textEntries.Keys | Sort-Object -CaseSensitive)) {
        if ([IO.Path]::GetExtension([string]$name) -cin @($authority.factory_zip_forbidden_extensions)) { throw "[mir4-w07-factory-executable-entry] $name" }
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes([string]$textEntries[$name])
        $entry = $zip.CreateEntry([string]$name,[IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = [DateTimeOffset]::new(1980,1,1,0,0,0,[TimeSpan]::Zero)
        $entryStream = $entry.Open(); try { $entryStream.Write($bytes,0,$bytes.Length) } finally { $entryStream.Dispose() }
      }
    } finally { $zip.Dispose() }
  } finally { $stream.Dispose() }
  $result = Test-MIR4CompatibilityFactoryDataBundleV1 -RepoRoot $repo -ZipPath $full
  return [pscustomobject][ordered]@{path=[IO.Path]::GetRelativePath($repo,$full).Replace('\','/');bytes=(Get-Item -LiteralPath $full).Length;sha256=(Get-MIR4W07FileSha256 $full);entry_count=[int]$result.entry_count;status='passed-data-only-package-excluded'}
}

function Test-MIR4CompatibilityFactoryDataBundleV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$ZipPath)
  $repo = Get-MIR4W07RepoRoot $RepoRoot
  $authority = Get-MIR4InspectorCompatibilityAuthority -RepoRoot $repo
  $path = if ([IO.Path]::IsPathRooted($ZipPath)) { $ZipPath } else { Join-Path $repo $ZipPath }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [IO.Compression.ZipFile]::OpenRead($path)
  try {
    $files = @($zip.Entries | Where-Object { -not $_.FullName.EndsWith('/') })
    $names = @($files.FullName | Sort-Object)
    if (($names -join '|') -cne (@($authority.factory_zip_allowlist | Sort-Object) -join '|')) { throw '[mir4-w07-factory-zip-entry-set]' }
    foreach ($entry in $files) {
      if ([IO.Path]::GetExtension([string]$entry.FullName) -cin @($authority.factory_zip_forbidden_extensions) -or
          [string]$entry.FullName -match '(?i)(^|/)(?:data|control)(?:-updates|-final-fixes)?\.lua$|(^|/)migrations?/|(^|/)prototypes?/') {
        throw "[mir4-w07-factory-zip-executable] $($entry.FullName)"
      }
      if ($entry.FullName.EndsWith('.json')) {
        $reader = [IO.StreamReader]::new($entry.Open()); try { $value = $reader.ReadToEnd() | ConvertFrom-Json -Depth 100 } finally { $reader.Dispose() }
        Test-MIR4W07ForbiddenValue -Value $value -Forbidden @($authority.forbidden_import_fields)
      }
    }
    return [pscustomobject][ordered]@{status='passed';entry_count=$files.Count;executable_entries=0;allowlist_exact=$true}
  } finally { $zip.Dispose() }
}
