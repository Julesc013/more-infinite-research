# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $RepoRoot 'tools/mir/application/release/readiness/Promotion.ps1')
$root=Join-Path $RepoRoot ('build/tests/promotion-recovery/'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $root | Out-Null
$script:source='a'*40;$script:original='b'*40
$script:mode='shape';$script:shape=@()
$script:main=$script:original;$script:protected=$false;$script:pushes=0
# All external boundaries are synthetic. No command can write to a real remote.
function git { $global:LASTEXITCODE=0 }
function Invoke-MIR441CaptureCommand {
  param($File,$Arguments)
  $call=$Arguments -join ' '
  if($call -match 'ls-remote --heads origin refs/heads/(main|dev)') {
    if($script:mode -eq 'shape') { return $script:shape }
    $oid=if($Matches[1] -eq 'main'){$script:main}else{$script:source}
    return "$oid`trefs/heads/$($Matches[1])"
  }
  if($File -eq 'git' -and $call -match ' push origin ') {
    $script:pushes++
    if(-not(Test-Path (Join-Path $script:evidence 'promotion/promotion-intent.json'))) { throw 'missing-intent-before-effect' }
    if($script:mode -eq 'reject') { throw 'simulated-rejection' }
    $script:main=$script:source
    if($script:mode -eq 'lost-response') { throw 'simulated-response-loss' }
    return
  }
  if($File -eq 'gh') {
    if($call -match '^repo view ') { return 'synthetic/repository' }
    if($call -match 'rules/branches/main$') { if($script:protected) { return '[{"type":"pull_request","ruleset_id":7}]' };return '[]' }
    if($call -match 'rulesets\?') { return '[]' }
    throw "Unexpected remote command: $call"
  }
  if($File -eq 'git' -and $call -match 'fetch --prune origin|merge-base --is-ancestor|ls-remote --tags origin') { return }
  throw "Unmocked command: $File $call"
}
function Assert-MIR441ExternalRoot { param($RepoRoot,$Path,$Name);return $Path }
function Write-MIR441Json { param($Value,$Path);$Value | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $Path }
function Get-MIR441DirectoryIdentities { param($Root,$Exclude);return @() }
function New-MIR441DeterministicDirectoryArchive { param($SourceRoot,$ArchivePath);return @{path=$ArchivePath;scope='synthetic'} }
function Get-MIR441FileIdentity { param($Path,$RelativePath);return @{path=$RelativePath;sha256=(Get-FileHash $Path).Hash} }
function Expect-Rejection([scriptblock]$Action,[string]$Code) { try { & $Action | Out-Null } catch { if($_.Exception.Message.Contains($Code)){return};throw };throw "Expected $Code" }
Expect-Rejection { Get-MIR441RemoteBranchOid -RepoRoot $RepoRoot -Branch main } 'remote-ref'
$script:shape=@("$script:source`trefs/heads/main")
if((Get-MIR441RemoteBranchOid -RepoRoot $RepoRoot -Branch main) -cne $script:source){throw 'single-reference-shape'}
$script:shape+=@("$script:original`trefs/heads/main")
Expect-Rejection { Get-MIR441RemoteBranchOid -RepoRoot $RepoRoot -Branch main } 'remote-ref'
foreach($case in @('success','lost-response','reject','protected')) {
  $script:mode=$case;$script:main=$script:original;$script:protected=$case -eq 'protected';$script:pushes=0
  $script:evidence=Join-Path $root $case
  $window=Join-Path $script:evidence 'release-window'
  New-Item -ItemType Directory -Force -Path $window | Out-Null
  Write-MIR441Json -Path (Join-Path $window 'technical-seal.json') -Value @{status='MIR41-TECHNICALLY-SEALED-AWAITING-EXACT-MAIN-PROMOTION';source=@{commit=$script:source;tree='c'*40};release=@{tag='v4.1.0'}}
  Write-MIR441Json -Path (Join-Path $window 'prepared-tag.json') -Value @{source_commit=$script:source;signature_verified=$true}
  if($case -eq 'protected') {
    $plan=Invoke-MIR441ExactMainPromotion -RepoRoot $RepoRoot -EvidenceRoot $script:evidence -Plan
    if($plan.blocking_pull_request_rules.Count -ne 1 -or $plan.pull_request_rules_to_suspend.Count -ne 0){throw 'effective-rules-plan'}
    Expect-Rejection { Invoke-MIR441ExactMainPromotion -RepoRoot $RepoRoot -EvidenceRoot $script:evidence } 'protected-pr-required'
    if($script:pushes){throw 'protected-push'}
  } elseif($case -eq 'reject') {
    Expect-Rejection { Invoke-MIR441ExactMainPromotion -RepoRoot $RepoRoot -EvidenceRoot $script:evidence } 'simulated-rejection'
    if(Test-Path (Join-Path $window 'main-promotion.json')){throw 'false-promotion-receipt'}
  } else {
    [void](Invoke-MIR441ExactMainPromotion -RepoRoot $RepoRoot -EvidenceRoot $script:evidence)
    [void](Invoke-MIR441ExactMainPromotion -RepoRoot $RepoRoot -EvidenceRoot $script:evidence)
    if($script:pushes -ne 1){throw 'repeated-promotion-effect'}
    $receipt=Get-Content -Raw (Join-Path $window 'main-promotion.json') | ConvertFrom-Json
    if($receipt.main_before -cne $script:original -or $receipt.main_after -cne $script:source){throw 'promotion-receipt-identity'}
    $intent=Join-Path $script:evidence 'promotion/promotion-intent.json'
    $record=Get-Content -Raw $intent | ConvertFrom-Json;$record.source_commit='d'*40;Write-MIR441Json -Path $intent -Value $record
    Expect-Rejection { Invoke-MIR441ExactMainPromotion -RepoRoot $RepoRoot -EvidenceRoot $script:evidence } 'intent-conflict'
  }
}
Write-Host 'Promotion passed zero/one/many refs, protected-rule preflight, intent-before-effect, rejection, applied/lost-response recovery, idempotence and conflicting-intent tests; no remote mutations.'
