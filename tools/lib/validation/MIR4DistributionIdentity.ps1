$script:MIR4TargetRegistryV1Path = ".mir/releases/waves/mir4-r0/MIR4-Target-RegistryV1.json"
$script:MIR4VersionAuthorityV1Path = ".mir/releases/waves/mir4-r0/MIR4-Versioning-and-Distribution-Identity-ADRv1.json"
$script:MIR4TargetRegistryV2Path = ".mir/releases/waves/mir4-r0/MIR4-Target-RegistryV2.json"
$script:MIR4VersionAuthorityV2Path = ".mir/releases/waves/mir4-r0/MIR4-Versioning-and-Distribution-Identity-ADRv2.json"
$script:MIR4CodecVectorsV2Path = ".mir/releases/waves/mir4-r0/MIR4-Distribution-Version-Codec-VectorsV2.json"

function Import-MIR4IdentityJson {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$RelativePath
  )

  $path = Join-Path $RepoRoot $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "[mir4-authority-absent] Required MIR 4 identity input is absent: $RelativePath"
  }
  return Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100
}

function Assert-MIR4IdentitySchema {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$SchemaRelativePath
  )

  $raw = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $RelativePath)
  if (-not ($raw | Test-Json -SchemaFile (Join-Path $RepoRoot $SchemaRelativePath) -ErrorAction Stop)) {
    throw "[mir4-schema] Schema validation failed: $RelativePath"
  }
}

function ConvertTo-MIR4DistributionComponent {
  param(
    [Parameter(Mandatory)][AllowEmptyString()][string]$DistributionTargetCode,
    [Parameter(Mandatory)][int]$SourcePatch
  )

  if ($DistributionTargetCode -notmatch '^[0-9]{3}$') {
    throw "[mir4-code-width] Distribution target code must be exactly three decimal digits."
  }

  $codeValue = [int]::Parse(
    $DistributionTargetCode,
    [Globalization.NumberStyles]::None,
    [Globalization.CultureInfo]::InvariantCulture
  )
  if ($codeValue -lt 1 -or $codeValue -gt 654) {
    throw "[mir4-code-range] Distribution target code must be between 001 and the internal boundary 654."
  }
  if ($SourcePatch -lt 0 -or $SourcePatch -gt 99) {
    throw "[mir4-patch-range] Source patch must be between 0 and 99."
  }

  $encoded = ($codeValue * 100) + $SourcePatch
  if ($encoded -gt 65499 -or $encoded -gt 65535) {
    throw "[mir4-encoded-range] Encoded component exceeds the admitted internal boundary."
  }

  return [pscustomobject][ordered]@{
    distribution_target_code = $DistributionTargetCode
    source_patch = $SourcePatch
    source_patch_text = $SourcePatch.ToString("D2", [Globalization.CultureInfo]::InvariantCulture)
    encoded_component = $encoded
    encoded_component_text = $encoded.ToString("D5", [Globalization.CultureInfo]::InvariantCulture)
  }
}

function ConvertFrom-MIR4DistributionComponent {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$EncodedComponentText)

  if ($EncodedComponentText -notmatch '^[0-9]{5}$') {
    throw "[mir4-encoded-width] Encoded component must be exactly five decimal digits."
  }

  $encoded = [int]::Parse(
    $EncodedComponentText,
    [Globalization.NumberStyles]::None,
    [Globalization.CultureInfo]::InvariantCulture
  )
  if ($encoded -lt 100 -or $encoded -gt 65499 -or $encoded -gt 65535) {
    throw "[mir4-encoded-range] Encoded component is outside the admitted internal boundary."
  }

  $codeValue = [int][Math]::Floor($encoded / 100)
  $sourcePatch = $encoded % 100
  return [pscustomobject][ordered]@{
    distribution_target_code = $codeValue.ToString("D3", [Globalization.CultureInfo]::InvariantCulture)
    source_patch = $sourcePatch
    source_patch_text = $sourcePatch.ToString("D2", [Globalization.CultureInfo]::InvariantCulture)
    encoded_component = $encoded
    encoded_component_text = $EncodedComponentText
  }
}

