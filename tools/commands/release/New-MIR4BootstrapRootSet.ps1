param(
  [string]$RepoRoot = "",
  [string]$OutputPath = "",
  [switch]$Check,
  [switch]$Print
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

$inputRelativePath = ".mir/releases/waves/mir4-r0/terminal-baseline-import.json"
$schemaRelativePath = "spec/schemas/mir4-bootstrap-root-set.schema.json"
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $RepoRoot ".mir\releases\waves\mir4-r0\bootstrap-root-set.json"
} elseif (-not [IO.Path]::IsPathRooted($OutputPath)) {
  $OutputPath = Join-Path $RepoRoot $OutputPath
}

function ConvertTo-MIRCanonicalJsonBytes($Value) {
  $json = ($Value | ConvertTo-Json -Depth 100) -replace "`r`n", "`n"
  return [Text.UTF8Encoding]::new($false).GetBytes($json + "`n")
}

function Get-MIRSha256Bytes([byte[]]$Bytes) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace("-", "") } finally { $sha.Dispose() }
}

function Get-MIRDomainRoot([string]$Domain, [Collections.Specialized.OrderedDictionary]$Fields) {
  $parts = [Collections.Generic.List[string]]::new()
  $parts.Add("domain=$Domain")
  foreach ($key in $Fields.Keys) { $parts.Add("$key=$($Fields[$key])") }
  $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($parts.ToArray() -join "`0"))
  return Get-MIRSha256Bytes -Bytes $bytes
}

function Add-MIRRecordSha256([Collections.Specialized.OrderedDictionary]$Material) {
  $record = [ordered]@{}
  foreach ($property in $Material.Keys) { $record[$property] = $Material[$property] }
  $record.record_sha256 = Get-MIRSha256Bytes -Bytes (ConvertTo-MIRCanonicalJsonBytes -Value $Material)
  return $record
}

function Assert-MIRRecordSha256($Record, [string]$Context) {
  $material = [ordered]@{}
  foreach ($property in $Record.PSObject.Properties) {
    if ($property.Name -ne "record_sha256") { $material[$property.Name] = $property.Value }
  }
  $expected = Get-MIRSha256Bytes -Bytes (ConvertTo-MIRCanonicalJsonBytes -Value $material)
  if ($expected -cne [string]$Record.record_sha256) { throw "$Context self-hash mismatch." }
}

function Assert-MIRHex([string]$Value, [int]$Length, [string]$Context) {
  $pattern = if ($Length -eq 40) { "^[a-f0-9]{40}$" } else { "^[A-F0-9]{$Length}$" }
  if ($Value -cnotmatch $pattern) { throw "$Context is not a canonical $Length-character hexadecimal identity." }
}

