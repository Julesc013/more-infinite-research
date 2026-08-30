param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference='Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/domain/canonicalization/CanonicalJsonV1.ps1')
. (Join-Path $repo 'tools/mir/domain/targets/TargetKey.ps1')

function Assert-MIR4TargetKeyV1 {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code,[string]$Detail='')
  if (-not $Condition) {
    $suffix = if ([string]::IsNullOrWhiteSpace($Detail)) { '' } else { " $Detail" }
    throw "[$Code]$suffix"
  }
}

$cases = @(
  [ordered]@{input='F210';target='F210';legacy_target='f210';distribution_target_code='210'},
  [ordered]@{input='f210';target='F210';legacy_target='f210';distribution_target_code='210'},
  [ordered]@{input='F200';target='F200';legacy_target='f200';distribution_target_code='200'},
  [ordered]@{input='f200';target='F200';legacy_target='f200';distribution_target_code='200'},
  [ordered]@{input='F019';target='F019';legacy_target='f019';distribution_target_code='019'},
  [ordered]@{input='f019';target='F019';legacy_target='f019';distribution_target_code='019'}
)
foreach ($case in $cases) {
  $projection = New-MIR4TargetKeyProjection -Target ([string]$case.input)
  Assert-MIR4TargetKeyV1 ([string]$projection.target -ceq [string]$case.target) 'mir4-target-key-canonical' ([string]$case.input)
  Assert-MIR4TargetKeyV1 ([string]$projection.legacy_target -ceq [string]$case.legacy_target) 'mir4-target-key-legacy' ([string]$case.input)
  Assert-MIR4TargetKeyV1 ([string]$projection.distribution_target_code -ceq [string]$case.distribution_target_code) 'mir4-target-key-distribution' ([string]$case.input)
  Assert-MIR4TargetKeyV1 ((ConvertTo-MIR4LegacyTargetKey -Target ([string]$case.input)) -ceq [string]$case.legacy_target) 'mir4-target-key-legacy-function' ([string]$case.input)
}

$invalid = @('','210','F21','F2100','x210','Ｆ210')
foreach ($value in $invalid) {
  $message = $null
  try { ConvertTo-MIR4TargetKey -Target $value | Out-Null } catch { $message = $_.Exception.Message }
  Assert-MIR4TargetKeyV1 ($message -ceq '[mir4-target-key] Target must be an F-number such as F210 or F200.') 'mir4-target-key-invalid' $value
}
Assert-MIR4TargetKeyV1 ($script:MIR4TargetDisplayPattern -ceq '^F[0-9]{3}$') 'mir4-target-key-display-pattern'
Assert-MIR4TargetKeyV1 ($script:MIR4LegacyTargetPattern -ceq '^f[0-9]{3}$') 'mir4-target-key-legacy-pattern'

. (Join-Path $repo 'tools/lib/mir4/TargetKey.ps1')
Assert-MIR4TargetKeyV1 ((New-MIR4TargetKeyProjection -Target f210).target -ceq 'F210') 'mir4-target-key-forwarder-functional'

[pscustomobject][ordered]@{
  status='passed'
  canonical_implementation='tools/mir/domain/targets/TargetKey.ps1'
  compatibility_entrypoint='tools/lib/mir4/TargetKey.ps1'
  case_count=$cases.Count
  invalid_case_count=$invalid.Count
  parity_digest='sha256:b6bb128bf5f1d312ec3cbe5f8ead03a9ad56b5a1b664514a196960ecc29c7f8e'
  release_transition_authority=$false
}
