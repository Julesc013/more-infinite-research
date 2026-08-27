. (Join-Path $PSScriptRoot '../../mir/domain/canonicalization/CanonicalJsonV1.ps1')

$script:MIR4EnvironmentPrivateFields = @(
  'access_token','api_key','authorization','cookie','credential','email','home','hostname',
  'machine','password','path','private_key','secret','token','user','username'
)

function Get-MIR4EnvironmentDigest {
  param([Parameter(Mandatory)]$Value)
  Get-MIR4CanonicalDigestV1 -Value $Value -Domain (Get-MIR4RecordDigestDomainV1 -Value $Value) -OmitTopLevelDigest
}

function Add-MIR4EnvironmentDigest {
  param([Parameter(Mandatory)]$Value)
  $Value.digest = Get-MIR4EnvironmentDigest $Value
  $Value
}

function Test-MIR4EnvironmentPrivateValue {
  param([Parameter(Mandatory)][AllowNull()]$Value,[string]$Location='$')
  if ($null -eq $Value) { return $true }
  if ($Value -is [Collections.IDictionary]) {
    foreach ($key in $Value.Keys) {
      $name = ([string]$key).ToLowerInvariant()
      if ($name -in $script:MIR4EnvironmentPrivateFields -or $name -match '(?:^|_)(?:token|secret|password|credential|private_key|username|hostname|machine|home|path)(?:$|_)') {
        throw "[mir4-environment-private-field] $Location.$key"
      }
      Test-MIR4EnvironmentPrivateValue -Value $Value[$key] -Location "$Location.$key" | Out-Null
    }
  } elseif ($Value -is [pscustomobject]) {
    foreach ($property in $Value.PSObject.Properties) {
      $name = ([string]$property.Name).ToLowerInvariant()
      if ($name -in $script:MIR4EnvironmentPrivateFields -or $name -match '(?:^|_)(?:token|secret|password|credential|private_key|username|hostname|machine|home|path)(?:$|_)') {
        throw "[mir4-environment-private-field] $Location.$($property.Name)"
      }
      Test-MIR4EnvironmentPrivateValue -Value $property.Value -Location "$Location.$($property.Name)" | Out-Null
    }
  } elseif ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
    $index = 0
    foreach ($item in $Value) {
      Test-MIR4EnvironmentPrivateValue -Value $item -Location "$Location[$index]" | Out-Null
      $index++
    }
  } elseif ($Value -is [string] -and ($Value -match '(?i)^[A-Z]:[\\/](?:Users|Documents and Settings)[\\/]' -or $Value -match '(?i)^/(?:home|Users)/[^/\s]+' -or $Value -match '(?i)\b(?:token|secret|password|api[_-]?key)\s*[=:]\s*[^\s,;]+')) {
    throw "[mir4-environment-private-value] $Location"
  }
  $true
}

function ConvertTo-MIR4PortableSha256 {
  param([Parameter(Mandatory)][string]$Value,[Parameter(Mandatory)][string]$Diagnostic)
  if ($Value.Trim() -match '^(?i:sha256:)?([0-9a-f]{64})$') { return 'sha256:' + $Matches[1].ToLowerInvariant() }
  throw "[$Diagnostic] $Value"
}

function ConvertTo-MIR4EnvironmentRows {
  param([AllowEmptyCollection()]$Rows,[Parameter(Mandatory)][string]$IdField,[Parameter(Mandatory)][string]$Diagnostic)
  $byId = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
  foreach ($row in @($Rows)) {
    $id = [string]$row.$IdField
    if ([string]::IsNullOrWhiteSpace($id) -or $byId.ContainsKey($id)) { throw "[$Diagnostic] $id" }
    $byId.Add($id,$row)
  }
  [string[]]$ids = @($byId.Keys)
  [Array]::Sort($ids,[StringComparer]::Ordinal)
  $result = @(
    foreach ($id in $ids) {
      $row = $byId[$id]
      $copy = [ordered]@{}
      foreach ($property in @($row.PSObject.Properties | Sort-Object Name -CaseSensitive)) { $copy[$property.Name] = $property.Value }
      [pscustomobject]$copy
    }
  )
  @($result)
}

