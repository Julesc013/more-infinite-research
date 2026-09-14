function Test-MIR4CurrentPackagePresentationV3LegacyContentChainMigration {
  [CmdletBinding()]
  param([Parameter(Mandatory)]$Ledger)

  $rows = @($Ledger.rows)
  return (
    [string]$Ledger.kind -ceq 'MIR4CurrentPackagePresentationV3Ledger' -and
    [string]$Ledger.record_sha256 -ceq 'E8F9FD3C982C4D531F7E917603DC63F8C07F9C237D3E2932F2CABF8A9E552717' -and
    $rows.Count -eq 2 -and
    [string]$Ledger.genesis_row_sha256 -ceq 'D3CFC1529C32C820458F4EEBD72E2A5A6401762ED037C376624A6534D41EEEF1' -and
    -not $Ledger.PSObject.Properties['genesis_record_sha256'] -and
    -not $Ledger.PSObject.Properties['custody'] -and
    [string]$rows[0].row_sha256 -ceq 'D3CFC1529C32C820458F4EEBD72E2A5A6401762ED037C376624A6534D41EEEF1' -and
    [string]$rows[1].row_sha256 -ceq '7B6B4DC410BC89DD5322F83803306B41F048785D47A4CD7E6891507000E9EEFC' -and
    [string]$rows[1].ledger_predecessor.record_sha256 -ceq '7837F146C60944351540005CCDE54E78A637768895DFF884EE2B672727A30AF5'
  )
}

function Test-MIR4CurrentPackagePresentationV3TrustedOriginUrl {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$OriginUrl)

  # Custody reads a protected GitHub remote only.  Plain HTTP is deliberately
  # excluded: Git permits it, but it does not provide transport integrity.
  return $OriginUrl -imatch '^(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)Julesc013/more-infinite-research(?:\.git)?/?$'
}

function Assert-MIR4CurrentPackagePresentationV3ProtectedCustodyPrefix {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)]$CandidateLedger,
    $TrustedLedger,
    [switch]$TrustedBaseHasNoV3,
    [string]$TrustedBaseRef = ''
  )

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  Assert-MIR4CurrentPackagePresentationV3LedgerRecord -RepoRoot $repo -Ledger $CandidateLedger -RequireLiveCurrent:$false | Out-Null
  if ($TrustedBaseHasNoV3) {
    if (
      [string]$CandidateLedger.custody.bootstrap -cne 'bounded-v3-content-chain-migration-v1' -or
      @($CandidateLedger.rows).Count -ne 2 -or
      [string]$CandidateLedger.rows[0].row_sha256 -cne 'D3CFC1529C32C820458F4EEBD72E2A5A6401762ED037C376624A6534D41EEEF1' -or
      [string]$CandidateLedger.rows[1].row_sha256 -cne '326F1140ABADED3076735C63FC2A88A494A347466187D5CD5FAF2C25108D2208'
    ) {
      throw '[mir4-package-presentation-v3-custody-bootstrap]'
    }
    return [pscustomobject][ordered]@{
      status = 'trusted-base-v3-absent-bounded-bootstrap'
      trusted_base_ref = $TrustedBaseRef
      candidate_rows = @($CandidateLedger.rows).Count
      protected_custody_required = $true
    }
  }

  if ($null -eq $TrustedLedger) { throw '[mir4-package-presentation-v3-custody-base-missing]' }
  if (Test-MIR4CurrentPackagePresentationV3LegacyContentChainMigration -Ledger $TrustedLedger) {
    if (
      [string]$CandidateLedger.custody.bootstrap -cne 'bounded-v3-content-chain-migration-v1' -or
      @($CandidateLedger.rows).Count -ne 2 -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $CandidateLedger.rows[0]) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $TrustedLedger.rows[0]) -or
      [string]$CandidateLedger.rows[1].row_sha256 -cne '326F1140ABADED3076735C63FC2A88A494A347466187D5CD5FAF2C25108D2208'
    ) {
      throw '[mir4-package-presentation-v3-custody-migration]'
    }
    return [pscustomobject][ordered]@{
      status = 'bounded-content-chain-migration'
      trusted_base_ref = $TrustedBaseRef
      candidate_rows = @($CandidateLedger.rows).Count
      protected_custody_required = $true
    }
  }

  Assert-MIR4CurrentPackagePresentationV3LedgerRecord -RepoRoot $repo -Ledger $TrustedLedger -RequireLiveCurrent:$false | Out-Null
  $candidateRows = @($CandidateLedger.rows)
  $trustedRows = @($TrustedLedger.rows)
  if ($candidateRows.Count -lt $trustedRows.Count) {
    throw '[mir4-package-presentation-v3-custody-tail-retention]'
  }
  for ($index = 0; $index -lt $trustedRows.Count; $index++) {
    if (
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $candidateRows[$index]) -cne
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $trustedRows[$index])
    ) {
      throw "[mir4-package-presentation-v3-custody-prefix] $index"
    }
  }
  return [pscustomobject][ordered]@{
    status = $(if ($candidateRows.Count -eq $trustedRows.Count) { 'protected-prefix-current' } else { 'protected-prefix-appended' })
    trusted_base_ref = $TrustedBaseRef
    trusted_rows = $trustedRows.Count
    candidate_rows = $candidateRows.Count
    protected_custody_required = $true
  }
}

