$script:MIR4HostedReceiptOnly = [string]$env:MIR4_EXTERNAL_EVIDENCE_MODE -ceq 'hosted-receipt'

if (-not [string]::IsNullOrWhiteSpace([string]$env:MIR4_EXTERNAL_EVIDENCE_MODE) -and
    -not $script:MIR4HostedReceiptOnly) {
  throw "Unknown MIR 4 external-evidence mode: $env:MIR4_EXTERNAL_EVIDENCE_MODE"
}
if ($script:MIR4HostedReceiptOnly -and [string]$env:GITHUB_ACTIONS -cne 'true') {
  throw 'MIR 4 hosted-receipt mode is restricted to GitHub Actions; local validation must inspect exact evidence bytes.'
}

function Test-MIR4HostedReceiptOnly {
  return $script:MIR4HostedReceiptOnly
}

function Assert-MIR4ExternalEvidenceBinding {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$Sha256,
    [string[]]$AllowedRoots = @('build/results/mir4-sol', 'build/mir4')
  )

  $normalized = $RelativePath.Replace('\', '/')
  if ([IO.Path]::IsPathRooted($RelativePath) -or
      $normalized -match '(^|/)\.\.(/|$)' -or
      @($AllowedRoots | Where-Object {
        $normalized -ceq $_ -or $normalized.StartsWith($_ + '/', [StringComparison]::Ordinal)
      }).Count -eq 0) {
    throw "MIR 4 receipt names an external-evidence path outside its private roots: $RelativePath"
  }
  if ($Sha256 -cnotmatch '^[A-F0-9]{64}$') {
    throw "MIR 4 receipt external-evidence binding lacks an uppercase SHA-256: $RelativePath"
  }
  if ($script:MIR4HostedReceiptOnly) {
    return $false
  }

  $path = Join-Path $RepoRoot $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
      (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $Sha256) {
    throw "MIR 4 exact external evidence is absent or differs from its receipt: $RelativePath"
  }
  return $true
}
