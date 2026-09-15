Set-StrictMode -Version Latest

# Read-only package-output view for current validation.  The editable authority
# is source/package-source.json plus a target composition; the historical
# Factorio-shaped repository root is deliberately never a fallback.
$mir4CurrentTargetPackageRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
if (-not (Get-Command Get-MIR4TargetMaterializerState -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir4CurrentTargetPackageRoot 'tools/mir/application/package/TargetMaterializer.ps1')
}

function Test-MIR4CurrentTargetPackageOutputPath {
  param([Parameter(Mandatory)][string]$RelativePath)
  $portable = $RelativePath.Replace('\', '/').TrimStart('/')
  return $portable -in @('info.json', 'changelog.txt', 'thumbnail.png', 'settings.lua', 'data.lua', 'data-updates.lua', 'data-final-fixes.lua', 'control.lua') -or
    $portable.StartsWith('prototypes/', [StringComparison]::Ordinal) -or
    $portable.StartsWith('locale/', [StringComparison]::Ordinal) -or
    $portable.StartsWith('migrations/', [StringComparison]::Ordinal)
}

function ConvertTo-MIR4CurrentTargetKey {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$FactorioVersion)
  $targetByFactorioVersion = @{
    '2.1' = 'f210'
    '2.0' = 'f200'
    '1.1' = 'f110'
    '1.0' = 'f100'
  }
  $target = [string]$targetByFactorioVersion[$FactorioVersion]
  if ([string]::IsNullOrWhiteSpace($target)) {
    throw "[mir4-current-target-package-unsupported-factorio-version] $FactorioVersion"
  }
  return $target
}

function New-MIR4CurrentTargetPackageContext {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [ValidateSet('f210','f200','f110','f100')][string]$Target = 'f210'
  )

  $state = Get-MIR4TargetMaterializerState -RepoRoot $RepoRoot -Target $Target
  $outputs = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
  foreach ($binding in @(Get-MIR4TargetMaterializationBindings -State $state).bindings) {
    $output = [string]$binding.output_path
    if (-not $outputs.TryAdd($output, [pscustomobject][ordered]@{
      output_path = $output
      source_path = [string]$binding.source_path
      source_file = Join-Path ([string]$state.repo) ([string]$binding.source_path)
      source_sha256 = [string]$binding.source_sha256
      output_sha256 = [string]$binding.output_sha256
      semantic_class = [string]$binding.semantic_class
      transform = [string]$binding.transform
      binding = $binding
    })) { throw "[mir4-current-target-package-output-collision] $Target $output" }
    # Verify the canonical source bytes and output transform before exposing a
    # path to a current validator.  This is a reader, never a second writer.
    $null = Read-MIR4CanonicalSourceBindingBytes -State $state -Binding $binding
  }
  return [pscustomobject][ordered]@{
    repo = [string]$state.repo
    target = $Target
    state = $state
    outputs = $outputs
    package_source_sha256 = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot ([string]$state.repo)
  }
}

function Resolve-MIR4CurrentTargetPackageOutputPath {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]$Context,
    [Parameter(Mandatory)][string]$RelativePath,
    [switch]$AllowMissing
  )
  $portable = $RelativePath.Replace('\', '/').TrimStart('/')
  $entry = $null
  if ($Context.outputs.TryGetValue($portable, [ref]$entry)) { return [string]$entry.source_file }
  if (Test-MIR4CurrentTargetPackageOutputPath -RelativePath $portable) {
    if ($AllowMissing) { return $null }
    throw "[mir4-current-target-package-undeclared-output] $($Context.target) $portable"
  }
  return Join-Path ([string]$Context.repo) $portable
}

function Get-MIR4CurrentTargetPackageOutputEntries {
  [CmdletBinding()]
  param([Parameter(Mandatory)]$Context,[string]$Prefix = '')
  $portablePrefix = $Prefix.Replace('\', '/')
  return @($Context.outputs.Values | Where-Object { [string]$_.output_path -like "$portablePrefix*" } | Sort-Object output_path -CaseSensitive)
}

function Get-MIR4CurrentTargetPackageOutputText {
  [CmdletBinding()]
  param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$RelativePath)
  $path = Resolve-MIR4CurrentTargetPackageOutputPath -Context $Context -RelativePath $RelativePath
  return Get-Content -Raw -LiteralPath $path
}

function Get-MIR4CurrentTargetPackageOutputBytes {
  [CmdletBinding()]
  param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$RelativePath)
  $portable = $RelativePath.Replace('\', '/').TrimStart('/')
  $entry = $null
  if (-not $Context.outputs.TryGetValue($portable, [ref]$entry)) {
    throw "[mir4-current-target-package-undeclared-output] $($Context.target) $portable"
  }
  # Reuse the canonical materializer's read-only binding transform.  This is
  # deliberately not an archive writer: validators compare its bytes with a
  # candidate archive without reviving the retired repository-root projection.
  [byte[]]$bytes = @(Read-MIR4CanonicalSourceBindingBytes -State $Context.state -Binding $entry.binding)
  return ,$bytes
}
