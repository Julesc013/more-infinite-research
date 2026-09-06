# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,[switch]$IdentityOnly)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function New-MIR4HistoricalReplayCheckout {
  param([Parameter(Mandatory)][string]$Repo,[Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)]$Epoch)
  $donor=Join-Path $Root 'refs.git'
  $source=Join-Path $Root 'source'
  New-Item -ItemType Directory -Force -Path $Root | Out-Null
  # Export upstream history as advertised heads in a disposable local remote.
  # Pin permanent branch roles so later development cannot reinterpret history.
  & git clone --bare --shared $Repo $donor 2>&1 | Out-Null
  if($LASTEXITCODE -ne 0) { throw '[mir4-history-ref-donor]' }
  & git -C $donor fetch --no-tags $Repo '+refs/remotes/origin/*:refs/heads/*' 2>&1 | Out-Null
  if($LASTEXITCODE -ne 0) { throw '[mir4-history-remote-ref-custody]' }
  & git -C $donor update-ref -d refs/heads/HEAD
  if($LASTEXITCODE -ne 0) { throw '[mir4-history-remote-head-cleanup]' }
  foreach($ref in $Epoch.historical_refs.PSObject.Properties) {
    & git -C $donor update-ref $ref.Name ([string]$ref.Value)
    if($LASTEXITCODE -ne 0) { throw "[mir4-history-ref-snapshot] $($ref.Name)" }
  }
  & git -C $donor symbolic-ref HEAD refs/heads/main
  if($LASTEXITCODE -ne 0) { throw '[mir4-history-default-head]' }
  # Pinned MIR 3 receipts bind Windows CRLF checkout bytes. Nested worktrees
  # also require long paths; both settings apply only to this replay clone.
  & git clone --shared --no-checkout -c core.autocrlf=true -c core.longpaths=true $donor $source 2>&1 | Out-Null
  if($LASTEXITCODE -ne 0) { throw '[mir4-history-clone]' }
  & git -C $source checkout --detach $Epoch.historical_commit 2>&1 | Out-Null
  if($LASTEXITCODE -ne 0) { throw '[mir4-history-materialization]' }
  return $source
}

$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$epoch=Get-Content -Raw (Join-Path $repo 'governance/repository/development-epoch-v1.json') | ConvertFrom-Json
if($epoch.historical_commit -cne '3683369ba00cfbdd7f8872a5a1b24f0d59f31062' -or $epoch.historical_tree -cne 'a95caf6e96ec9b0eef4eb19677e9a8192821f522') { throw '[mir4-history-trust-anchor]' }
$tree=(& git -C $repo rev-parse ($epoch.historical_commit+'^{tree}')).Trim()
if($LASTEXITCODE -ne 0 -or $tree -cne $epoch.historical_tree) { throw '[mir4-history-tree]' }
foreach($path in $epoch.immutable_paths) {
  $changed=@(& git -C $repo diff --name-only $epoch.historical_commit -- $path)
  if($LASTEXITCODE -ne 0 -or $changed.Count) { throw "[mir4-history-immutable-change] $path" }
  $new=@(& git -C $repo ls-files --others --exclude-standard -- $path)
  if($LASTEXITCODE -ne 0 -or $new.Count) { throw "[mir4-history-unreviewed-receipt] $path" }
}
$expectedRefs=@('refs/heads/dev','refs/heads/legacy','refs/heads/main','refs/heads/release/4.0')
if(@(Compare-Object $expectedRefs @($epoch.historical_refs.PSObject.Properties.Name | Sort-Object)).Count) { throw '[mir4-history-ref-inventory]' }
foreach($ref in $epoch.historical_refs.PSObject.Properties) {
  if([string]$ref.Value -cnotmatch '^[0-9a-f]{40}$') { throw '[mir4-history-ref-identity]' }
  $commit=(& git -C $repo rev-parse ([string]$ref.Value+'^{commit}')).Trim()
  if($LASTEXITCODE -ne 0 -or $commit -cne [string]$ref.Value) { throw '[mir4-history-ref-object]' }
}
if($epoch.historical_refs.'refs/heads/dev' -cne $epoch.historical_commit -or
   (& git -C $repo rev-parse ($epoch.historical_refs.'refs/heads/main'+'^{tree}')).Trim() -cne $epoch.historical_tree) { throw '[mir4-history-ref-baseline]' }
