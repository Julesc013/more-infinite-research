param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Args
)

$ErrorActionPreference = "Stop"

$repo = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$scriptRoot = Join-Path $repo "scripts"
. (Join-Path $repo "tools\lib\cli\Console.ps1")
. (Join-Path $repo "tools\lib\cli\PathResolver.ps1")
. (Join-Path $repo "tools\lib\cli\LocalModIndex.ps1")
. (Join-Path $repo "tools\lib\cli\Reports.ps1")
. (Join-Path $repo "tools\mir\domain\targets\TargetKey.ps1")
. (Join-Path $repo "tools\mir\cli\router\ArgumentParsing.ps1")
. (Join-Path $repo "tools\mir\cli\router\RunProfiles.ps1")
. (Join-Path $repo "tools\mir\cli\router\DocsOnlyRelease.ps1")
. (Join-Path $repo "tools\mir\cli\router\MIR4BootstrapCommands.ps1")
. (Join-Path $repo "tools\mir\cli\router\MIR4ApplicationCommands.ps1")
. (Join-Path $repo "tools\mir\cli\router\MIR4MigrationCommands.ps1")
. (Join-Path $repo "tools\mir\cli\router\MIR4PlatformCommands.ps1")
. (Join-Path $repo "tools\mir\cli\router\MIR4CommandDispatcher.ps1")
. (Join-Path $repo "tools\mir\cli\router\CoreCommands.ps1")
. (Join-Path $repo "tools\mir\cli\router\ProductCommands.ps1")
. (Join-Path $repo "tools\mir\cli\router\RepositoryCommands.ps1")
. (Join-Path $repo "tools\mir\cli\router\CommandDispatcher.ps1")

