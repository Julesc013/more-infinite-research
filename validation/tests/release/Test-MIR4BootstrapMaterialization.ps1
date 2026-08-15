param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

. (Join-Path $RepoRoot "tools/lib/mir4/BootstrapMaterialization.ps1")

function Assert-True([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw $Message }
}

function Assert-Throws([scriptblock]$Action, [string]$Message) {
  $threw = $false
  try { & $Action } catch { $threw = $true }
  if (-not $threw) { throw $Message }
}

$planPath = Join-Path $RepoRoot ".mir/releases/waves/mir4-r0/MIR4-Bootstrap-Local-Candidate-PlanV1.json"
$planText = Get-Content -Raw -LiteralPath $planPath
$plan = $planText | ConvertFrom-Json
Assert-True ($plan.kind -eq "MIR4BootstrapLocalCandidatePlanV1") "Unexpected MIR4 bootstrap plan kind."
Assert-True ($plan.public_output_authorized -eq $false) "MIR4 bootstrap plan must remain publication-forbidden."
Assert-True (Test-MIR4BootstrapRecordHash -Record $plan) "MIR4 bootstrap plan self-hash is stale."
Assert-True (@($plan.targets).Count -eq 4) "MIR4 bootstrap plan must bind four requested targets."
Assert-True (@($plan.targets.target_key | Sort-Object -Unique).Count -eq 4) "MIR4 bootstrap target keys must be unique."

$expected = [ordered]@{ f210 = "4.0.21000"; f200 = "4.0.20000"; f110 = "4.0.11000"; f100 = "4.0.10000" }
foreach ($target in $plan.targets) {
  Assert-True ($expected.Contains([string]$target.target_key)) "Unexpected bootstrap target $($target.target_key)."
  Assert-True ([string]$target.distribution_version -eq [string]$expected[[string]$target.target_key]) "Distribution projection is wrong for $($target.target_key)."
  Assert-True ([int]$target.distribution_target_code * 100 -eq [int](([string]$target.distribution_version -split '\.')[2])) "Distribution codec arithmetic is wrong for $($target.target_key)."
  $archivePath = Join-Path $RepoRoot ([string]$target.predecessor.archive_path)
  Assert-True ((Get-MIR4Sha256File -Path $archivePath) -eq [string]$target.predecessor.archive_sha256) "Terminal predecessor archive changed for $($target.target_key)."
  Assert-True ((Get-MIR4GitTree -RepoRoot $RepoRoot -Commit ([string]$target.source.candidate_commit)) -eq [string]$target.source.source_tree) "Terminal predecessor source tree changed for $($target.target_key)."
}

if (-not (Get-Command Test-Json -ErrorAction SilentlyContinue)) { throw "Test-Json is required for fail-closed MIR 4 tests." }
$planSchema = Join-Path $RepoRoot "spec/schemas/mir4-bootstrap-local-candidate-plan.schema.json"
Assert-True ($planText | Test-Json -SchemaFile $planSchema) "MIR4 bootstrap plan schema validation failed."

