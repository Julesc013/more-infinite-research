# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot='')
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($RepoRoot)){$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path}
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/release/F210QualificationPolicy.ps1')
$writer=Join-Path $repo 'tools/commands/mir4/Update-MIR4F210CurrentQualificationPolicyV3Authority.ps1'
$defaultCheck=& $writer -Check
if([string]$defaultCheck.status-cne'current'){throw '[mir4-f210-v3-default-reporoot]'}
& $writer -RepoRoot $repo -Check|Out-Null
$v2=Get-MIR4F210CurrentQualificationPolicyV2 -RepoRoot $repo
$v3=Get-MIR4F210CurrentQualificationPolicyV3 -RepoRoot $repo
$receipt=Get-MIR4F210CurrentQualificationPolicySuccessionV2 -RepoRoot $repo
$channel=Get-Content -Raw -LiteralPath (Join-Path $repo 'spec/engines/mir4-factorio-2.1-experimental-channel-v2.json')|ConvertFrom-Json -Depth 100 -DateKind String
$observedAt=[string]$channel.current_review.observed_at
if([string]$v2.support_floor-cne'2.1.18' -or [string]$v3.support_floor-cne'2.1.18' -or [string]$receipt.current_policy.record_sha256-cne[string]$v3.record_sha256 -or [string]$v3.recorded_at-cne$observedAt -or [string]$receipt.recorded_at-cne$observedAt -or [string]$v3.observed_engine_channel_review.observed_at-cne$observedAt){throw '[mir4-f210-v3-policy-binding]'}
$info=Get-Content -Raw -LiteralPath (Join-Path $repo 'source/presentation/f210/info.json.template')|ConvertFrom-Json -Depth 20
$required=@('base >= 2.1.18','? recycler >= 2.1.18','? space-age >= 2.1.18')
if(@($required|Where-Object {$_ -notin @($info.dependencies)}).Count-ne0){throw '[mir4-f210-v3-metadata-floor]'}
$profile=Get-Content -Raw -LiteralPath (Join-Path $repo 'validation/profiles/factorio-2.1.json')|ConvertFrom-Json -Depth 20
if([string]$profile.minimum_factorio_version-cne'2.1.18' -or [string]$profile.qualification_factorio_channel_authority-cne'spec/engines/mir4-factorio-2.1-experimental-channel-v2.json'){throw '[mir4-f210-v3-profile-binding]'}
if([string]$channel.current_review.version-cne'2.1.22' -or [string]$channel.current_review.binary_sha256-cne'D8C745FD4E8C901BF0FC250C4D0FF75B454987857C1AEAADF8E775F0E65A9E4B' -or [string]$observedAt-cne'2026-10-19T12:39:29.3637648+00:00' -or @($channel.current_review.review_tasks|Where-Object status -ne 'complete').Count-ne0){throw '[mir4-f210-v3-channel-binding]'}
if(-not[bool]$v3.qualification.current_engine_intake_observed -or [bool]$v3.qualification.current_engine_api_prototype_data_mod_capsule_admitted -or [bool]$v3.qualification.current_engine_qualification_passed -or [bool]$receipt.exact_engine_qualification.admitted -or [bool]$receipt.exact_engine_qualification.qualified -or @($v3.boundaries.PSObject.Properties|Where-Object {[bool]$_.Value}).Count-ne0){throw '[mir4-f210-v3-native-boundary]'}
$policyPath=Join-Path $repo $script:MIR4F210CurrentPolicyV3RelativePath
$receiptPath=Join-Path $repo $script:MIR4F210CurrentPolicySuccessionV2RelativePath
$policyHash=(Get-FileHash -LiteralPath $policyPath -Algorithm SHA256).Hash
$receiptHash=(Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash
$current=& $writer -RepoRoot $repo
if([string]$current.status-cne'current' -or [string]$current.recorded_at-cne$observedAt -or (Get-FileHash -LiteralPath $policyPath -Algorithm SHA256).Hash-cne$policyHash -or (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash-cne$receiptHash){throw '[mir4-f210-v3-idempotent]'}
$timestampConflict=$false;try{& $writer -RepoRoot $repo -RecordedAt '2026-10-19T12:39:30.3637648+00:00'|Out-Null}catch{$timestampConflict=$_.Exception.Message-match'existing-timestamp-immutable'}
if(-not$timestampConflict){throw '[mir4-f210-v3-timestamp-immutable]'}
Write-Host '[ok] F210 2.1.22 observation successor is host-validated; package support floor and native boundaries remain unchanged.'