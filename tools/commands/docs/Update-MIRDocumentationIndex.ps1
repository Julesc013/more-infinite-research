param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path,
  [switch]$ImportLegacyIndex,
  [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$docsRoot = Join-Path $repo "docs"
$indexPath = Join-Path $repo ".mir/docs.yml"
$immutableTruthPath = Join-Path $repo ".mir/docs-immutable-source-truth.json"
$immutableTruthSchemaPath = Join-Path $repo "spec/schemas/mir-immutable-documentation-source-truth-v1.schema.json"
$script:immutableTruthMap = @{}
$utf8 = [Text.UTF8Encoding]::new($false)
$lf = [string][char]10
$cr = [string][char]13

function Normalize-Lf([string]$Text) {
  return $Text.Replace($cr + $lf, $lf).Replace($cr, $lf)
}

function Quote-Yaml([string]$Value) {
  return '"' + $Value.Replace("\", "\\").Replace('"', '\"') + '"'
}

function Table-Text([string]$Value) {
  return $Value.Replace("|", "\|").Replace($cr, " ").Replace($lf, " ")
}

function Relative-Path([string]$Path) {
  return [IO.Path]::GetRelativePath($repo, (Resolve-Path -LiteralPath $Path).Path).Replace("\", "/")
}

function Read-Frontmatter([string]$Text,[string]$Relative) {
  $match = [regex]::Match($Text, '\A---\r?\n(?<body>.*?)(\r?\n)---\r?\n', [Text.RegularExpressions.RegexOptions]::Singleline)
  if (-not $match.Success) { throw "[mir-doc-index-frontmatter] $Relative" }
  $fields = [ordered]@{}
  $lines = @($match.Groups["body"].Value -split "\r?\n")
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ([string]$lines[$i] -notmatch '^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$') { continue }
    $name = [string]$matches[1]
    $value = ([string]$matches[2]).Trim()
    if ($name -ne "source_of_truth_for") {
      $fields[$name] = $value.Trim('"').Trim("'")
      continue
    }
    $items = @()
    if ($value -match '^\[(?<body>.*)\]$') {
      if (-not [string]::IsNullOrWhiteSpace([string]$matches["body"])) {
        $items = @([string]$matches["body"] -split ',' | ForEach-Object { $_.Trim().Trim('"').Trim("'") })
      }
    } elseif ([string]::IsNullOrWhiteSpace($value)) {
      while (($i + 1) -lt $lines.Count -and [string]$lines[$i + 1] -match '^\s{2}-\s+(.+?)\s*$') {
        $i++
        $items += ([string]$matches[1]).Trim().Trim('"').Trim("'")
      }
    } else {
      throw "[mir-doc-index-source-list] $Relative"
    }
    $fields[$name] = @($items)
  }
  return [pscustomobject]@{match=$match;fields=$fields}
}

function Read-LegacyTruths([string]$Text) {
  $map = @{}
  $path = $null
  $reading = $false
  foreach ($line in @((Normalize-Lf $Text) -split $lf)) {
    if ($line -match '^\s{2}- path:\s+(docs/.+?\.md)\s*$') {
      $path = [string]$matches[1]
      $map[$path] = @()
      $reading = $false
      continue
    }
    if ($null -eq $path) { continue }
    if ($line -match '^\s{4}source_of_truth_for:\s*(.*?)\s*$') {
      $reading = $true
      $inline = ([string]$matches[1]).Trim()
      if ($inline -match '^\[(?<body>.*)\]$' -and -not [string]::IsNullOrWhiteSpace([string]$matches["body"])) {
        $map[$path] = @([string]$matches["body"] -split ',' | ForEach-Object { $_.Trim().Trim('"').Trim("'") })
      }
      continue
    }
    if ($reading -and $line -match '^\s{6}-\s+([A-Za-z0-9._-]+)\s*$') {
      $map[$path] += [string]$matches[1]
      continue
    }
    if ($line -match '^\s{4}[A-Za-z_][A-Za-z0-9_]*:') { $reading = $false }
  }
  return $map
}

function Import-Truths([string]$Path,[string]$Relative,[string[]]$Truths) {
  if (@($Truths).Count -eq 0) { return }
  $text = [IO.File]::ReadAllText($Path)
  $front = Read-Frontmatter $text $Relative
  if ($front.fields.Contains("source_of_truth_for")) { return }
  $newline = if ($text.Contains($cr + $lf)) { $cr + $lf } else { $lf }
  $addition = $newline + "source_of_truth_for:"
  $addition += $newline + (@($Truths | ForEach-Object { "  - $_" }) -join $newline)
  $offset = $front.match.Groups["body"].Index + $front.match.Groups["body"].Length
  [IO.File]::WriteAllText($Path, $text.Insert($offset, $addition), $utf8)
}

function Remove-EmptyTruthField([string]$Path,[string]$Relative) {
  $text = [IO.File]::ReadAllText($Path)
  $newline = if ($text.Contains($cr + $lf)) { $cr + $lf } else { $lf }
  $pattern = '(?m)^source_of_truth_for:(?:[ \t]*\[\]|\r?\n[ ]{2}-[ \t]*)\r?\n'
  $repaired = [regex]::Replace($text, $pattern, '')
  if ($repaired -ceq $text) { return }
  if ($Check) { throw "[mir-doc-index-redundant-empty-truth] $Relative" }
  [IO.File]::WriteAllText($Path, $repaired, $utf8)
}

function Read-Record([string]$Path,[string]$Relative) {
  $front = Read-Frontmatter ([IO.File]::ReadAllText($Path)) $Relative
  foreach ($field in @("title","status","applies_to","audience","doc_type","owner","last_reviewed")) {
    if (-not $front.fields.Contains($field)) { throw "[mir-doc-index-field] $Relative -> $field" }
  }
  $reviewed = [DateTime]::MinValue
  if (-not [DateTime]::TryParseExact([string]$front.fields.last_reviewed, "yyyy-MM-dd", [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$reviewed)) {
    throw "[mir-doc-index-review-date] $Relative"
  }
  $truths = @(if ($front.fields.Contains("source_of_truth_for")) { @($front.fields.source_of_truth_for) } else { @() })
  if ($script:immutableTruthMap.ContainsKey($Relative)) {
    if ($truths.Count -gt 0) { throw "[mir-doc-index-immutable-truth-in-page] $Relative" }
    $truths = @($script:immutableTruthMap[$Relative])
  }
  foreach ($truth in $truths) {
    if ([string]$truth -notmatch '^[A-Za-z0-9._-]+$') { throw "[mir-doc-index-truth-id] $Relative -> $truth" }
  }
  return [pscustomobject][ordered]@{
    path=$Relative
    title=[string]$front.fields.title
    status=[string]$front.fields.status
    applies_to=[string]$front.fields.applies_to
    audience=[string]$front.fields.audience
    doc_type=[string]$front.fields.doc_type
    owner=[string]$front.fields.owner
    last_reviewed=[string]$front.fields.last_reviewed
    source_of_truth_for=@($truths)
  }
}

function Generated-Record([string]$Path,[string]$Title,[string]$Truth) {
  return [pscustomobject][ordered]@{
    path=$Path;title=$Title;status="current";applies_to="MIR 4.0.0+"
    audience="maintainer";doc_type="reference";owner="mir-maintainers"
    last_reviewed="2026-08-26";source_of_truth_for=@($Truth)
  }
}

function Frontmatter($Record) {
  $lines = @(
    "---","title: $(Quote-Yaml $Record.title)","status: $($Record.status)",
    "applies_to: $(Quote-Yaml $Record.applies_to)","audience: $($Record.audience)",
    "doc_type: $($Record.doc_type)","owner: $($Record.owner)",
    "last_reviewed: $($Record.last_reviewed)","supersedes: []","superseded_by: []",
    "source_of_truth_for:"
  )
  $lines += @($Record.source_of_truth_for | ForEach-Object { "  - $_" })
  $lines += "---"
  return $lines -join $lf
}

function Doc-Link($Record) {
  return "../../" + $Record.path.Substring(5)
}

$immutableText = [IO.File]::ReadAllText($immutableTruthPath)
if (-not ($immutableText | Test-Json -SchemaFile $immutableTruthSchemaPath)) {
  throw "[mir-doc-index-immutable-truth-schema]"
}
$immutableRecord = $immutableText | ConvertFrom-Json -Depth 20
foreach ($record in @($immutableRecord.records)) {
  $path = [string]$record.path
  if ($script:immutableTruthMap.ContainsKey($path)) { throw "[mir-doc-index-immutable-truth-duplicate] $path" }
  $script:immutableTruthMap[$path] = @($record.source_of_truth_for)
}

if ($ImportLegacyIndex) {
  if ($Check) { throw "[mir-doc-index-mode] import and check are mutually exclusive" }
  $legacy = Read-LegacyTruths ([IO.File]::ReadAllText($indexPath))
  foreach ($file in @(Get-ChildItem -LiteralPath $docsRoot -Recurse -File -Filter "*.md" | Sort-Object FullName)) {
    $relative = Relative-Path $file.FullName
    $truths = if ($legacy.ContainsKey($relative)) { @($legacy[$relative]) } else { @() }
    if ($script:immutableTruthMap.ContainsKey($relative)) { continue }
    Import-Truths $file.FullName $relative $truths
  }
}

$generated = [ordered]@{
  "docs/reference/generated/documentation-index.md" = Generated-Record "docs/reference/generated/documentation-index.md" "Generated Documentation Index" "generated-documentation-index"
  "docs/reference/generated/documentation-owner-dashboard.md" = Generated-Record "docs/reference/generated/documentation-owner-dashboard.md" "Generated Documentation Owner Dashboard" "generated-documentation-owner-dashboard"
  "docs/reference/generated/documentation-review-age.md" = Generated-Record "docs/reference/generated/documentation-review-age.md" "Generated Documentation Review Age" "generated-documentation-review-age"
  "docs/reference/generated/documentation-navigation.md" = Generated-Record "docs/reference/generated/documentation-navigation.md" "Generated Documentation Navigation" "generated-documentation-navigation"
  "docs/reference/generated/documentation-reference-matrix.md" = Generated-Record "docs/reference/generated/documentation-reference-matrix.md" "Generated Documentation Reference Matrix" "generated-documentation-reference-matrix"
}

$records = @()
foreach ($file in @(Get-ChildItem -LiteralPath $docsRoot -Recurse -File -Filter "*.md" | Sort-Object FullName)) {
  $relative = Relative-Path $file.FullName
  if ($generated.Contains($relative)) { continue }
  Remove-EmptyTruthField $file.FullName $relative
  $records += Read-Record $file.FullName $relative
}
$records += @($generated.Values)
$records = @($records | Sort-Object path)
$truthRows = @($records | ForEach-Object { $record=$_; @($record.source_of_truth_for) | ForEach-Object { [pscustomobject]@{id=$_;record=$record} } })
$duplicates = @($truthRows | Group-Object id | Where-Object Count -gt 1)
if ($duplicates.Count -gt 0) { throw "[mir-doc-index-duplicate-truth] $($duplicates.Name -join ', ')" }
$asOf = @($records | ForEach-Object { [DateTime]::ParseExact($_.last_reviewed, "yyyy-MM-dd", [Globalization.CultureInfo]::InvariantCulture) } | Sort-Object -Descending)[0]

$yaml = @(
  "# GENERATED by tools/commands/docs/Update-MIRDocumentationIndex.ps1.",
  "# Edit Markdown front matter, then regenerate this compatibility projection.",
  "# Versioned release-note source IDs come from the immutable custody sidecar.",
  "schema: 1","authority: markdown-frontmatter","generated: true","","docs:"
)
foreach ($record in $records) {
  $yaml += @(
    "  - path: $($record.path)","    title: $(Quote-Yaml $record.title)",
    "    status: $($record.status)","    audience: $($record.audience)",
    "    doc_type: $($record.doc_type)","    owner: $($record.owner)"
  )
  if (@($record.source_of_truth_for).Count -eq 0) {
    $yaml += "    source_of_truth_for: []"
  } else {
    $yaml += "    source_of_truth_for:"
    $yaml += @($record.source_of_truth_for | ForEach-Object { "      - $_" })
  }
}

$pages = [ordered]@{}
$self = $generated["docs/reference/generated/documentation-index.md"]
$body = @((Frontmatter $self),"","# Documentation index","","Generated from Markdown front matter plus the immutable versioned-release-note custody sidecar for $($records.Count) pages as of $($asOf.ToString('yyyy-MM-dd')).","","| Path | Title | Status | Audience | Type | Owner | Reviewed |","| --- | --- | --- | --- | --- | --- | --- |")
$body += @($records | ForEach-Object { "| $($_.path) | $(Table-Text $_.title) | $($_.status) | $($_.audience) | $($_.doc_type) | $($_.owner) | $($_.last_reviewed) |" })
$pages[$self.path] = ($body -join $lf) + $lf

$self = $generated["docs/reference/generated/documentation-owner-dashboard.md"]
$body = @((Frontmatter $self),"","# Documentation owner dashboard","","Generated from Markdown front matter as of $($asOf.ToString('yyyy-MM-dd')).","","| Owner | Total | Current | Draft | Historical or retired |","| --- | ---: | ---: | ---: | ---: |")
foreach ($group in @($records | Group-Object owner | Sort-Object Name)) {
  $rows=@($group.Group);$current=@($rows|Where-Object status -eq "current").Count;$draft=@($rows|Where-Object status -eq "draft").Count
  $body += "| $($group.Name) | $($rows.Count) | $current | $draft | $($rows.Count-$current-$draft) |"
}
$pages[$self.path] = ($body -join $lf) + $lf

$self = $generated["docs/reference/generated/documentation-review-age.md"]
$body = @((Frontmatter $self),"","# Documentation review age","","Ages are measured against the newest governed review date, $($asOf.ToString('yyyy-MM-dd')), so checkout results do not change with wall-clock time.","","| Path | Status | Last reviewed | Age (days) | Review band |","| --- | --- | --- | ---: | --- |")
foreach ($record in $records) {
  $date=[DateTime]::ParseExact($record.last_reviewed,"yyyy-MM-dd",[Globalization.CultureInfo]::InvariantCulture);$age=[Math]::Max(0,[int]($asOf-$date).TotalDays)
  $band=if($age-le90){"current-window"}elseif($age-le180){"review-soon"}else{"review-overdue"}
  $body += "| $($record.path) | $($record.status) | $($record.last_reviewed) | $age | $band |"
}
$pages[$self.path] = ($body -join $lf) + $lf

$self = $generated["docs/reference/generated/documentation-navigation.md"]
$body = @((Frontmatter $self),"","# Documentation navigation","","Current-page navigation generated from Markdown front matter as of $($asOf.ToString('yyyy-MM-dd')).","")
foreach ($audience in @($records|Where-Object status -eq "current"|Group-Object audience|Sort-Object Name)) {
  $body += @("## $($audience.Name)","")
  foreach($type in @($audience.Group|Group-Object doc_type|Sort-Object Name)){
    $body += @("### $($type.Name)","")
    $body += @($type.Group|Sort-Object title|ForEach-Object{"- [$($_.title)]($(Doc-Link $_))"})
    $body += ""
  }
}
$pages[$self.path] = ($body -join $lf).TrimEnd() + $lf

$self = $generated["docs/reference/generated/documentation-reference-matrix.md"]
$body = @((Frontmatter $self),"","# Documentation reference matrix","","Generated from source-of-truth identifiers in Markdown front matter plus the immutable versioned-release-note custody sidecar as of $($asOf.ToString('yyyy-MM-dd')).","","| Authority ID | Document | Status |","| --- | --- | --- |")
$body += @($truthRows|Sort-Object id|ForEach-Object{"| $($_.id) | [$($_.record.title)]($(Doc-Link $_.record)) | $($_.record.status) |"})
$pages[$self.path] = ($body -join $lf) + $lf

$desired = [ordered]@{$indexPath=(($yaml -join $lf)+$lf)}
foreach($entry in $pages.GetEnumerator()){$desired[(Join-Path $repo $entry.Key)]=$entry.Value}
$changed=@()
foreach($entry in $desired.GetEnumerator()){
  $actual=if(Test-Path -LiteralPath $entry.Key -PathType Leaf){Normalize-Lf([IO.File]::ReadAllText($entry.Key))}else{$null}
  $expected=Normalize-Lf([string]$entry.Value)
  if($actual-cne$expected){
    $relative=[IO.Path]::GetRelativePath($repo,$entry.Key).Replace("\","/")
    if($Check){$changed+=$relative}else{[IO.File]::WriteAllText($entry.Key,$expected,$utf8);$changed+=$relative}
  }
}
if($Check-and$changed.Count-gt0){throw "[mir-doc-index-stale] $($changed -join ', ')"}
[pscustomobject][ordered]@{status=if($Check){"passed"}else{"generated"};authority="markdown-frontmatter";document_count=$records.Count;source_of_truth_count=$truthRows.Count;generated_projection_count=$desired.Count;changed=@($changed)}|ConvertTo-Json -Depth 5
