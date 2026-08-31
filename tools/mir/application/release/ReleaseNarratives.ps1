Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'ReleaseNarrativeModel.ps1')
. (Join-Path $PSScriptRoot 'SourceChangelogRenderer.ps1')
. (Join-Path $PSScriptRoot 'FactorioTargetChangelogRenderer.ps1')
. (Join-Path $PSScriptRoot 'GitHubReleaseRenderer.ps1')
. (Join-Path $PSScriptRoot 'ModPortalRenderer.ps1')
. (Join-Path $PSScriptRoot 'TechnicalReleaseRenderer.ps1')
. (Join-Path $PSScriptRoot 'ReleaseManifestChangeRenderer.ps1')

function Get-MIR4ReleaseNarrativeMaterialV1 {
  param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][string]$PlanPath)
  $plan = Read-MIR4NarrativeJsonV1 -RepoRoot $RepoRoot -Path $PlanPath -SchemaPath 'contracts/release/mir4-release-narrative-plan-v1.schema.json'
  if ([string]$plan.renderer_abi -cne $script:MIR4NarrativeAbi -or -not [bool]$plan.shadow_only -or [bool]$plan.publication_authorized) { throw '[mir4-release-narrative-plan-firewall]' }
  if (@($plan.targets.target | Sort-Object -Unique).Count -ne @($plan.targets).Count) { throw '[mir4-release-narrative-duplicate-plan-target]' }

  $fragments = [Collections.Generic.List[object]]::new()
  $identities = [Collections.Generic.List[object]]::new()
  $ids = @{}
  foreach ($path in @($plan.change_fragments)) {
    $fragment = Read-MIR4NarrativeJsonV1 -RepoRoot $RepoRoot -Path ([string]$path) -SchemaPath 'contracts/release/mir4-change-fragment-v2.schema.json'
    Assert-MIR4NarrativeFragmentV1 -Fragment $fragment
    if ($ids.ContainsKey([string]$fragment.change_id)) { throw "[mir4-release-narrative-duplicate-change] $($fragment.change_id)" }
    $ids[[string]$fragment.change_id] = $true
    $fragments.Add($fragment)
    $identities.Add((Get-MIR4NarrativeFileIdentityV1 -RepoRoot $RepoRoot -Path ([string]$path)))
  }
  $orderedFragments = @($fragments | Sort-Object change_id)
  foreach ($target in @($plan.targets)) {
    $affectedPlayerChanges = @($orderedFragments | Where-Object {
      [string]$_.package_visibility -ceq 'player-package' -and
      [string]$_.release_surfaces.target_changelog -cne 'omit' -and
      [string](@($_.target_dispositions | Where-Object target -eq ([string]$target.target))[0].disposition) -ceq 'affected'
    })
    if ([string]$target.package_action -ceq 'build' -and $affectedPlayerChanges.Count -eq 0) { throw "[mir4-release-narrative-empty-package-plan] $($target.target)" }
    if ([string]$target.package_action -cne 'build' -and $affectedPlayerChanges.Count -ne 0) { throw "[mir4-release-narrative-affected-target-without-package] $($target.target)" }
  }
  $outputs = [ordered]@{}
  $outputs['CHANGELOG.md'] = [ordered]@{surface='source-changelog';target=$null;text=(Render-MIR4SourceChangelogV1 -Plan $plan -Fragments $orderedFragments)}
  $outputs['github-release.md'] = [ordered]@{surface='github-release';target=$null;text=(Render-MIR4GitHubReleaseV1 -Plan $plan -Fragments $orderedFragments)}
  $outputs['technical-release.md'] = [ordered]@{surface='technical-release';target=$null;text=(Render-MIR4TechnicalReleaseV1 -Plan $plan -Fragments $orderedFragments)}
  $outputs['release-manifest.json'] = [ordered]@{surface='manifest-change-inventory';target=$null;text=(Render-MIR4ReleaseManifestChangesV1 -Plan $plan -Fragments $orderedFragments)}
  foreach ($target in @($plan.targets | Where-Object package_action -eq 'build')) {
    $targetName = ([string]$target.target).ToLowerInvariant()
    $outputs["$targetName/changelog.txt"] = [ordered]@{surface='factorio-changelog';target=[string]$target.target;text=(Render-MIR4FactorioTargetChangelogV1 -Plan $plan -Target $target -Fragments $orderedFragments)}
    $outputs["$targetName/mod-portal.md"] = [ordered]@{surface='mod-portal';target=[string]$target.target;text=(Render-MIR4ModPortalV1 -Plan $plan -Target $target -Fragments $orderedFragments)}
  }
  return [pscustomobject][ordered]@{plan=$plan;fragments=$orderedFragments;fragment_identities=@($identities);plan_identity=(Get-MIR4NarrativeFileIdentityV1 -RepoRoot $RepoRoot -Path $PlanPath);outputs=$outputs}
}

