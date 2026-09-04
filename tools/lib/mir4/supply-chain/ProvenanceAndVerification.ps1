function New-MIR4SlsaProvenanceV1 {
  param(
    [Parameter(Mandatory)]$Inventory,
    [string]$ComponentId
  )

  if (-not (Test-MIR4ComponentInventoryV1 -Inventory $Inventory)) {
    throw '[mir4-slsa-inventory]'
  }
  $components = if ([string]::IsNullOrWhiteSpace($ComponentId)) {
    @($Inventory.components)
  } else {
    @($Inventory.components | Where-Object { [string]$_.component_id -ceq $ComponentId })
  }
  if ($components.Count -eq 0) {
    throw "Unknown MIR 4 SLSA component: $ComponentId"
  }
  $subjects = @(
    foreach ($component in $components) {
      $sha256 = if ($null -ne $component.artifact) {
        [string]$component.artifact.sha256
      } else {
        [string]$component.content_root.sha256
      }
      [pscustomobject][ordered]@{
        name = [string]$component.component_id
        digest = [pscustomobject][ordered]@{ sha256 = $sha256.ToLowerInvariant() }
      }
    }
  )
  $resolved = [Collections.Generic.List[object]]::new()
  $resolved.Add([pscustomobject][ordered]@{
    uri = "git+https://github.com/Julesc013/more-infinite-research@$($Inventory.source.commit)"
    digest = [pscustomobject][ordered]@{
      gitCommit = [string]$Inventory.source.commit
      gitTree = [string]$Inventory.source.tree
    }
  })
  foreach ($set in $Inventory.identity_sets) {
    $resolved.Add([pscustomobject][ordered]@{
      uri = "urn:mir4:identity-set:$($set.name)"
      digest = [pscustomobject][ordered]@{
        sha256 = ([string]$set.root_sha256).ToLowerInvariant()
      }
    })
  }
  return [pscustomobject][ordered]@{
    '_type' = 'https://in-toto.io/Statement/v1'
    subject = $subjects
    predicateType = 'https://slsa.dev/provenance/v1'
    predicate = [pscustomobject][ordered]@{
      buildDefinition = [pscustomobject][ordered]@{
        buildType = 'https://more-infinite-research.invalid/build-types/supply-chain-v1'
        externalParameters = [pscustomobject][ordered]@{
          programme_id = [string]$Inventory.programme_id
          turn = 'T15'
          state = [string]$Inventory.state
          component_ids = @($components | ForEach-Object { [string]$_.component_id })
        }
        internalParameters = [pscustomobject][ordered]@{
          network = 'disabled'
          source_date_epoch = [long]$Inventory.source.source_date_epoch
          archive_order = [string]$Inventory.construction.archive_order
          archive_timestamp = [string]$Inventory.construction.archive_timestamp
          working_tree_clean = [bool]$Inventory.source.working_tree_clean
        }
        resolvedDependencies = $resolved.ToArray()
      }
      runDetails = [pscustomobject][ordered]@{
        builder = [pscustomobject][ordered]@{
          id = 'https://github.com/Julesc013/more-infinite-research/tools/lib/mir4/SupplyChain.ps1'
          builderDependencies = @([pscustomobject][ordered]@{
            uri = 'urn:mir4:canonicalization:MIR4BootstrapCanonicalJsonV1'
            digest = [pscustomobject][ordered]@{
              sha256 = ([string]$Inventory.identity_sets[0].root_sha256).ToLowerInvariant()
            }
          })
          version = [pscustomobject][ordered]@{ SupplyChain = '1' }
        }
        metadata = [pscustomobject][ordered]@{
          invocationId = "urn:mir4:t15:$($Inventory.record_sha256.ToLowerInvariant())"
          startedOn = [string]$Inventory.source.commit_time
          finishedOn = [string]$Inventory.source.commit_time
        }
        byproducts = @([pscustomobject][ordered]@{
          name = 'component-inventory.json'
          digest = [pscustomobject][ordered]@{
            sha256 = ([string]$Inventory.record_sha256).ToLowerInvariant()
          }
        })
      }
    }
  }
}

