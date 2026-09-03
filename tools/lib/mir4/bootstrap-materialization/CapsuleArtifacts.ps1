function Assert-MIR4BootstrapCapsuleArtifact {
  param(
    [Parameter(Mandatory)][string]$CapsulePath,
    [Parameter(Mandatory)][string]$EnvelopePath,
    [Parameter(Mandatory)][string]$RunnerPath,
    [Parameter(Mandatory)][string]$SchemaRoot
  )

  $envelopeText = Get-Content -Raw -LiteralPath $EnvelopePath
  if (-not ($envelopeText | Test-Json -SchemaFile (Join-Path $SchemaRoot 'mir4-bootstrap-source-capsule.schema.json'))) {
    throw "MIR 4 source capsule envelope schema validation failed: $EnvelopePath"
  }
  $envelope = $envelopeText | ConvertFrom-Json -Depth 100 -DateKind String
  if (-not (Test-MIR4BootstrapRecordHash -Record $envelope)) { throw "MIR 4 source capsule envelope self-hash mismatch: $EnvelopePath" }
  $lane = [string]$envelope.lane
  if ($lane -cnotin @('emergency', 'local-playtest-shadow')) { throw 'MIR 4 source capsule has an unknown construction lane.' }
  $inventory = Get-MIR4ArchiveInventory -Path $CapsulePath
  if ([string]$inventory.root -cne 'mir4-source-capsule') { throw 'Unexpected MIR 4 source capsule archive root.' }
  foreach ($field in @('archive_sha256', 'content_sha256', 'bytes', 'entry_count')) {
    if ([string]$inventory.$field -cne [string]$envelope.capsule.$field) { throw "MIR 4 capsule $field differs from its envelope." }
  }
  $runnerIdentity = Get-MIR4RawFileIdentity -Path $RunnerPath
  if ([string]$runnerIdentity.sha256 -cne [string]$envelope.bootstrap_runner.sha256 -or
      [long]$runnerIdentity.bytes -ne [long]$envelope.bootstrap_runner.bytes) {
    throw 'Detached MIR 4 capsule runner differs from its envelope.'
  }

  $manifestText = Read-MIR4ArchiveText -Path $CapsulePath -RelativePath '.mir/capsule/manifest.json'
  if (-not ($manifestText | Test-Json -SchemaFile (Join-Path $SchemaRoot 'mir4-bootstrap-capsule-manifest.schema.json'))) {
    throw 'MIR 4 capsule-internal manifest schema validation failed.'
  }
  $manifest = $manifestText | ConvertFrom-Json -Depth 100 -DateKind String
  if (-not (Test-MIR4BootstrapRecordHash -Record $manifest)) { throw 'MIR 4 capsule-internal manifest self-hash mismatch.' }
  if ([string]$manifest.record_sha256 -cne [string]$envelope.closure.internal_manifest_record_sha256) {
    throw 'MIR 4 capsule internal-manifest binding differs from its envelope.'
  }
  if ([string]$manifest.lane -cne $lane -or
      [string]$manifest.target.target_key -cne [string]$envelope.target_key -or
      [string]$manifest.target.factorio_line -cne [string]$envelope.factorio_line -or
      [string]$manifest.target.distribution_version -cne [string]$envelope.distribution_version -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $manifest.target.source) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $envelope.source) -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $manifest.target.predecessor) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $envelope.predecessor)) {
    throw 'MIR 4 capsule internal target authority differs from its detached envelope.'
  }
  if ([int]$manifest.member_count -ne @($manifest.members).Count) { throw 'MIR 4 capsule member count is inconsistent.' }
  $inventoryMap = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
  foreach ($entry in @($inventory.entries)) { $inventoryMap.Add([string]$entry.path, $entry) }
  $expectedCount = @($manifest.members).Count + 1
  if ($inventoryMap.Count -ne $expectedCount -or -not $inventoryMap.ContainsKey('.mir/capsule/manifest.json')) {
    throw 'MIR 4 capsule membership is not exactly its manifest plus the non-recursive manifest record.'
  }
  $memberFields = [ordered]@{}
  $authorityFields = [ordered]@{}
  $lastPath = ''
  foreach ($member in @($manifest.members)) {
    $relative = [string]$member.path
    if (-not [string]::IsNullOrEmpty($lastPath) -and [StringComparer]::Ordinal.Compare($lastPath, $relative) -ge 0) {
      throw 'MIR 4 capsule manifest members are not unique and ordinally ordered.'
    }
    $lastPath = $relative
    if (-not $inventoryMap.ContainsKey($relative)) { throw "MIR 4 capsule manifest member is absent: $relative" }
    $entry = $inventoryMap[$relative]
    if ([long]$entry.raw_bytes -ne [long]$member.bytes -or [string]$entry.raw_sha256 -cne [string]$member.sha256) {
      throw "MIR 4 capsule manifest member identity differs: $relative"
    }
    $memberFields[$relative] = "$([string]$member.role)|$([long]$member.bytes)|$([string]$member.sha256)"
    if ([string]$member.role -ceq 'authority') { $authorityFields[$relative] = [string]$member.sha256 }
  }
  $payloadRoot = Get-MIR4DomainSha256 -Domain 'mir4.bootstrap.capsule-payload.v1' -Fields $memberFields
  $authorityRoot = Get-MIR4DomainSha256 -Domain 'mir4.bootstrap.capsule-authority.v1' -Fields $authorityFields
  $contentRoot = Get-MIR4DomainSha256 -Domain 'mir4.bootstrap.capsule-content.v1' -Fields ([ordered]@{
    payload_root_sha256 = $payloadRoot
    internal_manifest_record_sha256 = [string]$manifest.record_sha256
  })
  foreach ($row in @(
    @($payloadRoot, $manifest.payload_root_sha256, 'payload root'),
    @($payloadRoot, $envelope.closure.payload_root_sha256, 'envelope payload root'),
    @($authorityRoot, $manifest.authority_closure_root_sha256, 'authority closure root'),
    @($authorityRoot, $envelope.closure.authority_closure_root_sha256, 'envelope authority root'),
    @($contentRoot, $envelope.closure.capsule_content_root_sha256, 'capsule content root')
  )) {
    if ([string]$row[0] -cne [string]$row[1]) { throw "MIR 4 capsule $($row[2]) mismatch." }
  }
  foreach ($field in @('git_source_proof_record_sha256', 'toolchain_lock_record_sha256', 'canonical_builder_sha256', 'reconstruction_runner_sha256')) {
    if ([string]$manifest.$field -cne [string]$envelope.closure.$field) { throw "MIR 4 capsule manifest/envelope $field mismatch." }
  }
  foreach ($binding in @(
    [pscustomobject]@{ path = 'tools/commands/package/Build-MIRPackage.ps1'; field = 'canonical_builder_sha256' },
    [pscustomobject]@{ path = 'tools/commands/release/Invoke-MIR4BootstrapCapsule.ps1'; field = 'reconstruction_runner_sha256' }
  )) {
    $memberRows = @($manifest.members | Where-Object { [string]$_.path -ceq [string]$binding.path })
    if ($memberRows.Count -ne 1 -or [string]$memberRows[0].sha256 -cne [string]$manifest.($binding.field)) {
      throw "MIR 4 capsule executable closure does not bind $($binding.path)."
    }
  }
  foreach ($binding in @(
    [pscustomobject]@{ path = 'tools/lib/validation/PackageIdentity.ps1'; expected = [string]$envelope.package_membership.authority_sha256 },
    [pscustomobject]@{ path = 'tools/lib/mir4/BootstrapMaterialization.ps1'; expected = [string]$envelope.package_membership.capsule_tool_sha256 }
  )) {
    $memberRows = @($manifest.members | Where-Object { [string]$_.path -ceq [string]$binding.path })
    if ($memberRows.Count -ne 1 -or [string]$memberRows[0].sha256 -cne [string]$binding.expected) {
      throw "MIR 4 capsule package-membership closure does not bind $($binding.path)."
    }
  }

  $toolchainText = Read-MIR4ArchiveText -Path $CapsulePath -RelativePath '.mir/capsule/toolchain-lock.json'
  if (-not ($toolchainText | Test-Json -SchemaFile (Join-Path $SchemaRoot 'mir4-bootstrap-toolchain-lock.schema.json'))) {
    throw 'MIR 4 capsule toolchain lock schema validation failed.'
  }
  $toolchain = $toolchainText | ConvertFrom-Json -Depth 100 -DateKind String
  if (-not (Test-MIR4BootstrapRecordHash -Record $toolchain) -or
      [string]$toolchain.record_sha256 -cne [string]$manifest.toolchain_lock_record_sha256 -or
      [string]$toolchain.record_sha256 -cne [string]$envelope.closure.toolchain_lock_record_sha256) {
    throw 'MIR 4 capsule toolchain lock binding mismatch.'
  }
  $gitText = Read-MIR4ArchiveText -Path $CapsulePath -RelativePath '.mir/capsule/git/source-identity.json'
  if (-not ($gitText | Test-Json -SchemaFile (Join-Path $SchemaRoot 'mir4-bootstrap-git-source-proof.schema.json'))) {
    throw 'MIR 4 capsule Git source proof schema validation failed.'
  }
  $gitProof = $gitText | ConvertFrom-Json -Depth 100 -DateKind String
  if (-not (Test-MIR4BootstrapRecordHash -Record $gitProof) -or
      [string]$gitProof.record_sha256 -cne [string]$manifest.git_source_proof_record_sha256 -or
      [string]$gitProof.record_sha256 -cne [string]$envelope.closure.git_source_proof_record_sha256 -or
      [string]$gitProof.candidate_commit -cne [string]$envelope.source.candidate_commit -or
      [string]$gitProof.source_tree -cne [string]$envelope.source.source_tree) {
    throw 'MIR 4 capsule Git source proof binding mismatch.'
  }
  $null = Assert-MIR4BootstrapCapsuleManifestClosure -Manifest $manifest -GitProof $gitProof -Lane $lane
  $commitBytes = Read-MIR4ArchiveBytes -Path $CapsulePath -RelativePath ([string]$gitProof.commit.payload_path)
  if ((Get-MIR4GitObjectSha1 -Type commit -Bytes $commitBytes) -cne [string]$gitProof.commit.sha1 -or
      (Get-MIR4Sha256Bytes -Bytes $commitBytes) -cne [string]$gitProof.commit.sha256 -or
      [long]$commitBytes.Length -ne [long]$gitProof.commit.bytes) {
    throw 'MIR 4 capsule raw Git commit proof differs.'
  }
  $commitText = [Text.UTF8Encoding]::new($false, $true).GetString($commitBytes)
  $treeMatches = [Text.RegularExpressions.Regex]::Matches($commitText, '(?m)^tree ([a-f0-9]{40})$')
  if ($treeMatches.Count -ne 1 -or [string]$treeMatches[0].Groups[1].Value -cne [string]$gitProof.source_tree) {
    throw 'MIR 4 capsule raw Git commit does not bind its declared source tree.'
  }
  $treeMap = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
  foreach ($tree in @($gitProof.tree_objects)) {
    $treeBytes = Read-MIR4ArchiveBytes -Path $CapsulePath -RelativePath ([string]$tree.payload_path)
    if ((Get-MIR4GitObjectSha1 -Type tree -Bytes $treeBytes) -cne [string]$tree.sha1 -or
        (Get-MIR4Sha256Bytes -Bytes $treeBytes) -cne [string]$tree.sha256 -or
        [long]$treeBytes.Length -ne [long]$tree.bytes) {
      throw "MIR 4 capsule raw Git tree proof differs: $($tree.sha1)"
    }
    $treeMap.Add([string]$tree.sha1, @(Read-MIR4GitTreeObject -Bytes $treeBytes))
  }
  if (-not $treeMap.ContainsKey([string]$gitProof.source_tree)) { throw 'MIR 4 capsule raw Git proof omits its root tree.' }
  $packagePaths = @()
  foreach ($root in @(Get-MIRPackageSourceRoots)) {
    $packagePaths += @($inventory.entries.path | Where-Object { [string]$_ -ceq $root -or ([string]$_).StartsWith("$root/", [StringComparison]::Ordinal) })
  }
  $packagePathSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($relative in $packagePaths) { $null = $packagePathSet.Add([string]$relative) }
  $packagePathList = [Collections.Generic.List[string]]::new()
  foreach ($relative in $packagePathSet) { $packagePathList.Add($relative) }
  $packagePathList.Sort([StringComparer]::Ordinal)
  $packagePaths = @($packagePathList)
  if (($packagePaths -join '|') -cne (@($gitProof.package_files.path) -join '|')) {
    throw 'MIR 4 capsule Git proof is not total over package-visible source membership.'
  }
  foreach ($file in @($gitProof.package_files)) {
    $fileBytes = Read-MIR4ArchiveBytes -Path $CapsulePath -RelativePath ([string]$file.path)
    if ((Get-MIR4GitObjectSha1 -Type blob -Bytes $fileBytes) -cne [string]$file.blob_sha1 -or
        (Get-MIR4Sha256Bytes -Bytes $fileBytes) -cne [string]$file.sha256 -or
        [long]$fileBytes.Length -ne [long]$file.bytes) {
      throw "MIR 4 capsule Git blob proof differs: $($file.path)"
    }
    $segments = @([string]$file.path -split '/')
    $treeId = [string]$gitProof.source_tree
    for ($index = 0; $index -lt $segments.Count; $index++) {
      if (-not $treeMap.ContainsKey($treeId)) { throw "MIR 4 capsule Git proof omits a tree for $($file.path)." }
      $matches = @($treeMap[$treeId] | Where-Object { [string]$_.name -ceq [string]$segments[$index] })
      if ($matches.Count -ne 1) { throw "MIR 4 capsule Git proof does not uniquely traverse $($file.path)." }
      $entry = $matches[0]
      if ($index -lt $segments.Count - 1) {
        if ([string]$entry.mode -cne '40000') { throw "MIR 4 capsule Git proof has a non-tree path segment for $($file.path)." }
        $treeId = [string]$entry.object_id
      } elseif ([string]$entry.mode -cne [string]$file.mode -or [string]$entry.object_id -cne [string]$file.blob_sha1) {
        throw "MIR 4 capsule Git proof leaf differs for $($file.path)."
      }
    }
  }
  return [pscustomobject][ordered]@{
    envelope = $envelope
    manifest = $manifest
    inventory = $inventory
    toolchain_lock = $toolchain
    git_source_proof = $gitProof
  }
}