function Get-MIR4ReleaseNarrativeResultDigestV1 {
  param([Parameter(Mandatory)]$Record)
  $copy = $Record | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
  $copy.result_digest = ''
  return Get-MIR4CanonicalDigestV1 -Value $copy -Domain 'mir4:release-narrative-result:1'
}

function Invoke-MIR4ReleaseNarrativesV1 {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][string]$PlanPath, [Parameter(Mandatory)][string]$OutputRoot, [ValidateSet('render','check')][string]$Command = 'render')
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $packageBefore = Get-MIRPackageSourceFingerprint -RepoRoot $repo
  if ($packageBefore -cne '8D59F97AC6A42917A22E160E492ED94854D3D377C57D22C3FE27AE6A9C77A336') { throw '[mir4-release-narrative-package-source-baseline]' }
  $first = Get-MIR4ReleaseNarrativeMaterialV1 -RepoRoot $repo -PlanPath $PlanPath
  $second = Get-MIR4ReleaseNarrativeMaterialV1 -RepoRoot $repo -PlanPath $PlanPath
  foreach ($key in $first.outputs.Keys) {
    if (-not $second.outputs.Contains($key) -or [string]$first.outputs[$key].text -cne [string]$second.outputs[$key].text) { throw "[mir4-release-narrative-determinism] $key" }
  }
  $root = if ([IO.Path]::IsPathRooted($OutputRoot)) { $OutputRoot } else { Join-Path $repo $OutputRoot }
  $descriptors = [Collections.Generic.List[object]]::new()
  foreach ($entry in $first.outputs.GetEnumerator()) {
    $relative = [string]$entry.Key
    $text = [string]$entry.Value.text
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($text)
    $sha = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    $descriptors.Add([ordered]@{surface=[string]$entry.Value.surface;target=$entry.Value.target;path=$relative;sha256=$sha;bytes=$bytes.Length})
    $full = Join-Path $root $relative
    if ($Command -ceq 'check') {
      if (-not (Test-Path -LiteralPath $full -PathType Leaf) -or [IO.File]::ReadAllText($full) -cne $text) { throw "[mir4-release-narrative-output-drift] $relative" }
    } else {
      [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $full))
      [IO.File]::WriteAllText($full, $text, [Text.UTF8Encoding]::new($false))
    }
  }
  if ((Get-MIRPackageSourceFingerprint -RepoRoot $repo) -cne $packageBefore) { throw '[mir4-release-narrative-package-source-mutation]' }
  $record = [ordered]@{
    schema=1;kind='MIR4ReleaseNarrativeResultV1';plan_id=[string]$first.plan.plan_id;renderer_abi=$script:MIR4NarrativeAbi
    plan=$first.plan_identity;accepted_changes=@($first.fragment_identities);outputs=@($descriptors)
    checks=[ordered]@{authority='passed';determinism='passed';target_filtering='passed';public_copy='passed';factorio_format='passed';package_non_interference='passed';unknown_dispositions=0}
    package_source_sha256=$packageBefore;package_visible_delta=@();transition_gate=[ordered]@{merge=$false;tagging=$false;signing=$false;sealing=$false;version_allocation=$false;publication=$false};result_digest=''
  }
  $record.result_digest = Get-MIR4ReleaseNarrativeResultDigestV1 -Record ([pscustomobject]$record)
  $resultJson = (($record | ConvertTo-Json -Depth 100).Replace("`r`n","`n") + "`n")
  if (-not ($resultJson | Test-Json -SchemaFile (Join-Path $repo 'contracts/release/mir4-release-narrative-result-v1.schema.json'))) { throw '[mir4-release-narrative-result-schema]' }
  $resultPath = Join-Path $root 'rendering-result.json'
  if ($Command -ceq 'check') {
    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf) -or [IO.File]::ReadAllText($resultPath) -cne $resultJson) { throw '[mir4-release-narrative-result-drift]' }
  } else { [IO.File]::WriteAllText($resultPath, $resultJson, [Text.UTF8Encoding]::new($false)) }
  return [pscustomobject]$record
}
