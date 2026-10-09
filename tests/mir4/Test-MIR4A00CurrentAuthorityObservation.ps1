# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path }
. (Join-Path $RepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')

function Assert-A00True { param([bool]$Value, [string]$Message) if (-not $Value) { throw $Message } }

$root = Join-Path $RepoRoot 'spec/programmes/evidence/synthesis-2026-09-10'
$path = Join-Path $root 'a00-current-authority-observation.json'
$raw = Get-Content -Raw -LiteralPath $path
Assert-A00True ($raw | Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/mir4-a00-current-authority-observation-v1.schema.json')) '[mir4-a00-schema]'
$record = $raw | ConvertFrom-Json -Depth 100 -DateKind String
Assert-A00True ([string]$record.kind -ceq 'MIR4A00CurrentAuthorityObservationV1') '[mir4-a00-kind]'
Assert-A00True (Test-MIR4BootstrapRecordHash $record) '[mir4-a00-self-hash]'
Assert-A00True ($record.recorded_at -notmatch 'T00:00:00') '[mir4-a00-synthetic-midnight]'
Assert-A00True ($record.base.origin_dev -ceq 'aed35814232d1ebf629f980ac98869c3e8336903' -and $record.base.tree -ceq 'd68c32d425ae544f73f5762925c3ce429ef6cd3c' -and $record.base.merge_base -ceq '3562377b520cccb071b97b3968946eae7024c950') '[mir4-a00-base]'
Assert-A00True ($record.base.main_to_dev_divergence.main_unique -eq 1 -and $record.base.main_to_dev_divergence.dev_unique -eq 21) '[mir4-a00-divergence]'
Assert-A00True ($record.current_candidate.bytes -eq 1103729 -and $record.current_candidate.sha256 -ceq '99C020CBA2800179FF2D76EE35F58B27A97CF2A7D89993CFFE06403DC140090E') '[mir4-a00-candidate]'
Assert-A00True ($record.recovery.snapshot_logical_id -ceq '20260909-205136-mir42-tin-browser-explanation' -and $record.recovery.entries -eq 180 -and $record.recovery.bytes -eq 238515273 -and $record.recovery.bundle_verified -and $record.recovery.apply_verified -and $record.recovery.restored_file_count -eq 13 -and $record.recovery.retained_stash_oid -ceq '67c267748c7690efbb35625a580fea0dabaddd2e') '[mir4-a00-recovery]'
Assert-A00True ($record.classification.f210_waiver.prior_release_only -and -not $record.classification.f210_waiver.mir42_qualification_authority) '[mir4-a00-f210-waiver-boundary]'
Assert-A00True (@($record.classification.authority.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -eq 0) '[mir4-a00-authority-denial]'
Assert-A00True ($raw -notmatch '(?i)(?:[A-Z]:\\|\\\\)') '[mir4-a00-no-absolute-path]'
$writer = Join-Path $RepoRoot 'tools/commands/mir4/Write-MIR4A00A03Evidence.ps1'
$writerSource = Get-Content -Raw -LiteralPath $writer
Assert-A00True ($writerSource -notmatch "ValidateSet\([^)]*A03Lock") '[mir4-a00-writer-lock-claim]'
$mismatchRejected = $false
$mismatchOutput = Join-Path $RepoRoot 'build/tests/a00-a03-writer-kind-mismatch.json'
try {
  & $writer -Kind A03Receipt -InputPath $path -OutputPath $mismatchOutput -RecordedAt ([string]$record.recorded_at) -TestOutput | Out-Null
} catch {
  $mismatchRejected = $_.Exception.Message -ceq '[mir4-a00-a03-kind-contract]'
} finally {
  if (Test-Path -LiteralPath $mismatchOutput) { Remove-Item -LiteralPath $mismatchOutput -Force }
}
Assert-A00True $mismatchRejected '[mir4-a00-writer-kind-dispatch]'

$writerCases = @(
  [pscustomobject]@{ kind='A00'; path=$path; schema='spec/schemas/mir4-a00-current-authority-observation-v1.schema.json' },
  [pscustomobject]@{ kind='A03ExecutionProof'; path=(Join-Path $root 'a03-k2-k2so-f210-execution-proof.json'); schema='spec/schemas/mir4-a03-k2-k2so-execution-proof-v1.schema.json' },
  [pscustomobject]@{ kind='A03Dossier'; path=(Join-Path $root 'a03-k2-k2so-f210-intake-dossier.json'); schema='spec/schemas/mir4-a03-k2-k2so-intake-dossier-v1.schema.json' },
  [pscustomobject]@{ kind='A03Receipt'; path=(Join-Path $root 'a03-k2-k2so-f210-intake-receipt.json'); schema='spec/schemas/mir4-a03-k2-k2so-intake-receipt-v1.schema.json' }
)
$writerRoot = Join-Path $RepoRoot ('build/tests/a00-a03-writer/' + [guid]::NewGuid().ToString('N'))
try {
  New-Item -ItemType Directory -Force -Path $writerRoot | Out-Null
  foreach ($case in $writerCases) {
    Assert-A00True (Test-Path -LiteralPath $case.path -PathType Leaf) "[mir4-a00-writer-case-missing] $($case.kind)"
    $caseRaw = Get-Content -Raw -LiteralPath $case.path
    Assert-A00True ($caseRaw | Test-Json -SchemaFile (Join-Path $RepoRoot $case.schema)) "[mir4-a00-writer-case-schema] $($case.kind)"
    $caseRecord = $caseRaw | ConvertFrom-Json -Depth 100 -DateKind String
    Assert-A00True (Test-MIR4BootstrapRecordHash $caseRecord) "[mir4-a00-writer-case-hash] $($case.kind)"
    $caseRecordedAt = [string]$caseRecord.recorded_at
    $output = Join-Path $writerRoot ($case.kind + '.json')
    $created = & $writer -Kind $case.kind -InputPath $case.path -OutputPath $output -RecordedAt $caseRecordedAt -TestOutput
    $adopted = & $writer -Kind $case.kind -InputPath $case.path -OutputPath $output -RecordedAt $caseRecordedAt -TestOutput
    Assert-A00True ($created -ceq $adopted) "[mir4-a00-writer-identical-adopt] $($case.kind)"
    $projected = Get-Content -Raw -LiteralPath $output | ConvertFrom-Json -Depth 100 -DateKind String
    Assert-A00True (Test-MIR4BootstrapRecordHash $projected) "[mir4-a00-writer-created-hash] $($case.kind)"
    $differentRejected = $false
    try { & $writer -Kind $case.kind -InputPath $case.path -OutputPath $output -RecordedAt '2026-09-10T00:00:01Z' -TestOutput | Out-Null } catch { $differentRejected = $_.Exception.Message -eq '[mir4-a00-a03-immutable-overwrite]' }
    Assert-A00True $differentRejected "[mir4-a00-writer-different-reject] $($case.kind)"
  }
  Assert-A00True (-not @(Get-ChildItem -LiteralPath $writerRoot -Filter '*.tmp' -Force).Count) '[mir4-a00-writer-temp-cleanup]'
} finally {
  if (Test-Path -LiteralPath $writerRoot) { Remove-Item -LiteralPath $writerRoot -Recurse -Force }
}

$outsideRejected = $false
try {
  & $writer -Kind A00 -InputPath $path -OutputPath (Join-Path ([IO.Path]::GetTempPath()) 'mir4-a00-outside-repo.json') -RecordedAt ([string]$record.recorded_at) -TestOutput | Out-Null
} catch {
  $outsideRejected = $_.Exception.Message -eq '[mir4-a00-a03-output-boundary]'
}
Assert-A00True $outsideRejected '[mir4-a00-writer-outside-repo-boundary]'

$traversalRejected = $false
try {
  & $writer -Kind A00 -InputPath $path -OutputPath 'build/tests/../a00-traversal.json' -RecordedAt ([string]$record.recorded_at) -TestOutput | Out-Null
} catch {
  $traversalRejected = $_.Exception.Message -eq '[mir4-a00-a03-output-boundary]'
}
Assert-A00True $traversalRejected '[mir4-a00-writer-traversal-boundary]'

$wrongKindRejected = $false
try {
  & $writer -Kind A00 -InputPath $path -OutputPath 'spec/programmes/evidence/synthesis-2026-09-10/a03-k2-k2so-f210-intake-receipt.json' -RecordedAt ([string]$record.recorded_at) | Out-Null
} catch {
  $wrongKindRejected = $_.Exception.Message -eq '[mir4-a00-a03-output-kind-boundary]'
}
Assert-A00True $wrongKindRejected '[mir4-a00-writer-output-kind-boundary]'

$relativeOutput = Join-Path $RepoRoot 'build/tests/a00-a03-relative-cwd.json'
try {
  Push-Location ([IO.Path]::GetTempPath())
  try {
    & $writer -Kind A00 -InputPath $path -OutputPath 'build/tests/a00-a03-relative-cwd.json' -RecordedAt ([string]$record.recorded_at) -TestOutput | Out-Null
  } finally {
    Pop-Location
  }
  Assert-A00True (Test-Path -LiteralPath $relativeOutput -PathType Leaf) '[mir4-a00-writer-relative-cwd-root]'
} finally {
  if (Test-Path -LiteralPath $relativeOutput) { Remove-Item -LiteralPath $relativeOutput -Force }
}

$raceOutput = Join-Path $RepoRoot 'build/tests/a00-a03-race.json'
$raceJobs = @()
try {
  if (Test-Path -LiteralPath $raceOutput) { Remove-Item -LiteralPath $raceOutput -Force }
  $raceScript = {
    param($WriterPath,$InputPath,$Output,$Timestamp)
    try {
      & $WriterPath -Kind A00 -InputPath $InputPath -OutputPath $Output -RecordedAt $Timestamp -TestOutput | Out-Null
      [pscustomobject]@{ succeeded=$true; message='' }
    } catch {
      [pscustomobject]@{ succeeded=$false; message=$_.Exception.Message }
    }
  }
  $raceJobs += Start-Job -ScriptBlock $raceScript -ArgumentList $writer,$path,$raceOutput,'2026-09-10T00:00:01Z'
  $raceJobs += Start-Job -ScriptBlock $raceScript -ArgumentList $writer,$path,$raceOutput,'2026-09-10T00:00:02Z'
  $raceResults = @($raceJobs | Wait-Job | Receive-Job)
  $raceWinners = @($raceResults | Where-Object succeeded)
  $raceLosers = @($raceResults | Where-Object { -not $_.succeeded -and $_.message -eq '[mir4-a00-a03-immutable-overwrite]' })
  $raceDiagnostic = @($raceResults | ForEach-Object { "succeeded=$($_.succeeded);message=$($_.message)" }) -join '|'
  Assert-A00True ($raceWinners.Count -eq 1) "[mir4-a00-writer-race-winner] $raceDiagnostic"
  Assert-A00True ($raceLosers.Count -eq 1) "[mir4-a00-writer-race-loser] $raceDiagnostic"
} finally {
  if ($raceJobs.Count) { $raceJobs | Remove-Job -Force -ErrorAction SilentlyContinue }
  if (Test-Path -LiteralPath $raceOutput) { Remove-Item -LiteralPath $raceOutput -Force }
}
Write-Host 'MIR4 A00 current-authority observation passed.'
