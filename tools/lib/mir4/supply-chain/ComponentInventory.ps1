function New-MIR4ComponentInventoryV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Collections.IDictionary]$ArtifactPaths = @{},
    [Collections.IDictionary]$ProvidedRowsByComponent = @{},
    [switch]$RequireClean
  )

  $repo = Resolve-MIR4SupplyChainRepoRoot -RepoRoot $RepoRoot
  $authority = Get-MIR4SupplyChainAuthority -RepoRoot $repo
  $source = Get-MIR4SupplyChainSourceIdentity -RepoRoot $repo
  if ($RequireClean -and -not [bool]$source.working_tree_clean) {
    throw '[mir4-supply-chain-clean-root-required]'
  }

  $cachedRepositoryRows = @(Get-MIR4SupplyChainRepositoryRows -RepoRoot $repo)
  $identitySets = [Collections.Generic.List[object]]::new()
  foreach ($property in $authority.identity_sets.PSObject.Properties) {
    $identityPaths = [string[]]@($property.Value | ForEach-Object { [string]$_ })
    $identityRows = @(Select-MIR4SupplyChainRows -Rows $cachedRepositoryRows -Paths $identityPaths)
    $identityRoot = Get-MIR4SupplyChainRowsRoot -Rows $identityRows
    $identitySets.Add([pscustomobject][ordered]@{
      name = $property.Name
      root_sha256 = $identityRoot.sha256
      file_count = $identityRoot.file_count
      total_bytes = $identityRoot.total_bytes
      files = $identityRows
    })
  }

  $cachedPackageRows = $null
  $components = [Collections.Generic.List[object]]::new()
  foreach ($component in $authority.components) {
    $componentId = [string]$component.component_id
    $materialization = 'source-closure'
    $artifact = $null
    if (Test-MIR4SupplyChainMapKey -Map $ProvidedRowsByComponent -Key $componentId) {
      $rows = @(
        $ProvidedRowsByComponent[$componentId] |
          ForEach-Object { ConvertTo-MIR4SupplyChainFileRow -Row $_ -Origin provided }
      )
      $materialization = 'provided-payload'
    } elseif (Test-MIR4SupplyChainMapKey -Map $ArtifactPaths -Key $componentId) {
      $artifactPath = Resolve-MIR4SupplyChainInputPath -RepoRoot $repo -Path ([string]$ArtifactPaths[$componentId])
      $rows = @(Get-MIR4SupplyChainArchiveRows -Path $artifactPath)
      $artifactItem = Get-Item -LiteralPath $artifactPath
      $artifact = [pscustomobject][ordered]@{
        name = [string]$component.inclusion.artifact_name
        bytes = [long]$artifactItem.Length
        sha256 = (Get-MIR4Sha256File -Path $artifactPath).ToUpperInvariant()
      }
      $materialization = 'artifact'
    } else {
      switch ([string]$component.source.selector) {
        'repository-tracked-source' {
          $rows = @($cachedRepositoryRows)
        }
        'player-package-source' {
          if ($null -eq $cachedPackageRows) {
            $cachedPackageRows = @(Select-MIR4SupplyChainRows -Rows $cachedRepositoryRows -Paths @(
              Get-MIRPackageSourceFiles -RepoRoot $repo
            ))
          }
          $rows = @($cachedPackageRows)
        }
        'explicit-files' {
          $explicitPaths = [string[]]@($component.source.paths | ForEach-Object { [string]$_ })
          $rows = @(Select-MIR4SupplyChainRows -Rows $cachedRepositoryRows -Paths $explicitPaths)
        }
        'preview-payload' {
          $previewPaths = @([string]$component.source_map.generator, $script:MIR4SupplyChainAuthorityPath, 'LICENSE') |
            Sort-Object -Unique -CaseSensitive
          $rows = @(Select-MIR4SupplyChainRows -Rows $cachedRepositoryRows -Paths $previewPaths)
        }
        default {
          throw "Unknown MIR 4 supply-chain selector: $($component.source.selector)"
        }
      }
    }
    if ($rows.Count -eq 0) {
      throw "MIR 4 supply-chain component is empty: $componentId"
    }
    $root = Get-MIR4SupplyChainRowsRoot -Rows $rows
    $components.Add([pscustomobject][ordered]@{
      component_id = $componentId
      name = [string]$component.name
      version = [string]$component.version
      artifact_class = [string]$component.artifact_class
      target = $component.target
      materialization = $materialization
      source_selector = [string]$component.source.selector
      source_map = $component.source_map
      license = $component.license
      copyright = $component.copyright
      redistribution_custody = $component.redistribution_custody
      capsule_partition = [string]$component.inclusion.release_capsule_partition
      artifact = $artifact
      content_root = $root
      files = @($rows | Sort-Object path -CaseSensitive)
    })
  }

  $record = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4ComponentInventoryV1'
    programme_id = [string]$authority.programme_id
    turn = 'T15'
    state = 'pre-freeze-supply-chain-preparation'
    source = $source
    standards = $authority.standards
    construction = $authority.construction
    identity_sets = $identitySets.ToArray()
    components = $components.ToArray()
    transition_authority = [pscustomobject][ordered]@{
      source_freeze = $false
      candidate_allocation = $false
      production_signing = $false
      publication = $false
    }
    record_sha256 = $null
  }
  $record.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $record
  return $record
}

function Test-MIR4ComponentInventoryV1 {
  param(
    [Parameter(Mandatory)]$Inventory,
    [string]$RepoRoot
  )

  try {
    if ([int]$Inventory.schema -ne 1 -or
        [string]$Inventory.kind -cne 'MIR4ComponentInventoryV1' -or
        [string]$Inventory.turn -cne 'T15' -or
        @($Inventory.components).Count -ne 9 -or
        -not (Test-MIR4BootstrapRecordHash -Record $Inventory)) {
      return $false
    }
    $ids = @($Inventory.components | ForEach-Object { [string]$_.component_id })
    if (@($ids | Sort-Object -Unique -CaseSensitive).Count -ne 9) { return $false }
    foreach ($component in $Inventory.components) {
      $root = Get-MIR4SupplyChainRowsRoot -Rows @($component.files)
      if ([string]$root.sha256 -cne [string]$component.content_root.sha256 -or
          [int]$root.file_count -ne [int]$component.content_root.file_count -or
          [long]$root.total_bytes -ne [long]$component.content_root.total_bytes) {
        return $false
      }
    }
    foreach ($set in $Inventory.identity_sets) {
      $root = Get-MIR4SupplyChainRowsRoot -Rows @($set.files)
      if ([string]$root.sha256 -cne [string]$set.root_sha256) { return $false }
    }
    if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) {
      $repo = Resolve-MIR4SupplyChainRepoRoot -RepoRoot $RepoRoot
      $raw = ConvertTo-MIR4BootstrapCanonicalJson -Value $Inventory
      if (-not ($raw | Test-Json -SchemaFile (Join-Path $repo $script:MIR4ComponentInventorySchemaPath) -ErrorAction Stop)) {
        return $false
      }
      $source = Get-MIR4SupplyChainSourceIdentity -RepoRoot $repo
      if ([string]$source.commit -cne [string]$Inventory.source.commit -or
          [string]$source.tree -cne [string]$Inventory.source.tree) {
        return $false
      }
    }
    return $true
  } catch {
    return $false
  }
}

