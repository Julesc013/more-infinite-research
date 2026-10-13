Set-StrictMode -Version Latest

# Historical 4.3 player inputs are not canonical materializer targets.  Their
# reader therefore authenticates their bytes through the canonical f100 source
# selection plus the historical target record's adapters and patches.  It
# never accepts an archive/member hash supplied solely by the candidate
# manifest.

function Assert-MIR43HistoricalCandidateAuthentication {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "[mir43-historical-current-candidate] $Message" }
}

function Get-MIR43HistoricalCandidateAuthenticationProjection {
  param(
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][ValidateSet('f017','f016','f015','f014','f013')][string]$Target,
    [Parameter(Mandatory)][ValidateSet('4.3.0','4.3.1')][string]$SourceVersion
  )

  $repo = (Resolve-Path -LiteralPath $Repository).Path
  $writer = Join-Path $repo 'tools/commands/release/New-MIR42HistoricalPlaytestCandidate.ps1'
  Assert-MIR43HistoricalCandidateAuthentication (Test-Path -LiteralPath $writer -PathType Leaf) 'authentication projection authority is missing'
  # The command's projection mode is pure: it reads the currently admitted
  # source/target authorities and produces expected member identities without
  # materializing a tree or archive.
  $projection = @(& $writer -RepoRoot $repo -Target $Target -SourceVersion $SourceVersion -AuthenticationProjection)
  Assert-MIR43HistoricalCandidateAuthentication ($projection.Count -eq 1) 'authentication projection result differs'
  $value = $projection[0]
  Assert-MIR43HistoricalCandidateAuthentication (
    [int]$value.schema -eq 1 -and
    [string]$value.kind -ceq 'MIR42HistoricalCandidateAuthenticationProjectionV1' -and
    [string]$value.target -ceq $Target -and
    [string]$value.source_version -ceq $SourceVersion -and
    [string]$value.distribution_root -match '^more-infinite-research_4[.]3[.][0-9]{5}$' -and
    [string]$value.member_projection_sha256 -match '^[0-9A-F]{64}$' -and
    @($value.members).Count -gt 0
  ) 'authentication projection contract differs'
  return $value
}

