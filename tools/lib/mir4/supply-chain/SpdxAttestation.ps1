function Get-MIR4SpdxElementToken {
  param([Parameter(Mandatory)][string]$Value)

  return (Get-MIR4Sha256String -Value $Value).Substring(0, 24).ToLowerInvariant()
}

function New-MIR4Spdx301Document {
  param(
    [Parameter(Mandatory)]$Inventory,
    [string]$ComponentId
  )

  if (-not (Test-MIR4ComponentInventoryV1 -Inventory $Inventory)) {
    throw '[mir4-spdx-inventory]'
  }
  $components = if ([string]::IsNullOrWhiteSpace($ComponentId)) {
    @($Inventory.components)
  } else {
    @($Inventory.components | Where-Object { [string]$_.component_id -ceq $ComponentId })
  }
  if ($components.Count -eq 0) {
    throw "Unknown MIR 4 SPDX component: $ComponentId"
  }

  $namespace = "https://more-infinite-research.invalid/spdx/3.0.1/$($Inventory.source.commit)/$($Inventory.record_sha256.ToLowerInvariant())"
  $creationId = '_:creationinfo'
  $toolId = "$namespace/agent/supply-chain"
  $documentId = "$namespace/document"
  $sbomId = "$namespace/sbom"
  $licenseId = "$namespace/license/mpl-2.0"
  $graph = [Collections.Generic.List[object]]::new()
  $documentElements = [Collections.Generic.List[string]]::new()
  $sbomElements = [Collections.Generic.List[string]]::new()
  $sbomRoots = [Collections.Generic.List[string]]::new()

  $graph.Add([pscustomobject][ordered]@{
    type = 'CreationInfo'
    '@id' = $creationId
    createdBy = @($toolId)
    specVersion = '3.0.1'
    created = [string]$Inventory.source.commit_time
  })
  $graph.Add([pscustomobject][ordered]@{
    type = 'Tool'
    spdxId = $toolId
    creationInfo = $creationId
    name = 'MIR4 SupplyChain.ps1'
  })
  $documentElements.Add($toolId)
  $graph.Add([pscustomobject][ordered]@{
    type = 'simplelicensing_LicenseExpression'
    spdxId = $licenseId
    creationInfo = $creationId
    simplelicensing_licenseExpression = 'MPL-2.0'
  })
  $documentElements.Add($licenseId)
  $documentElements.Add($sbomId)

  foreach ($component in $components) {
    $packageId = "$namespace/package/$($component.component_id)"
    $sbomRoots.Add($packageId)
    $sbomElements.Add($packageId)
    $documentElements.Add($packageId)
    $packageElement = [ordered]@{
      type = 'software_Package'
      spdxId = $packageId
      creationInfo = $creationId
      name = [string]$component.name
      software_packageVersion = [string]$component.version
      software_downloadLocation = 'https://github.com/Julesc013/more-infinite-research/releases'
      software_primaryPurpose = $(if ([string]$component.artifact_class -eq 'source-release') { 'source' } else { 'archive' })
      software_attributionText = @(
        "Declared license: MPL-2.0; preserve LICENSE. Copyright: NOASSERTION. MIR4 content root: sha256:$(([string]$component.content_root.sha256).ToLowerInvariant())."
      )
      software_copyrightText = 'NOASSERTION'
      verifiedUsing = @([pscustomobject][ordered]@{
        type = 'Hash'
        '@id' = "_:hash-$(Get-MIR4SpdxElementToken -Value $packageId)"
        algorithm = 'sha256'
        hashValue = $(if ($null -ne $component.artifact) {
          ([string]$component.artifact.sha256).ToLowerInvariant()
        } else {
          ([string]$component.content_root.sha256).ToLowerInvariant()
        })
      })
    }
    $graph.Add([pscustomobject]$packageElement)

    $fileIds = [Collections.Generic.List[string]]::new()
    foreach ($row in $component.files) {
      $fileId = "$namespace/file/$($component.component_id)/$(Get-MIR4SpdxElementToken -Value ([string]$row.path))"
      $fileIds.Add($fileId)
      $sbomElements.Add($fileId)
      $documentElements.Add($fileId)
      $graph.Add([pscustomobject][ordered]@{
        type = 'software_File'
        spdxId = $fileId
        creationInfo = $creationId
        name = [string]$row.path
        software_primaryPurpose = $(switch ([string]$row.source_class) {
          'binary-asset' { 'other' }
          'generated-projection' { 'evidence' }
          default { 'source' }
        })
        software_attributionText = @('Declared license: MPL-2.0; see LICENSE. Copyright: NOASSERTION.')
        software_copyrightText = 'NOASSERTION'
        verifiedUsing = @([pscustomobject][ordered]@{
          type = 'Hash'
          '@id' = "_:hash-$(Get-MIR4SpdxElementToken -Value $fileId)"
          algorithm = 'sha256'
          hashValue = ([string]$row.sha256).ToLowerInvariant()
        })
      })
    }

    $containsId = "$namespace/relationship/$($component.component_id)/contains"
    $licenseRelationshipId = "$namespace/relationship/$($component.component_id)/declared-license"
    $graph.Add([pscustomobject][ordered]@{
      type = 'Relationship'
      spdxId = $containsId
      creationInfo = $creationId
      from = $packageId
      relationshipType = 'contains'
      to = $fileIds.ToArray()
      completeness = 'complete'
    })
    $graph.Add([pscustomobject][ordered]@{
      type = 'Relationship'
      spdxId = $licenseRelationshipId
      creationInfo = $creationId
      from = $packageId
      relationshipType = 'hasDeclaredLicense'
      to = @($licenseId)
      completeness = 'complete'
    })
    $documentElements.Add($containsId)
    $documentElements.Add($licenseRelationshipId)
  }

  $graph.Insert(2, [pscustomobject][ordered]@{
    type = 'SpdxDocument'
    spdxId = $documentId
    creationInfo = $creationId
    rootElement = @($sbomId)
    element = $documentElements.ToArray()
    profileConformance = @('core', 'software', 'simpleLicensing')
  })
  $graph.Insert(3, [pscustomobject][ordered]@{
    type = 'software_Sbom'
    spdxId = $sbomId
    creationInfo = $creationId
    rootElement = $sbomRoots.ToArray()
    element = $sbomElements.ToArray()
    software_sbomType = @('build')
  })
  return [pscustomobject][ordered]@{
    '@context' = 'https://spdx.org/rdf/3.0.1/spdx-context.jsonld'
    '@graph' = $graph.ToArray()
  }
}

