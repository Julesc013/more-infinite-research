function Invoke-MIRCoreCommandGroup {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]$RepoRoot,
    [Parameter(Mandatory)][string]$ScriptRoot,
    [Parameter(Mandatory)][string]$Area,
    [Parameter(Mandatory)][string]$Verb,
    [AllowEmptyCollection()][string[]]$CommandArguments = @()
  )

  & {
    param(
      $repo,
      [string]$scriptRoot,
      [string]$area,
      [string]$verb
    )

    switch ($area) {
      "layout" {
        if ($verb -notin @("check", "inventory")) { throw "Unknown layout command: $verb" }
        $output = Get-MIRArgValue -Items $Args -Name "--output"
        $params = @{
          RepoRoot = $repo.Path
          Strict = (Test-MIRArgSwitch -Items $Args -Name "--strict")
          InventoryOnly = ($verb -eq "inventory")
        }
        if (-not [string]::IsNullOrWhiteSpace($output)) { $params.OutputPath = $output }
        & (Join-Path $repo "tools/commands/workspace/Invoke-MIRLayoutCheck.ps1") @params
      }
      "path" {
        if ($verb -ne "resolve") { throw "Unknown path command: $verb" }
        $id = Get-MIRArgValue -Items $Args -Name "--id"
        $path = Get-MIRArgValue -Items $Args -Name "--path"
        if ([string]::IsNullOrWhiteSpace($id) -and [string]::IsNullOrWhiteSpace($path) -and $Args.Count -gt 2) {
          $id = $Args[2]
        }
        $params = @{RepoRoot=$repo.Path}
        if (-not [string]::IsNullOrWhiteSpace($id)) { $params.Id = $id }
        if (-not [string]::IsNullOrWhiteSpace($path)) { $params.Path = $path }
        & (Join-Path $repo "tools/commands/workspace/Resolve-MIRRepoPath.ps1") @params
      }
      "verify" {
        $verifyCommand = switch ($verb) {
          "plan" { "plan" }
          "fingerprint" { "fingerprint" }
          "explain" { "explain" }
          "run-one" { "run-one" }
          "run" { "verify" }
          "import-workers" { "import-workers" }
          "gate" { "gate" }
          "qualify" { "qualify" }
          default { throw "Unknown verify command: $verb" }
        }
        [string[]]$verifyArgs = @($verifyCommand)
        if ($Args.Count -gt 2) { $verifyArgs += @($Args[2..($Args.Count - 1)]) }
        & (Join-Path $scriptRoot "Invoke-MIRAssurance.ps1") @verifyArgs
      }
      "assurance" {
        [string[]]$assuranceArgs = if ($Args.Count -gt 1) { @($Args[1..($Args.Count - 1)]) } else { @("help") }
        & (Join-Path $scriptRoot "Invoke-MIRAssurance.ps1") @assuranceArgs
      }
      "docs" {
        if ($verb -ne "check") { throw "Unknown docs command: $verb" }
        & (Join-Path $scriptRoot "Invoke-MIRValidation.ps1") -DocsOnly
      }
      "architecture" {
        if ($verb -ne "check") { throw "Unknown architecture command: $verb" }
        & (Join-Path $scriptRoot "Invoke-MIRValidation.ps1") -ArchitectureOnly
      }
      "manifests" {
        if ($verb -ne "check") { throw "Unknown manifests command: $verb" }
        & (Join-Path $scriptRoot "Invoke-MIRValidation.ps1") -ManifestsOnly
      }
      default { throw '[mir4-router-core-area]' }
    }
  } $RepoRoot $ScriptRoot $Area $Verb @CommandArguments
}