function Read-MIR43HistoricalCurrentCandidate {
  param(
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][string]$Archive,
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][ValidateSet('f017','f016','f015','f014','f013')][string]$Target,
    [Parameter(Mandatory)][ValidateSet('4.3.0','4.3.1')][string]$SourceVersion
  )

  $repo = (Resolve-Path -LiteralPath $Repository).Path
  . (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
  . (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
  $candidate = (Resolve-Path -LiteralPath $Archive).Path
  $manifestFile = (Resolve-Path -LiteralPath $ManifestPath).Path
  $manifest = Get-Content -LiteralPath $manifestFile -Raw | ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR43HistoricalCandidateAuthentication (Test-MIR4BootstrapRecordHash -Record $manifest) 'candidate manifest record hash differs'
  Assert-MIR43HistoricalCandidateAuthentication (
    [int]$manifest.schema -eq 1 -and
    [string]$manifest.kind -ceq 'MIR42HistoricalPlaytestCandidateManifestV1' -and
    [string]$manifest.status -ceq 'built-private-historical-unqualified' -and
    [string]$manifest.target -ceq $Target -and
    [string]$manifest.candidate_row.kind -ceq 'MIR42HistoricalCandidateRowV1' -and
    [string]$manifest.candidate_row.status -ceq 'deterministic-historical-candidate-construction-input-unqualified' -and
    [string]$manifest.candidate_row.target -ceq $Target -and
    [string]$manifest.candidate_row.source_version -ceq $SourceVersion -and
    [bool]$manifest.candidate_row.deterministic_archive_bytes -and
    [bool]$manifest.candidate_row.package_excluded_surface -and
    [string]$manifest.candidate_row.qualification -ceq 'not-performed-in-this-construction-record' -and
    [string]$manifest.candidate_row.technical_seal -ceq 'not-performed' -and
    [string]$manifest.candidate_row.signing -ceq 'not-performed' -and
    -not [bool]$manifest.candidate_row.public_output_authorized -and
    -not [bool]$manifest.candidate_row.publication_authorized -and
    -not [bool]$manifest.public_output_authorized -and
    -not [bool]$manifest.publication_authorized
  ) 'candidate manifest identity differs'

  $projection = Get-MIR43HistoricalCandidateAuthenticationProjection -Repository $repo -Target $Target -SourceVersion $SourceVersion
  $head = (& git -C $repo rev-parse HEAD).Trim()
  $tree = (& git -C $repo rev-parse 'HEAD^{tree}').Trim()
  Assert-MIR43HistoricalCandidateAuthentication ($LASTEXITCODE -eq 0 -and
    [string]$manifest.source.commit -ceq $head -and [string]$manifest.source.tree -ceq $tree -and
    [string]$manifest.source.commit -ceq [string]$projection.source.commit -and
    [string]$manifest.source.tree -ceq [string]$projection.source.tree -and
    [string]$manifest.candidate_row.source.commit -ceq [string]$projection.source.commit -and
    [string]$manifest.candidate_row.source.tree -ceq [string]$projection.source.tree -and
    [string]$manifest.factorio_line -ceq [string]$projection.factorio_line -and
    [string]$manifest.distribution_version -ceq [string]$projection.distribution_version -and
    [string]$manifest.candidate_row.distribution_version -ceq [string]$projection.distribution_version
  ) 'candidate source or distribution identity differs'
  Assert-MIR43HistoricalCandidateAuthentication (
    [string]$manifest.target_record.path -ceq [string]$projection.target_record.path -and
    [string]$manifest.target_record.sha256 -ceq [string]$projection.target_record.sha256 -and
    [string]$manifest.candidate_row.target_record.path -ceq [string]$projection.target_record.path -and
    [string]$manifest.candidate_row.target_record.sha256 -ceq [string]$projection.target_record.sha256
  ) 'candidate target record differs'
  Assert-MIR43HistoricalCandidateAuthentication (
    [string]$manifest.authentication_projection.kind -ceq 'MIR42HistoricalCandidateAuthenticationProjectionV1' -and
    [string]$manifest.authentication_projection.member_projection_sha256 -ceq [string]$projection.member_projection_sha256 -and
    [int]$manifest.authentication_projection.member_count -eq @($projection.members).Count -and
    [string]$manifest.authentication_projection.canonical_base.package_authority_sha256 -ceq [string]$projection.canonical_base.package_authority_sha256 -and
    [string]$manifest.authentication_projection.canonical_base.source_manifest_sha256 -ceq [string]$projection.canonical_base.source_manifest_sha256 -and
    [string]$manifest.authentication_projection.canonical_base.target_registry_sha256 -ceq [string]$projection.canonical_base.target_registry_sha256 -and
    [string]$manifest.authentication_projection.canonical_base.support_policy_sha256 -ceq [string]$projection.canonical_base.support_policy_sha256 -and
    [string]$manifest.authentication_projection.canonical_base.target_overlay_sha256 -ceq [string]$projection.canonical_base.target_overlay_sha256
  ) 'candidate canonical source authority differs'

  $expectedName = 'more-infinite-research_' + [string]$projection.distribution_version + '.zip'
  Assert-MIR43HistoricalCandidateAuthentication ([IO.Path]::GetFileName($candidate) -ceq $expectedName) 'candidate archive filename differs'
  $inventory = Get-MIR4ArchiveInventory -Path $candidate
  Assert-MIR43HistoricalCandidateAuthentication (
    [string]$inventory.root -ceq [string]$projection.distribution_root -and
    [string]$inventory.archive_sha256 -ceq [string]$manifest.distribution.sha256 -and
    [string]$inventory.archive_sha256 -ceq [string]$manifest.candidate_row.asset.sha256 -and
    [string]$inventory.archive_sha256 -ceq [string]$manifest.candidate_row.build_a_sha256 -and
    [string]$inventory.archive_sha256 -ceq [string]$manifest.candidate_row.build_b_sha256 -and
    [string]$inventory.content_sha256 -ceq [string]$manifest.distribution.content_sha256 -and
    [string]$inventory.content_sha256 -ceq [string]$manifest.candidate_row.content_sha256 -and
    [int]$inventory.entry_count -eq [int]$manifest.distribution.entry_count -and
    [int]$inventory.entry_count -eq [int]$manifest.candidate_row.entry_count
  ) 'candidate archive inventory differs'

  $actual = @{}
  foreach ($entry in @($inventory.entries)) {
    if ($actual.ContainsKey([string]$entry.path)) { throw '[mir43-historical-current-candidate] duplicate archive member differs' }
    $actual[[string]$entry.path] = $entry
  }
  $expected = @{}
  foreach ($entry in @($projection.members)) {
    $path = [string]$entry.path
    Assert-MIR43HistoricalCandidateAuthentication (-not $expected.ContainsKey($path)) 'projection member collision differs'
    $expected[$path] = $entry
  }
  Assert-MIR43HistoricalCandidateAuthentication ($actual.Count -eq $expected.Count) 'candidate package membership differs'
  foreach ($path in @($expected.Keys | Sort-Object -CaseSensitive)) {
    $actualEntry = $actual[$path]
    $expectedEntry = $expected[$path]
    Assert-MIR43HistoricalCandidateAuthentication ($null -ne $actualEntry -and
      [int64]$actualEntry.raw_bytes -eq [int64]$expectedEntry.bytes -and
      [string]$actualEntry.raw_sha256 -ceq [string]$expectedEntry.sha256) "candidate member differs: $path"
  }

  $info = Read-MIR4ArchiveText -Path $candidate -RelativePath 'info.json' | ConvertFrom-Json -Depth 20 -DateKind String
  Assert-MIR43HistoricalCandidateAuthentication (
    [string]$info.name -ceq 'more-infinite-research' -and
    [string]$info.version -ceq [string]$projection.distribution_version -and
    [string]$info.factorio_version -ceq [string]$projection.factorio_line
  ) 'candidate metadata differs'
  return [pscustomobject][ordered]@{ path = $candidate; receipt = $manifest.candidate_row; manifest = $manifest; projection = $projection; inventory = $inventory }
}

# Focused archive-admission controls.  The caller supplies one writer-produced
# private archive and an empty, controlled scratch directory; this helper does
# not invoke a materializer or native engine.
function Invoke-MIR43HistoricalCurrentCandidateAuthenticationControls {
  param(
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][string]$Archive,
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][ValidateSet('f017','f016','f015','f014','f013')][string]$Target,
    [Parameter(Mandatory)][ValidateSet('4.3.0','4.3.1')][string]$SourceVersion,
    [Parameter(Mandatory)][string]$WorkRoot
  )

  $repo = (Resolve-Path -LiteralPath $Repository).Path
  # Archive inventory and record hashing are used to forge a self-consistent
  # caller manifest.  Import the canonical helpers in this caller scope: the
  # reader imports them only inside its own function scope.
  . (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
  . (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
  $inputArchive = (Resolve-Path -LiteralPath $Archive).Path
  $inputManifest = (Resolve-Path -LiteralPath $ManifestPath).Path
  $root = [IO.Path]::GetFullPath($WorkRoot)
  if (Test-Path -LiteralPath $root) { throw '[mir43-historical-current-candidate] controlled output already exists' }
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  $script:mir43HistoricalCandidateAuthenticationControlAssertions = 0
  function Assert-MIR43HistoricalCandidateControlRejects {
    param([scriptblock]$Action,[string]$Needle)
    $failure = ''
    try { & $Action | Out-Null } catch { $failure = $_.Exception.Message }
    if (-not $failure.Contains($Needle, [StringComparison]::Ordinal)) {
      throw "[mir43-historical-current-candidate] expected $Needle; got $failure"
    }
    $script:mir43HistoricalCandidateAuthenticationControlAssertions++
  }
  try {
    $verified = Read-MIR43HistoricalCurrentCandidate -Repository $repo -Archive $inputArchive -ManifestPath $inputManifest -Target $Target -SourceVersion $SourceVersion
    if ([string]$verified.receipt.distribution_version -cne [string]$verified.projection.distribution_version) {
      throw '[mir43-historical-current-candidate] controlled accepted identity differs'
    }
    $script:mir43HistoricalCandidateAuthenticationControlAssertions++

    $forgedArchive = Join-Path $root ([IO.Path]::GetFileName($inputArchive))
    $forgedManifest = Join-Path $root 'forged-player-byte.json'
    Copy-Item -LiteralPath $inputArchive -Destination $forgedArchive
    Copy-Item -LiteralPath $inputManifest -Destination $forgedManifest
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::Open($forgedArchive, [IO.Compression.ZipArchiveMode]::Update)
    try {
      $entry = $zip.GetEntry(([string]$verified.projection.distribution_root) + '/data.lua')
      if ($null -eq $entry) { throw '[mir43-historical-current-candidate] controlled data member missing' }
      $entry.Delete()
      $replacement = $zip.CreateEntry(([string]$verified.projection.distribution_root) + '/data.lua')
      $writer = [IO.StreamWriter]::new($replacement.Open(), [Text.UTF8Encoding]::new($false))
      try { $writer.Write("return { forged = true }`n") } finally { $writer.Dispose() }
    } finally { $zip.Dispose() }
    $forged = Get-Content -LiteralPath $forgedManifest -Raw | ConvertFrom-Json -Depth 100 -DateKind String
    $forgedInventory = Get-MIR4ArchiveInventory -Path $forgedArchive
    $forged.distribution.sha256 = [string]$forgedInventory.archive_sha256
    $forged.distribution.content_sha256 = [string]$forgedInventory.content_sha256
    $forged.distribution.entry_count = [int]$forgedInventory.entry_count
    $forged.candidate_row.asset.bytes = [int64](Get-Item -LiteralPath $forgedArchive).Length
    $forged.candidate_row.asset.sha256 = [string]$forgedInventory.archive_sha256
    $forged.candidate_row.content_sha256 = [string]$forgedInventory.content_sha256
    $forged.candidate_row.entry_count = [int]$forgedInventory.entry_count
    $forged.candidate_row.build_a_sha256 = [string]$forgedInventory.archive_sha256
    $forged.candidate_row.build_b_sha256 = [string]$forgedInventory.archive_sha256
    $forged.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $forged
    [IO.File]::WriteAllText($forgedManifest, (($forged | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n"), [Text.UTF8Encoding]::new($false))
    Assert-MIR43HistoricalCandidateControlRejects {
      Read-MIR43HistoricalCurrentCandidate -Repository $repo -Archive $forgedArchive -ManifestPath $forgedManifest -Target $Target -SourceVersion $SourceVersion
    } 'candidate member differs: data.lua'

    $forgedSourceManifest = Join-Path $root 'forged-source-pin.json'
    $forgedSource = Get-Content -LiteralPath $inputManifest -Raw | ConvertFrom-Json -Depth 100 -DateKind String
    $forgedSource.source.tree = '0' * 40
    $forgedSource.candidate_row.source.tree = '0' * 40
    $forgedSource.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $forgedSource
    [IO.File]::WriteAllText($forgedSourceManifest, (($forgedSource | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n"), [Text.UTF8Encoding]::new($false))
    Assert-MIR43HistoricalCandidateControlRejects {
      Read-MIR43HistoricalCurrentCandidate -Repository $repo -Archive $inputArchive -ManifestPath $forgedSourceManifest -Target $Target -SourceVersion $SourceVersion
    } 'candidate source or distribution identity differs'

    $forgedTargetManifest = Join-Path $root 'forged-target-pin.json'
    $forgedTarget = Get-Content -LiteralPath $inputManifest -Raw | ConvertFrom-Json -Depth 100 -DateKind String
    $forgedTarget.target_record.sha256 = '0' * 64
    $forgedTarget.candidate_row.target_record.sha256 = '0' * 64
    $forgedTarget.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $forgedTarget
    [IO.File]::WriteAllText($forgedTargetManifest, (($forgedTarget | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n"), [Text.UTF8Encoding]::new($false))
    Assert-MIR43HistoricalCandidateControlRejects {
      Read-MIR43HistoricalCurrentCandidate -Repository $repo -Archive $inputArchive -ManifestPath $forgedTargetManifest -Target $Target -SourceVersion $SourceVersion
    } 'candidate target record differs'
  } finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
  }
  return [pscustomobject][ordered]@{ status = 'passed'; assertions = $script:mir43HistoricalCandidateAuthenticationControlAssertions; native_factorio = $false; package_materialization = $false }
}