function New-MIR4Spdx23CompatibilityDocument {
  param(
    [Parameter(Mandatory)]$Inventory,
    [string]$ComponentId
  )

  if (-not (Test-MIR4ComponentInventoryV1 -Inventory $Inventory)) {
    throw '[mir4-spdx2-inventory]'
  }
  $components = if ([string]::IsNullOrWhiteSpace($ComponentId)) {
    @($Inventory.components)
  } else {
    @($Inventory.components | Where-Object { [string]$_.component_id -ceq $ComponentId })
  }
  if ($components.Count -eq 0) {
    throw "Unknown MIR 4 SPDX 2.3 component: $ComponentId"
  }
  $packages = [Collections.Generic.List[object]]::new()
  $files = [Collections.Generic.List[object]]::new()
  $relationships = [Collections.Generic.List[object]]::new()
  foreach ($component in $components) {
    $packageSpdxId = "SPDXRef-Package-$($component.component_id)"
    $package = [ordered]@{
      name = [string]$component.name
      SPDXID = $packageSpdxId
      versionInfo = [string]$component.version
      downloadLocation = 'NOASSERTION'
      filesAnalyzed = $true
      licenseConcluded = 'NOASSERTION'
      licenseDeclared = 'MPL-2.0'
      copyrightText = 'NOASSERTION'
      externalRefs = @([ordered]@{
        referenceCategory = 'OTHER'
        referenceType = 'mir4-content-root'
        referenceLocator = "sha256:$(([string]$component.content_root.sha256).ToLowerInvariant())"
      })
    }
    if ($null -ne $component.artifact) {
      $package['packageFileName'] = [string]$component.artifact.name
      $package['checksums'] = @([ordered]@{
        algorithm = 'SHA256'
        checksumValue = ([string]$component.artifact.sha256).ToLowerInvariant()
      })
    }
    $packages.Add([pscustomobject]$package)
    $relationships.Add([pscustomobject][ordered]@{
      spdxElementId = 'SPDXRef-DOCUMENT'
      relationshipType = 'DESCRIBES'
      relatedSpdxElement = $packageSpdxId
    })
    foreach ($row in $component.files) {
      $fileSpdxId = "SPDXRef-File-$($component.component_id)-$(Get-MIR4SpdxElementToken -Value ([string]$row.path))"
      $files.Add([pscustomobject][ordered]@{
        fileName = "./$([string]$row.path)"
        SPDXID = $fileSpdxId
        checksums = @([ordered]@{
          algorithm = 'SHA256'
          checksumValue = ([string]$row.sha256).ToLowerInvariant()
        })
        licenseConcluded = 'NOASSERTION'
        licenseInfoInFiles = @('NOASSERTION')
        copyrightText = 'NOASSERTION'
      })
      $relationships.Add([pscustomobject][ordered]@{
        spdxElementId = $packageSpdxId
        relationshipType = 'CONTAINS'
        relatedSpdxElement = $fileSpdxId
      })
    }
  }
  return [pscustomobject][ordered]@{
    spdxVersion = 'SPDX-2.3'
    dataLicense = 'CC0-1.0'
    SPDXID = 'SPDXRef-DOCUMENT'
    name = 'More Infinite Research 4 compatibility SBOM'
    documentNamespace = "https://more-infinite-research.invalid/spdx/2.3/$($Inventory.source.commit)/$($Inventory.record_sha256.ToLowerInvariant())"
    creationInfo = [pscustomobject][ordered]@{
      created = [string]$Inventory.source.commit_time
      creators = @('Tool: MIR4 SupplyChain.ps1')
    }
    documentDescribes = @($packages | ForEach-Object { [string]$_.SPDXID })
    packages = $packages.ToArray()
    files = $files.ToArray()
    relationships = $relationships.ToArray()
  }
}

