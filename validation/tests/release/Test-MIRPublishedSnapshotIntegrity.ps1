[CmdletBinding()]
param(
    [switch]$Index
)
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MirLegacyScriptRoot
$sourceLockRelative = ".mir/releases/sources/published-source-locks.json"
$sourceLockPath = Join-Path $repoRoot ($sourceLockRelative -replace "/", "\")
$distributionManifestPath = Join-Path $repoRoot ".mir\distributions.json"
. (Join-Path $repoRoot "tools\lib\validation\PackageIdentity.ps1")
. (Join-Path $repoRoot "tools\lib\mir4\PreFreezeRelease.ps1")

if (-not (Test-Path -LiteralPath $sourceLockPath -PathType Leaf)) {
    throw "Published source-lock authority not found: $sourceLockPath"
}
if (-not (Test-Path -LiteralPath $distributionManifestPath -PathType Leaf)) {
    throw "Distribution inventory not found: $distributionManifestPath"
}

$sourceLocks = Get-Content -LiteralPath $sourceLockPath -Raw | ConvertFrom-Json
$distributionManifest = Get-Content -LiteralPath $distributionManifestPath -Raw | ConvertFrom-Json
if ($sourceLocks.schema -ne 1 -or
    [string]$sourceLocks.authority -ne "MIRPublishedSourceLocksV1" -or
    [string]$sourceLocks.status -ne "active-compact-source-locks" -or
    -not $sourceLocks.versions) {
    throw "Unsupported or empty published source-lock authority: $sourceLockPath"
}
if ($distributionManifest.schema -ne 1 -or -not $distributionManifest.distributions) {
    throw "Unsupported or empty distribution inventory: $distributionManifestPath"
}

Push-Location $repoRoot
try {
    $rootTree = if ($Index) {
        (& git write-tree).Trim()
    }
    else {
        (& git rev-parse "HEAD^{tree}").Trim()
    }

    if ($LASTEXITCODE -ne 0 -or -not $rootTree) {
        throw "Unable to resolve the Git tree used for snapshot verification."
    }

    $failures = [System.Collections.Generic.List[string]]::new()

    $selectedSourceLockBlob = @(& git rev-parse "$rootTree`:$sourceLockRelative" 2>$null)
    if ($LASTEXITCODE -ne 0 -or
        $selectedSourceLockBlob.Count -ne 1 -or
        [string]$selectedSourceLockBlob[0] -notmatch '^[0-9a-f]{40}$') {
        $failures.Add("selected Git tree does not contain the compact published source-lock authority")
    }

    $activeSnapshotTree = @(& git rev-parse "$rootTree`:.mir/target-lines" 2>$null)
    if ($LASTEXITCODE -eq 0 -and $activeSnapshotTree.Count -gt 0) {
        $failures.Add("selected Git tree still contains retired materialized target snapshots")
    }

    $retirement = $sourceLocks.retirement
    $snapshotParentCommit = [string]$retirement.snapshot_parent_commit
    $retirementCommit = [string]$retirement.retirement_commit
    if ([string]$retirement.state -ne "materialized-snapshots-retired-from-active-checkout" -or
        [string]$retirement.offline_bundle_custody -ne "pending-terminal-eol-bundle-and-restore-rehearsal" -or
        [bool]$retirement.history_rewritten -or
        [bool]$retirement.active_checkout_contains_materialized_snapshots) {
        $failures.Add("published source-lock retirement state is invalid or overclaims offline custody")
    }
    if ([string]$retirement.verification.method -ne "two-independent-git-tree-resolution-v1") {
        $failures.Add("published source-lock authority does not require two independent tree resolutions")
    }

    $resolvedSnapshotAggregate = @(& git rev-parse "$snapshotParentCommit`:.mir/target-lines" 2>$null)
    if ($LASTEXITCODE -ne 0 -or
        $resolvedSnapshotAggregate.Count -ne 1 -or
        [string]$resolvedSnapshotAggregate[0] -ne [string]$retirement.snapshot_aggregate_tree) {
        $failures.Add("retired aggregate snapshot tree cannot be recovered exactly from Git history")
    }
    $resolvedSnapshotIndex = @(& git rev-parse "$snapshotParentCommit`:.mir/target-lines/index.json" 2>$null)
    if ($LASTEXITCODE -ne 0 -or
        $resolvedSnapshotIndex.Count -ne 1 -or
        [string]$resolvedSnapshotIndex[0] -ne [string]$retirement.snapshot_index_blob) {
        $failures.Add("retired snapshot index blob cannot be recovered exactly from Git history")
    }
    $resolvedRetirementParent = @(& git rev-parse "$retirementCommit^" 2>$null)
    if ($LASTEXITCODE -ne 0 -or
        $resolvedRetirementParent.Count -ne 1 -or
        [string]$resolvedRetirementParent[0] -ne $snapshotParentCommit -or
        [string]$retirement.retirement_commit_parent -ne $snapshotParentCommit) {
        $failures.Add("snapshot retirement commit is not the direct child of the bound snapshot authority")
    }
    $retiredTreeAtRetirement = @(& git rev-parse "$retirementCommit`:.mir/target-lines" 2>$null)
    if ($LASTEXITCODE -eq 0 -and $retiredTreeAtRetirement.Count -gt 0) {
        $failures.Add("snapshot retirement commit still contains .mir/target-lines")
    }

    # A published current-line version remains package-source immutable even
    # when package-excluded release documentation continues on the branch.
    # This closes the gap where a documentation edit to a package-visible root
    # (notably README.md) could silently rebuild an already published version.
    $info = Get-Content -LiteralPath (Join-Path $repoRoot "info.json") -Raw | ConvertFrom-Json
    $releaseRecordPath = Join-Path $repoRoot ".mir\releases\records\$($info.version).json"
    if (Test-Path -LiteralPath $releaseRecordPath -PathType Leaf) {
        $releaseRecord = Get-Content -LiteralPath $releaseRecordPath -Raw | ConvertFrom-Json
        $immutableStates = @("tagged", "published", "publicly-verified")
        if ([string]$releaseRecord.state -in $immutableStates) {
            $actualPackageSourceSha256 = Get-MIRPackageSourceFingerprint -RepoRoot $repoRoot
            $expectedPackageSourceSha256 = [string]$releaseRecord.package.source_sha256
            if ($actualPackageSourceSha256 -ne $expectedPackageSourceSha256) {
                $programmePath = Join-Path $repoRoot ".mir\releases\waves\mir4-r0\MIR4-Pre-Freeze-Execution-ProgrammeV1.json"
                $authorizedPreFreezeTransition = $false
                $authorizedAuthorityKind = $null
                if (Test-Path -LiteralPath $programmePath -PathType Leaf) {
                    $programme = Get-Content -LiteralPath $programmePath -Raw | ConvertFrom-Json -Depth 100
                    $enabledTransitions = @(
                        $programme.transition_gate.PSObject.Properties |
                            Where-Object { [bool]$_.Value }
                    )
                    $authorizedPreFreezeTransition =
                        [string]$programme.kind -ceq "MIR4PreFreezeExecutionProgrammeV1" -and
                        [string]$programme.release_cut.source_version -cne [string]$info.version -and
                        [string]$programme.release_cut.candidate_state -ceq "pre-freeze-unallocated" -and
                        [string]$programme.source_baseline.package_source_sha256 -ceq $actualPackageSourceSha256 -and
                        [string]$programme.status -match "RELEASE-BLOCKED$" -and
                        $enabledTransitions.Count -eq 0
                    if ($authorizedPreFreezeTransition) { $authorizedAuthorityKind = 'source-baseline' }
                }
                if (-not $authorizedPreFreezeTransition) {
                    try {
                        # T14 intentionally evolved only the package-facing README. T15 and
                        # the T17 machine-preparation receipt retain that exact fingerprint,
                        # while Test-MIR4PreFreezeAuthorities replays every schema-checked
                        # append-only successor and rejects authority or transition drift.
                        Test-MIR4PreFreezeAuthorities -RepoRoot $repoRoot | Out-Null
                        $t14 = Read-MIR4PreFreezeJson -RepoRoot $repoRoot `
                            -RelativePath '.mir/releases/waves/mir4-r0/MIR4-T14-Authority-Evolution-ReceiptV1.json' `
                            -Kind 'MIR4T14AuthorityEvolutionReceiptV1'
                        $t15 = Read-MIR4PreFreezeJson -RepoRoot $repoRoot `
                            -RelativePath '.mir/releases/waves/mir4-r0/MIR4-T15-Authority-Evolution-ReceiptV1.json' `
                            -Kind 'MIR4T15AuthorityEvolutionReceiptV1'
                        $t17 = Read-MIR4PreFreezeJson -RepoRoot $repoRoot `
                            -RelativePath '.mir/releases/waves/mir4-r0/MIR4-T17-Machine-Preparation-Authority-Evolution-ReceiptV1.json' `
                            -Kind 'MIR4T17MachinePreparationAuthorityEvolutionReceiptV1'
                        $targetCompilerMigration = Read-MIR4PreFreezeJson -RepoRoot $repoRoot `
                            -RelativePath 'releases/migrations/MIR4-Target-Compiler-Tooling-MigrationV1.json' `
                            -Kind 'MIR4TargetCompilerMigrationReceiptV1'
                        $semanticCompilerPolicyMigration = Read-MIR4PreFreezeJson -RepoRoot $repoRoot `
                            -RelativePath 'releases/migrations/MIR4-Semantic-Compiler-Policy-Tooling-MigrationV1.json' `
                            -Kind 'MIR4SemanticCompilerPolicyMigrationReceiptV1'
                        $programmeTransitions = @($programme.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value })
                        $t14Transitions = @($t14.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value })
                        $t15Transitions = @($t15.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value })
                        $t17Transitions = @($t17.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value })
                        $targetCompilerTransitions = @($targetCompilerMigration.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value })
                        $semanticCompilerPolicyTransitions = @($semanticCompilerPolicyMigration.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value })
                        $authorizedPreFreezeTransition =
                            [string]$programme.kind -ceq 'MIR4PreFreezeExecutionProgrammeV1' -and
                            [string]$programme.release_cut.source_version -cne [string]$info.version -and
                            [string]$programme.release_cut.candidate_state -ceq 'pre-freeze-unallocated' -and
                            [string]$programme.status -ceq 'T15-COMPLETE-T16-T17-HUMAN-BLOCKED-RELEASE-BLOCKED' -and
                            $programmeTransitions.Count -eq 0 -and
                            [string]$t14.player_package_source_sha256 -ceq $actualPackageSourceSha256 -and
                            (@($t14.conformance.package_visible_delta) -join '|') -ceq 'README.md' -and
                            [bool]$t14.conformance.player_executable_sources_unchanged -and
                            [bool]$t14.conformance.one_emitter_preserved -and
                            -not [bool]$t14.conformance.release_transition_authority -and
                            $t14Transitions.Count -eq 0 -and
                            [string]$t15.player_package_source_sha256 -ceq $actualPackageSourceSha256 -and
                            -not [bool]$t15.conformance.release_transition_authority -and
                            $t15Transitions.Count -eq 0 -and
                            [string]$t17.player_package_source_sha256 -ceq $actualPackageSourceSha256 -and
                            @($t17.package_visible_delta).Count -eq 0 -and
                            [string]$t17.execution_state.programme_status -ceq [string]$programme.status -and
                            -not [bool]$t17.human_gate.f210_decision_recorded -and
                            -not [bool]$t17.human_gate.f200_decision_recorded -and
                            -not [bool]$t17.human_gate.acceptance_inferred -and
                            $t17Transitions.Count -eq 0 -and
                            [string]$targetCompilerMigration.package_source_sha256 -ceq $actualPackageSourceSha256 -and
                            @($targetCompilerMigration.package_visible_delta).Count -eq 0 -and
                            @($targetCompilerMigration.release_transition_authority.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -eq 0 -and
                            $targetCompilerTransitions.Count -eq 0 -and
                            [string]$semanticCompilerPolicyMigration.package_source_sha256 -ceq $actualPackageSourceSha256 -and
                            @($semanticCompilerPolicyMigration.package_visible_delta).Count -eq 0 -and
                            @($semanticCompilerPolicyMigration.release_transition_authority.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -eq 0 -and
                            $semanticCompilerPolicyTransitions.Count -eq 0
                        if ($authorizedPreFreezeTransition) { $authorizedAuthorityKind = 'append-only-semantic-compiler-policy-successor' }
                    }
                    catch {
                        $authorizedPreFreezeTransition = $false
                    }
                }
                if ($authorizedPreFreezeTransition) {
                    Write-Host (
                        "PASS $($info.version): published source remains immutable while the explicit " +
                        "$($programme.release_cut.source_version) pre-freeze authority binds development roots " +
                        "$actualPackageSourceSha256 and denies production transitions ($authorizedAuthorityKind)"
                    )
                }
                else {
                    $failures.Add(
                        "$($info.version): current package roots changed after publication without an exact " +
                        "blocked pre-freeze successor authority; expected $expectedPackageSourceSha256, " +
                        "observed $actualPackageSourceSha256"
                    )
                }
            }
            else {
                Write-Host "PASS $($info.version): current package roots match the immutable published source"
            }
        }
    }

    $seenVersions = @{}
    foreach ($entry in $sourceLocks.versions) {
        $version = [string]$entry.version
        $legacySnapshotRelative = [string]$entry.legacy_snapshot
        $distRelative = [string]$entry.dist
        $distPath = Join-Path $repoRoot ($distRelative -replace "/", "\")

        if ([string]::IsNullOrWhiteSpace($version) -or $seenVersions.ContainsKey($version)) {
            $failures.Add("published source-lock versions must be nonempty and unique: '$version'")
            continue
        }
        $seenVersions[$version] = $true

        $resolvedCommit = @(& git rev-parse "$([string]$entry.commit)^{commit}" 2>$null)
        if ($LASTEXITCODE -ne 0 -or
            $resolvedCommit.Count -ne 1 -or
            [string]$resolvedCommit[0] -ne [string]$entry.commit) {
            $failures.Add("${version}: source commit cannot be resolved exactly")
            continue
        }
        $resolvedTag = @(& git rev-parse "refs/tags/$([string]$entry.tag)^{commit}" 2>$null)
        if ($LASTEXITCODE -ne 0 -or
            $resolvedTag.Count -ne 1 -or
            [string]$resolvedTag[0] -ne [string]$entry.commit) {
            $failures.Add("${version}: release tag does not resolve to the bound source commit")
        }
        $sourceTree = @(& git rev-parse "$([string]$entry.commit)^{tree}" 2>$null)
        if ($LASTEXITCODE -ne 0 -or
            $sourceTree.Count -ne 1 -or
            [string]$sourceTree[0] -ne [string]$entry.tree) {
            $failures.Add("${version}: source commit tree does not match the source lock")
            continue
        }
        $snapshotTree = @(& git rev-parse "$snapshotParentCommit`:$legacySnapshotRelative" 2>$null)
        if ($LASTEXITCODE -ne 0 -or
            $snapshotTree.Count -ne 1 -or
            [string]$snapshotTree[0] -ne [string]$entry.tree) {
            $failures.Add("${version}: retired snapshot tree does not match the independently resolved source tree")
            continue
        }

        $treeFileRows = @(& git ls-tree -r -l ([string]$entry.tree))
        if ($LASTEXITCODE -ne 0) {
            $failures.Add("${version}: unable to enumerate canonical source-lock blobs")
            continue
        }
        $treeFileCount = 0
        $byteCount = [long]0
        foreach ($row in $treeFileRows) {
            if ([string]$row -notmatch '^\d+\s+blob\s+[0-9a-f]+\s+(\d+)\t') {
                $failures.Add("${version}: unexpected Git tree row '$row'")
                continue
            }
            $treeFileCount++
            $byteCount += [long]$Matches[1]
        }
        if ($treeFileCount -ne [int]$entry.files) {
            $failures.Add("${version}: file count $treeFileCount does not match $($entry.files)")
        }
        if ([long]$byteCount -ne [long]$entry.bytes) {
            $failures.Add("${version}: byte count $byteCount does not match $($entry.bytes)")
        }

        if (-not (Test-Path -LiteralPath $distPath -PathType Leaf)) {
            $failures.Add("${version}: missing distribution $distRelative")
        }
        else {
            $distHash = (Get-FileHash -LiteralPath $distPath -Algorithm SHA256).Hash
            if ($distHash -ne [string]$entry.dist_sha256) {
                $failures.Add("${version}: distribution SHA-256 $distHash does not match $($entry.dist_sha256)")
            }
        }

        $inventoryRows = @($distributionManifest.distributions | Where-Object { [string]$_.path -eq $distRelative })
        if ($inventoryRows.Count -ne 1 -or
            [string]$inventoryRows[0].version -ne $version -or
            [string]$inventoryRows[0].sha256 -ne [string]$entry.dist_sha256 -or
            [string]$inventoryRows[0].source_ref -ne [string]$entry.tag) {
            $failures.Add("${version}: source lock and distribution inventory disagree")
        }

        Write-Host "PASS ${version}: tag/commit and retired snapshot resolve the same tree, files, bytes, and distribution"
    }

    $expectedDistributionPaths = @($distributionManifest.distributions | ForEach-Object { [string]$_.path })
    $actualDistributionPaths = @(
        Get-ChildItem -LiteralPath (Join-Path $repoRoot "dist") -File -Filter "*.zip" |
            ForEach-Object { "dist/$($_.Name)" } |
            Sort-Object
    )
    if ($actualDistributionPaths.Count -ne [int]$distributionManifest.distribution_count) {
        $failures.Add("root dist count $($actualDistributionPaths.Count) does not match $($distributionManifest.distribution_count)")
    }
    $distributionPathDelta = @(Compare-Object ($expectedDistributionPaths | Sort-Object) $actualDistributionPaths)
    if ($distributionPathDelta.Count -gt 0) {
        $failures.Add("root dist paths do not exactly match .mir/distributions.json")
    }
    $treeDistributionPaths = @(
        & git ls-tree -r --name-only $rootTree -- dist |
            Where-Object { $_ -like "dist/*.zip" } |
            Sort-Object
    )
    $treeDistributionPathDelta = @(Compare-Object ($expectedDistributionPaths | Sort-Object) $treeDistributionPaths)
    if ($treeDistributionPathDelta.Count -gt 0) {
        $failures.Add("selected Git tree dist paths do not exactly match .mir/distributions.json")
    }

    foreach ($distribution in $distributionManifest.distributions) {
        $distributionPath = Join-Path $repoRoot ([string]$distribution.path -replace "/", "\")
        if (-not (Test-Path -LiteralPath $distributionPath -PathType Leaf)) {
            $failures.Add("$($distribution.version): missing inventory distribution $($distribution.path)")
            continue
        }
        $distributionFile = Get-Item -LiteralPath $distributionPath
        if ($distributionFile.Length -ne [long]$distribution.bytes) {
            $failures.Add("$($distribution.version): distribution bytes $($distributionFile.Length) do not match $($distribution.bytes)")
        }
        $distributionHash = (Get-FileHash -LiteralPath $distributionPath -Algorithm SHA256).Hash
        if ($distributionHash -ne [string]$distribution.sha256) {
            $failures.Add("$($distribution.version): inventory SHA-256 $distributionHash does not match $($distribution.sha256)")
        }
    }

    if ($failures.Count -gt 0) {
        foreach ($failure in $failures) {
            Write-Error $failure
        }
        throw "Published snapshot integrity failed with $($failures.Count) error(s)."
    }

    Write-Host "Published source-lock integrity passed for $($sourceLocks.versions.Count) compact source locks."
    Write-Host "Retired snapshot custody remains reconstructable from immutable Git history; offline bundle custody is still pending."
    Write-Host "Distribution integrity passed for $($distributionManifest.distributions.Count) root archives."
}
finally {
    Pop-Location
}