function New-MIR4EnvironmentLockV1 {
  param([Parameter(Mandatory)]$Manifest,[string]$Capture='authority-projected')
  Test-MIR4EnvironmentPrivateValue -Value $Manifest | Out-Null
  if ([string]$Manifest.target -cnotmatch '^f[0-9]{3}$' -or
      [string]$Manifest.engine.version -cnotmatch '^[0-9]+(?:\.[0-9]+){1,2}(?:-[a-z0-9.-]+)?$' -or
      [string]$Manifest.mir.version -cnotmatch '^4\.0\.[0-9]{5}$') { throw '[mir4-environment-lock-identity]' }
  $engine = [ordered]@{
    version=[string]$Manifest.engine.version
    executable_sha256=ConvertTo-MIR4PortableSha256 -Value ([string]$Manifest.engine.executable_sha256) -Diagnostic 'mir4-environment-engine-digest'
  }
  $mir = [ordered]@{
    version=[string]$Manifest.mir.version
    package_sha256=ConvertTo-MIR4PortableSha256 -Value ([string]$Manifest.mir.package_sha256) -Diagnostic 'mir4-environment-package-digest'
    source_commit=[string]$Manifest.mir.source_commit
    source_tree=[string]$Manifest.mir.source_tree
  }
  if ($mir.source_commit -cnotmatch '^[0-9a-f]{40}$' -or $mir.source_tree -cnotmatch '^[0-9a-f]{40}$') { throw '[mir4-environment-source-identity]' }
  $mods = @(ConvertTo-MIR4EnvironmentRows -Rows @($Manifest.mods) -IdField 'name' -Diagnostic 'mir4-environment-mod-id')
  foreach ($mod in $mods) {
    if ([string]$mod.name -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,99}$' -or [string]$mod.version -cnotmatch '^[0-9]+(?:\.[0-9]+){1,3}(?:-[a-z0-9.-]+)?$') { throw "[mir4-environment-mod] $($mod.name)" }
    $mod.sha256 = ConvertTo-MIR4PortableSha256 -Value ([string]$mod.sha256) -Diagnostic 'mir4-environment-mod-digest'
  }
  $settings = @(ConvertTo-MIR4EnvironmentRows -Rows @($Manifest.startup_settings) -IdField 'name' -Diagnostic 'mir4-environment-setting-id')
  $extensions = @(ConvertTo-MIR4EnvironmentRows -Rows @($Manifest.extensions) -IdField 'extension_id' -Diagnostic 'mir4-environment-extension-id')
  foreach ($extension in $extensions) {
    $extension.digest = ConvertTo-MIR4PortableSha256 -Value ([string]$extension.digest) -Diagnostic 'mir4-environment-extension-digest'
  }
  $record = [pscustomobject][ordered]@{
    schema=1;kind='MIR4EnvironmentLockV1';maturity='developer-preview';capture=$Capture;target=[string]$Manifest.target
    engine=$engine;mir=$mir;mods=$mods;startup_settings=$settings;extensions=$extensions
    contracts=@(Get-MIR4OrdinalSortedUniqueV1 -Values @($Manifest.contracts | ForEach-Object { [string]$_ }))
    canonicalization='mir-canonical-json/1';portable=$true;privacy_safe=$true;package_visible=$false
    player_mutation_authorized=$false;prototype_write_authorized=$false;public_support_authorized=$false;release_authority=$false;digest=''
  }
  Add-MIR4EnvironmentDigest $record | Out-Null
  Test-MIR4EnvironmentLockV1 -Lock $record | Out-Null
  $record
}

