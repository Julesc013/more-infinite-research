# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..'))
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $RepoRoot 'tools/mir/application/technology/TechnologyAcceptance.ps1')

function Assert-MIRTechnologyCatalogEvaluation {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "[mir4-technology-catalog-evaluation-test] $Message" }
}

function Copy-MIRTechnologyCatalogEvaluationValue {
  param([Parameter(Mandatory)]$Value)
  return ($Value | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100)
}

function Assert-MIRTechnologyCatalogEvaluationRejects {
  param(
    [Parameter(Mandatory)][scriptblock]$Action,
    [Parameter(Mandatory)][string]$ExpectedCode,
    [Parameter(Mandatory)][string]$Name
  )
  $caught = $null
  try {
    & $Action
  } catch {
    $caught = $_.Exception.Message
  }
  Assert-MIRTechnologyCatalogEvaluation ($null -ne $caught) "$Name did not reject the incomplete catalog."
  Assert-MIRTechnologyCatalogEvaluation ($caught.Contains($ExpectedCode)) "$Name rejected with the wrong error: $caught"
}

function Assert-MIRTechnologyCatalogEvaluationRejectsBeforeWrite {
  param(
    [Parameter(Mandatory)][scriptblock]$Action,
    [Parameter(Mandatory)][string]$ExpectedOutput,
    [Parameter(Mandatory)][string]$Name
  )
  Assert-MIRTechnologyCatalogEvaluationRejects -Action $Action `
    -ExpectedCode '[mir4-technology-catalog-full-diagnostics-required]' -Name $Name
  Assert-MIRTechnologyCatalogEvaluation (-not (Test-Path -LiteralPath $ExpectedOutput)) `
    "$Name wrote an artifact after rejecting the incomplete catalog."
  $parent = Split-Path -Parent $ExpectedOutput
  Assert-MIRTechnologyCatalogEvaluation (-not (Test-Path -LiteralPath $parent)) `
    "$Name created its output directory before rejecting the incomplete catalog."
}

function Write-MIRTechnologyCatalogEvaluationJson {
  param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][string]$Path)
  $Value | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding utf8NoBOM
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("mir4-technology-catalog-evaluation-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null

try {
  $firstAlternative = [ordered]@{
    alternative_id = 'emit:mir-evaluation-a'
    action = 'emit'
    disposition = 'materialize'
    design_fingerprint = 'design-evaluation-a'
    qualification_fingerprint = 'qualification-evaluation-a'
    qualification_decision = 'qualified'
    technology_design = [ordered]@{
      technology_id = 'mir-evaluation-a'
      design_fingerprint = 'design-evaluation-a'
    }
  }
  $secondAlternative = [ordered]@{
    alternative_id = 'diagnose:mir-evaluation-b'
    action = 'diagnose'
    disposition = 'safe-diagnostic'
    design_fingerprint = 'design-evaluation-b'
    qualification_fingerprint = 'qualification-evaluation-b'
    qualification_decision = 'qualified'
    technology_design = [ordered]@{
      technology_id = 'mir-evaluation-b'
      design_fingerprint = 'design-evaluation-b'
    }
  }
  $historical = [ordered]@{
    schema = 3
    phase = 'final'
    mutation_authority = $false
    selection_authority = 'deterministic-policy-v2'
    candidate_catalog_fingerprint = 'candidate-evaluation'
    qualification_catalog_fingerprint = 'qualification-evaluation'
    preselection_catalog_fingerprint = 'preselection-evaluation'
    selection_fingerprint = 'selection-evaluation'
    catalog_fingerprint = 'catalog-evaluation'
    generation_plan_fingerprint = 'generation-evaluation'
    compilation_plan_fingerprint = 'compilation-evaluation'
    candidates = @([ordered]@{
      candidate_id = 'candidate/evaluation'
      alternatives = @($firstAlternative)
    })
    current_selections = @([ordered]@{
      candidate_id = 'candidate/evaluation'
      alternative_id = 'emit:mir-evaluation-a'
      action = 'emit'
      design_fingerprint = 'design-evaluation-a'
      qualification_fingerprint = 'qualification-evaluation-a'
    })
    qualifications = @()
  }
  $historical = Copy-MIRTechnologyCatalogEvaluationValue $historical
  Assert-MIR4FullTechnologyCatalog -Catalog $historical

  $schema3Input = Join-Path $tempRoot 'historical-schema3.json'
  $schema3Output = Join-Path $tempRoot 'schema3-output/catalog.json'
  Write-MIRTechnologyCatalogEvaluationJson -Value $historical -Path $schema3Input
  & (Join-Path $RepoRoot 'tools/commands/technology/Export-MIRTechnologyCatalog.ps1') `
    -CatalogPath $schema3Input -OutputPath $schema3Output
  Assert-MIRTechnologyCatalogEvaluation (Test-Path -LiteralPath $schema3Output) `
    'Schema 3 historical catalog was not accepted by the exact catalog exporter.'
  Assert-MIRTechnologyCatalogEvaluation (
    (Get-FileHash -Algorithm SHA256 -LiteralPath $schema3Input).Hash -ceq
    (Get-FileHash -Algorithm SHA256 -LiteralPath $schema3Output).Hash
  ) 'Schema 3 historical catalog was not retained byte-for-byte by the exact catalog exporter.'

  $complete = Copy-MIRTechnologyCatalogEvaluationValue $historical
  $complete.schema = 4
  $complete.candidates[0].alternatives = @(
    (Copy-MIRTechnologyCatalogEvaluationValue $firstAlternative),
    (Copy-MIRTechnologyCatalogEvaluationValue $secondAlternative)
  )
  $complete.candidates[0] | Add-Member -NotePropertyName diagnostic_evaluation -NotePropertyValue ([pscustomobject][ordered]@{
    state = 'constructed'
    alternative_id = 'diagnose:mir-evaluation-b'
    design_fingerprint = 'design-evaluation-b'
    qualification_fingerprint = 'qualification-evaluation-b'
  })
  $complete | Add-Member -NotePropertyName alternative_evaluation -NotePropertyValue ([pscustomobject][ordered]@{
    mode = 'full-diagnostics'
    complete = $true
    deferred_diagnostic_alternatives = 0
    evaluated_alternatives = 2
  })
  Assert-MIR4FullTechnologyCatalog -Catalog $complete

  $partial = Copy-MIRTechnologyCatalogEvaluationValue $complete
  $partial.alternative_evaluation.complete = $false
  Assert-MIRTechnologyCatalogEvaluationRejects -Name 'partial schema 4 catalog' `
    -ExpectedCode '[mir4-technology-catalog-full-diagnostics-required]' `
    -Action { Assert-MIR4FullTechnologyCatalog -Catalog $partial }

  $missingState = Copy-MIRTechnologyCatalogEvaluationValue $complete
  $missingState.candidates[0].PSObject.Properties.Remove('diagnostic_evaluation')
  Assert-MIRTechnologyCatalogEvaluationRejects -Name 'schema 4 catalog with missing candidate state' `
    -ExpectedCode '[mir4-technology-catalog-full-diagnostics-required]' `
    -Action { Assert-MIR4FullTechnologyCatalog -Catalog $missingState }

  $forgedComplete = Copy-MIRTechnologyCatalogEvaluationValue $complete
  $forgedComplete.candidates[0].diagnostic_evaluation.state = 'deferred'
  Assert-MIRTechnologyCatalogEvaluationRejects -Name 'schema 4 catalog with forged complete evaluation' `
    -ExpectedCode '[mir4-technology-catalog-full-diagnostics-required]' `
    -Action { Assert-MIR4FullTechnologyCatalog -Catalog $forgedComplete }

  $wrongBinding = Copy-MIRTechnologyCatalogEvaluationValue $complete
  $wrongBinding.candidates[0].diagnostic_evaluation.design_fingerprint = 'design-evaluation-a'
  Assert-MIRTechnologyCatalogEvaluationRejects -Name 'schema 4 catalog with a misbound constructed diagnostic' `
    -ExpectedCode '[mir4-technology-catalog-full-diagnostics-required]' `
    -Action { Assert-MIR4FullTechnologyCatalog -Catalog $wrongBinding }

  $deferred = Copy-MIRTechnologyCatalogEvaluationValue $complete
  $deferred.alternative_evaluation.deferred_diagnostic_alternatives = 1
  Assert-MIRTechnologyCatalogEvaluationRejects -Name 'schema 4 catalog with deferred alternatives' `
    -ExpectedCode '[mir4-technology-catalog-full-diagnostics-required]' `
    -Action { Assert-MIR4FullTechnologyCatalog -Catalog $deferred }

  $booleanDeferred = Copy-MIRTechnologyCatalogEvaluationValue $complete
  $booleanDeferred.alternative_evaluation.deferred_diagnostic_alternatives = $false
  Assert-MIRTechnologyCatalogEvaluationRejects -Name 'schema 4 catalog with a Boolean deferred count' `
    -ExpectedCode '[mir4-technology-catalog-full-diagnostics-required]' `
    -Action { Assert-MIR4FullTechnologyCatalog -Catalog $booleanDeferred }

  $forgedCount = Copy-MIRTechnologyCatalogEvaluationValue $complete
  $forgedCount.alternative_evaluation.evaluated_alternatives = 1
  Assert-MIRTechnologyCatalogEvaluationRejects -Name 'schema 4 catalog with a forged evaluation count' `
    -ExpectedCode '[mir4-technology-catalog-evaluation-count]' `
    -Action { Assert-MIR4FullTechnologyCatalog -Catalog $forgedCount }

  $fractionalCount = Copy-MIRTechnologyCatalogEvaluationValue $complete
  $fractionalCount.alternative_evaluation.evaluated_alternatives = 2.5
  Assert-MIRTechnologyCatalogEvaluationRejects -Name 'schema 4 catalog with a fractional evaluation count' `
    -ExpectedCode '[mir4-technology-catalog-evaluation-count]' `
    -Action { Assert-MIR4FullTechnologyCatalog -Catalog $fractionalCount }

  $booleanEvaluated = Copy-MIRTechnologyCatalogEvaluationValue $complete
  $booleanEvaluated.alternative_evaluation.evaluated_alternatives = $true
  Assert-MIRTechnologyCatalogEvaluationRejects -Name 'schema 4 catalog with a Boolean evaluation count' `
    -ExpectedCode '[mir4-technology-catalog-evaluation-count]' `
    -Action { Assert-MIR4FullTechnologyCatalog -Catalog $booleanEvaluated }

  $partialPath = Join-Path $tempRoot 'partial-schema4.json'
  Write-MIRTechnologyCatalogEvaluationJson -Value $partial -Path $partialPath
  $catalogOutput = Join-Path $tempRoot 'catalog-output/catalog.json'
  Assert-MIRTechnologyCatalogEvaluationRejectsBeforeWrite -Name 'catalog export' -ExpectedOutput $catalogOutput `
    -Action {
      & (Join-Path $RepoRoot 'tools/commands/technology/Export-MIRTechnologyCatalog.ps1') `
        -CatalogPath $partialPath -OutputPath $catalogOutput
    }

  $previewOutput = Join-Path $tempRoot 'preview-output'
  Assert-MIRTechnologyCatalogEvaluationRejectsBeforeWrite -Name 'compiler preview export' `
    -ExpectedOutput (Join-Path $previewOutput 'technology-catalog.full.json') -Action {
      & (Join-Path $RepoRoot 'tools/commands/technology/Export-MIRCompilerPreview.ps1') `
        -CatalogPath $partialPath -OutputDirectory $previewOutput
    }

  $qualityOutput = Join-Path $tempRoot 'quality-output/assessment.json'
  Assert-MIRTechnologyCatalogEvaluationRejectsBeforeWrite -Name 'quality assessment' -ExpectedOutput $qualityOutput `
    -Action {
      & (Join-Path $RepoRoot 'tools/commands/technology/New-MIRTechnologyQualityAssessment.ps1') `
        -CatalogPath $partialPath -CandidateId 'candidate/evaluation' `
        -ProfilePath (Join-Path $RepoRoot '.mir/technology-quality-profiles.json') `
        -ProfileId 'existing-stream-attachment-v1' -OutputPath $qualityOutput
    }

  $dossierOutput = Join-Path $tempRoot 'dossier-output/dossier.json'
  Assert-MIRTechnologyCatalogEvaluationRejectsBeforeWrite -Name 'review dossier' -ExpectedOutput $dossierOutput `
    -Action {
      & (Join-Path $RepoRoot 'tools/commands/technology/New-MIRTechnologyReviewDossier.ps1') `
        -CatalogPath $partialPath -CandidateId 'candidate/evaluation' -OutputPath $dossierOutput
    }

  $queueOutput = Join-Path $tempRoot 'queue-output/acceptance-queue.json'
  Assert-MIRTechnologyCatalogEvaluationRejectsBeforeWrite -Name 'technology acceptance queue' -ExpectedOutput $queueOutput `
    -Action {
      & (Join-Path $RepoRoot 'tools/commands/mir4/New-MIR4TechnologyAcceptanceQueue.ps1') `
        -RepoRoot $RepoRoot -CatalogPath $partialPath -Target 'F200' -Ecosystem 'aai' -OutputPath $queueOutput
    }

  [pscustomobject][ordered]@{
    status = 'passed'
    schema3_historical_catalog_retained = $true
    schema4_full_diagnostics_accepted = $true
    rejected = @('partial', 'missing-state', 'forged-complete', 'wrong-binding', 'nonzero-deferred', 'boolean-deferred', 'forged-count', 'fractional-count', 'boolean-count')
    prewrite_entrypoints = @('catalog-export', 'compiler-preview', 'quality-assessment', 'review-dossier', 'acceptance-queue')
  } | ConvertTo-Json -Depth 10
} finally {
  if (Test-Path -LiteralPath $tempRoot) {
    $resolvedTempRoot = [IO.Path]::GetFullPath($tempRoot)
    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $tempPrefix = $tempBase + [IO.Path]::DirectorySeparatorChar
    $leaf = [IO.Path]::GetFileName($resolvedTempRoot)
    if (-not $resolvedTempRoot.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) `
        -or $leaf -notlike 'mir4-technology-catalog-evaluation-*') {
      throw "[mir4-technology-catalog-evaluation-test] Refusing unsafe cleanup path: $resolvedTempRoot"
    }
    Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force
  }
}
