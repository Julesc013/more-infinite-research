[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [switch]$Check
)

$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/MIR441PackagePresentation.ps1')

$rows=[Collections.Generic.List[object]]::new()
foreach($target in @('f210','f200','f110','f100')){
  $presentation=Get-MIR441PackagePresentationV1 -RepoRoot $repo -Target $target -SourceVersion '4.1.0'
  $second=Get-MIR441PackagePresentationV1 -RepoRoot $repo -Target $target -SourceVersion '4.1.0'
  if([string]$presentation.readme_sha256-cne[string]$second.readme_sha256-or
     [string]$presentation.changelog_sha256-cne[string]$second.changelog_sha256-or
     [string]$presentation.readme-notmatch[regex]::Escape([string]$presentation.distribution_version)-or
     [string]$presentation.changelog-notmatch("(?m)^Version:\s+"+[regex]::Escape([string]$presentation.distribution_version)+"$")-or
     [string]$presentation.readme-match'[A-Za-z]:\\'){
    throw "[mir441-package-presentation-proof] $target"
  }
  $rows.Add([pscustomobject][ordered]@{target=$target;distribution_version=[string]$presentation.distribution_version;readme_sha256=[string]$presentation.readme_sha256;changelog_sha256=[string]$presentation.changelog_sha256;baseline_templates_unchanged=$true})
}

[pscustomobject][ordered]@{
  status='MIR-4.1-PACKAGE-PRESENTATION-AUTHORITY-PASSED'
  targets=@($rows)
  generated_at_materialization=$true
  baseline_templates_unchanged=$true
  check=[bool]$Check
  publication_authorized=$false
}