function New-MIR4BootstrapSourceCapsule {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)]$Target,
    [Parameter(Mandatory)][string]$OutputRoot,
    [ValidateSet('emergency', 'local-playtest-shadow')]
    [string]$Lane = 'emergency',
    [ValidatePattern('^[A-Z]$')]
    [string]$CapsuleId = 'A'
  )

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $output = [IO.Path]::GetFullPath($OutputRoot)
  $output = Assert-MIR4DescendantPath -Root (Join-Path $repo 'build/mir4') -Path $output
  $null = Assert-MIR4NoReparseAncestors -Root $repo -Path $output
  if (-not (Test-Path -LiteralPath $output -PathType Container)) { New-Item -ItemType Directory -Force -Path $output | Out-Null }
  $validTarget = if ($Lane -ceq 'emergency') {
    [string]$Target.target_key -ceq 'f210' -and [string]$Target.admission -ceq 'admitted-local-emergency-lane'
  } else {
    [string]$Target.target_key -cin @('f200', 'f110', 'f100') -and [string]$Target.admission -ceq 'non-authoritative-shadow-blocked-by-eol'
  }
  if (-not $validTarget) {
    throw "[mir4-entry-gate] Capsule V2 construction target is not admitted by lane '$Lane'."
  }
  $targetRoot = Join-Path $output "capsules\$($Target.target_key)\$CapsuleId"
  $workRoot = Join-Path $targetRoot 'work'
  Remove-MIR4BuildTree -OutputRoot $output -Path $targetRoot
  New-Item -ItemType Directory -Force -Path $workRoot | Out-Null

  $actualTree = Get-MIR4GitTree -RepoRoot $repo -Commit ([string]$Target.source.candidate_commit)
  if ($actualTree -ne [string]$Target.source.source_tree) {
    throw "Source tree mismatch for $($Target.target_key): expected $($Target.source.source_tree), got $actualTree."
  }

  $existingRoots = @()
  foreach ($root in @(Get-MIRPackageSourceRoots)) {
    & git -C $repo cat-file -e "$($Target.source.candidate_commit):$root" 2>$null
    if ($LASTEXITCODE -eq 0) { $existingRoots += $root }
  }
  if ($existingRoots.Count -eq 0) { throw "No package roots exist at $($Target.source.candidate_commit)." }

  $gitArchive = Join-Path $workRoot 'git-source.zip'
  # git archive otherwise honors host core.autocrlf while producing ZIP payloads.
  # Force LF/no-conversion and let the raw Git-blob proof reject any remaining
  # attribute-level transformation.
  [string[]]$archiveArgs = @('-c', 'core.autocrlf=false', '-c', 'core.eol=lf', '-C', $repo, 'archive', '--format=zip', '--prefix=source/', "--output=$gitArchive", [string]$Target.source.candidate_commit, '--') + @($existingRoots)
  & git @archiveArgs
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $gitArchive -PathType Leaf)) {
    throw "git archive failed for $($Target.target_key)."
  }

  $extractContainer = Join-Path $workRoot 'extract'
  Expand-MIR4SafeArchive -ArchivePath $gitArchive -Destination $extractContainer -OutputRoot $output
  $capsuleRoot = Join-Path $extractContainer 'source'
  Assert-MIR4SourceTreeSafe -SourceRoot $capsuleRoot

  foreach ($relative in @((Get-MIR4BootstrapCapsuleControllerPaths) + (Get-MIR4BootstrapCapsuleAuthorityPaths -Lane $Lane) + (Get-MIR4BootstrapCapsuleSchemaPaths -Lane $Lane))) {
    Copy-MIR4CapsuleClosureFile -RepoRoot $repo -CapsuleRoot $capsuleRoot -RelativePath $relative
  }

  $toolchainLock = New-MIR4BootstrapToolchainLock -PwshPath (Get-Process -Id $PID).Path
  $toolchainLockPath = Join-Path $capsuleRoot '.mir/capsule/toolchain-lock.json'
  $null = Write-MIR4BootstrapRecord -Record $toolchainLock -Path $toolchainLockPath
  $gitProof = New-MIR4GitSourceProof `
    -RepoRoot $repo `
    -Commit ([string]$Target.source.candidate_commit) `
    -ExpectedTree ([string]$Target.source.source_tree) `
    -CapsuleRoot $capsuleRoot
  $instructionsPath = Join-Path $capsuleRoot '.mir/capsule/RECONSTRUCT.md'
  [IO.File]::WriteAllText(
    $instructionsPath,
    "MIR 4 bootstrap source capsule V2.`n`nRun the detached Invoke-MIR4BootstrapCapsule.ps1 with this capsule, its detached envelope, the exact predecessor archive, the exact bound PowerShell home, and a new output root. No repository checkout argument is accepted.`n",
    [Text.UTF8Encoding]::new($false)
  )

  $manifestRelative = '.mir/capsule/manifest.json'
  $members = @()
  foreach ($item in @(Get-ChildItem -LiteralPath $capsuleRoot -Recurse -File -Force)) {
    $relative = [IO.Path]::GetRelativePath($capsuleRoot, $item.FullName).Replace('\', '/')
    if ($relative -ceq $manifestRelative) { throw 'A stale recursive capsule manifest exists in the staging tree.' }
    $identity = Get-MIR4RawFileIdentity -Path $item.FullName
    $members += [pscustomobject][ordered]@{
      path = $relative
      role = Get-MIR4CapsuleMemberRole -RelativePath $relative
      bytes = [long]$identity.bytes
      sha256 = [string]$identity.sha256
    }
  }
  $memberMap = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
  foreach ($member in $members) { $memberMap.Add([string]$member.path, $member) }
  $orderedMemberPaths = [Collections.Generic.List[string]]::new()
  foreach ($relative in $memberMap.Keys) { $orderedMemberPaths.Add($relative) }
  $orderedMemberPaths.Sort([StringComparer]::Ordinal)
  $members = @($orderedMemberPaths | ForEach-Object { $memberMap[[string]$_] })
  $memberFields = [ordered]@{}
  $authorityFields = [ordered]@{}
  foreach ($member in $members) {
    $memberFields[[string]$member.path] = "$([string]$member.role)|$([long]$member.bytes)|$([string]$member.sha256)"
    if ([string]$member.role -ceq 'authority') { $authorityFields[[string]$member.path] = [string]$member.sha256 }
  }
  $payloadRoot = Get-MIR4DomainSha256 -Domain 'mir4.bootstrap.capsule-payload.v1' -Fields $memberFields
  $authorityClosureRoot = Get-MIR4DomainSha256 -Domain 'mir4.bootstrap.capsule-authority.v1' -Fields $authorityFields
  $builderIdentity = Get-MIR4RawFileIdentity -Path (Join-Path $capsuleRoot 'tools/commands/package/Build-MIRPackage.ps1')
  $runnerIdentity = Get-MIR4RawFileIdentity -Path (Join-Path $capsuleRoot 'tools/commands/release/Invoke-MIR4BootstrapCapsule.ps1')
  $targetDescriptor = [ordered]@{
    target_key = [string]$Target.target_key
    factorio_line = [string]$Target.factorio_line
    distribution_version = [string]$Target.distribution_version
    source = $Target.source
    predecessor = $Target.predecessor
  }
  $correctionBinding = $null
  if ($null -ne $Target.PSObject.Properties['correction_authority']) {
    $correctionPath = Join-Path $repo ([string]$Target.correction_authority.path)
    $correction = Get-Content -Raw -LiteralPath $correctionPath | ConvertFrom-Json -Depth 100 -DateKind String
    if (-not (Test-MIR4BootstrapRecordHash -Record $correction) -or
        [string]$correction.record_sha256 -cne [string]$Target.correction_authority.record_sha256) {
      throw '[mir4-approved-delta] Capsule construction received a stale correction binding.'
    }
    $findingIdentity = if ($null -ne $correction.PSObject.Properties['findings']) {
      @($correction.findings | Sort-Object) -join '+'
    } else {
      [string]$correction.finding
    }
    $correctionBinding = [pscustomobject][ordered]@{
      path = [string]$Target.correction_authority.path
      kind = [string]$correction.kind
      finding = $findingIdentity
      record_sha256 = [string]$correction.record_sha256
    }
    $targetDescriptor.correction_authority = $correctionBinding
  }
  $laneBinding = $null
  if ($Lane -ceq 'local-playtest-shadow') {
    $laneRelativePath = '.mir/releases/waves/mir4-r0/MIR4-Private-Lane-AuthorizationV3.json'
    $lanePath = Join-Path $repo $laneRelativePath
    $laneText = Get-Content -Raw -LiteralPath $lanePath
    if (-not ($laneText | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-private-lane-authorization-v3.schema.json'))) {
      throw '[mir4-local-playtest-shadow] The lane authorization fails its exact schema.'
    }
    $laneAuthority = $laneText | ConvertFrom-Json -Depth 100 -DateKind String
    if (-not (Test-MIR4BootstrapRecordHash -Record $laneAuthority)) {
      throw '[mir4-local-playtest-shadow] The lane authorization self-hash is stale.'
    }
    $laneTargets = @($laneAuthority.authorized_targets | Where-Object { [string]$_.target_key -ceq [string]$Target.target_key })
    if ($laneTargets.Count -ne 1 -or
        [string]$laneTargets[0].source_commit -cne [string]$Target.source.candidate_commit -or
        [string]$laneTargets[0].source_tree -cne [string]$Target.source.source_tree -or
        [string]$laneTargets[0].predecessor_archive_sha256 -cne [string]$Target.predecessor.archive_sha256) {
      throw '[mir4-local-playtest-shadow] The target is not exactly bound by the private lane authorization.'
    }
    $laneBinding = [pscustomobject][ordered]@{
      path = $laneRelativePath
      kind = [string]$laneAuthority.kind
      authority_family = [string]$laneAuthority.authority_family
      record_sha256 = [string]$laneAuthority.record_sha256
    }
    $targetDescriptor.local_lane_authority = $laneBinding
  }
  $manifest = [pscustomobject][ordered]@{
    schema = 2
    kind = 'MIR4BootstrapCapsuleManifestV2'
    status = 'local-unpublished-closed-construction-input'
    canonicalization = 'MIR4BootstrapCanonicalJsonV1'
    lane = $Lane
    target = [pscustomobject]$targetDescriptor
    package_membership_authority = 'tools/lib/validation/PackageIdentity.ps1#Get-MIRPackageSourceRoots'
    member_count = [int]$members.Count
    members = $members
    payload_root_sha256 = $payloadRoot
    authority_closure_root_sha256 = $authorityClosureRoot
    git_source_proof_record_sha256 = [string]$gitProof.record_sha256
    toolchain_lock_record_sha256 = [string]$toolchainLock.record_sha256
    canonical_builder_sha256 = [string]$builderIdentity.sha256
    reconstruction_runner_sha256 = [string]$runnerIdentity.sha256
    record_sha256 = ''
  }
  $manifestPath = Join-Path $capsuleRoot $manifestRelative
  $null = Write-MIR4BootstrapRecord -Record $manifest -Path $manifestPath
  $capsuleContentRoot = Get-MIR4DomainSha256 -Domain 'mir4.bootstrap.capsule-content.v1' -Fields ([ordered]@{
    payload_root_sha256 = $payloadRoot
    internal_manifest_record_sha256 = [string]$manifest.record_sha256
  })

  $capsulePath = Join-Path $targetRoot 'source-capsule.zip'
  Write-MIR4DeterministicRawTreeArchive -SourceRoot $capsuleRoot -EntryRoot 'mir4-source-capsule' -OutputPath $capsulePath -ContainmentRoot $output
  $inventory = Get-MIR4ArchiveInventory -Path $capsulePath
  if ([string]$inventory.root -cne 'mir4-source-capsule') {
    throw "MIR 4 source capsules require the exact archive root 'mir4-source-capsule'; got '$($inventory.root)'."
  }
  $runnerSidecarPath = Join-Path $targetRoot 'Invoke-MIR4BootstrapCapsule.ps1'
  Copy-Item -LiteralPath (Join-Path $capsuleRoot 'tools/commands/release/Invoke-MIR4BootstrapCapsule.ps1') -Destination $runnerSidecarPath
  $recordFields = [ordered]@{
    schema = 2
    kind = 'MIR4BootstrapSourceCapsuleV2'
    status = 'local-unpublished-input'
    canonicalization = 'MIR4BootstrapCanonicalJsonV1'
    public_output_authorized = $false
    lane = $Lane
    target_key = [string]$Target.target_key
    factorio_line = [string]$Target.factorio_line
    distribution_version = [string]$Target.distribution_version
    source = $Target.source
    predecessor = $Target.predecessor
    package_membership = [pscustomobject][ordered]@{
      authority = 'tools/lib/validation/PackageIdentity.ps1#Get-MIRPackageSourceRoots'
      authority_sha256 = Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
      capsule_tool = 'tools/lib/mir4/BootstrapMaterialization.ps1#New-MIR4BootstrapSourceCapsule'
      capsule_tool_sha256 = Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
      shipped_sidecars = @()
      evidence_inside_package = $false
    }
    closure = [pscustomobject][ordered]@{
      internal_manifest_record_sha256 = [string]$manifest.record_sha256
      payload_root_sha256 = $payloadRoot
      capsule_content_root_sha256 = $capsuleContentRoot
      authority_closure_root_sha256 = $authorityClosureRoot
      git_source_proof_record_sha256 = [string]$gitProof.record_sha256
      toolchain_lock_record_sha256 = [string]$toolchainLock.record_sha256
      canonical_builder_sha256 = [string]$builderIdentity.sha256
      reconstruction_runner_sha256 = [string]$runnerIdentity.sha256
    }
    bootstrap_runner = [pscustomobject][ordered]@{
      capsule_path = 'tools/commands/release/Invoke-MIR4BootstrapCapsule.ps1'
      detached_path = 'Invoke-MIR4BootstrapCapsule.ps1'
      sha256 = [string]$runnerIdentity.sha256
      bytes = [long]$runnerIdentity.bytes
    }
    capsule = [pscustomobject][ordered]@{
      path = 'source-capsule.zip'
      archive_sha256 = $inventory.archive_sha256
      content_sha256 = $inventory.content_sha256
      bytes = $inventory.bytes
      entry_count = $inventory.entry_count
    }
  }
  if ($null -ne $correctionBinding) { $recordFields.correction_authority = $correctionBinding }
  if ($null -ne $laneBinding) { $recordFields.local_lane_authority = $laneBinding }
  $recordFields.record_sha256 = ''
  $record = [pscustomobject]$recordFields
  $recordPath = Join-Path $targetRoot 'source-capsule.json'
  $null = Write-MIR4BootstrapRecord -Record $record -Path $recordPath
  if (Get-Command Test-Json -ErrorAction SilentlyContinue) {
    $schemaPath = Join-Path $repo 'spec/schemas/mir4-bootstrap-source-capsule.schema.json'
    if (-not ((Get-Content -Raw -LiteralPath $recordPath) | Test-Json -SchemaFile $schemaPath)) {
      throw "Generated MIR 4 source capsule record failed schema validation for $($Target.target_key)/$CapsuleId."
    }
  }
  Remove-MIR4BuildTree -OutputRoot $output -Path $workRoot
  return [pscustomobject][ordered]@{
    archive_path = $capsulePath
    record_path = $recordPath
    runner_path = $runnerSidecarPath
    record = $record
  }
}