function Test-MIR4EnvironmentLockV1 {
  param([Parameter(Mandatory)]$Lock)
  Test-MIR4EnvironmentPrivateValue -Value $Lock | Out-Null
  if ([int]$Lock.schema -ne 1 -or [string]$Lock.kind -cne 'MIR4EnvironmentLockV1' -or
      [string]$Lock.maturity -cne 'developer-preview' -or [string]$Lock.target -cnotmatch '^f[0-9]{3}$' -or
      [string]$Lock.canonicalization -cne 'mir-canonical-json/1' -or -not [bool]$Lock.portable -or -not [bool]$Lock.privacy_safe -or
      [bool]$Lock.package_visible -or [bool]$Lock.player_mutation_authorized -or [bool]$Lock.prototype_write_authorized -or
      [bool]$Lock.public_support_authorized -or [bool]$Lock.release_authority) { throw '[mir4-environment-lock-boundary]' }
  Test-MIR4OrdinalSortedUniqueV1 -Values @($Lock.contracts) -Diagnostic 'mir4-environment-contract-order' | Out-Null
  foreach ($pair in @(@($Lock.mods,'name'),@($Lock.startup_settings,'name'),@($Lock.extensions,'extension_id'))) {
    $values = @($pair[0] | ForEach-Object { [string]$_.$($pair[1]) })
    Test-MIR4OrdinalSortedUniqueV1 -Values $values -Diagnostic 'mir4-environment-row-order' | Out-Null
  }
  if ([string]$Lock.digest -cne (Get-MIR4EnvironmentDigest $Lock)) { throw '[mir4-environment-lock-digest]' }
  $true
}

function New-MIR4EnvironmentDiffV1 {
  param([Parameter(Mandatory)]$Base,[Parameter(Mandatory)]$Candidate)
  Test-MIR4EnvironmentLockV1 $Base | Out-Null
  Test-MIR4EnvironmentLockV1 $Candidate | Out-Null
  $changes = @()
  foreach ($name in @('target','engine','mir','mods','startup_settings','extensions','contracts')) {
    $beforeCanonical = ConvertTo-MIR4CanonicalJsonV1 ([ordered]@{value=$Base.$name})
    $afterCanonical = ConvertTo-MIR4CanonicalJsonV1 ([ordered]@{value=$Candidate.$name})
    if ($beforeCanonical -cne $afterCanonical) {
      $changes += [ordered]@{path="/$name";category=$name;before=$Base.$name;after=$Candidate.$name}
    }
  }
  $record = [pscustomobject][ordered]@{
    schema=1;kind='MIR4EnvironmentDiffV1';maturity='developer-preview';base_digest=[string]$Base.digest;candidate_digest=[string]$Candidate.digest
    status=$(if($changes.Count){'changed'}else{'identical'});change_count=$changes.Count;changes=@($changes)
    summary=[ordered]@{
      identity_changed=[bool](@($changes | Where-Object category -in @('target','engine','mir')).Count)
      mods_changed=[bool](@($changes | Where-Object category -eq 'mods').Count)
      settings_changed=[bool](@($changes | Where-Object category -eq 'startup_settings').Count)
      extensions_changed=[bool](@($changes | Where-Object category -eq 'extensions').Count)
      contracts_changed=[bool](@($changes | Where-Object category -eq 'contracts').Count)
    }
    canonicalization='mir-canonical-json/1';portable=$true;privacy_safe=$true;package_visible=$false
    player_mutation_authorized=$false;prototype_write_authorized=$false;public_support_authorized=$false;release_authority=$false;digest=''
  }
  Add-MIR4EnvironmentDigest $record | Out-Null
  Test-MIR4EnvironmentDiffV1 $record | Out-Null
  $record
}

function Test-MIR4EnvironmentDiffV1 {
  param([Parameter(Mandatory)]$Diff)
  if ([int]$Diff.schema -ne 1 -or [string]$Diff.kind -cne 'MIR4EnvironmentDiffV1' -or
      [string]$Diff.status -notin @('identical','changed') -or [int]$Diff.change_count -ne @($Diff.changes).Count -or
      [bool]$Diff.package_visible -or [bool]$Diff.player_mutation_authorized -or [bool]$Diff.prototype_write_authorized -or
      [bool]$Diff.public_support_authorized -or [bool]$Diff.release_authority -or
      [string]$Diff.digest -cne (Get-MIR4EnvironmentDigest $Diff)) { throw '[mir4-environment-diff]' }
  $true
}