if($IdentityOnly -or $env:GITHUB_ACTIONS -cne 'true') { Write-Host 'Pinned historical commit, tree and immutable paths verified; original-profile replay requires the hosted receipt context and remains a required CI check.'; return }
$root=Join-Path $repo ('build/tests/historical-baseline/'+[guid]::NewGuid().ToString('N'))
$worktree=New-MIR4HistoricalReplayCheckout -Repo $repo -Root $root -Epoch $epoch
$priorMode=$env:MIR4_EXTERNAL_EVIDENCE_MODE
if($env:GITHUB_ACTIONS -ceq 'true') { $env:MIR4_EXTERNAL_EVIDENCE_MODE='hosted-receipt' }
$results=@()
try {
  # The pinned source supplies both the selected profile and its original
  # validators. Current validators cannot silently reinterpret old receipts.
  $assurance=Get-Content -Raw (Join-Path $worktree '.mir/assurance.json') | ConvertFrom-Json
  $catalog=Get-Content -Raw (Join-Path $worktree 'validation/tests.yml') | ConvertFrom-Json
  Push-Location $worktree
  try {
    & pwsh -NoProfile -File tools/mir.ps1 verify plan --profile $epoch.historical_profile --output (Join-Path $root 'verification-plan.json') *> (Join-Path $root 'plan.log')
    if($LASTEXITCODE -ne 0) { throw "[mir4-history-plan] $root" }
    foreach($id in $assurance.profiles.($epoch.historical_profile)) {
      $row=@($catalog.tests | Where-Object id -CEQ $id)
      if($row.Count -ne 1 -or $row[0].requires_factorio) { throw "[mir4-history-test-contract] $id" }
      $parts=([string]$row[0].command).Split(' ',[StringSplitOptions]::RemoveEmptyEntries)
      if($parts[0] -notmatch '^\./(?:tests|scripts)/[A-Za-z0-9/.-]+[.]ps1$') { throw "[mir4-history-command] $id" }
      $log=Join-Path $root ($id+'.log')
      Write-Host "[historical-source] $id"
      & pwsh -NoProfile -File @parts *> $log
      $code=$LASTEXITCODE
      $results+=@{id=$id;exit_code=$code;log_sha256=(Get-FileHash -LiteralPath $log).Hash;scope='pinned-historical-source'}
      if($code -ne 0) { Get-Content -LiteralPath $log -Tail 12; throw "[mir4-history-test-failed] $id; evidence: $root" }
    }
  } finally { Pop-Location }
  [ordered]@{status='passed';scope='historical-integrity-not-current-qualification';commit=$epoch.historical_commit;tree=$tree;historical_refs=$epoch.historical_refs;tests=$results} | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $root 'receipt.json')
} finally {
  $env:MIR4_EXTERNAL_EVIDENCE_MODE=$priorMode
  $dirty=@(& git -C $worktree status --porcelain)
  if($LASTEXITCODE -eq 0 -and $dirty.Count -eq 0) {
    $resolved=[IO.Path]::GetFullPath($worktree)
    $boundary=[IO.Path]::GetFullPath((Join-Path $repo 'build/tests/historical-baseline'))+[IO.Path]::DirectorySeparatorChar
    if(-not $resolved.StartsWith($boundary,[StringComparison]::OrdinalIgnoreCase)) { throw '[mir4-history-cleanup-boundary]' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
    $donor=[IO.Path]::GetFullPath((Join-Path $root 'refs.git'))
    if(-not $donor.StartsWith($boundary,[StringComparison]::OrdinalIgnoreCase)) { throw '[mir4-history-cleanup-boundary]' }
    Remove-Item -LiteralPath $donor -Recurse -Force
  } else { Write-Warning "Retained historical worktree with changed material: $worktree" }
}
Write-Host "Historical profile passed on pinned source; current gameplay remains separately qualified. Evidence: $root"