function New-MIR4DistributionIdentityProjection {
  param(
    [Parameter(Mandatory)][string]$DistributionTargetCode,
    [Parameter(Mandatory)][int]$SourceMinor,
    [Parameter(Mandatory)][int]$SourcePatch
  )

  if ($SourceMinor -lt 0 -or $SourceMinor -gt 65535) {
    throw "[mir4-minor-range] Source minor must be between 0 and 65535."
  }

  $component = ConvertTo-MIR4DistributionComponent `
    -DistributionTargetCode $DistributionTargetCode `
    -SourcePatch $SourcePatch
  $sourceVersion = "4.$SourceMinor.$SourcePatch"
  $distributionVersion = "4.$SourceMinor.$($component.encoded_component_text)"
  return [pscustomobject][ordered]@{
    distribution_target_code = $DistributionTargetCode
    source_minor = $SourceMinor
    source_patch = $SourcePatch
    source_patch_text = [string]$component.source_patch_text
    source_version = $sourceVersion
    source_tag = "v$sourceVersion"
    encoded_component = [int]$component.encoded_component
    encoded_component_text = [string]$component.encoded_component_text
    distribution_version = $distributionVersion
    distribution_tag = "dist/f$DistributionTargetCode/v$distributionVersion"
    package_name = "more-infinite-research_$distributionVersion.zip"
  }
}

