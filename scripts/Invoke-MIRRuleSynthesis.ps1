param(
  [Parameter(Mandatory)][string]$Family,
  [string]$CorpusPath = ".mir\technology-review-corpus.json",
  [string]$SnapshotsPath = ".mir\technology-review-snapshots.json",
  [string]$AuthorityPath = ".mir\rule-synthesis.json",
  [Parameter(Mandatory)][string]$OutputPath
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

function Resolve-MIRPath {
  param([string]$Path)
  if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
  return [IO.Path]::GetFullPath((Join-Path $repo $Path))
}

function Get-MIRTextSha256 {
  param([string]$Text)
  $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "") }
  finally { $sha.Dispose() }
}

function Test-MIRPredicateMatch {
  param([string[]]$Selected, $Subject)
  $present = @{}
  foreach ($predicate in @($Subject.predicates)) { $present[[string]$predicate] = $true }
  foreach ($predicate in $Selected) {
    if (-not $present.ContainsKey($predicate)) { return $false }
  }
  return $true
}

$corpusFile = Resolve-MIRPath $CorpusPath
$snapshotsFile = Resolve-MIRPath $SnapshotsPath
$authorityFile = Resolve-MIRPath $AuthorityPath
$corpus = Get-Content -Raw -LiteralPath $corpusFile | ConvertFrom-Json
$snapshots = Get-Content -Raw -LiteralPath $snapshotsFile | ConvertFrom-Json
$authority = Get-Content -Raw -LiteralPath $authorityFile | ConvertFrom-Json
if ($corpus.schema -ne 1 -or $snapshots.schema -ne 1 -or $authority.schema -ne 1) {
  throw "Rule synthesis requires schema 1 corpus, snapshot, and authority inputs."
}
$familyRecord = @($corpus.families | Where-Object { $_.family -eq $Family })
if ($familyRecord.Count -ne 1) { throw "Rule synthesis family is missing or ambiguous: $Family" }
$familyRecord = $familyRecord[0]

$allowed = @($authority.allowed_predicates | ForEach-Object { [string]$_ } | Sort-Object -Unique)
$mandatory = @($authority.mandatory_hard_predicates | ForEach-Object { [string]$_ })
$membership = @($authority.family_membership_predicates | ForEach-Object { [string]$_ })
if ($allowed.Count -gt 20) { throw "Rule synthesis predicate search exceeds the bounded 20-predicate limit." }

$candidates = @()
$limit = [int][math]::Pow(2, $allowed.Count)
for ($mask = 0; $mask -lt $limit; $mask++) {
  $selected = @()
  for ($index = 0; $index -lt $allowed.Count; $index++) {
    if (($mask -band (1 -shl $index)) -ne 0) { $selected += $allowed[$index] }
  }
  if (@($mandatory | Where-Object { $_ -notin $selected }).Count -gt 0) { continue }
  if (@($membership | Where-Object { $_ -in $selected }).Count -eq 0) { continue }
  if (@($familyRecord.positive_examples | Where-Object { -not (Test-MIRPredicateMatch $selected $_) }).Count -gt 0) { continue }
  if (@($familyRecord.negative_examples | Where-Object { Test-MIRPredicateMatch $selected $_ }).Count -gt 0) { continue }

  $newMatches = @()
  foreach ($snapshot in @($snapshots.snapshots | Sort-Object snapshot_id)) {
    foreach ($subject in @($snapshot.subjects | Where-Object { $_.family -eq $Family -and -not $_.reviewed } | Sort-Object recipe)) {
      if (Test-MIRPredicateMatch $selected $subject) {
        $newMatches += [ordered]@{snapshot_id=[string]$snapshot.snapshot_id; recipe=[string]$subject.recipe}
      }
    }
  }
  $candidates += [pscustomobject][ordered]@{
    selected = @($selected)
    new_matches = @($newMatches)
    sort_key = ("{0:D6}|{1:D3}|{2}" -f $newMatches.Count, $selected.Count, ($selected -join "|"))
  }
}

$selectedCandidate = @($candidates | Sort-Object sort_key | Select-Object -First 1)
$status = if ($selectedCandidate.Count -eq 1) { "REVIEW_REQUIRED" } else { "QUARANTINED_NO_SAFE_RULE" }
$selectedPredicates = if ($selectedCandidate.Count -eq 1) { @($selectedCandidate[0].selected) } else { @() }
$currentPredicates = @($familyRecord.current_predicates | ForEach-Object { [string]$_ } | Sort-Object -Unique)
$added = @($selectedPredicates | Where-Object { $_ -notin $currentPredicates })
$removed = @($currentPredicates | Where-Object { $_ -notin $selectedPredicates })
$newMatches = @()
if ($selectedCandidate.Count -eq 1) { $newMatches = @($selectedCandidate[0].new_matches) }

$proposal = [ordered]@{
  schema = 1
  kind = "mir-family-rule-proposal"
  status = $status
  family = $Family
  structural_envelope = [string]$familyRecord.structural_envelope
  selected_predicates = $selectedPredicates
  reviewed_positive_count = @($familyRecord.positive_examples).Count
  reviewed_negative_count = @($familyRecord.negative_examples).Count
  new_unreviewed_matches = [object[]]$newMatches
  current_rule_diff = [ordered]@{added=$added; removed=$removed}
  objective_order = @($authority.objective_order)
  required_review_evidence = @($authority.production_entry_requirements)
  corpus_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $corpusFile).Hash
  snapshots_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $snapshotsFile).Hash
  authority_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $authorityFile).Hash
  production_mutation_authorized = $false
}
$proposal.proposal_sha256 = Get-MIRTextSha256 (($proposal | ConvertTo-Json -Depth 100 -Compress))

$destination = Resolve-MIRPath $OutputPath
$parent = Split-Path -Parent $destination
if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
$proposal | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $destination -Encoding UTF8
Write-Host "[ok] wrote offline MIR rule proposal $destination status=$status predicates=$($selectedPredicates.Count) new_matches=$($newMatches.Count)"
