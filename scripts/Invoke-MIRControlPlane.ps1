param(
  [Parameter(Position=0)][ValidateSet("help", "validate", "package-freeze", "baseline", "status", "views")][string]$Command = "help",
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [switch]$AllLocks,
  [switch]$Check
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
foreach ($module in @("Core", "Records", "Planner", "Evidence", "Views", "Shadow")) {
  . (Join-Path $PSScriptRoot "MIRControlPlane/$module.ps1")
}

switch ($Command) {
  "help" {
    @"
MIR Control Plane v5

  validate                  Validate typed records and package freeze.
  package-freeze            Verify the current target package roots and locked archive.
  package-freeze -AllLocks  Reconstruct every locked commit package identity.
  baseline                  Print the immutable 3.2.2 v4 baseline.
  status                    Print current release roles and shadow status.
  views                     Generate release, branch, publication, backport, TODO, and dashboard views.
  views -Check              Fail when any generated control-plane view is stale.
"@ | Write-Host
  }
  "validate" {
    $records = Assert-MIRCPRecords -RepoRoot $repo
    $freeze = Assert-MIRCPPackageFreeze -RepoRoot $repo -AllLocks:$AllLocks
    [pscustomobject][ordered]@{status="passed"; records=$records; package_freeze=$freeze} | ConvertTo-Json -Depth 10
  }
  "package-freeze" {
    Assert-MIRCPPackageFreeze -RepoRoot $repo -AllLocks:$AllLocks | ConvertTo-Json -Depth 10
  }
  "baseline" {
    Read-MIRCPJson -Path ".mir/control-plane/baselines/3.2.2-v4.json" -RepoRoot $repo | ConvertTo-Json -Depth 20
  }
  "status" {
    [pscustomobject][ordered]@{
      canonical = Get-MIRCPCurrentRelease -Role canonical -RepoRoot $repo
      backport = Get-MIRCPCurrentRelease -Role backport_calibration -RepoRoot $repo
      shadow = Get-MIRCPShadowStatus -RepoRoot $repo
    } | ConvertTo-Json -Depth 20
  }
  "views" {
    Update-MIRCPViews -RepoRoot $repo -Check:$Check | ConvertTo-Json -Depth 10
  }
}
