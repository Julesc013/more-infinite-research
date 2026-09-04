# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $repo 'tools/mir/application/release/MIR441ReleaseReadiness.ps1')

function Assert-MIR441Test([bool]$Condition,[string]$Code){if(-not$Condition){throw "[$Code]"}}

$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
$contract=Get-MIR441ReleaseReadinessContract -RepoRoot $repo
$check=Test-MIR441ReleaseReadinessContract -RepoRoot $repo
Assert-MIR441Test ([string]$check.status-ceq'MIR-4.1-RELEASE-READINESS-CONTRACT-PASSED'-and[bool]$check.private_build_authorized-and[bool]$check.technical_seal_authorized-and[bool]$check.exact_main_promotion_authorized-and-not[bool]$check.tagging_authorized-and-not[bool]$check.publication_authorized) 'mir441-contract-gates'
Assert-MIR441Test ((@($contract.targets.distribution_version)-join'|')-ceq'4.1.21000|4.1.20000|4.1.11000|4.1.10000') 'mir441-target-versions'
Assert-MIR441Test (@($contract.targets|Where-Object qualification_role -eq 'technical-required').Count-eq4) 'mir441-four-target-technical-role'
Assert-MIR441Test (@($contract.targets|Where-Object publication_role -eq 'primary').Count-eq2-and@($contract.targets|Where-Object publication_role -eq 'supplemental-lts').Count-eq2) 'mir441-publication-role'
Assert-MIR441Test ([string]$contract.package_source.current_sha256-ceq$packageBefore-and[string]$contract.package_source.predecessor_sha256-ceq'0DEDF851B388D8523110A2ABEDB3A7B2091E1CC119944F5EA7D4C1E7C01698DA') 'mir441-package-source-succession'

$modules=@('Common.ps1','Contract.ps1','ResourceGovernor.ps1','CandidateBuild.ps1','Qualification.ps1','IndependentVerification.ps1','TechnicalSeal.ps1','Promotion.ps1')
foreach($name in $modules){$path=Join-Path $repo "tools/mir/application/release/readiness/$name";$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors);Assert-MIR441Test ($errors.Count-eq0) "mir441-module-syntax-$name";Assert-MIR441Test (([IO.File]::ReadAllLines($path).Count)-le260) "mir441-module-bound-$name"}

$resourceText=[IO.File]::ReadAllText((Join-Path $repo 'tools/mir/application/release/readiness/ResourceGovernor.ps1'))
$commonText=[IO.File]::ReadAllText((Join-Path $repo 'tools/mir/application/release/readiness/Common.ps1'))
$buildText=[IO.File]::ReadAllText((Join-Path $repo 'tools/mir/application/release/readiness/CandidateBuild.ps1'))
$materializerText=[IO.File]::ReadAllText((Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1'))
$promotionText=[IO.File]::ReadAllText((Join-Path $repo 'tools/mir/application/release/readiness/Promotion.ps1'))
Assert-MIR441Test ($resourceText-match'EnumerateFiles'-and$resourceText-match'Write-MIR441Json'-and$resourceText-match'resource-hard-stop'-and$commonText-match'AppendAllText') 'mir441-streaming-resource-governor'
Assert-MIR441Test ($buildText-notmatch'ForEach-Object\s+-Parallel|Start-Job|Start-ThreadJob'-and$buildText-match'foreach\(\$target') 'mir441-serial-materializer'
Assert-MIR441Test ($buildText-match"-SourceVersion '4[.]1[.]0'"-and$materializerText-match'\$info[.]version\s*=\s*\[string\]\$identity[.]distribution_version') 'mir441-candidate-version-materialized-from-intent'
Assert-MIR441Test ($promotionText-match'fast_forward=\$true'-and$promotionText-match'finally\s*\{'-and$promotionText-match'post_promotion_tests=\$false'-and$promotionText-notmatch'--force|reset --hard') 'mir441-exact-promotion-boundary'

$external=Assert-MIR441ExternalRoot -RepoRoot $repo -Path 'E:\MIR-READINESS-TEST' -Name test
Assert-MIR441Test ($external-ceq'E:\MIR-READINESS-TEST') 'mir441-external-root-positive'
try{Assert-MIR441ExternalRoot -RepoRoot $repo -Path (Join-Path $repo 'build/test') -Name invalid|Out-Null;throw '[mir441-external-root-negative-missed]'}catch{Assert-MIR441Test ($_.Exception.Message-match'mir441-external-root-repository') 'mir441-external-root-negative'}
Assert-MIR441Test (Test-MIR441PathContained -Root 'E:\MIR-READINESS-TEST' -Path 'E:\MIR-READINESS-TEST\child') 'mir441-containment-positive'
Assert-MIR441Test (-not(Test-MIR441PathContained -Root 'E:\MIR-READINESS-TEST' -Path 'E:\MIR-READINESS-TEST-OTHER\child')) 'mir441-containment-prefix-rejection'

foreach($script in @(@{name='prepare';text=Get-MIR441PrepareTagScriptText},@{name='playtest';text=Get-MIR441PlaytestScriptText},@{name='finalize';text=Get-MIR441FinalizeScriptText})){$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput([string]$script.text,[ref]$tokens,[ref]$errors);Assert-MIR441Test ($errors.Count-eq0) "mir441-generated-$([string]$script.name)-syntax"}
$tagScript=Get-MIR441PrepareTagScriptText;$finalizer=Get-MIR441FinalizeScriptText
Assert-MIR441Test ($tagScript-match' tag -s '-and$tagScript-match'verify-tag'-and$tagScript-notmatch'push origin') 'mir441-signed-tag-prepared-not-pushed'
Assert-MIR441Test ($finalizer-match'--verify-tag'-and$finalizer-match'--draft'-and$finalizer-match'release download'-and$finalizer-notmatch'Invoke-MIRValidation|New-MIR4TargetPackage|candidate-build|qualification') 'mir441-finalizer-publisher-cannot-build'

& (Join-Path $repo 'tools/commands/mir4/Update-MIR441UpgradeFixtures.ps1') -RepoRoot $repo -Check|Out-Null
& (Join-Path $repo 'tools/commands/mir4/Update-MIR441PackagePresentationAuthority.ps1') -RepoRoot $repo -Check|Out-Null
& (Join-Path $repo 'tools/commands/mir4/Update-MIR441SourceFreezeAuthority.ps1') -RepoRoot $repo -Check|Out-Null
$source=Update-MIR4SourceChangelogV1 -RepoRoot $repo -PlanPath 'releases/governance/MIR4-Source-Changelog-PlanV1.json' -Check
Assert-MIR441Test ([string]$source.status-ceq'current') 'mir441-source-changelog-current'
$cli=& (Join-Path $repo 'tools/mir.ps1') mir4 release-engine readiness-check 2>&1|Out-String
Assert-MIR441Test ($cli-match'MIR-4.1-RELEASE-READINESS-PASSED') 'mir441-public-cli'
Assert-MIR441Test ((Get-MIRPackageSourceFingerprint -RepoRoot $repo)-ceq$packageBefore) 'mir441-test-package-noninterference'

[pscustomobject][ordered]@{status='MIR-4.1-RELEASE-READINESS-STATIC-PROOF-PASSED';module_count=$modules.Count;targets=4;publisher_can_build=$false;package_source_sha256=$packageBefore}
