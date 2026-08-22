param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)

$ErrorActionPreference='Stop'
. (Join-Path $RepoRoot 'tools/lib/mir4/PlatformPreview.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')

$authority=Get-MIR4TargetCompilerAuthority -RepoRoot $RepoRoot
$contracts=New-MIR4TargetContractSet -RepoRoot $RepoRoot
$laws=Test-MIR4TargetProviderLaws -RepoRoot $RepoRoot
if(@($contracts.targets).Count-ne 17-or@($contracts.targets.target|Sort-Object -Unique).Count-ne 17){throw '[mir4-w02-target-count]'}
if(-not$laws.passed-or@($laws.targets|Where-Object status -ne 'passed').Count-ne 0){throw '[mir4-w02-provider-laws]'}
if(@($contracts.targets|Where-Object{$_.target-in@('f012','f011','f010','f009','f008','f007','f006')-and$_.inputs.status-ne'BLOCKED_WITH_EVIDENCE'}).Count-ne 0){throw '[mir4-w02-museum-boundary]'}
if(@($contracts.targets|Where-Object{$_.target-in@('f210','f200')-and$_.maturity-ne'stable'}).Count-ne 0){throw '[mir4-w02-modern-maturity]'}
if(@($contracts.targets|Where-Object{$_.authoritative_output-or$_.mutation_capability-or$_.public_support_claim}).Count-ne 0){throw '[mir4-w02-shadow-authority]'}
if(@($contracts.targets.facilities|Where-Object{[string]$_.disposition-notin@($authority.facility_dispositions)}).Count-ne 0){throw '[mir4-w02-facility-disposition]'}

$packageFiles=@(Get-MIRPackageSourceFiles -RepoRoot $RepoRoot)
foreach($path in @('.mir/releases/waves/mir4-r0/MIR4-Target-Compiler-ProgrammeV1.json','tools/lib/mir4/TargetCompiler.ps1','tools/commands/mir4/New-MIR4TargetProductSet.ps1')){if($path-in$packageFiles){throw "[mir4-w02-package-visible] $path"}}
Write-Host '[ok] MIR 4 W02 target contracts and all nine provider laws passed for f006-f210.'
