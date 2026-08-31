param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/RunnerPublisherConfinement.ps1')
. (Join-Path $repo 'tools/lib/mir4/PackagePresentation.ps1')

function Assert-MIR4RunnerTest {
  param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Code)
  if (-not $Condition) { throw "[$Code]" }
}

function Assert-MIR4RunnerThrows {
  param([Parameter(Mandatory)][scriptblock]$Action, [Parameter(Mandatory)][string]$Code)
  $threw = $false
  try { & $Action } catch { $threw = $true }
  if (-not $threw) { throw "[$Code]" }
}

$receiptA = New-MIR4RunnerPublisherConfinementReceiptV1 -RepoRoot $repo
$receiptB = New-MIR4RunnerPublisherConfinementReceiptV1 -RepoRoot $repo
Assert-MIR4RunnerTest (Test-MIR4RunnerPublisherConfinementReceiptV1 -Receipt $receiptA -RepoRoot $repo) 'mir4-runner-current-receipt'
Assert-MIR4RunnerTest ([string]$receiptA.record_sha256 -ceq [string]$receiptB.record_sha256) 'mir4-runner-determinism'
Assert-MIR4RunnerTest (@($receiptA.workflow_closure.rows).Count -eq 21) 'mir4-runner-workflow-count'
Assert-MIR4RunnerTest (@($receiptA.checks).Count -eq 10) 'mir4-runner-check-count'
foreach ($workflow in @($receiptA.workflow_closure.rows)) {
  $relative = [string]$workflow.path
  Assert-MIR4WorkflowCheckoutContractV1 -RepoRoot $repo -RelativePath $relative -FullPath (Join-Path $repo $relative)
}
Assert-MIR4RunnerThrows {
  Assert-MIR4CanonicalLfByteSequenceV1 -Bytes ([Text.Encoding]::UTF8.GetBytes("name: test`r`n")) -Path '<crlf-fixture>'
} 'mir4-runner-workflow-crlf-negative'

$lock = Get-Content -LiteralPath (Join-Path $repo '.mir/releases/governance/mir4/github-actions-lock-v2.json') -Raw | ConvertFrom-Json -Depth 30
Assert-MIR4RunnerThrows { Assert-MIR4ExternalActionReferenceV1 -Reference 'actions/checkout@v4' -Lock $lock } 'mir4-runner-floating-action-negative'
$validate = [IO.File]::ReadAllText((Join-Path $repo '.github/workflows/validate.yml'))
Assert-MIR4RunnerThrows { Assert-MIR4WorkflowTextBoundaryV1 -Purpose public-pr -Text ($validate + "`n    secret: `${{ secrets.RELEASE_TOKEN }}") } 'mir4-runner-public-secret-negative'
$publisher = [IO.File]::ReadAllText((Join-Path $repo '.github/workflows/mir4-target-publication.yml'))
Assert-MIR4RunnerThrows { Assert-MIR4WorkflowTextBoundaryV1 -Purpose publisher -Text ($publisher + "`n      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262") } 'mir4-runner-publisher-checkout-negative'
$builder = [IO.File]::ReadAllText((Join-Path $repo '.github/workflows/mir4-target-build.yml'))
Assert-MIR4RunnerThrows { Assert-MIR4WorkflowTextBoundaryV1 -Purpose builder -Text ($builder + "`n          TOKEN: `${{ secrets.PUBLISHER_TOKEN }}") } 'mir4-runner-builder-secret-negative'
$qualifier = [IO.File]::ReadAllText((Join-Path $repo '.github/workflows/mir4-target-qualification.yml'))
Assert-MIR4RunnerThrows { Assert-MIR4WorkflowTextBoundaryV1 -Purpose qualifier -Text ($qualifier + "`n          Copy-Item package.zip replacement.zip") } 'mir4-runner-qualifier-mutation-negative'
Assert-MIR4RunnerThrows { Assert-MIR4WorkflowTextBoundaryV1 -Purpose builder -Text ($builder + "`n          Write-Host '`${{ inputs.source_commit }}'") } 'mir4-runner-shell-input-negative'
Assert-MIR4RunnerTest ([string]$receiptA.package_source_sha256 -ceq (Get-MIR4CurrentPackageSourceSha256 -RepoRoot $repo)) 'mir4-runner-package-non-interference'

[pscustomobject][ordered]@{
  status = 'passed'
  workflows = @($receiptA.workflow_closure.rows).Count
  action_lock_sha256 = [string]$receiptA.action_lock.file_sha256
  workflow_root_sha256 = [string]$receiptA.workflow_closure.root_sha256
  receipt_sha256 = [string]$receiptA.record_sha256
  negative_cases = @('workflow-crlf','floating-action','public-pr-secret','publisher-checkout','builder-release-secret','qualifier-mutation','shell-input-interpolation')
  package_source_sha256 = [string]$receiptA.package_source_sha256
  production_authority = $false
  release_transition_performed = $false
}
