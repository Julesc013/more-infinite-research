param(
  [Parameter(Mandatory,Position=0)][ValidateSet('lock','diff','bundle','minimize','verify','reference')][string]$Mode,
  [string]$InputPath,
  [string]$OtherPath,
  [string]$OutputPath,
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
)
$ErrorActionPreference='Stop'
. (Join-Path $RepoRoot 'tools/mir/application/assurance/EnvironmentEvidence.ps1')

function Read-MIR4EnvironmentJson([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { throw '[mir4-environment-cli-input]' }
  Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -Depth 100
}

function Write-MIR4EnvironmentResult($Value) {
  $json=(ConvertTo-MIR4CanonicalJsonV1 $Value)+[Environment]::NewLine
  if ($OutputPath) {
    $full=[IO.Path]::GetFullPath($OutputPath)
    $parent=Split-Path -Parent $full
    if (-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    [IO.File]::WriteAllText($full,$json,[Text.UTF8Encoding]::new($false))
  } else { $json }
}

switch($Mode) {
  'lock' { Write-MIR4EnvironmentResult (New-MIR4EnvironmentLockV1 (Read-MIR4EnvironmentJson $InputPath)) }
  'diff' { Write-MIR4EnvironmentResult (New-MIR4EnvironmentDiffV1 -Base (Read-MIR4EnvironmentJson $InputPath) -Candidate (Read-MIR4EnvironmentJson $OtherPath)) }
  'bundle' {
    $request=Read-MIR4EnvironmentJson $InputPath
    Write-MIR4EnvironmentResult (New-MIR4EnvironmentSupportBundleV1 -EnvironmentLock $request.environment_lock -BundleId $request.bundle_id -EvidenceItems @($request.evidence_items) -Diagnostics @($request.diagnostics))
  }
  'minimize' { Write-MIR4EnvironmentResult (Minimize-MIR4SupportBundleV1 (Read-MIR4EnvironmentJson $InputPath)) }
  'verify' {
    $value=Read-MIR4EnvironmentJson $InputPath
    if([string]$value.kind -ceq'MIR4EnvironmentLockV1'){Test-MIR4EnvironmentLockV1 $value|Out-Null}
    elseif([string]$value.kind -ceq'MIR4EnvironmentDiffV1'){Test-MIR4EnvironmentDiffV1 $value|Out-Null}
    elseif([string]$value.kind -ceq'MIR4SupportBundleV1'){Test-MIR4SupportBundleV1 $value|Out-Null}
    else{throw '[mir4-environment-cli-kind]'}
    [pscustomobject][ordered]@{status='passed';kind=[string]$value.kind;digest=[string]$value.digest}|ConvertTo-Json -Compress
  }
  'reference' { Write-MIR4EnvironmentResult (New-MIR4ReferenceEnvironmentEvidenceV1 -RepoRoot $RepoRoot) }
}