function ConvertTo-MIR4RedactedDiagnosticV1 {
  param([Parameter(Mandatory)]$Diagnostic)
  $message = [string]$Diagnostic.message
  $message = [regex]::Replace($message,'(?i)[A-Z]:[\\/](?:Users|Documents and Settings)[\\/][^\\/\s]+','<user-home>')
  $message = [regex]::Replace($message,'(?i)/(?:home|Users)/[^/\s]+','<user-home>')
  $message = [regex]::Replace($message,'(?i)\b(token|secret|password|api[_-]?key)\s*[=:]\s*[^\s,;]+','$1=<redacted>')
  [ordered]@{code=[string]$Diagnostic.code;severity=$(if($Diagnostic.severity){[string]$Diagnostic.severity}else{'error'});message=$message}
}

function Get-MIR4EvidenceClosureV1 {
  param([Parameter(Mandatory)]$Evidence,[AllowEmptyCollection()][string[]]$Roots)
  $byId = @{}
  foreach ($item in @($Evidence)) {
    $id = [string]$item.id
    if ([string]::IsNullOrWhiteSpace($id) -or $byId.ContainsKey($id)) { throw "[mir4-support-evidence-id] $id" }
    $byId[$id] = $item
  }
  $needed = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  $queue = [Collections.Generic.Queue[string]]::new()
  foreach ($root in @($Roots)) { if (-not $byId.ContainsKey($root)) { throw "[mir4-support-evidence-missing] $root" }; $queue.Enqueue($root) }
  while ($queue.Count) {
    $id = $queue.Dequeue()
    if (-not $needed.Add($id)) { continue }
    foreach ($dependency in @($byId[$id].dependencies)) {
      $dep = [string]$dependency
      if (-not $byId.ContainsKey($dep)) { throw "[mir4-support-evidence-dependency] $id -> $dep" }
      $queue.Enqueue($dep)
    }
  }
  @($Evidence | Where-Object { $needed.Contains([string]$_.id) } | Sort-Object id -CaseSensitive)
}

function Get-MIR4ReproducerSignatureV1 {
  param([Parameter(Mandatory)]$EnvironmentLock,[Parameter(Mandatory)]$Evidence,[AllowEmptyCollection()][string[]]$Roots)
  $closure = @(Get-MIR4EvidenceClosureV1 -Evidence $Evidence -Roots $Roots)
  $material = [ordered]@{
    environment_lock_digest=[string]$EnvironmentLock.digest;roots=@($Roots | Sort-Object -CaseSensitive)
    witnesses=@($closure | ForEach-Object { [ordered]@{id=[string]$_.id;kind=[string]$_.kind;summary=[string]$_.summary;dependencies=@($_.dependencies | Sort-Object -CaseSensitive)} })
  }
  Get-MIR4CanonicalDigestV1 -Value $material -Domain 'mir4:environment-reproducer-v1'
}

