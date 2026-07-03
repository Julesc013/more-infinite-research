$ErrorActionPreference = "Stop"

function Get-MIRReleaseDependencies {
  param([Parameter(Mandatory)]$Release)

  $deps = @()
  foreach ($dependency in @($Release.info_json.dependencies)) {
    if ([string]::IsNullOrWhiteSpace($dependency)) { continue }
    $deps += ConvertFrom-MIRDependencyString -Dependency $dependency
  }
  return $deps
}

function Resolve-MIRRequiredDependencyClosure {
  param(
    [Parameter(Mandatory)][string[]]$RootModNames,
    [Parameter(Mandatory)][scriptblock]$GetFullMod,
    [Parameter(Mandatory)][scriptblock]$SelectRelease,
    [string[]]$ExcludeModNames = @("base", "space-age", "quality", "elevated-rails", "recycler"),
    [switch]$FailFast
  )

  $excluded = @{}
  foreach ($name in $ExcludeModNames) { $excluded[$name] = $true }

  $queue = [System.Collections.Generic.Queue[string]]::new()
  foreach ($name in $RootModNames) {
    if (-not $excluded[$name]) { $queue.Enqueue($name) }
  }

  $resolved = @{}
  $failures = @()

  while ($queue.Count -gt 0) {
    $name = $queue.Dequeue()
    if ($excluded[$name] -or $resolved.ContainsKey($name)) { continue }

    try {
      $full = & $GetFullMod $name
      $release = & $SelectRelease $full
      if (-not $release) {
        throw "No compatible release selected for dependency '$name'."
      }

      $deps = @(Get-MIRReleaseDependencies -Release $release)
      $resolved[$name] = [pscustomobject]@{
        name = $name
        full = $full
        release = $release
        dependencies = $deps
      }

      foreach ($dep in $deps) {
        if ($dep.required -and -not $excluded[$dep.name] -and -not $resolved.ContainsKey($dep.name)) {
          $queue.Enqueue($dep.name)
        }
      }
    } catch {
      $failures += [pscustomobject]@{
        name = $name
        error = $_.Exception.Message
      }
      if ($FailFast) { throw }
    }
  }

  [pscustomobject]@{
    resolved = @($resolved.Values | Sort-Object name)
    failures = $failures
  }
}
