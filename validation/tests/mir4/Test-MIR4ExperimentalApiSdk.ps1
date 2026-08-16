$ErrorActionPreference='Stop';$repo=(Resolve-Path(Join-Path $PSScriptRoot '..\..\..')).Path
& (Join-Path $repo 'tools\commands\mir4\Invoke-MIR4ExperimentalApi.ps1') -Command sdk-check -RepoRoot $repo
& (Join-Path $repo 'tools\commands\mir4\Invoke-MIR4ExperimentalApi.ps1') -Command api-check -RepoRoot $repo
& (Join-Path $repo 'tools\commands\mir4\Invoke-MIR4ExperimentalApi.ps1') -Command api-conformance -RepoRoot $repo
$actual=@('sdk/experimental/mir4','spec/api/mir4-v0','spec/schemas/experimental','fixtures/mir4-api-v0','docs/reference/generated/mir4-experimental-api-v0.md','tools/lib/mir4/ExperimentalApiSdk.ps1','tools/commands/mir4/Invoke-MIR4ExperimentalApi.ps1','validation/tests/mir4/Test-MIR4ExperimentalApiSdk.ps1')
. (Join-Path $repo 'tools\lib\validation\PackageIdentity.ps1')
$shipped=@(Get-MIRPackageSourceFiles -RepoRoot $repo)
foreach($path in $actual){if(@($shipped|Where-Object{$_-eq $path-or $_.StartsWith($path.TrimEnd('/')+'/')}).Count){throw "[mir4-api-package-visible] Experimental artifact entered package: $path"}}
Write-Host 'MIR4 experimental API/SDK validation passed.'
