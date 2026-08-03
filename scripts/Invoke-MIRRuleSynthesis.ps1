param(
  [Parameter(Mandatory)][string]$Family,
  [string]$CorpusPath = ".mir\technology-review-corpus.json",
  [string]$SnapshotsPath = ".mir\technology-review-snapshots.json",
  [string]$AuthorityPath = ".mir\rule-synthesis.json",
  [Parameter(Mandatory)][string]$OutputPath
)

# MIR-L5-LEGACY-COMMAND-WRAPPER: retained for historical command compatibility only.
$canonicalCommand = Join-Path $PSScriptRoot "../tools/commands/technology/Invoke-MIRRuleSynthesis.ps1"
& $canonicalCommand @PSBoundParameters
exit $LASTEXITCODE