function Invoke-MIR4CommandDispatch {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]$RepoRoot,
    [Parameter(Mandatory)][string]$ScriptRoot,
    [Parameter(Mandatory)][string]$Verb,
    [AllowEmptyCollection()][string[]]$CommandArguments = @()
  )

  $bootstrapCommands = @('capture-terminal-baselines','import-terminal-baselines','check','build-local-beta','check-local-beta','build-local-playtest','check-local-playtest','build-historical-private','check-historical-private','build-m4c01-player-set','check-m4c01-player-set','runtime-historical-private','api','sdk','platform')
  $applicationCommands = @('environment-evidence','assurance-scale','release-governance','release-engine','tooling','patch-rehearsal','release-narratives','repository','factorio-2.1-channel','package-source')
  $migrationCommands = @('canonicalization-migration','diagnostics-migration','target-key-migration','whole-platform-migration','technology-acceptance-migration','target-compiler-migration','semantic-compiler-policy-migration','runtime-continuity-migration','module-sdk-mep-migration','processir-exact-migration','inspector-compatibility-migration','assurance-offline-custody-migration','historical-tooling-migration','release-tooling-migration','historical-succession')
  $platformCommands = @('targets','semantic','runtime-continuity','module-ecosystem','processir-synthesis','exact-processir','release-canaries','inspector-compatibility','whole-platform','acceptance','extension','handoff-m4c01')

  if ($Verb -in $bootstrapCommands) { return Invoke-MIR4BootstrapCommandGroup -RepoRoot $RepoRoot -ScriptRoot $ScriptRoot -Verb $Verb -CommandArguments $CommandArguments }
  if ($Verb -in $applicationCommands) { return Invoke-MIR4ApplicationCommandGroup -RepoRoot $RepoRoot -ScriptRoot $ScriptRoot -Verb $Verb -CommandArguments $CommandArguments }
  if ($Verb -in $migrationCommands) { return Invoke-MIR4MigrationCommandGroup -RepoRoot $RepoRoot -ScriptRoot $ScriptRoot -Verb $Verb -CommandArguments $CommandArguments }
  if ($Verb -in $platformCommands) { return Invoke-MIR4PlatformCommandGroup -RepoRoot $RepoRoot -ScriptRoot $ScriptRoot -Verb $Verb -CommandArguments $CommandArguments }
  throw "Unknown mir4 command: $Verb"
}