function New-MIRBootstrapTargetRoot {
  param(
    [Parameter(Mandatory)]$ImportRow,
    [Parameter(Mandatory)][Collections.Specialized.OrderedDictionary]$Expected
  )

  $snapshot = $ImportRow.snapshot
  if ([string]$ImportRow.release -cne [string]$Expected.predecessor_release -or
      [string]$ImportRow.target -cne [string]$Expected.factorio_line -or
      [string]$ImportRow.successor_target -cne [string]$Expected.import_successor_target -or
      [string]$snapshot.release -cne [string]$Expected.predecessor_release -or
      [string]$snapshot.successor_target -cne [string]$Expected.import_successor_target -or
      [string]$snapshot.target -cne [string]$ImportRow.target) {
    throw "Terminal import identity mismatch for $($Expected.target_id)."
  }

  $expectedBaselinePath = ".mir/releases/terminal/baselines/$($Expected.predecessor_release)/baseline-manifest.json"
  $expectedSnapshotPath = ".mir/releases/terminal/baselines/$($Expected.predecessor_release)/normalized-snapshot.json"
  if ([string]$ImportRow.baseline_manifest.path -cne $expectedBaselinePath -or
      [string]$ImportRow.normalized_snapshot.path -cne $expectedSnapshotPath -or
      [string]$snapshot.record_sha256 -cne [string]$ImportRow.normalized_snapshot.record_sha256 -or
      [string]$snapshot.distribution.archive_sha256 -cne [string]$ImportRow.distribution.archive_sha256 -or
      [string]$snapshot.distribution.content_sha256 -cne [string]$ImportRow.distribution.content_sha256) {
    throw "Terminal baseline, snapshot, or distribution binding mismatch for $($Expected.target_id)."
  }

  $source = $snapshot.source_identity
  Assert-MIRHex -Value ([string]$source.candidate_commit) -Length 40 -Context "$($Expected.target_id) candidate commit"
  Assert-MIRHex -Value ([string]$source.source_tree) -Length 40 -Context "$($Expected.target_id) candidate tree"
  Assert-MIRHex -Value ([string]$source.common_source_commit) -Length 40 -Context "$($Expected.target_id) common source commit"
  Assert-MIRHex -Value ([string]$ImportRow.distribution.archive_sha256) -Length 64 -Context "$($Expected.target_id) terminal archive"
  Assert-MIRHex -Value ([string]$ImportRow.distribution.content_sha256) -Length 64 -Context "$($Expected.target_id) terminal content"
  Assert-MIRHex -Value ([string]$ImportRow.baseline_manifest.record_sha256) -Length 64 -Context "$($Expected.target_id) baseline record"
  Assert-MIRHex -Value ([string]$ImportRow.baseline_manifest.input_root_sha256) -Length 64 -Context "$($Expected.target_id) baseline input root"
  Assert-MIRHex -Value ([string]$ImportRow.normalized_snapshot.record_sha256) -Length 64 -Context "$($Expected.target_id) snapshot record"
  Assert-MIRHex -Value ([string]$snapshot.engine.executable_sha256) -Length 64 -Context "$($Expected.target_id) exact engine"

  $semanticDomain = "mir4.bootstrap.semantic.v1"
  $semanticRoot = Get-MIRDomainRoot -Domain $semanticDomain -Fields ([ordered]@{
    target_id = [string]$Expected.target_id
    factorio_line = [string]$Expected.factorio_line
    predecessor_release = [string]$Expected.predecessor_release
    candidate_commit = [string]$source.candidate_commit
    candidate_tree = [string]$source.source_tree
    common_source_commit = [string]$source.common_source_commit
    terminal_content_sha256 = [string]$ImportRow.distribution.content_sha256
  })

  $authorityDomain = "mir4.bootstrap.authority.v1"
  $authorityRoot = Get-MIRDomainRoot -Domain $authorityDomain -Fields ([ordered]@{
    target_id = [string]$Expected.target_id
    semantic_root = $semanticRoot
    baseline_path = $expectedBaselinePath
    baseline_record_sha256 = [string]$ImportRow.baseline_manifest.record_sha256
    baseline_input_root_sha256 = [string]$ImportRow.baseline_manifest.input_root_sha256
    snapshot_path = $expectedSnapshotPath
    snapshot_record_sha256 = [string]$ImportRow.normalized_snapshot.record_sha256
    terminal_archive_sha256 = [string]$ImportRow.distribution.archive_sha256
    terminal_content_sha256 = [string]$ImportRow.distribution.content_sha256
  })

  $qualificationDomain = "mir4.bootstrap.qualification.v1"
  $qualificationRoot = Get-MIRDomainRoot -Domain $qualificationDomain -Fields ([ordered]@{
    target_id = [string]$Expected.target_id
    semantic_root = $semanticRoot
    authority_root = $authorityRoot
    engine_version = [string]$snapshot.engine.version
    engine_executable_sha256 = [string]$snapshot.engine.executable_sha256
  })

  return [ordered]@{
    target_id = [string]$Expected.target_id
    factorio_line = [string]$Expected.factorio_line
    predecessor_release = [string]$Expected.predecessor_release
    source_identity = [ordered]@{
      candidate_commit = [string]$source.candidate_commit
      candidate_tree = [string]$source.source_tree
      common_source_commit = [string]$source.common_source_commit
    }
    terminal_distribution = [ordered]@{
      archive_sha256 = [string]$ImportRow.distribution.archive_sha256
      content_sha256 = [string]$ImportRow.distribution.content_sha256
    }
    baseline_identity = [ordered]@{
      path = $expectedBaselinePath
      record_sha256 = [string]$ImportRow.baseline_manifest.record_sha256
      input_root_sha256 = [string]$ImportRow.baseline_manifest.input_root_sha256
    }
    snapshot_identity = [ordered]@{
      path = $expectedSnapshotPath
      record_sha256 = [string]$ImportRow.normalized_snapshot.record_sha256
    }
    exact_engine = [ordered]@{
      version = [string]$snapshot.engine.version
      executable_sha256 = [string]$snapshot.engine.executable_sha256
    }
    roots = [ordered]@{
      semantic = [ordered]@{domain=$semanticDomain;sha256=$semanticRoot}
      authority = [ordered]@{domain=$authorityDomain;sha256=$authorityRoot}
      qualification = [ordered]@{domain=$qualificationDomain;sha256=$qualificationRoot}
    }
  }
}

function Assert-MIRCustodyIsolation {
  param(
    [Parameter(Mandatory)]$ImportRow,
    [Parameter(Mandatory)][Collections.Specialized.OrderedDictionary]$Expected,
    [Parameter(Mandatory)][Collections.Specialized.OrderedDictionary]$Original
  )

  $probe = $ImportRow | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
  $probe.baseline_manifest.status = "custody-isolation-probe"
  $probe.baseline_manifest.record_sha256 = "A" * 64
  $probe.normalized_snapshot.record_sha256 = "B" * 64
  $probe.snapshot.record_sha256 = "B" * 64
  $probe.snapshot.status = "custody-isolation-probe"
  $probe.release_closure.status = "custody-isolation-probe"
  $probe.release_closure.record_sha256 = "C" * 64
  $derived = New-MIRBootstrapTargetRoot -ImportRow $probe -Expected $Expected
  if ([string]$derived.roots.semantic.sha256 -cne [string]$Original.roots.semantic.sha256) {
    throw "Custody-only input changed the semantic root for $($Expected.target_id)."
  }
  if ([string]$derived.roots.authority.sha256 -ceq [string]$Original.roots.authority.sha256 -or
      [string]$derived.roots.qualification.sha256 -ceq [string]$Original.roots.qualification.sha256) {
    throw "Custody-isolation probe did not invalidate authority and qualification roots for $($Expected.target_id)."
  }
}

