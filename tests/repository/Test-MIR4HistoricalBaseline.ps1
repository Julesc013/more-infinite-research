# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,[switch]$IdentityOnly)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
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
if($IdentityOnly -or $env:GITHUB_ACTIONS -cne 'true') { Write-Host 'Pinned historical commit, tree and immutable paths verified; original-profile replay requires the hosted receipt context and remains a required CI check.'; return }
$root=Join-Path $repo ('build/tests/historical-baseline/'+[guid]::NewGuid().ToString('N'))
$worktree=Join-Path $root 'source'
New-Item -ItemType Directory -Force -Path $root | Out-Null
# Historical MIR 3 records bind CRLF checkout bytes. Use an isolated clone
# with the original Windows checkout convention and the pinned attributes.
# Nested historical worktrees inherit long-path support from this clone only.
& git clone --shared --no-checkout -c core.autocrlf=true -c core.longpaths=true $repo $worktree 2>&1 | Out-Null
if($LASTEXITCODE -ne 0) { throw '[mir4-history-clone]' }

# A local clone advertises local heads, whereas Actions keeps branch history
# under refs/remotes/origin. Preserve that read-only namespace in the replay.
& git -C $worktree fetch --no-tags $repo '+refs/remotes/origin/*:refs/remotes/origin/*' 2>&1 | Out-Null
if($LASTEXITCODE -ne 0) { throw '[mir4-history-remote-ref-custody]' }

# Original branch-policy checks fetch advertised heads. The local object donor
# is not that remote; keep the primary checkout's upstream for those reads.
$upstreamOrigin=(& git -C $repo remote get-url origin).Trim()
if($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($upstreamOrigin)) { throw '[mir4-history-upstream-origin]' }
& git -C $worktree remote set-url origin $upstreamOrigin
if($LASTEXITCODE -ne 0) { throw '[mir4-history-upstream-origin]' }

& git -C $worktree checkout --detach $epoch.historical_commit 2>&1 | Out-Null
if($LASTEXITCODE -ne 0) { throw '[mir4-history-materialization]' }
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
  [ordered]@{status='passed';scope='historical-integrity-not-current-qualification';commit=$epoch.historical_commit;tree=$tree;tests=$results} | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $root 'receipt.json')
} finally {
  $env:MIR4_EXTERNAL_EVIDENCE_MODE=$priorMode
  $dirty=@(& git -C $worktree status --porcelain)
  if($LASTEXITCODE -eq 0 -and $dirty.Count -eq 0) {
    $resolved=[IO.Path]::GetFullPath($worktree)
    $boundary=[IO.Path]::GetFullPath((Join-Path $repo 'build/tests/historical-baseline'))+[IO.Path]::DirectorySeparatorChar
    if(-not $resolved.StartsWith($boundary,[StringComparison]::OrdinalIgnoreCase)) { throw '[mir4-history-cleanup-boundary]' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
  } else { Write-Warning "Retained historical worktree with changed material: $worktree" }
}
Write-Host "Historical profile passed on pinned source; current gameplay remains separately qualified. Evidence: $root"
