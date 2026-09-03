function Invoke-MIRCommandDispatch {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]$RepoRoot,
    [Parameter(Mandatory)][string]$ScriptRoot,
    [AllowEmptyCollection()][string[]]$CommandArguments = @()
  )

  & {
    param(
      $repo,
      [string]$scriptRoot
    )

    if ($Args.Count -eq 0 -or $Args[0] -eq "help" -or $Args -contains "-h" -or $Args -contains "--help") {
      Show-MIRHelp
      return
    }

    $area = $Args[0]
    $verb = if ($Args.Count -gt 1) { $Args[1] } else { "" }
    $coreAreas = @('layout','path','verify','assurance','docs','architecture','manifests')
    $productAreas = @('technology','release','playtest','rulesets','overnight','audit')
    $repositoryAreas = @('package','backport','storage','report','legacy','profile','run','local-index')

    if ($area -eq "mir4") { return Invoke-MIR4CommandDispatch -RepoRoot $repo -ScriptRoot $scriptRoot -Verb $verb -CommandArguments $Args }
    if ($area -in $coreAreas) { return Invoke-MIRCoreCommandGroup -RepoRoot $repo -ScriptRoot $scriptRoot -Area $area -Verb $verb -CommandArguments $Args }
    if ($area -in $productAreas) { return Invoke-MIRProductCommandGroup -RepoRoot $repo -ScriptRoot $scriptRoot -Area $area -Verb $verb -CommandArguments $Args }
    if ($area -in $repositoryAreas) { return Invoke-MIRRepositoryCommandGroup -RepoRoot $repo -ScriptRoot $scriptRoot -Area $area -Verb $verb -CommandArguments $Args }
    throw "Unknown command area: $area"
  } $RepoRoot $ScriptRoot @CommandArguments
}