function New-MIR4EnvironmentSupportBundleV1 {
  param(
    [Parameter(Mandatory)]$EnvironmentLock,[string]$BundleId='org.more-infinite-research.environment.reference',
    [AllowEmptyCollection()]$Subjects=@(),[AllowNull()]$SourceLedgerDigest=$null,
    [AllowEmptyCollection()]$EvidenceItems=@(),[AllowEmptyCollection()]$Diagnostics=@()
  )
  Test-MIR4EnvironmentLockV1 $EnvironmentLock | Out-Null
  $evidence = @(ConvertTo-MIR4EnvironmentRows -Rows @($EvidenceItems) -IdField 'id' -Diagnostic 'mir4-support-evidence-id')
  foreach ($item in $evidence) {
    if ($null -eq $item.PSObject.Properties['dependencies']) { $item | Add-Member -NotePropertyName dependencies -NotePropertyValue @() }
    if ($null -eq $item.PSObject.Properties['required_by_reproducer']) { $item | Add-Member -NotePropertyName required_by_reproducer -NotePropertyValue $false }
    $item.dependencies = @($item.dependencies | ForEach-Object { [string]$_ } | Sort-Object -CaseSensitive)
  }
  $roots = @($evidence | Where-Object { [bool]$_.required_by_reproducer } | ForEach-Object { [string]$_.id } | Sort-Object -CaseSensitive)
  [void](Get-MIR4EvidenceClosureV1 -Evidence $evidence -Roots $roots)
  $redacted = @($Diagnostics | ForEach-Object { ConvertTo-MIR4RedactedDiagnosticV1 $_ })
  $redactedCount = 0
  for($index=0;$index-lt$redacted.Count;$index++){if([string]$redacted[$index].message-cne[string]$Diagnostics[$index].message){$redactedCount++}}
  $record = [pscustomobject][ordered]@{
    schema=1;kind='MIR4SupportBundleV1';bundle_id=$BundleId;target=[string]$EnvironmentLock.target
    subjects=@($Subjects);source_ledger_digest=$SourceLedgerDigest;environment_lock=$EnvironmentLock;environment_lock_digest=[string]$EnvironmentLock.digest
    evidence_items=$evidence;diagnostics=$redacted
    redaction=[ordered]@{policy='mir4-support-redaction/1';messages_redacted=$redactedCount;raw_private_values_retained=$false}
    reproducer=[ordered]@{required_evidence_ids=$roots;signature=(Get-MIR4ReproducerSignatureV1 -EnvironmentLock $EnvironmentLock -Evidence $evidence -Roots $roots);preserved=$true}
    minimized=$false;source_bundle_digest=$null
    minimization=[ordered]@{strategy='none';original_evidence_count=$evidence.Count;retained_evidence_count=$evidence.Count;removed_evidence_count=0}
    maturity='developer-preview';synthetic=$true;claim_eligible=$false;arbitrary_code=$false;executable_content=$false
    network_access_authorized=$false;package_visible=$false;player_mutation_authorized=$false;prototype_write_authorized=$false
    public_support_authorized=$false;release_authority=$false;canonicalization='mir-canonical-json/1';digest=''
  }
  Add-MIR4EnvironmentDigest $record | Out-Null
  Test-MIR4SupportBundleV1 $record | Out-Null
  $record
}

function Test-MIR4SupportBundleV1 {
  param([Parameter(Mandatory)]$Bundle)
  Test-MIR4EnvironmentLockV1 $Bundle.environment_lock | Out-Null
  if ([int]$Bundle.schema -ne 1 -or [string]$Bundle.kind -cne 'MIR4SupportBundleV1' -or
      [string]$Bundle.target -cne [string]$Bundle.environment_lock.target -or
      [string]$Bundle.environment_lock_digest -cne [string]$Bundle.environment_lock.digest -or
      [bool]$Bundle.claim_eligible -or [bool]$Bundle.arbitrary_code -or [bool]$Bundle.executable_content -or
      [bool]$Bundle.network_access_authorized -or [bool]$Bundle.package_visible -or [bool]$Bundle.player_mutation_authorized -or
      [bool]$Bundle.prototype_write_authorized -or [bool]$Bundle.public_support_authorized -or [bool]$Bundle.release_authority) { throw '[mir4-support-bundle-boundary]' }
  $roots = @($Bundle.reproducer.required_evidence_ids | ForEach-Object { [string]$_ })
  $signature = Get-MIR4ReproducerSignatureV1 -EnvironmentLock $Bundle.environment_lock -Evidence @($Bundle.evidence_items) -Roots $roots
  if ([string]$Bundle.reproducer.signature -cne $signature -or -not [bool]$Bundle.reproducer.preserved -or
      [bool]$Bundle.redaction.raw_private_values_retained -or [string]$Bundle.digest -cne (Get-MIR4EnvironmentDigest $Bundle)) { throw '[mir4-support-bundle-integrity]' }
  foreach ($diagnostic in @($Bundle.diagnostics)) {
    if ([string]$diagnostic.message -match '(?i)[A-Z]:[\\/](?:Users|Documents and Settings)[\\/]|/(?:home|Users)/[^/\s]+|(?:token|secret|password|api[_-]?key)\s*[=:]\s*(?!<redacted>)') { throw '[mir4-support-bundle-redaction]' }
  }
  $true
}

