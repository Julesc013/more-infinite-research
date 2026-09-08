# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $repo 'tools/lib/mir4/PreFreezeRelease.ps1')

function Assert-MIR4StructuredDoctorFailure {
  param([Parameter(Mandatory)]$Result,[Parameter(Mandatory)][string]$Route)
  $candidate=@($Result.checks|Where-Object id -eq 'final-mile-playtest-candidate-authority')
  $manual=@($Result.checks|Where-Object id -eq 'maintainer-manual-playtest')
  $automated=@($Result.checks|Where-Object stage -eq 'automated')
  $human=@($Result.checks|Where-Object stage -eq 'human')
  $failed=@($automated|Where-Object status -ne 'passed')
  $blocked=@($human|Where-Object status -ne 'passed')
  if($candidate.Count-ne1-or[string]$candidate[0].stage-cne'automated'-or[string]$candidate[0].status-cne'failed'-or
     [string]$candidate[0].detail-cne'[mir4-final-mile-playtest-authority-package-source]') { throw "[mir4-release-doctor-structured-candidate] $Route" }
  if($manual.Count-ne1-or[string]$manual[0].stage-cne'human'-or[string]$manual[0].status-cne'blocked'-or
     [string]$manual[0].detail-cne'Candidate authority is unavailable; maintainer playtest receipts cannot be inspected and acceptance is never inferred.') { throw "[mir4-release-doctor-structured-manual] $Route" }
  if([string]$Result.prefreeze_status-cne'not-ready'-or[string]$Result.release_status-cne'blocked'-or
     [int]$Result.counts.automated_total-ne$automated.Count-or[int]$Result.counts.automated_failed-ne$failed.Count-or
     [int]$Result.counts.automated_failed-le0-or[int]$Result.counts.human_blocked-ne$blocked.Count-or
     [bool]$Result.source_freeze_authorized-or[bool]$Result.candidate_allocation_authorized-or[bool]$Result.publication_authorized) { throw "[mir4-release-doctor-structured-result] $Route" }
}

$authorityPaths=@(
  '.mir/releases/waves/mir4-r0/MIR4-Final-Mile-Playtest-Candidate-AuthorityV1.json',
  '.mir/releases/waves/mir4-r0/MIR4-Maintainer-Final-GitHub-Release-AuthorizationV1.json',
  '.mir/releases/waves/mir4-r0/MIR4-T06-Authority-Evolution-ReceiptV1.json',
  'src/mod/package-source.json',
  'targets/package-authority.json'
)
$before=[ordered]@{}
foreach($relative in $authorityPaths){$before[$relative]=(Get-MIR4PreFreezeFileSha256 (Join-Path $repo $relative))}
$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
$externalEvidenceMode=[Environment]::GetEnvironmentVariable('MIR4_EXTERNAL_EVIDENCE_MODE','Process')
try {
  [Environment]::SetEnvironmentVariable('MIR4_EXTERNAL_EVIDENCE_MODE',$null,'Process')
  $direct=Get-MIR4ReleaseDoctor -RepoRoot $repo -Explain
  Assert-MIR4StructuredDoctorFailure -Result $direct -Route 'direct'

  $run=Join-Path $repo ('build/tests/mir4-release-doctor-structured/'+[guid]::NewGuid().ToString('N'))
  $output=Join-Path $run 'doctor.json'
  $stderr=Join-Path $run 'stderr.txt'
  New-Item -ItemType Directory -Path $run -Force|Out-Null
  $pwsh=Join-Path $PSHOME 'pwsh.exe'
  $stdout=@(& $pwsh -NoProfile -File (Join-Path $repo 'tools/mir.ps1') release doctor --json --dry-run --output $output 2>$stderr)
  $exitCode=$LASTEXITCODE
  if($exitCode-ne2-or-not(Test-Path -LiteralPath $output -PathType Leaf)-or-not(Test-Path -LiteralPath $stderr -PathType Leaf)-or-not[string]::IsNullOrWhiteSpace((Get-Content -Raw -LiteralPath $stderr))){throw '[mir4-release-doctor-structured-cli-exit-or-output]'}
  $cli=($stdout-join[Environment]::NewLine)|ConvertFrom-Json -Depth 100
  $written=Get-Content -Raw -LiteralPath $output|ConvertFrom-Json -Depth 100
  Assert-MIR4StructuredDoctorFailure -Result $cli -Route 'cli-stdout'
  Assert-MIR4StructuredDoctorFailure -Result $written -Route 'cli-output'
} finally {
  [Environment]::SetEnvironmentVariable('MIR4_EXTERNAL_EVIDENCE_MODE',$externalEvidenceMode,'Process')
}
if((Get-MIRPackageSourceFingerprint -RepoRoot $repo)-cne$packageBefore){throw '[mir4-release-doctor-structured-package-mutation]'}
foreach($relative in $authorityPaths){if((Get-MIR4PreFreezeFileSha256 (Join-Path $repo $relative))-cne$before[$relative]){throw "[mir4-release-doctor-structured-authority-mutation] $relative"}}
$global:LASTEXITCODE=0
[pscustomobject][ordered]@{status='passed';test_id='static.mir4-release-doctor-structured-failure';candidate_authority_error='[mir4-final-mile-playtest-authority-package-source]';cli_exit=2;output_written_during_dry_run=$true;authority_or_package_mutation=$false}|ConvertTo-Json -Compress