function Test-MIR4Spdx301Document {
  param(
    [Parameter(Mandatory)]$Document,
    [Parameter(Mandatory)]$Inventory,
    [string]$RepoRoot,
    [string]$OfficialSchemaPath
  )

  try {
    if ([string]$Document.'@context' -cne 'https://spdx.org/rdf/3.0.1/spdx-context.jsonld') {
      return $false
    }
    $graph = @($Document.'@graph')
    if (@($graph | Where-Object { [string]$_.type -ceq 'SpdxDocument' }).Count -ne 1 -or
        @($graph | Where-Object { [string]$_.type -ceq 'software_Sbom' }).Count -ne 1 -or
        @($graph | Where-Object { [string]$_.type -ceq 'software_Package' }).Count -eq 0 -or
        @($graph | Where-Object { [string]$_.type -ceq 'software_File' }).Count -eq 0) {
      return $false
    }
    $allowedTypes = @(
      'CreationInfo',
      'Tool',
      'SpdxDocument',
      'software_Sbom',
      'simplelicensing_LicenseExpression',
      'software_Package',
      'software_File',
      'Relationship'
    )
    if (@($graph | Where-Object { [string]$_.type -cnotin $allowedTypes }).Count -ne 0) {
      return $false
    }
    $elementIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($element in $graph) {
      $id = if ($element.PSObject.Properties['spdxId']) {
        [string]$element.spdxId
      } else {
        [string]$element.'@id'
      }
      if ([string]::IsNullOrWhiteSpace($id) -or -not $elementIds.Add($id)) {
        return $false
      }
      switch ([string]$element.type) {
        'CreationInfo' {
          if ($id -cnotmatch '^_:[a-z0-9-]+$' -or
              [string]$element.specVersion -cne '3.0.1' -or
              [string]$element.created -cnotmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$' -or
              @($element.createdBy).Count -ne 1) {
            return $false
          }
        }
        'Tool' {
          if ([string]$element.name -cne 'MIR4 SupplyChain.ps1') { return $false }
        }
        'SpdxDocument' {
          if (@($element.rootElement).Count -ne 1 -or
              @($element.profileConformance | Sort-Object -CaseSensitive) -join '|' -cne 'core|simpleLicensing|software') {
            return $false
          }
        }
        'software_Sbom' {
          if (@($element.rootElement).Count -eq 0 -or
              @($element.software_sbomType).Count -ne 1 -or
              [string]$element.software_sbomType[0] -cne 'build') {
            return $false
          }
        }
        'simplelicensing_LicenseExpression' {
          if ([string]$element.simplelicensing_licenseExpression -cne 'MPL-2.0') { return $false }
        }
        'software_Package' {
          if ([string]$element.software_copyrightText -cne 'NOASSERTION' -or
              @($element.software_attributionText).Count -ne 1) {
            return $false
          }
        }
        'software_File' {
          Assert-MIR4SupplyChainRelativePath -Path ([string]$element.name)
          if ([string]$element.software_copyrightText -cne 'NOASSERTION' -or
              @($element.software_attributionText).Count -ne 1) {
            return $false
          }
        }
        'Relationship' {
          if ([string]$element.relationshipType -cnotin @('contains', 'hasDeclaredLicense') -or
              [string]$element.completeness -cne 'complete' -or
              @($element.to).Count -eq 0) {
            return $false
          }
        }
      }
      if ([string]$element.type -ne 'CreationInfo' -and
          [string]$element.creationInfo -cne '_:creationinfo') {
        return $false
      }
    }
    foreach ($element in $graph) {
      if (-not $element.PSObject.Properties['verifiedUsing']) { continue }
      foreach ($hash in @($element.verifiedUsing)) {
        if ([string]$hash.type -cne 'Hash' -or
            [string]$hash.algorithm -cne 'sha256' -or
            [string]$hash.hashValue -cnotmatch '^[a-f0-9]{64}$') {
          return $false
        }
      }
    }
    $raw = ConvertTo-MIR4BootstrapCanonicalJson -Value $Document
    if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) {
      if (-not ($raw | Test-Json -SchemaFile (Join-Path $RepoRoot $script:MIR4SpdxProfileSchemaPath) -ErrorAction Stop)) {
        return $false
      }
    }
    if (-not [string]::IsNullOrWhiteSpace($OfficialSchemaPath)) {
      $officialHash = (Get-MIR4Sha256File -Path $OfficialSchemaPath).ToUpperInvariant()
      if ($officialHash -cne [string]$Inventory.standards.primary_sbom.official_schema_sha256) {
        return $false
      }
      # PowerShell's Test-Json expands the official SPDX anyOf closure once per
      # graph element. A whole-project graph can consume the host's entire RAM.
      # Validate one generator-complete component against the exact official
      # schema, then validate every full-graph element above with the same
      # closed generator profile.
      $representativeId = [string](@(
        $Inventory.components |
          Sort-Object { @($_.files).Count }, component_id |
          Select-Object -First 1
      )[0].component_id)
      $representative = New-MIR4Spdx301Document -Inventory $Inventory -ComponentId $representativeId
      $representativeRaw = ConvertTo-MIR4BootstrapCanonicalJson -Value $representative
      if (-not ($representativeRaw | Test-Json -SchemaFile $OfficialSchemaPath -ErrorAction Stop)) {
        return $false
      }
    }
    return $true
  } catch {
    return $false
  }
}

function Test-MIR4Spdx23CompatibilityDocument {
  param(
    [Parameter(Mandatory)]$Document,
    [Parameter(Mandatory)][string]$RepoRoot
  )

  try {
    $raw = ConvertTo-MIR4BootstrapCanonicalJson -Value $Document
    return [string]$Document.spdxVersion -ceq 'SPDX-2.3' -and
      [string]$Document.dataLicense -ceq 'CC0-1.0' -and
      ($raw | Test-Json -SchemaFile (Join-Path $RepoRoot $script:MIR4Spdx2ProfileSchemaPath) -ErrorAction Stop)
  } catch {
    return $false
  }
}

function Test-MIR4SlsaProvenanceV1 {
  param(
    [Parameter(Mandatory)]$Statement,
    [Parameter(Mandatory)][string]$RepoRoot
  )

  try {
    if ([string]$Statement.'_type' -cne 'https://in-toto.io/Statement/v1' -or
        [string]$Statement.predicateType -cne 'https://slsa.dev/provenance/v1' -or
        [string]$Statement.predicate.buildDefinition.internalParameters.network -cne 'disabled' -or
        @($Statement.subject).Count -eq 0) {
      return $false
    }
    $raw = ConvertTo-MIR4BootstrapCanonicalJson -Value $Statement
    return ($raw | Test-Json -SchemaFile (Join-Path $RepoRoot $script:MIR4SlsaProfileSchemaPath) -ErrorAction Stop)
  } catch {
    return $false
  }
}

function Write-MIR4SupplyChainRecord {
  param(
    [Parameter(Mandatory)]$Record,
    [Parameter(Mandatory)][string]$Path
  )

  $parent = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  [IO.File]::WriteAllText(
    $Path,
    (ConvertTo-MIR4BootstrapCanonicalJson -Value $Record) + [char]10,
    [Text.UTF8Encoding]::new($false)
  )
}