function Show-MIRHelp {
  Write-Host @"
MIR developer CLI

Usage:
  .\tools\mir.ps1 layout check [--strict] [--output <path>]
  .\tools\mir.ps1 layout inventory [--output <path>]
  .\tools\mir.ps1 path resolve <logical-id>
  .\tools\mir.ps1 path resolve --path <historical-path>
  .\tools\mir.ps1 docs check
  .\tools\mir.ps1 architecture check
  .\tools\mir.ps1 manifests check
  .\tools\mir.ps1 mir4 capture-terminal-baselines [--check] [--build-bundles]
  .\tools\mir.ps1 mir4 import-terminal-baselines [--output <path>] [--check]
  .\tools\mir.ps1 mir4 check [--update] [--build-bundles]
  .\tools\mir.ps1 mir4 build-local-beta [--target <all|F210|F200|F110|F100>] [--output <path>] [--repetitions <n>]
  .\tools\mir.ps1 mir4 check-local-beta [--target <all|F210|F200|F110|F100>] [--output <path>]
  .\tools\mir.ps1 mir4 build-local-playtest [--target <all|F200|F110|F100>] [--repetitions <n>]
  .\tools\mir.ps1 mir4 check-local-playtest [--target <all|F200|F110|F100>]
  .\tools\mir.ps1 mir4 build-historical-private [--target <all|F018|F017|F016|F015|F014|F013>]
  .\tools\mir.ps1 mir4 check-historical-private [--target <all|F018|F017|F016|F015|F014|F013>]
  .\tools\mir.ps1 mir4 build-m4c01-player-set
  .\tools\mir.ps1 mir4 check-m4c01-player-set
  .\tools\mir.ps1 mir4 runtime-historical-private --target <F017|F016|F015|F014|F013> [--factorio-bin <path>] [--candidate <path>] [--evidence <path>]
  .\tools\mir.ps1 mir4 api <check|conformance>
  .\tools\mir.ps1 mir4 sdk <generate|check>
  .\tools\mir.ps1 mir4 platform <generate|check|conformance|package>
  .\tools\mir.ps1 mir4 platform compile --target <FNNN> --extension <path> --output <path>
  .\tools\mir.ps1 mir4 environment-evidence <lock|diff|bundle|minimize|verify|reference> [--input <path>] [--other <path>] [--output <path>]
  .\tools\mir.ps1 mir4 assurance-scale <export|check> [--output <path>]
  .\tools\mir.ps1 mir4 release-governance <check|initialize> [--output <path>]
  .\tools\mir.ps1 mir4 release-engine <show|check|phase|readiness-check|candidate-build|qualification|independent-verify|technical-seal|prepare-tag|promotion-plan|promote> [--phase <id>] [--work-root <external path>] [--evidence-root <external path>] [--signing-key <protected path>] [release identity options]
  .\tools\mir.ps1 mir4 tooling <inventory|inventory-check|test-authority|test-authority-check|tests|tests-check|workflows|workflows-check>
  .\tools\mir.ps1 mir4 patch-rehearsal <run|check> [--output <path>]
  .\tools\mir.ps1 mir4 release-narratives <render|check> --plan <path> --output <path>
  .\tools\mir.ps1 mir4 repository <generate|check|inventory|initialize> [--output <path>]
  .\tools\mir.ps1 mir4 factorio-2.1-channel <inspect|check> [--factorio <path>] [--output <path>]
  .\tools\mir.ps1 mir4 package-source <baseline|baseline-check|shadow|shadow-check|model|model-check> [--target <f210|f200|f110|f100>] [--output <path>]
  .\tools\mir.ps1 mir4 canonicalization-migration <check|show> [--output <path>]
  .\tools\mir.ps1 mir4 diagnostics-migration <check|show> [--output <path>]
  .\tools\mir.ps1 mir4 target-key-migration <check|show> [--output <path>]
  .\tools\mir.ps1 mir4 whole-platform-migration <check|show> [--output <path>]
  .\tools\mir.ps1 mir4 technology-acceptance-migration <check|show> [--output <path>]
  .\tools\mir.ps1 mir4 target-compiler-migration <check|show> [--output <path>]
  .\tools\mir.ps1 mir4 semantic-compiler-policy-migration <check|show> [--output <path>]
  .\tools\mir.ps1 mir4 runtime-continuity-migration <check|show> [--output <path>]
  .\tools\mir.ps1 mir4 module-sdk-mep-migration <check|show> [--output <path>]
  .\tools\mir.ps1 mir4 processir-exact-migration <check|show> [--output <path>]
  .\tools\mir.ps1 mir4 inspector-compatibility-migration <check|show> [--output <path>]
  .\tools\mir.ps1 mir4 assurance-offline-custody-migration <check|show> [--output <path>]
  .\tools\mir.ps1 mir4 historical-tooling-migration <generate|check|show> [--output <path>]
  .\tools\mir.ps1 mir4 historical-succession <export|check> [--output <path>]
  .\tools\mir.ps1 mir4 package-source <baseline|baseline-check|shadow|shadow-check|model|model-check|materialize|materialize-check|runtime-replay|runtime-replay-check> [--target <f210|f200|f110|f100>] [--source-version <4.MINOR.PATCH>] [--distribution-version <4.MINOR.ENCODED>] [--candidate-id <id>] [--factorio <path>] [--work-root <path>] [--evidence-root <path>] [--retention <OnFailure|Always|Never>] [--output <path>]
  .\tools\mir.ps1 mir4 targets <contracts|laws|build|check> [--target <all|FNNN>] [--output <path>]
  .\tools\mir.ps1 mir4 semantic <export|check|laws> [--output <path>]
  .\tools\mir.ps1 mir4 runtime-continuity <export|check|laws> [--candidate <path>] [--output <path>]
  .\tools\mir.ps1 mir4 module-ecosystem <export|check> [--candidate <path>] [--output <path>]
  .\tools\mir.ps1 mir4 processir-synthesis <export|check> [--output <path>]
  .\tools\mir.ps1 mir4 exact-processir <export|check> [--capture <id>]... [--repetitions <1-4>] [--output <path>] [--reference <path>] [--publish-reference]
  .\tools\mir.ps1 mir4 release-canaries <export|check> [--capture-root <path>] [--upgrade-root <path>] [--output <path>] [--reference <path>] [--publish-reference]
  .\tools\mir.ps1 mir4 inspector-compatibility <export|check> [--output <path>]
  .\tools\mir.ps1 mir4 whole-platform <generate|check|matrix|target-key> [--target <FNNN>]
  .\tools\mir.ps1 mir4 acceptance queue --catalog <path> --target <FNNN> --ecosystem <id> --output <path>
  .\tools\mir.ps1 mir4 extension <init|validate|explain|test|package|migrate|doctor|lock|diff|ci-init|discover> [--extension <path>] [--discovery <snapshot.json>] [--output <path>] [--id <reverse.dns.id>] [--template <minimal|all-fragments|unavailable>] [--target <FNNN>] [--base <path>] [--candidate <path>]
  .\tools\mir.ps1 mir4 handoff-m4c01 [--output <path>]
  .\tools\mir.ps1 release doctor [--json] [--dry-run] [--explain] [--output <path>]
  .\tools\mir.ps1 playtest prepare --target <F210|F200> [--candidate <path>] [--predecessor <path>] [--factorio <path>] [--settings <path>] [--save <path>] [--output <path>] [--dry-run] [--json]
  .\tools\mir.ps1 playtest capture --session <path> [--capture <path>]... [--observations <path>] [--dry-run] [--json]
  .\tools\mir.ps1 playtest finalize --session <path> --decision <ACCEPTED|CHANGES-REQUESTED|REJECTED> --reviewer <name> [--notes <text>] [--dry-run] [--json]
  .\tools\mir.ps1 rulesets audit [--json] [--output <path>]
  .\tools\mir.ps1 release gate [--profile <name>] [--no-git-pull]
  .\tools\mir.ps1 release docs-only
  .\tools\mir.ps1 release docs-refresh
  .\tools\mir.ps1 overnight local [--profile <name>]
  .\tools\mir.ps1 audit local [--profile <name>]
  .\tools\mir.ps1 audit top25 --space-age
  .\tools\mir.ps1 package build [--target <f210|f200|f110|f100>] [--source-version <4.MINOR.PATCH>] [--distribution-version <4.MINOR.ENCODED>] [--candidate-id <id>] [--output <build/packages/...>]
  .\tools\mir.ps1 backport validate [--manifest <path>] [--allow-pending-tags]
  .\tools\mir.ps1 backport materialize --source <tag> --baseline <tag> --target <line> --manifest <path> --worktree <path> [--receipt <path>]
  .\tools\mir.ps1 storage audit [--all-worktrees] [--older-than-days <days>]
  .\tools\mir.ps1 storage clean [--all-worktrees] [--older-than-days <days>] --apply
  .\tools\mir.ps1 technology quality-assessment --catalog <path> --candidate <id> --profile <path> [--metrics <path>] --output <path>
  .\tools\mir.ps1 technology review-dossier --catalog <path> --candidate <id> [--assessment <path>] --output <path>
  .\tools\mir.ps1 technology promotion-gate --catalog <path> --assessment <path> --approval <path> --promotion <path> --profile <path> [--migration <path>] --output <path>
  .\tools\mir.ps1 assurance <doctor|inventory|impact|domains|plan|fingerprint|build|run-one|verify|gate|qualify|seal|check-seal|locale|balance|backport|explain>
  .\tools\mir.ps1 verify <plan|fingerprint|explain|run-one|run|import-workers|gate|qualify>
  .\tools\mir.ps1 report latest
  .\tools\mir.ps1 report missing-deps --run <path>
  .\tools\mir.ps1 report observations --run <path>
  .\tools\mir.ps1 legacy inventory [--output <path>] [--check]
  .\tools\mir.ps1 profile stub <group-id> --grouped-failures <path>
  .\tools\mir.ps1 run -Profile <profile-name-or-path>
  .\tools\mir.ps1 local-index build --mods <path>

Common overrides:
  --factorio <path>   Factorio binary path
  --factorio-line <2.0|2.1>
  --candidate <path>  Exact MIR candidate ZIP for candidate-bound runtime work
  --mods <path>       Local mod zip/library directory
  --output <path>     Output artifact directory
  --timeout <seconds> Per-scenario timeout
  --link-mode <mode>  Copy, Hardlink, or Symlink local zips into scenario mod dirs
  --skip-strict-gate  Reuse an already completed strict gate in a composed assurance run
  --skip-clean-git-status  Leave source authority to the composed assurance and sealing gates
"@
}

Invoke-MIRCommandDispatch -RepoRoot $repo -ScriptRoot $scriptRoot -CommandArguments $Args