$entryGateText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/MIR4-Entry-GateV1.json')
Assert-True ($entryGateText | Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/mir4-r0-authority.schema.json')) "MIR4 entry gate does not satisfy the R0 authority schema."
$entryGate = $entryGateText | ConvertFrom-Json
Assert-True ($entryGate.kind -ceq 'MIR4-Entry-GateV1') "Unexpected MIR4 entry-gate kind."
Assert-True ($entryGate.status -ceq 'pre-eol-local-proof-authorized-publication-forbidden') "Unexpected MIR4 entry-gate state."
Assert-True ($entryGate.package_visible -eq $false -and $entryGate.payload.public_version_4_before_eol -eq $false) "MIR4 entry gate must remain package- and publication-forbidden."
Assert-True ($entryGate.target_dispositions.'factorio-2.1' -ceq 'local-emergency-proof-first') "MIR4 entry gate no longer admits only the f210 emergency lane first."
Assert-True ($entryGate.target_dispositions.'other-active-targets' -ceq 'blocked-until-r1-and-eol') "MIR4 entry gate no longer blocks other active targets."
Assert-True (@($entryGate.payload.before_mir3_eol | Where-Object { [string]$_ -ceq 'generate-local-behavior-equivalent-factorio-2.1-distribution' }).Count -eq 1) "MIR4 entry gate must contain exactly one local f210 construction admission."
Assert-True (@($plan.targets | Where-Object { $_.target_key -eq 'f210' -and $_.admission -eq 'admitted-local-emergency-lane' }).Count -eq 1) "The f210 plan row is not uniquely admitted by the emergency lane."
Assert-True (@($plan.targets | Where-Object { $_.target_key -ne 'f210' -and $_.admission -ne 'non-authoritative-shadow-blocked-by-eol' }).Count -eq 0) "A pre-EOL non-f210 target is executable."

$testRoot = Join-Path $RepoRoot "build/tests/mir4-bootstrap-materialization"
if (Test-Path -LiteralPath $testRoot) { Remove-MIR4BuildTree -OutputRoot (Join-Path $RepoRoot "build/tests") -Path $testRoot }
New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
try {
  Add-Type -AssemblyName System.IO.Compression
  function New-RawProbeZip([string]$Path, [object[]]$Entries) {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Create)
    $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $false)
    try {
      foreach ($row in $Entries) {
        $entry = $zip.CreateEntry([string]$row.name)
        if ($null -ne $row.content) {
          $writer = [IO.StreamWriter]::new($entry.Open(), [Text.UTF8Encoding]::new($false))
          try { $writer.Write([string]$row.content) } finally { $writer.Dispose() }
        }
      }
    } finally { $zip.Dispose(); $stream.Dispose() }
  }

  $predecessorSource = Join-Path $testRoot "predecessor-source"
  $candidateSource = Join-Path $testRoot "candidate-source"
  New-Item -ItemType Directory -Force -Path $predecessorSource, $candidateSource | Out-Null
  $predecessorInfo = "{`n  `"name`": `"mir4-probe`",`n  `"version`": `"3.2.9`",`n  `"factorio_version`": `"2.1`",`n  `"dependencies`": [`"base >= 2.0`"]`n}`n"
  [IO.File]::WriteAllText((Join-Path $predecessorSource "info.json"), $predecessorInfo, [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText((Join-Path $predecessorSource "data.lua"), "return true`n", [Text.UTF8Encoding]::new($false))
  Copy-Item -LiteralPath (Join-Path $predecessorSource "info.json") -Destination (Join-Path $candidateSource "info.json")
  Copy-Item -LiteralPath (Join-Path $predecessorSource "data.lua") -Destination (Join-Path $candidateSource "data.lua")
  Set-MIR4InfoVersion -InfoPath (Join-Path $candidateSource "info.json") -Version "4.0.21000"

  $predecessorZip = Join-Path $testRoot "predecessor.zip"
  $candidateA = Join-Path $testRoot "candidate-a.zip"
  $candidateB = Join-Path $testRoot "candidate-b.zip"
  Write-MIR4DeterministicArchive -SourceRoot $predecessorSource -EntryRoot "mir4-probe_3.2.9" -OutputPath $predecessorZip -ContainmentRoot $testRoot
  Write-MIR4DeterministicArchive -SourceRoot $candidateSource -EntryRoot "mir4-probe_4.0.21000" -OutputPath $candidateA -ContainmentRoot $testRoot
  Write-MIR4DeterministicArchive -SourceRoot $candidateSource -EntryRoot "mir4-probe_4.0.21000" -OutputPath $candidateB -ContainmentRoot $testRoot
  Assert-True ((Get-MIR4Sha256File -Path $candidateA) -eq (Get-MIR4Sha256File -Path $candidateB)) "Independent deterministic archives differ."
  $comparison = Compare-MIR4BootstrapCandidate -CandidatePath $candidateA -PredecessorPath $predecessorZip -ExpectedCandidateRoot "mir4-probe_4.0.21000" -ExpectedPredecessorRoot "mir4-probe_3.2.9" -ExpectedCandidateVersion "4.0.21000" -ExpectedPredecessorVersion "3.2.9" -ThrowOnDifference
  Assert-True $comparison.equivalent "The bounded version/root difference was not accepted."

  [IO.File]::WriteAllText((Join-Path $candidateSource "data.lua"), "return false`n", [Text.UTF8Encoding]::new($false))
  $badCandidate = Join-Path $testRoot "candidate-bad.zip"
  Write-MIR4DeterministicArchive -SourceRoot $candidateSource -EntryRoot "mir4-probe_4.0.21000" -OutputPath $badCandidate -ContainmentRoot $testRoot
  Assert-Throws { Compare-MIR4BootstrapCandidate -CandidatePath $badCandidate -PredecessorPath $predecessorZip -ExpectedCandidateRoot "mir4-probe_4.0.21000" -ExpectedPredecessorRoot "mir4-probe_3.2.9" -ExpectedCandidateVersion "4.0.21000" -ExpectedPredecessorVersion "3.2.9" -ThrowOnDifference } "An unclassified package-visible change was accepted."
  Assert-Throws { Assert-MIR4DescendantPath -Root $testRoot -Path (Join-Path $testRoot "../escape") } "A path outside the build root was accepted."
  Assert-Throws { Resolve-MIR4ArtifactPath -OutputRoot $testRoot -RelativePath '../escape.zip' } "A traversing artifact path was accepted."

  $unsafeDirectoryZip = Join-Path $testRoot 'unsafe-directory.zip'
  New-RawProbeZip -Path $unsafeDirectoryZip -Entries @([pscustomobject]@{name='probe/';content=$null}, [pscustomobject]@{name='probe/../';content=$null}, [pscustomobject]@{name='probe/info.json';content='{}'})
  Assert-Throws { Get-MIR4ArchiveInventory -Path $unsafeDirectoryZip } "An unsafe ZIP directory entry was accepted."
  $caseCollisionZip = Join-Path $testRoot 'case-collision.zip'
  New-RawProbeZip -Path $caseCollisionZip -Entries @([pscustomobject]@{name='probe/info.json';content='{}'}, [pscustomobject]@{name='probe/INFO.JSON';content='{}'})
  Assert-Throws { Get-MIR4ArchiveInventory -Path $caseCollisionZip } "Case-colliding ZIP entries were accepted."
  $duplicateZip = Join-Path $testRoot 'duplicate.zip'
  New-RawProbeZip -Path $duplicateZip -Entries @([pscustomobject]@{name='probe/info.json';content='{}'}, [pscustomobject]@{name='probe/info.json';content='{}'})
  Assert-Throws { Get-MIR4ArchiveInventory -Path $duplicateZip } "Exact duplicate ZIP entries were accepted."
  $rootFileZip = Join-Path $testRoot 'root-file.zip'
  New-RawProbeZip -Path $rootFileZip -Entries @([pscustomobject]@{name='info.json';content='{}'})
  Assert-Throws { Get-MIR4ArchiveInventory -Path $rootFileZip } "A root-level ZIP file was accepted."
  $caseRootCollisionZip = Join-Path $testRoot 'case-root-collision.zip'
  New-RawProbeZip -Path $caseRootCollisionZip -Entries @([pscustomobject]@{name='Probe/info.json';content='{}'}, [pscustomobject]@{name='probe/data.lua';content='return true'})
  Assert-Throws { Get-MIR4ArchiveInventory -Path $caseRootCollisionZip } "Case-colliding ZIP package roots were accepted."
  $wrongRootZip = Join-Path $testRoot 'wrong-root.zip'
  Write-MIR4DeterministicArchive -SourceRoot $candidateSource -EntryRoot "wrong-root" -OutputPath $wrongRootZip -ContainmentRoot $testRoot
  Assert-Throws { Compare-MIR4BootstrapCandidate -CandidatePath $wrongRootZip -PredecessorPath $predecessorZip -ExpectedCandidateRoot "mir4-probe_4.0.21000" -ExpectedPredecessorRoot "mir4-probe_3.2.9" -ExpectedCandidateVersion "4.0.21000" -ExpectedPredecessorVersion "3.2.9" -ThrowOnDifference } "A candidate with the wrong archive root was accepted."
  $caseRenamePredecessor = Join-Path $testRoot 'case-rename-predecessor.zip'
  $caseRenameCandidate = Join-Path $testRoot 'case-rename-candidate.zip'
  New-RawProbeZip -Path $caseRenamePredecessor -Entries @(
    [pscustomobject]@{name='mir4-probe_3.2.9/info.json';content=$predecessorInfo},
    [pscustomobject]@{name='mir4-probe_3.2.9/data.lua';content='return true'}
  )
  New-RawProbeZip -Path $caseRenameCandidate -Entries @(
    [pscustomobject]@{name='mir4-probe_4.0.21000/info.json';content=($predecessorInfo -replace '3\.2\.9','4.0.21000')},
    [pscustomobject]@{name='mir4-probe_4.0.21000/Data.lua';content='return true'}
  )
  Assert-Throws { Compare-MIR4BootstrapCandidate -CandidatePath $caseRenameCandidate -PredecessorPath $caseRenamePredecessor -ExpectedCandidateRoot "mir4-probe_4.0.21000" -ExpectedPredecessorRoot "mir4-probe_3.2.9" -ExpectedCandidateVersion "4.0.21000" -ExpectedPredecessorVersion "3.2.9" -ThrowOnDifference } "A case-only package path rename was accepted."

  $reformattedInfoCandidate = Join-Path $testRoot 'reformatted-info-candidate.zip'
  $projectedInfo = $predecessorInfo -replace '3\.2\.9', '4.0.21000'
  $reformattedInfo = $projectedInfo | ConvertFrom-Json | ConvertTo-Json -Compress
  New-RawProbeZip -Path $reformattedInfoCandidate -Entries @(
    [pscustomobject]@{name='mir4-probe_4.0.21000/info.json';content=$reformattedInfo},
    [pscustomobject]@{name='mir4-probe_4.0.21000/data.lua';content="return true`n"}
  )
  Assert-Throws { Compare-MIR4BootstrapCandidate -CandidatePath $reformattedInfoCandidate -PredecessorPath $predecessorZip -ExpectedCandidateRoot "mir4-probe_4.0.21000" -ExpectedPredecessorRoot "mir4-probe_3.2.9" -ExpectedCandidateVersion "4.0.21000" -ExpectedPredecessorVersion "3.2.9" -ThrowOnDifference } "An info.json formatting change outside the version value was accepted."

  $lfZip = Join-Path $testRoot 'lf.zip'
  $crlfZip = Join-Path $testRoot 'crlf.zip'
  New-RawProbeZip -Path $lfZip -Entries @([pscustomobject]@{name='probe/info.json';content="{`n  `"version`": `"1.0.0`"`n}`n"})
  New-RawProbeZip -Path $crlfZip -Entries @([pscustomobject]@{name='probe/info.json';content=([char]0xFEFF + "{`r`n  `"version`": `"1.0.0`"`r`n}`r`n")})
  Assert-True ((Get-MIR4ArchiveInventory -Path $lfZip).content_sha256 -eq (Get-MIR4ArchiveInventory -Path $crlfZip).content_sha256) "Canonical package content identity diverged for BOM/line-ending-only text."
  $rawLfPredecessor = Join-Path $testRoot 'raw-lf-predecessor.zip'
  $rawCrlfCandidate = Join-Path $testRoot 'raw-crlf-candidate.zip'
  New-RawProbeZip -Path $rawLfPredecessor -Entries @(
    [pscustomobject]@{name='mir4-probe_3.2.9/info.json';content=$predecessorInfo},
    [pscustomobject]@{name='mir4-probe_3.2.9/data.lua';content="return true`n"}
  )
  New-RawProbeZip -Path $rawCrlfCandidate -Entries @(
    [pscustomobject]@{name='mir4-probe_4.0.21000/info.json';content=($predecessorInfo -replace '3\.2\.9','4.0.21000')},
    [pscustomobject]@{name='mir4-probe_4.0.21000/data.lua';content="return true`r`n"}
  )
  Assert-Throws { Compare-MIR4BootstrapCandidate -CandidatePath $rawCrlfCandidate -PredecessorPath $rawLfPredecessor -ExpectedCandidateRoot "mir4-probe_4.0.21000" -ExpectedPredecessorRoot "mir4-probe_3.2.9" -ExpectedCandidateVersion "4.0.21000" -ExpectedPredecessorVersion "3.2.9" -ThrowOnDifference } "An unclassified package-visible line-ending change was accepted."
  $lfTool = Join-Path $testRoot 'tool-lf.ps1'
  $crlfTool = Join-Path $testRoot 'tool-crlf.ps1'
  [IO.File]::WriteAllText($lfTool, "param()`n'probe'`n", [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($crlfTool, "param()`r`n'probe'`r`n", [Text.UTF8Encoding]::new($false))
  Assert-True ((Get-MIR4BootstrapTextSha256 -Path $lfTool) -eq (Get-MIR4BootstrapTextSha256 -Path $crlfTool)) "Bootstrap tool identity diverged for line-ending-only text."

  $layoutProbe = [pscustomobject]@{
    target_key = 'f210'
    distribution_version = '4.0.21000'
    source_capsule = [pscustomobject]@{ path = 'capsules/f210/A/source-capsule.zip' }
    local_distribution = [pscustomobject]@{ path = 'distributions/more-infinite-research_4.0.21000.zip' }
    reconstructions = @(
      [pscustomobject]@{ id = 'A'; path = 'candidates/f210/A/more-infinite-research_4.0.21000.zip'; source_capsule_path = 'capsules/f210/A/source-capsule.zip' },
      [pscustomobject]@{ id = 'B'; path = 'candidates/f210/B/more-infinite-research_4.0.21000.zip'; source_capsule_path = 'capsules/f210/B/source-capsule.zip' },
      [pscustomobject]@{ id = 'C'; path = 'candidates/f210/C/more-infinite-research_4.0.21000.zip'; source_capsule_path = 'capsules/f210/C/source-capsule.zip' }
    )
  }
  Assert-MIR4BootstrapCandidateArtifactLayout -Manifest $layoutProbe
  $layoutProbe.reconstructions[1].path = $layoutProbe.reconstructions[0].path
  Assert-Throws { Assert-MIR4BootstrapCandidateArtifactLayout -Manifest $layoutProbe } "Aliased A/B construction paths were accepted."
} finally {
  if (Test-Path -LiteralPath $testRoot) { Remove-MIR4BuildTree -OutputRoot (Join-Path $RepoRoot "build/tests") -Path $testRoot }
}

Write-Host "MIR4 bootstrap materialization tests passed."