function Minimize-MIR4SupportBundleV1 {
  param([Parameter(Mandatory)]$Bundle)
  Test-MIR4SupportBundleV1 $Bundle | Out-Null
  $roots = @($Bundle.reproducer.required_evidence_ids | ForEach-Object { [string]$_ })
  $retained = @(Get-MIR4EvidenceClosureV1 -Evidence @($Bundle.evidence_items) -Roots $roots)
  $record = New-MIR4EnvironmentSupportBundleV1 -EnvironmentLock $Bundle.environment_lock -BundleId ([string]$Bundle.bundle_id) -Subjects @($Bundle.subjects) -SourceLedgerDigest $Bundle.source_ledger_digest -EvidenceItems $retained -Diagnostics @($Bundle.diagnostics)
  $record.minimized = $true
  $record.source_bundle_digest = [string]$Bundle.digest
  $record.minimization = [ordered]@{strategy='required-reproducer-transitive-closure';original_evidence_count=@($Bundle.evidence_items).Count;retained_evidence_count=$retained.Count;removed_evidence_count=@($Bundle.evidence_items).Count-$retained.Count}
  $record.reproducer.signature = [string]$Bundle.reproducer.signature
  Add-MIR4EnvironmentDigest $record | Out-Null
  Test-MIR4SupportBundleV1 $record | Out-Null
  $record
}

function New-MIR4ReferenceEnvironmentEvidenceV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $plan = Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Bootstrap-Local-Candidate-PlanV3.json') | ConvertFrom-Json -Depth 100
  $locks = [ordered]@{}
  foreach ($target in @($plan.targets | Where-Object target_key -in @('f210','f200'))) {
    $manifest = [pscustomobject][ordered]@{
      target=[string]$target.target_key
      engine=[ordered]@{version=[string]$target.engine_lock.version;executable_sha256=[string]$target.engine_lock.executable_sha256}
      mir=[ordered]@{version=[string]$target.distribution_version;package_sha256=[string]$target.predecessor.archive_sha256;source_commit=[string]$target.source.candidate_commit;source_tree=[string]$target.source.source_tree}
      mods=@();startup_settings=@();extensions=@();contracts=@('mir4-environment-lock/1','mir4-support-bundle/1')
    }
    $locks[[string]$target.target_key] = New-MIR4EnvironmentLockV1 $manifest
  }
  $diff = New-MIR4EnvironmentDiffV1 -Base $locks.f210 -Candidate $locks.f200
  $evidence = @(
    [pscustomobject][ordered]@{id='authority.bootstrap-plan';kind='authority';summary='Exact bootstrap target identity source.';dependencies=@();required_by_reproducer=$false}
    [pscustomobject][ordered]@{id='witness.f210-environment';kind='witness';summary='F210 exact environment lock witness.';dependencies=@('authority.bootstrap-plan');required_by_reproducer=$true}
    [pscustomobject][ordered]@{id='context.nonessential';kind='context';summary='Removable non-reproducer context.';dependencies=@();required_by_reproducer=$false}
  )
  $bundle = New-MIR4EnvironmentSupportBundleV1 -EnvironmentLock $locks.f210 -EvidenceItems $evidence -Diagnostics @([pscustomobject][ordered]@{code='mir4-support-reference';severity='info';message='Authority-projected reference evidence contains no private host state.'})
  [pscustomobject][ordered]@{f210=$locks.f210;f200=$locks.f200;diff=$diff;bundle=$bundle;minimized=(Minimize-MIR4SupportBundleV1 $bundle)}
}