function Resolve-MIR4CurrentPackagePresentationV3TrustedBase {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [string]$TrustedBaseRef = '',
    [switch]$HostedContext
  )

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $baseName = if ([string]::IsNullOrWhiteSpace($TrustedBaseRef)) {
    if ([string]::IsNullOrWhiteSpace($env:GITHUB_BASE_REF)) { 'dev' } else { [string]$env:GITHUB_BASE_REF }
  } else {
    ''
  }
  $reference = if ([string]::IsNullOrWhiteSpace($TrustedBaseRef)) {
    'refs/remotes/origin/' + $baseName
  } else {
    $TrustedBaseRef
  }
  if (
    $reference -notmatch '^refs/remotes/origin/[A-Za-z0-9][A-Za-z0-9._/-]*$' -or
    $reference.Contains('..') -or
    $reference.Contains('//')
  ) {
    throw '[mir4-package-presentation-v3-custody-base-untrusted]'
  }

  $origin = @(& git -C $repo remote get-url origin 2>$null)
  if ($LASTEXITCODE -ne 0 -or $origin.Count -ne 1 -or
      -not (Test-MIR4CurrentPackagePresentationV3TrustedOriginUrl -OriginUrl ([string]$origin[0]))) {
    throw '[mir4-package-presentation-v3-custody-origin-untrusted]'
  }
  $commit = @(& git -C $repo rev-parse --verify ($reference + '^{commit}') 2>$null)
  if ($LASTEXITCODE -ne 0 -or $commit.Count -ne 1 -or [string]$commit[0] -notmatch '^[a-f0-9]{40}$') {
    throw '[mir4-package-presentation-v3-custody-base-unavailable]'
  }

  $ledgerRelative = 'spec/distribution/mir4-current-package-presentation-v3.json'
  & git -C $repo cat-file -e (([string]$commit[0]) + ':' + $ledgerRelative) 2>$null
  $hasV3 = $LASTEXITCODE -eq 0
  if ($hasV3) {
    $text = [string]((& git -C $repo show (([string]$commit[0]) + ':' + $ledgerRelative) 2>$null) -join [Environment]::NewLine)
    if ($LASTEXITCODE -ne 0) { throw '[mir4-package-presentation-v3-custody-base-read]' }
    try { $ledger = $text | ConvertFrom-Json -Depth 100 -DateKind String }
    catch { throw '[mir4-package-presentation-v3-custody-base-json]' }
    return [pscustomobject][ordered]@{
      reference = $reference
      commit = [string]$commit[0]
      has_v3 = $true
      ledger = $ledger
    }
  }

  $v2Relative = 'spec/distribution/mir4-current-package-presentation-v2.json'
  $v2Text = [string]((& git -C $repo show (([string]$commit[0]) + ':' + $v2Relative) 2>$null) -join [Environment]::NewLine)
  if ($LASTEXITCODE -ne 0) { throw '[mir4-package-presentation-v3-custody-base-v2-unavailable]' }
  try { $v2 = $v2Text | ConvertFrom-Json -Depth 100 -DateKind String }
  catch { throw '[mir4-package-presentation-v3-custody-base-v2-json]' }
  if ([string]$v2.record_sha256 -cne 'C33F1B568CA247108D88C4F2A109C45E29F2C77C4EE026CB4C9047BAA3A2360F') {
    throw '[mir4-package-presentation-v3-custody-base-v2-untrusted]'
  }
  return [pscustomobject][ordered]@{
    reference = $reference
    commit = [string]$commit[0]
    has_v3 = $false
    ledger = $null
  }
}

function Assert-MIR4CurrentPackagePresentationV3ProtectedCustody {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    $CandidateLedger,
    [string]$TrustedBaseRef = '',
    [switch]$HostedContext
  )

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $candidate = if ($null -eq $CandidateLedger) {
    Assert-MIR4CurrentPackagePresentationV3Ledger -RepoRoot $repo
  } else {
    $CandidateLedger
  }
  $base = Resolve-MIR4CurrentPackagePresentationV3TrustedBase -RepoRoot $repo -TrustedBaseRef $TrustedBaseRef -HostedContext:$HostedContext
  return Assert-MIR4CurrentPackagePresentationV3ProtectedCustodyPrefix -RepoRoot $repo -CandidateLedger $candidate -TrustedLedger $base.ledger -TrustedBaseHasNoV3:(!$base.has_v3) -TrustedBaseRef ([string]$base.reference)
}