$inputPath = Join-Path $RepoRoot $inputRelativePath
$schemaPath = Join-Path $RepoRoot $schemaRelativePath
foreach ($path in @($inputPath, $schemaPath)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required MIR 4 bootstrap root input is absent: $path" }
}

$inputRaw = Get-Content -Raw -LiteralPath $inputPath
if (-not ($inputRaw | Test-Json -SchemaFile (Join-Path $RepoRoot "spec/schemas/mir4-terminal-baseline-import.schema.json") -ErrorAction Stop)) {
  throw "Terminal baseline import schema validation failed."
}
$import = $inputRaw | ConvertFrom-Json -Depth 100
Assert-MIRRecordSha256 -Record $import -Context "Terminal baseline import"
if ([string]$import.kind -cne "MIR4TerminalBaselineImportV1" -or
    [bool]$import.semantic_authority -or
    [string]$import.source_generation -cne "MIR4-R0-pre-release" -or
    @($import.releases).Count -ne 9) {
  throw "Terminal baseline import is not the admitted pre-EOL all-nine source."
}

$expectedTargets = @(
  [ordered]@{target_id="f210";factorio_line="2.1";import_successor_target="MIR4-R0/2.1";predecessor_release="3.2.9"},
  [ordered]@{target_id="f200";factorio_line="2.0";import_successor_target="MIR4-R0/2.0";predecessor_release="2.5.9"},
  [ordered]@{target_id="f110";factorio_line="1.1";import_successor_target="MIR4-R0/1.1";predecessor_release="1.9.9"},
  [ordered]@{target_id="f100";factorio_line="1.0";import_successor_target="MIR4-R0/1.0";predecessor_release="1.8.9"}
)
$targets = @()
foreach ($expected in $expectedTargets) {
  $matches = @($import.releases | Where-Object {
    [string]$_.release -ceq [string]$expected.predecessor_release -and
    [string]$_.target -ceq [string]$expected.factorio_line -and
    [string]$_.successor_target -ceq [string]$expected.import_successor_target
  })
  if ($matches.Count -ne 1) { throw "Expected one terminal import row for $($expected.target_id)." }
  $target = New-MIRBootstrapTargetRoot -ImportRow $matches[0] -Expected $expected
  Assert-MIRCustodyIsolation -ImportRow $matches[0] -Expected $expected -Original $target
  $targets += $target
}
if (@($targets.source_identity.common_source_commit | Sort-Object -Unique).Count -ne 1) {
  throw "The four bootstrap targets do not bind one common terminal source commit."
}
foreach ($rootClass in @("semantic", "authority", "qualification")) {
  if (@($targets | ForEach-Object { $_.roots[$rootClass].sha256 } | Sort-Object -Unique).Count -ne 4) {
    throw "The four bootstrap targets do not have distinct $rootClass roots."
  }
}

$material = [ordered]@{
  schema = 1
  kind = "MIR4BootstrapRootSetV1"
  status = "current-pre-eol-package-excluded"
  package_visible = $false
  semantic_authority = $false
  source_generation = "MIR4-R0-pre-release"
  canonicalization = "utf8-null-delimited-labelled-fields-v1"
  hash_algorithm = "sha256"
  derived_from = [ordered]@{path=$inputRelativePath;record_sha256=[string]$import.record_sha256}
  targets = @($targets)
}
$record = Add-MIRRecordSha256 -Material $material
$bytes = ConvertTo-MIRCanonicalJsonBytes -Value $record
$json = [Text.UTF8Encoding]::new($false).GetString($bytes)
if (-not ($json | Test-Json -SchemaFile $schemaPath -ErrorAction Stop)) {
  throw "Generated MIR 4 bootstrap root set failed schema validation."
}

if ($Print) {
  [Console]::Out.Write($json)
  return
}

if ($Check) {
  if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) { throw "Tracked MIR 4 bootstrap root set is absent: $OutputPath" }
  $actual = [IO.File]::ReadAllBytes($OutputPath)
  if (-not [Linq.Enumerable]::SequenceEqual([byte[]]$actual, [byte[]]$bytes)) {
    throw "Tracked MIR 4 bootstrap root set is stale: $OutputPath"
  }
  Write-Host "[ok] MIR 4 bootstrap root set is current: $($record.record_sha256)"
  return
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputPath) | Out-Null
[IO.File]::WriteAllBytes($OutputPath, $bytes)
Write-Host "[ok] wrote MIR 4 bootstrap root set: $($record.record_sha256)"
