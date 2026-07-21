[CmdletBinding()]
param(
    [switch]$Index
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $repoRoot ".mir\target-lines\index.json"
$distributionManifestPath = Join-Path $repoRoot ".mir\distributions.json"

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Published snapshot index not found: $manifestPath"
}
if (-not (Test-Path -LiteralPath $distributionManifestPath -PathType Leaf)) {
    throw "Distribution inventory not found: $distributionManifestPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$distributionManifest = Get-Content -LiteralPath $distributionManifestPath -Raw | ConvertFrom-Json
if ($manifest.schema -ne 1 -or -not $manifest.versions) {
    throw "Unsupported or empty published snapshot index: $manifestPath"
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

    foreach ($entry in $manifest.versions) {
        $snapshotRelative = [string]$entry.snapshot
        $snapshotPath = Join-Path $repoRoot ($snapshotRelative -replace "/", "\")
        $distRelative = [string]$entry.dist
        $distPath = Join-Path $repoRoot ($distRelative -replace "/", "\")

        if (-not (Test-Path -LiteralPath $snapshotPath -PathType Container)) {
            $failures.Add("$($entry.version): missing snapshot $snapshotRelative")
            continue
        }

        $actualTree = (& git rev-parse "$rootTree`:$snapshotRelative" 2>$null).Trim()
        if ($LASTEXITCODE -ne 0 -or $actualTree -ne [string]$entry.tree) {
            $failures.Add("$($entry.version): snapshot tree $actualTree does not match $($entry.tree)")
        }

        $treeFileRows = @(& git ls-tree -r -l $actualTree)
        if ($LASTEXITCODE -ne 0) {
            $failures.Add("$($entry.version): unable to enumerate canonical snapshot blobs")
            continue
        }
        $treeFileCount = 0
        $byteCount = [long]0
        foreach ($row in $treeFileRows) {
            if ([string]$row -notmatch '^\d+\s+blob\s+[0-9a-f]+\s+(\d+)\t') {
                $failures.Add("$($entry.version): unexpected Git tree row '$row'")
                continue
            }
            $treeFileCount++
            $byteCount += [long]$Matches[1]
        }
        if ($treeFileCount -ne [int]$entry.files) {
            $failures.Add("$($entry.version): file count $treeFileCount does not match $($entry.files)")
        }
        if ([long]$byteCount -ne [long]$entry.bytes) {
            $failures.Add("$($entry.version): byte count $byteCount does not match $($entry.bytes)")
        }

        if (-not (Test-Path -LiteralPath $distPath -PathType Leaf)) {
            $failures.Add("$($entry.version): missing distribution $distRelative")
        }
        else {
            $distHash = (Get-FileHash -LiteralPath $distPath -Algorithm SHA256).Hash
            if ($distHash -ne [string]$entry.dist_sha256) {
                $failures.Add("$($entry.version): distribution SHA-256 $distHash does not match $($entry.dist_sha256)")
            }
        }

        Write-Host "PASS $($entry.version): tree, files, bytes, and distribution"
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

    Write-Host "Published snapshot integrity passed for $($manifest.versions.Count) source snapshots."
    Write-Host "Distribution integrity passed for $($distributionManifest.distributions.Count) root archives."
}
finally {
    Pop-Location
}