function Resolve-MIR4DistributionIdentity {
  param(
    [Parameter(Mandatory)]$TargetRegistry,
    [Parameter(Mandatory)]$VersionAuthority,
    [Parameter(Mandatory)][string]$TargetId,
    [Parameter(Mandatory)][int]$SourceMinor,
    [Parameter(Mandatory)][int]$SourcePatch
  )

  if ([string]$TargetRegistry.kind -eq "MIR4-Target-RegistryV1" -or
      [string]$VersionAuthority.kind -eq "MIR4-Versioning-and-Distribution-Identity-ADRv1") {
    throw "[mir4-historical-authority] V1 identity records are immutable historical evidence and cannot resolve an executable distribution."
  }
  if ([int]$TargetRegistry.schema -ne 2 -or
      [string]$TargetRegistry.kind -ne "MIR4-Target-RegistryV2" -or
      [string]$TargetRegistry.status -ne "accepted-pre-publication-current" -or
      [int]$VersionAuthority.schema -ne 2 -or
      [string]$VersionAuthority.kind -ne "MIR4-Versioning-and-Distribution-Identity-ADRv2" -or
      [string]$VersionAuthority.status -ne "accepted-pre-publication-current") {
    throw "[mir4-current-authority] Only the accepted V2 registry and codec may resolve an executable distribution."
  }

  $rows = @($TargetRegistry.payload.targets | Where-Object { [string]$_.id -eq $TargetId })
  if ($rows.Count -ne 1) {
    throw "[mir4-target-unallocated] Target '$TargetId' is not uniquely allocated in the current V2 registry."
  }

  $projection = New-MIR4DistributionIdentityProjection `
    -DistributionTargetCode ([string]$rows[0].distribution_target_code) `
    -SourceMinor $SourceMinor `
    -SourcePatch $SourcePatch
  return [pscustomobject][ordered]@{
    target_id = $TargetId
    distribution_target_code = [string]$projection.distribution_target_code
    source_minor = [int]$projection.source_minor
    source_patch = [int]$projection.source_patch
    source_patch_text = [string]$projection.source_patch_text
    source_version = [string]$projection.source_version
    source_tag = [string]$projection.source_tag
    encoded_component = [int]$projection.encoded_component
    encoded_component_text = [string]$projection.encoded_component_text
    distribution_version = [string]$projection.distribution_version
    distribution_tag = [string]$projection.distribution_tag
    package_name = [string]$projection.package_name
  }
}

function Assert-MIR4R0DistributionIdentity {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
  $historicalHashes = [ordered]@{
    ".mir/releases/waves/mir4-r0/MIR4-Target-RegistryV1.json" = "617D620628C4308C0402874907DC90127CD3770887D6089E34E6EF2AF1EA7607"
    ".mir/releases/waves/mir4-r0/MIR4-Versioning-and-Distribution-Identity-ADRv1.json" = "E0DC9EF324EE8930D282AFBC222785344F8ACE288B3FDFC5D31046B9156FD01C"
  }
  foreach ($binding in $historicalHashes.GetEnumerator()) {
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $RepoRoot $binding.Key)).Hash.ToUpperInvariant()
    if ($actual -ne [string]$binding.Value) {
      throw "[mir4-historical-rewrite] Historical V1 identity evidence changed: $($binding.Key)"
    }
  }

  Assert-MIR4IdentitySchema -RepoRoot $RepoRoot -RelativePath $script:MIR4TargetRegistryV2Path -SchemaRelativePath "spec/schemas/mir4-target-registry-v2.schema.json"
  Assert-MIR4IdentitySchema -RepoRoot $RepoRoot -RelativePath $script:MIR4VersionAuthorityV2Path -SchemaRelativePath "spec/schemas/mir4-versioning-distribution-identity-v2.schema.json"
  Assert-MIR4IdentitySchema -RepoRoot $RepoRoot -RelativePath $script:MIR4CodecVectorsV2Path -SchemaRelativePath "spec/schemas/mir4-distribution-version-codec-vectors-v2.schema.json"

  $registryV1 = Import-MIR4IdentityJson -RepoRoot $RepoRoot -RelativePath $script:MIR4TargetRegistryV1Path
  $versionV1 = Import-MIR4IdentityJson -RepoRoot $RepoRoot -RelativePath $script:MIR4VersionAuthorityV1Path
  $registry = Import-MIR4IdentityJson -RepoRoot $RepoRoot -RelativePath $script:MIR4TargetRegistryV2Path
  $version = Import-MIR4IdentityJson -RepoRoot $RepoRoot -RelativePath $script:MIR4VersionAuthorityV2Path
  $vectors = Import-MIR4IdentityJson -RepoRoot $RepoRoot -RelativePath $script:MIR4CodecVectorsV2Path

  if ((@($registry.imports) -join "|") -ne ".mir/targets.json|.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV1.json|.mir/releases/terminal/MIR3-Terminal-Shadow-ProjectionProfilesV1.json|.mir/releases/terminal/MIR3-Terminal-Target-MatrixV1.json|.mir/releases/waves/mir4-r0/MIR4-Terminal-Predecessor-RefreshV1.json" -or
      (@($version.imports) -join "|") -ne ".mir/releases/waves/mir4-r0/MIR4-Versioning-and-Distribution-Identity-ADRv1.json|.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV2.json" -or
      [string]$version.payload.conformance_fixture_kind -ne "MIR4-Distribution-Version-Codec-VectorsV2") {
    throw "[mir4-authority-lineage] V2 identity authority does not bind the exact historical and current lineage."
  }

  $expected = @(
    [ordered]@{id="factorio-2.1";factorio="2.1";code="210";support="current";disposition="bootstrap-mandatory";blocking=$true;predecessor="3.2.10"},
    [ordered]@{id="factorio-2.0";factorio="2.0";code="200";support="maintained";disposition="bootstrap-mandatory";blocking=$true;predecessor="2.5.9"},
    [ordered]@{id="factorio-1.1";factorio="1.1";code="110";support="lts";disposition="bootstrap-conditional";blocking=$false;predecessor="1.9.9"},
    [ordered]@{id="factorio-1.0";factorio="1.0";code="100";support="lts";disposition="bootstrap-conditional";blocking=$false;predecessor="1.8.9"},
    [ordered]@{id="factorio-0.18";factorio="0.18";code="018";support="historical";disposition="deferred-bridge";blocking=$false;predecessor=$null},
    [ordered]@{id="factorio-0.17";factorio="0.17";code="017";support="historical";disposition="deferred-evolved";blocking=$false;predecessor="1.7.9"},
    [ordered]@{id="factorio-0.16";factorio="0.16";code="016";support="historical";disposition="deferred-evolved";blocking=$false;predecessor="1.6.9"},
    [ordered]@{id="factorio-0.15";factorio="0.15";code="015";support="historical";disposition="deferred-evolved";blocking=$false;predecessor="1.5.9"},
    [ordered]@{id="factorio-0.14";factorio="0.14";code="014";support="historical";disposition="deferred-evolved";blocking=$false;predecessor="1.4.9"},
    [ordered]@{id="factorio-0.13";factorio="0.13";code="013";support="historical";disposition="deferred-evolved";blocking=$false;predecessor="1.3.9"},
    [ordered]@{id="factorio-0.12";factorio="0.12";code="012";support="museum";disposition="deferred-museum";blocking=$false;predecessor=$null},
    [ordered]@{id="factorio-0.11";factorio="0.11";code="011";support="museum";disposition="deferred-museum";blocking=$false;predecessor=$null},
    [ordered]@{id="factorio-0.10";factorio="0.10";code="010";support="museum";disposition="deferred-museum";blocking=$false;predecessor=$null},
    [ordered]@{id="factorio-0.9";factorio="0.9";code="009";support="museum";disposition="deferred-museum";blocking=$false;predecessor=$null},
    [ordered]@{id="factorio-0.8";factorio="0.8";code="008";support="museum";disposition="deferred-museum";blocking=$false;predecessor=$null},
    [ordered]@{id="factorio-0.7";factorio="0.7";code="007";support="museum";disposition="deferred-museum";blocking=$false;predecessor=$null},
    [ordered]@{id="factorio-0.6";factorio="0.6";code="006";support="museum";disposition="deferred-museum";blocking=$false;predecessor=$null}
  )

  $targets = @($registry.payload.targets)
  if ($targets.Count -ne 17 -or [int]$registry.payload.target_count -ne 17 -or
      @($targets | Group-Object id | Where-Object Count -ne 1).Count -ne 0 -or
      @($targets | Group-Object distribution_target_code | Where-Object Count -ne 1).Count -ne 0) {
    throw "[mir4-registry-cardinality] V2 must contain exactly 17 unique target IDs and codes."
  }
  for ($index = 0; $index -lt $expected.Count; $index++) {
    $row = $targets[$index]
    $want = $expected[$index]
    $actualPredecessor = if ($null -eq $row.mir3_predecessor) { $null } else { [string]$row.mir3_predecessor }
    if ([string]$row.id -ne [string]$want.id -or
        [string]$row.factorio -ne [string]$want.factorio -or
        [string]$row.distribution_target_code -ne [string]$want.code -or
        [string]$row.support_tier -ne [string]$want.support -or
        [string]$row.disposition -ne [string]$want.disposition -or
        [bool]$row.release_blocking -ne [bool]$want.blocking -or
        $actualPredecessor -ne $want.predecessor) {
      throw "[mir4-registry-mapping] V2 target mapping or disposition drifted at index $index."
    }
  }

  $legacyFieldName = "portal" + "_target_id"
  $historicalRegistryPath = (Resolve-Path -LiteralPath (Join-Path $RepoRoot $script:MIR4TargetRegistryV1Path)).Path
  $repositoryTextFiles = @(& git -C $RepoRoot ls-files --cached --others --exclude-standard -- '*.json' '*.ps1' '*.md' '*.yml' '*.yaml' '*.lua' '*.toml' '*.txt')
  if ($LASTEXITCODE -ne 0) { throw "[mir4-v1-field-scan] Unable to enumerate tracked and untracked non-ignored authority and executable text." }
  $governedTextFiles = @(
    $repositoryTextFiles |
      ForEach-Object { ([string]$_).Replace("\", "/") } |
      Where-Object {
        $_ -and
        $_ -notlike ".mir/target-lines/*" -and
        $_ -notlike ".mir/evidence/*" -and
        $_ -notlike "dist/*" -and
        $_ -notlike "build/results/*" -and
        $_ -notlike "build/*"
      } |
      Sort-Object -Unique
  )
  foreach ($relativePath in $governedTextFiles) {
    $path = Join-Path $RepoRoot ([string]$relativePath)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        [string]::Equals((Resolve-Path -LiteralPath $path).Path, $historicalRegistryPath, [StringComparison]::OrdinalIgnoreCase)) {
      continue
    }
    if (Select-String -LiteralPath $path -SimpleMatch $legacyFieldName -Quiet) {
      throw "[mir4-v1-field-executable] Legacy V1 target identity exists outside its frozen historical record: $relativePath"
    }
  }

  $patchSuite = @(0, 1, 8, 9, 99)
  if ((@($vectors.public_patch_suite) -join "|") -ne "00|01|08|09|99" -or
      @($vectors.valid_vectors).Count -ne 86 -or
      @($vectors.invalid_vectors).Count -ne 8 -or
      @($vectors.valid_vectors | Group-Object case_id | Where-Object Count -ne 1).Count -ne 0 -or
      @($vectors.invalid_vectors | Group-Object case_id | Where-Object Count -ne 1).Count -ne 0) {
    throw "[mir4-vector-cardinality] Codec vectors must contain the exact 85 public, one internal, and eight negative cases."
  }

  foreach ($want in $expected) {
    foreach ($sourcePatch in $patchSuite) {
      $caseId = "$($want.id)-patch-$($sourcePatch.ToString('D2', [Globalization.CultureInfo]::InvariantCulture))"
      $rows = @($vectors.valid_vectors | Where-Object { [string]$_.case_id -eq $caseId -and [string]$_.scope -eq "public-target" })
      if ($rows.Count -ne 1) {
        throw "[mir4-vector-coverage] Missing or duplicate public codec vector: $caseId"
      }
      $actual = Resolve-MIR4DistributionIdentity -TargetRegistry $registry -VersionAuthority $version -TargetId ([string]$want.id) -SourceMinor 0 -SourcePatch $sourcePatch
      $vector = $rows[0]
      foreach ($field in @("target_id", "distribution_target_code", "source_minor", "source_patch", "source_patch_text", "source_version", "source_tag", "encoded_component", "encoded_component_text", "distribution_version", "distribution_tag")) {
        if ([string]$actual.$field -cne [string]$vector.$field) {
          throw "[mir4-vector-value] Codec vector '$caseId' disagrees with the executable projection at '$field'."
        }
      }
      $decoded = ConvertFrom-MIR4DistributionComponent -EncodedComponentText ([string]$vector.encoded_component_text)
      if ([string]$decoded.distribution_target_code -cne [string]$want.code -or [int]$decoded.source_patch -ne $sourcePatch) {
        throw "[mir4-vector-round-trip] Codec vector '$caseId' is not exactly reversible."
      }
    }
  }

  $upperRows = @($vectors.valid_vectors | Where-Object { [string]$_.case_id -eq "internal-upper-bound" -and [string]$_.scope -eq "internal-boundary" })
  if ($upperRows.Count -ne 1) { throw "[mir4-vector-boundary] Internal upper-boundary vector is absent or duplicated." }
  $upper = New-MIR4DistributionIdentityProjection -DistributionTargetCode "654" -SourceMinor 65535 -SourcePatch 99
  foreach ($field in @("distribution_target_code", "source_minor", "source_patch", "source_patch_text", "source_version", "source_tag", "encoded_component", "encoded_component_text", "distribution_version", "distribution_tag")) {
    if ([string]$upper.$field -cne [string]$upperRows[0].$field) {
      throw "[mir4-vector-boundary] Internal upper-boundary vector disagrees at '$field'."
    }
  }

  foreach ($negative in @($vectors.invalid_vectors)) {
    $caught = $false
    try {
      switch ([string]$negative.operation) {
        "encode" {
          $null = ConvertTo-MIR4DistributionComponent -DistributionTargetCode ([string]$negative.distribution_target_code) -SourcePatch ([int]$negative.source_patch)
        }
        "decode" {
          $null = ConvertFrom-MIR4DistributionComponent -EncodedComponentText ([string]$negative.encoded_component_text)
        }
        "resolve-historical" {
          $null = Resolve-MIR4DistributionIdentity -TargetRegistry $registryV1 -VersionAuthority $versionV1 -TargetId ([string]$negative.target_id) -SourceMinor 0 -SourcePatch ([int]$negative.source_patch)
        }
        default { throw "[mir4-negative-operation] Unknown negative vector operation." }
      }
    } catch {
      if (-not $_.Exception.Message.Contains("[$([string]$negative.expected_error)]")) {
        throw "[mir4-negative-result] Negative vector '$($negative.case_id)' failed for the wrong reason: $($_.Exception.Message)"
      }
      $caught = $true
    }
    if (-not $caught) {
      throw "[mir4-negative-result] Negative vector '$($negative.case_id)' was unexpectedly accepted."
    }
  }

  return [pscustomobject][ordered]@{
    kind = "MIR4R0DistributionIdentityValidationV2"
    status = "passed"
    public_target_count = 17
    public_vector_count = 85
    internal_boundary_vector_count = 1
    negative_vector_count = 8
    historical_v1_executable = $false
  }
}
