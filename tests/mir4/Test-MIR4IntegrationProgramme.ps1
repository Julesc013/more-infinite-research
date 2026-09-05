# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$path=Join-Path $RepoRoot 'spec/programmes/mir4-4x-operating-programme-v1.json'
$raw=Get-Content -Raw -LiteralPath $path
if(-not($raw | Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/mir4-4x-operating-programme-v1.schema.json'))) { throw '[synthesis-programme-schema]' }
$p=$raw | ConvertFrom-Json -Depth 100 -DateKind String
$root=Join-Path $RepoRoot 'spec/programmes/inputs/synthesis-2026-09-05'
$m=Get-Content -Raw -LiteralPath (Join-Path $root 'manifest.json') | ConvertFrom-Json
foreach($f in $m.files) {
 $full=[IO.Path]::GetFullPath((Join-Path $root $f.path))
 if(-not $full.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw '[synthesis-input-path]' }
 if((Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash -ine $f.sha256 -or (Get-Item -LiteralPath $full).Length -ne $f.bytes) { throw "[synthesis-input-identity] $($f.path)" }
}
$requests=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $p.synthesis.request_ledger) | ConvertFrom-Json -Depth 100
$expected=@(1..7 | ForEach-Object { 'K2-{0:D2}' -f $_ })+@(1..16 | ForEach-Object { 'BA-{0:D2}' -f $_ })
if(@(Compare-Object ($expected | Sort-Object) @($requests.requests.id | Sort-Object)).Count -ne 0) { throw '[synthesis-exact-23-requests]' }
$components=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $p.synthesis.component_destinations) | ConvertFrom-Json
$platform=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'spec/platform/mir4-preview-v0/platform.json') | ConvertFrom-Json
if(@(Compare-Object @($platform.components.id | Sort-Object) @($components.components.id | Sort-Object)).Count -ne 0) { throw '[synthesis-component-coverage]' }
$tasks=@($p.synthesis.tasks)
$ids=@($tasks.id)
if(@($ids | Sort-Object -Unique).Count -ne $tasks.Count) { throw '[synthesis-duplicate-task]' }
$done=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
while($done.Count -lt $tasks.Count) {
 $before=$done.Count
 foreach($t in $tasks) {
  if(@($t.depends_on | Where-Object { $_ -notin $ids }).Count -ne 0) { throw '[synthesis-unknown-dependency]' }
  if(@($t.requests | Where-Object { $_ -notin $expected }).Count -ne 0) { throw '[synthesis-unknown-request]' }
  if(@($t.programme_mapping | Where-Object { $_ -notin $p.work_packages.id -and $_ -ne 'maintenance' }).Count -ne 0) { throw '[synthesis-unknown-programme]' }
  if($t.state -eq 'complete' -and @($t.evidence).Count -eq 0) { throw '[synthesis-false-completion]' }
  if(@($t.depends_on | Where-Object { -not $done.Contains($_) }).Count -eq 0) { [void]$done.Add($t.id) }
 }
 if($done.Count -eq $before) { throw '[synthesis-dependency-cycle]' }
}
if(@(Compare-Object ($expected | Sort-Object) @($tasks.requests | Sort-Object -Unique)).Count -ne 0) { throw '[synthesis-unowned-request]' }
if($p.synthesis.objectives_measured -or $p.synthesis.heavy_engine_concurrency -ne 1) { throw '[synthesis-unmeasured-capacity]' }
if($p.synthesis.release_baseline.source -cne '3562377b520cccb071b97b3968946eae7024c950' -or $p.synthesis.release_baseline.human_acceptance.f210 -cne 'release-specific-direct-playtest-waiver') { throw '[synthesis-release-history]' }
if(@($p.work_packages | Where-Object { $_.id -eq 'M41-08' -and $_.state -eq 'complete' }).Count -ne 1 -or @($p.work_packages | Where-Object { $_.id -eq 'M43-00' -and $_.state -eq 'active' }).Count -ne 1) { throw '[synthesis-current-state]' }
Write-Output 'Synthesis input integrity, complete request/component coverage, dependency graph, and truthful completion boundaries passed.'

# The controlled proof is reusable only for these exact current module bytes.
$scienceEvidence=Join-Path $RepoRoot 'spec/programmes/evidence/synthesis-2026-09-06/science-modules.json'
$science=Get-Content -Raw $scienceEvidence | ConvertFrom-Json
if($science.status -cne 'passed' -or $science.assertions -ne 33 -or $science.scope -cne 'controlled-modules-not-real-k2-qualification') { throw '[synthesis-science-proof-scope]' }
foreach($module in $science.modules) {
  if((Get-FileHash -LiteralPath (Join-Path $RepoRoot $module.path)).Hash -cne $module.sha256) { throw "[synthesis-science-proof-stale] $($module.path)" }
}
if((Get-FileHash -LiteralPath (Join-Path $RepoRoot 'tests/compiler/science_planning.lua')).Hash -cne $science.test_sha256) { throw '[synthesis-science-test-stale]' }
