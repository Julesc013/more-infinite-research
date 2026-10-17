# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$DeliveryScriptPath=(Join-Path $RepoRoot 'tools/mir/application/release/LocalDelivery.ps1')
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. $DeliveryScriptPath
$root=Join-Path $RepoRoot ('build/tests/local-delivery/'+[guid]::NewGuid().ToString('N'))
$source=Join-Path $root 'source';$repo=Join-Path $root 'repo'
New-Item -ItemType Directory -Force -Path $source,$repo | Out-Null
[IO.File]::WriteAllText((Join-Path $source 'package.zip'),'exact accepted package')
[IO.File]::WriteAllText((Join-Path $source 'notes.md'),'matching release notes')
$files=@(
 [pscustomobject]@{source_path='package.zip';destination_path='package.zip';sha256=(Get-FileHash (Join-Path $source 'package.zip')).Hash},
 [pscustomobject]@{source_path='notes.md';destination_path='release/notes.md';sha256=(Get-FileHash (Join-Path $source 'notes.md')).Hash}
)
function Expect-Blocked([scriptblock]$Action,[string]$Code) {
 try { & $Action | Out-Null } catch { if($_.Exception.Message.Contains($Code)) { return }; throw }
 throw "Expected rejection: $Code"
}
Expect-Blocked { Invoke-MIR4LocalDelivery -RepoRoot $repo -SourceRoot $source -Files $files -ReleaseId 'probe' -AfterCopy { throw 'simulated-process-loss' } } 'simulated-process-loss'
if(-not(Test-Path (Join-Path $repo 'build/delivery/probe/intent.json')) -or (Test-Path (Join-Path $repo 'build/delivery/probe/receipt.json'))) { throw 'Intent must precede effects and completion must await all files.' }
$result=Invoke-MIR4LocalDelivery -RepoRoot $repo -SourceRoot $source -Files $files -ReleaseId 'probe'
if($result.status -cne 'delivered-and-verified' -or $result.files.Count -ne 2) { throw 'Resume did not complete exact files.' }
[void](Invoke-MIR4LocalDelivery -RepoRoot $repo -SourceRoot $source -Files $files -ReleaseId 'probe')
$conflict=Join-Path $repo 'dist/release/notes.md'
[IO.File]::WriteAllText($conflict,'user material')
Expect-Blocked { Invoke-MIR4LocalDelivery -RepoRoot $repo -SourceRoot $source -Files $files -ReleaseId 'probe' } 'destination-conflict'
if([IO.File]::ReadAllText($conflict) -cne 'user material') { throw 'Conflict was overwritten.' }
$unownedReplacement=[pscustomobject]@{source_path='notes.md';destination_path='release/notes.md';sha256=(Get-FileHash -LiteralPath (Join-Path $source 'notes.md')).Hash;replace_existing_sha256=(Get-FileHash -LiteralPath $conflict).Hash;preserve_existing_destination_path='release/previous-notes.md'}
Expect-Blocked { Invoke-MIR4LocalDelivery -RepoRoot $repo -SourceRoot $source -Files @($unownedReplacement) -ReleaseId 'unowned-replacement' } 'replacement-contract'
if([IO.File]::ReadAllText($conflict) -cne 'user material') { throw 'Generic replacement contract overwrote user material.' }
$bad=[pscustomobject]@{source_path='package.zip';destination_path='../escape.zip';sha256=$files[0].sha256}
Expect-Blocked { Invoke-MIR4LocalDelivery -RepoRoot $repo -SourceRoot $source -Files @($bad) -ReleaseId 'unsafe' } 'delivery-path'
$bad.destination_path='new.zip';$bad.sha256='0'*64
Expect-Blocked { Invoke-MIR4LocalDelivery -RepoRoot $repo -SourceRoot $source -Files @($bad) -ReleaseId 'unsafe' } 'source-identity'
Expect-Blocked { Invoke-MIR4LocalDelivery -RepoRoot $repo -SourceRoot $source -Files @($files[0],$files[0]) -ReleaseId 'duplicate' } 'duplicate-destination'
Expect-Blocked { Invoke-MIR4LocalDelivery -RepoRoot $repo -SourceRoot $source -Files @($files[0]) -ReleaseId 'probe' } 'intent-conflict'

function Write-MIR4LocalDeliveryFixtureFile {
  param([string]$Root,[string]$RelativePath,[string]$Content)
  $path = Join-Path $Root $RelativePath
  $parent = Split-Path -Parent $path
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
  [IO.File]::WriteAllText($path, $Content, [Text.UTF8Encoding]::new($false))
  return [pscustomobject][ordered]@{path=$RelativePath;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash;bytes=(Get-Item -LiteralPath $path).Length}
}

function Write-MIR4LocalDeliveryFixtureBundle {
  param([string]$SourceRoot,[string]$BundleName,[object[]]$Packages)
  $path = Join-Path $SourceRoot $BundleName
  if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
  Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
  $archive = [IO.Compression.ZipFile]::Open($path, [IO.Compression.ZipArchiveMode]::Create)
  try {
    foreach ($package in $Packages) {
      $entry = $archive.CreateEntry([string]$package.public_name)
      $input = [IO.File]::OpenRead((Join-Path $SourceRoot ([string]$package.path)))
      $output = $entry.Open()
      try { $input.CopyTo($output) } finally { $output.Dispose(); $input.Dispose() }
    }
  } finally { $archive.Dispose() }
}

function New-MIR4NineTargetLocalDeliveryFixture {
  param(
    [string]$Root,
    [string]$Name,
    [string]$SourceVersion = '4.4.2',
    [string]$ExistingRepo = ''
  )
  $base = Join-Path $Root $Name
  $fixtureSource = Join-Path $base 'source'
  $fixtureRepo = if ([string]::IsNullOrWhiteSpace($ExistingRepo)) { Join-Path $base 'repo' } else { $ExistingRepo }
  New-Item -ItemType Directory -Force -Path $fixtureSource,$fixtureRepo | Out-Null
  if ($SourceVersion -notmatch '^(?<major>[0-9]+)\.(?<minor>[0-9]+)\.(?<patch>[0-9]{1,2})$') { throw 'Invalid fixture source version.' }
  $sourcePatch = [int]$Matches.patch
  $targets = @('f210','f200','f110','f100','f017','f016','f015','f014','f013')
  $packages = @()
  foreach ($target in $targets) {
    $code = $target.Substring(1)
    $version = ($Matches.major + '.' + $Matches.minor + '.' + $code + ('{0:D2}' -f $sourcePatch))
    $name = 'more-infinite-research_' + $version + '.zip'
    $asset = Write-MIR4LocalDeliveryFixtureFile -Root $fixtureSource -RelativePath ('assets/' + $target + '/' + $name) -Content ('exact package for ' + $target)
    $packages += [pscustomobject][ordered]@{target=$target;distribution_version=$version;path=$asset.path;public_name=$name;sha256=$asset.sha256;bytes=$asset.bytes;content_sha256=('A' * 64);entry_count=1}
  }
  $checksum = Write-MIR4LocalDeliveryFixtureFile -Root $fixtureSource -RelativePath 'SHA256SUMS.txt' -Content 'checksums'
  $signature = Write-MIR4LocalDeliveryFixtureFile -Root $fixtureSource -RelativePath 'SHA256SUMS.txt.sig' -Content 'signature'
  $collector = Write-MIR4LocalDeliveryFixtureFile -Root $fixtureSource -RelativePath 'MIR42-Offline-Support-Collector.zip' -Content 'collector'
  $documents = @{}
  foreach ($role in @('qualification','provenance','components','release_manifest')) {
    $suffix = if ($role -ceq 'release_manifest') { 'release' } else { $role }
    $asset = Write-MIR4LocalDeliveryFixtureFile -Root $fixtureSource -RelativePath ('mir-' + $sourceVersion + '.' + $suffix + '.json') -Content $role
    $documents[$role] = [pscustomobject][ordered]@{role=$role.Replace('_','-');path=$asset.path;sha256=$asset.sha256;bytes=$asset.bytes;record_sha256=('B' * 64)}
  }
  $notes = Write-MIR4LocalDeliveryFixtureFile -Root $fixtureSource -RelativePath 'release-notes.md' -Content 'release notes'
  $uploads = @()
  foreach ($target in $targets) {
    $asset = Write-MIR4LocalDeliveryFixtureFile -Root $fixtureSource -RelativePath ('upload-text/' + $target + '.md') -Content ('portal copy ' + $target)
    $uploads += [pscustomobject][ordered]@{target=$target;path=$asset.path;sha256=$asset.sha256;bytes=$asset.bytes}
  }
  $bundleName = 'MIR_' + $sourceVersion.Replace('.', '_') + '_DISTRIBUTIONS.zip'
  Write-MIR4LocalDeliveryFixtureBundle -SourceRoot $fixtureSource -BundleName $bundleName -Packages $packages
  $f210 = @($packages | Where-Object target -ceq 'f210')[0]
  $f200 = @($packages | Where-Object target -ceq 'f200')[0]
  $pointer = @(
    ('Published: v' + $sourceVersion),
    ('GitHub: https://github.com/Julesc013/more-infinite-research/releases/tag/v' + $sourceVersion),
    ('Nine correct player ZIPs: dist/' + $sourceVersion + ' and top-level dist'),
    ('Factorio 2.1 upload: ' + $f210.public_name),
    ('Factorio 2.0 upload: ' + $f200.public_name)
  ) -join "`n"
  foreach ($name in @('LATEST-MIR42-PUBLISHED.txt','LATEST-MIR42-FINAL-CANDIDATE.txt',('UPLOAD-' + $sourceVersion + '.txt'))) {
    [IO.File]::WriteAllText((Join-Path $fixtureSource $name), $pointer + "`n", [Text.UTF8Encoding]::new($false))
  }
  $github = @($packages | ForEach-Object { [pscustomobject][ordered]@{name=$_.public_name;role='package';target=$_.target;sha256=$_.sha256;bytes=$_.bytes} })
  $github += [pscustomobject][ordered]@{name=$collector.path;role='support-collector';target='';sha256=$collector.sha256;bytes=$collector.bytes}
  $record = [pscustomobject][ordered]@{
    release=[pscustomobject][ordered]@{source_version=$sourceVersion;tag=('v' + $sourceVersion)}
    record_sha256=('C' * 64)
    package_assets=$packages
    github_assets=$github
    checksum=$checksum
    signature=[pscustomobject][ordered]@{path=$signature.path;sha256=$signature.sha256;bytes=$signature.bytes;signature_verified=$false}
    qualification=$documents.qualification
    provenance=$documents.provenance
    components=$documents.components
    release_manifest=$documents.release_manifest
    release_notes=$notes
    mod_portal_upload_texts=$uploads
  }
  $inventoryPath = Join-Path $base 'frozen-inventory.json'
  [IO.File]::WriteAllText($inventoryPath, '{"fixture":true}' + "`n", [Text.UTF8Encoding]::new($false))
  return [pscustomobject]@{source=$fixtureSource;repo=$fixtureRepo;inventory_path=$inventoryPath;record=$record;packages=$packages;bundle_name=$bundleName}
}

$global:MIR4LocalDeliveryFixtureInventory = $null
function global:Read-MIR42NineTargetReleaseAssetInventory {
  param([string]$Path)
  if ($null -eq $global:MIR4LocalDeliveryFixtureInventory) { throw '[test-mir42-delivery-inventory-not-configured]' }
  return [pscustomobject][ordered]@{path=$Path;sha256=('D' * 64);record=$global:MIR4LocalDeliveryFixtureInventory}
}

$nineTarget = New-MIR4NineTargetLocalDeliveryFixture -Root $root -Name 'nine-target'
$global:MIR4LocalDeliveryFixtureInventory = $nineTarget.record
$nineTargetResult = Invoke-MIR42NineTargetLocalDelivery -RepoRoot $nineTarget.repo -SourceRoot $nineTarget.source -FrozenInventoryPath $nineTarget.inventory_path -ReleaseId 'nine-target'
if ($nineTargetResult.status -cne 'delivered-and-verified' -or $nineTargetResult.files.Count -ne 39 -or $nineTargetResult.direct_root_package_count -ne 9 -or $nineTargetResult.mod_portal_upload_performed) {
  throw 'Nine-target delivery did not preserve the expected local-only projection.'
}
$nineTargetReceipt = [IO.File]::ReadAllText((Join-Path $nineTarget.repo 'build/delivery/nine-target/receipt.json')) | ConvertFrom-Json
if ([string]$nineTargetReceipt.source_version -cne '4.4.2' -or [string]$nineTargetReceipt.release_tag -cne 'v4.4.2' -or
    [int]$nineTargetReceipt.direct_root_package_count -ne 9 -or [string]$nineTargetReceipt.versioned_bundle -cne '4.4.2/MIR_4_4_2_DISTRIBUTIONS.zip' -or
    [string]$nineTargetReceipt.versioned_bundle_sha256 -cne (Get-FileHash -LiteralPath (Join-Path $nineTarget.source $nineTarget.bundle_name) -Algorithm SHA256).Hash -or
    [int64]$nineTargetReceipt.versioned_bundle_bytes -ne (Get-Item -LiteralPath (Join-Path $nineTarget.source $nineTarget.bundle_name) -Force).Length -or
    [string]$nineTargetReceipt.frozen_inventory.record_sha256 -cne ('C' * 64) -or [bool]$nineTargetReceipt.mod_portal_upload_performed) {
  throw 'Nine-target delivery did not persist the enriched accepted-inventory receipt facts.'
}
foreach ($package in $nineTarget.packages) {
  if (-not (Test-Path -LiteralPath (Join-Path $nineTarget.repo ('dist/' + $package.public_name)) -PathType Leaf) -or
      -not (Test-Path -LiteralPath (Join-Path $nineTarget.repo ('dist/4.4.2/' + $package.public_name)) -PathType Leaf)) {
    throw 'Nine-target delivery omitted a direct or versioned package.'
  }
}
if (-not (Test-Path -LiteralPath (Join-Path $nineTarget.repo ('dist/4.4.2/' + $nineTarget.bundle_name)) -PathType Leaf)) { throw 'Nine-target delivery omitted the validated bundle.' }
$nineTargetSourceBundleHash = (Get-FileHash -LiteralPath (Join-Path $nineTarget.source $nineTarget.bundle_name) -Algorithm SHA256).Hash
$nineTargetSourceBundleBytes = (Get-Item -LiteralPath (Join-Path $nineTarget.source $nineTarget.bundle_name) -Force).Length
[void](Invoke-MIR42NineTargetLocalDelivery -RepoRoot $nineTarget.repo -SourceRoot $nineTarget.source -FrozenInventoryPath $nineTarget.inventory_path -ReleaseId 'nine-target')
$global:MIR4LocalDeliveryFixtureInventory.record_sha256 = 'E' * 64
Expect-Blocked { Invoke-MIR42NineTargetLocalDelivery -RepoRoot $nineTarget.repo -SourceRoot $nineTarget.source -FrozenInventoryPath $nineTarget.inventory_path -ReleaseId 'nine-target' } 'intent-conflict'
$global:MIR4LocalDeliveryFixtureInventory.record_sha256 = 'C' * 64
$boundReceipt = [IO.File]::ReadAllText((Join-Path $nineTarget.repo 'build/delivery/nine-target/receipt.json')) | ConvertFrom-Json
if ([string]$boundReceipt.frozen_inventory.record_sha256 -cne ('C' * 64)) { throw 'Changed inventory authority rewrote an existing delivery receipt.' }
if ((Get-FileHash -LiteralPath (Join-Path $nineTarget.source $nineTarget.bundle_name) -Algorithm SHA256).Hash -cne $nineTargetSourceBundleHash) {
  throw 'A valid existing source bundle was rewritten.'
}
$nineTargetIntent = [IO.File]::ReadAllText((Join-Path $nineTarget.repo 'build/delivery/nine-target/intent.json')) | ConvertFrom-Json
$nineTargetBundleIntent = @($nineTargetIntent.files | Where-Object destination_path -ceq ('4.4.2/' + $nineTarget.bundle_name))
$nineTargetBundleReceipt = @($boundReceipt.files | Where-Object destination_path -ceq ('4.4.2/' + $nineTarget.bundle_name))
if ($nineTargetBundleIntent.Count -ne 1 -or $nineTargetBundleReceipt.Count -ne 1 -or
    [string]$nineTargetBundleIntent[0].sha256 -cne $nineTargetSourceBundleHash -or
    [string]$nineTargetBundleReceipt[0].sha256 -cne $nineTargetSourceBundleHash -or
    [string]$nineTargetIntent.receipt_metadata.versioned_bundle_sha256 -cne $nineTargetSourceBundleHash -or
    [int64]$nineTargetIntent.receipt_metadata.versioned_bundle_bytes -ne $nineTargetSourceBundleBytes) {
  throw 'Delivery intent or receipt omitted the exact versioned bundle identity.'
}

# A missing bundle is built only after the authoritative inventory has already
# bound all nine package bytes. Planning alone must not create delivery output.
$generatedA = New-MIR4NineTargetLocalDeliveryFixture -Root $root -Name 'generated-bundle-a'
$global:MIR4LocalDeliveryFixtureInventory = $generatedA.record
$generatedABundlePath = Join-Path $generatedA.source $generatedA.bundle_name
Remove-Item -LiteralPath $generatedABundlePath -Force
$generatedAPlan = Get-MIR42NineTargetLocalDeliveryPlan -RepoRoot $generatedA.repo -SourceRoot $generatedA.source -FrozenInventoryPath $generatedA.inventory_path -ReleaseId 'generated-bundle-a'
if (-not (Test-Path -LiteralPath $generatedABundlePath -PathType Leaf) -or
    (Test-Path -LiteralPath (Join-Path $generatedA.repo 'dist')) -or
    (Test-Path -LiteralPath (Join-Path $generatedA.repo 'build/delivery/generated-bundle-a/receipt.json'))) {
  throw 'Accepted-inventory bundle preparation either failed or performed delivery.'
}
$generatedAHash = (Get-FileHash -LiteralPath $generatedABundlePath -Algorithm SHA256).Hash
$generatedABytes = (Get-Item -LiteralPath $generatedABundlePath -Force).Length
$generatedAPlanBundle = @($generatedAPlan.files | Where-Object destination_path -ceq ('4.4.2/' + $generatedA.bundle_name))
if ($generatedAPlanBundle.Count -ne 1 -or [string]$generatedAPlan.bundle.sha256 -cne $generatedAHash -or
    [int64]$generatedAPlan.bundle.bytes -ne $generatedABytes -or [string]$generatedAPlanBundle[0].sha256 -cne $generatedAHash) {
  throw 'Accepted-inventory plan did not freeze the generated bundle identity.'
}
$generatedAResult = Invoke-MIR42NineTargetLocalDelivery -RepoRoot $generatedA.repo -SourceRoot $generatedA.source -FrozenInventoryPath $generatedA.inventory_path -ReleaseId 'generated-bundle-a'
$generatedAReceipt = [IO.File]::ReadAllText((Join-Path $generatedA.repo 'build/delivery/generated-bundle-a/receipt.json')) | ConvertFrom-Json
$generatedAIntent = [IO.File]::ReadAllText((Join-Path $generatedA.repo 'build/delivery/generated-bundle-a/intent.json')) | ConvertFrom-Json
foreach ($record in @($generatedAIntent,$generatedAReceipt)) {
  $bundleEntry = @($record.files | Where-Object destination_path -ceq ('4.4.2/' + $generatedA.bundle_name))
  if ($bundleEntry.Count -ne 1 -or [string]$bundleEntry[0].sha256 -cne $generatedAHash) {
    throw 'Generated bundle byte identity was not retained through delivery.'
  }
}
if ([string]$generatedAIntent.receipt_metadata.versioned_bundle_sha256 -cne $generatedAHash -or
    [int64]$generatedAIntent.receipt_metadata.versioned_bundle_bytes -ne $generatedABytes -or
    [string]$generatedAReceipt.versioned_bundle_sha256 -cne $generatedAHash -or
    [int64]$generatedAReceipt.versioned_bundle_bytes -ne $generatedABytes) {
  throw 'Generated bundle byte identity was not retained in the delivery intent and receipt metadata.'
}

# Deterministic archive layout: independent identical frozen inputs create the
# same bundle bytes; a later plan preserves the first valid generated bundle.
$generatedB = New-MIR4NineTargetLocalDeliveryFixture -Root $root -Name 'generated-bundle-b'
$global:MIR4LocalDeliveryFixtureInventory = $generatedB.record
$generatedBBundlePath = Join-Path $generatedB.source $generatedB.bundle_name
Remove-Item -LiteralPath $generatedBBundlePath -Force
$generatedBPlan = Get-MIR42NineTargetLocalDeliveryPlan -RepoRoot $generatedB.repo -SourceRoot $generatedB.source -FrozenInventoryPath $generatedB.inventory_path -ReleaseId 'generated-bundle-b'
if ((Get-FileHash -LiteralPath $generatedBBundlePath -Algorithm SHA256).Hash -cne $generatedAHash -or
    (Get-Item -LiteralPath $generatedBBundlePath -Force).Length -ne $generatedABytes) {
  throw 'Identical nine-package inputs did not produce stable bundle bytes.'
}
$generatedBHash = (Get-FileHash -LiteralPath $generatedBBundlePath -Algorithm SHA256).Hash
[void](Get-MIR42NineTargetLocalDeliveryPlan -RepoRoot $generatedB.repo -SourceRoot $generatedB.source -FrozenInventoryPath $generatedB.inventory_path -ReleaseId 'generated-bundle-b')
if ((Get-FileHash -LiteralPath $generatedBBundlePath -Algorithm SHA256).Hash -cne $generatedBHash) {
  throw 'A valid generated source bundle was rewritten.'
}

$wrongDirect = New-MIR4NineTargetLocalDeliveryFixture -Root $root -Name 'wrong-direct'
$global:MIR4LocalDeliveryFixtureInventory = $wrongDirect.record
$wrongDirectPath = Join-Path $wrongDirect.repo ('dist/' + $wrongDirect.packages[0].public_name)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $wrongDirectPath) | Out-Null
[IO.File]::WriteAllText($wrongDirectPath, 'stale package', [Text.UTF8Encoding]::new($false))
Expect-Blocked { Invoke-MIR42NineTargetLocalDelivery -RepoRoot $wrongDirect.repo -SourceRoot $wrongDirect.source -FrozenInventoryPath $wrongDirect.inventory_path -ReleaseId 'wrong-direct' } 'destination-conflict'

$stalePointer = New-MIR4NineTargetLocalDeliveryFixture -Root $root -Name 'stale-pointer'
$global:MIR4LocalDeliveryFixtureInventory = $stalePointer.record
$pointerPath = Join-Path $stalePointer.source 'LATEST-MIR42-PUBLISHED.txt'
$oldPointer = [IO.File]::ReadAllText($pointerPath).Replace('v4.4.2','v4.4.1').Replace('dist/4.4.2','dist/4.4.1').Replace('4.4.21002','4.4.21001').Replace('4.4.20002','4.4.20001')
$staleWithCurrentTokens = $oldPointer + "`nHistorical comparison references v4.4.2, releases/tag/v4.4.2, dist/4.4.2, more-infinite-research_4.4.21002.zip and more-infinite-research_4.4.20002.zip.`n"
[IO.File]::WriteAllText($pointerPath, $staleWithCurrentTokens, [Text.UTF8Encoding]::new($false))
Expect-Blocked { Invoke-MIR42NineTargetLocalDelivery -RepoRoot $stalePointer.repo -SourceRoot $stalePointer.source -FrozenInventoryPath $stalePointer.inventory_path -ReleaseId 'stale-pointer' } 'pointer-stale'

$duplicatePointer = New-MIR4NineTargetLocalDeliveryFixture -Root $root -Name 'duplicate-pointer'
$global:MIR4LocalDeliveryFixtureInventory = $duplicatePointer.record
$pointerPath = Join-Path $duplicatePointer.source 'LATEST-MIR42-PUBLISHED.txt'
[IO.File]::AppendAllText($pointerPath, "Published: v4.4.2`n", [Text.UTF8Encoding]::new($false))
Expect-Blocked { Invoke-MIR42NineTargetLocalDelivery -RepoRoot $duplicatePointer.repo -SourceRoot $duplicatePointer.source -FrozenInventoryPath $duplicatePointer.inventory_path -ReleaseId 'duplicate-pointer' } 'pointer-selector'

$missingVersioned = New-MIR4NineTargetLocalDeliveryFixture -Root $root -Name 'missing-versioned'
$global:MIR4LocalDeliveryFixtureInventory = $missingVersioned.record
Remove-Item -LiteralPath (Join-Path $missingVersioned.source 'release-notes.md') -Force
Expect-Blocked { Invoke-MIR42NineTargetLocalDelivery -RepoRoot $missingVersioned.repo -SourceRoot $missingVersioned.source -FrozenInventoryPath $missingVersioned.inventory_path -ReleaseId 'missing-versioned' } 'source-identity'

$wrongBundle = New-MIR4NineTargetLocalDeliveryFixture -Root $root -Name 'wrong-bundle'
$global:MIR4LocalDeliveryFixtureInventory = $wrongBundle.record
Write-MIR4LocalDeliveryFixtureBundle -SourceRoot $wrongBundle.source -BundleName $wrongBundle.bundle_name -Packages @($wrongBundle.packages[0..7])
$wrongBundlePath = Join-Path $wrongBundle.source $wrongBundle.bundle_name
$wrongBundleHash = (Get-FileHash -LiteralPath $wrongBundlePath -Algorithm SHA256).Hash
Expect-Blocked { Invoke-MIR42NineTargetLocalDelivery -RepoRoot $wrongBundle.repo -SourceRoot $wrongBundle.source -FrozenInventoryPath $wrongBundle.inventory_path -ReleaseId 'wrong-bundle' } 'bundle-member-set'
if ((Get-FileHash -LiteralPath $wrongBundlePath -Algorithm SHA256).Hash -cne $wrongBundleHash) { throw 'Wrong-member source bundle was overwritten.' }

# A stale-version archive can have the required count but not current names.
$wrongVersionBundle = New-MIR4NineTargetLocalDeliveryFixture -Root $root -Name 'wrong-version-bundle'
$wrongVersionSource = New-MIR4NineTargetLocalDeliveryFixture -Root $root -Name 'wrong-version-source' -SourceVersion '4.4.1'
$global:MIR4LocalDeliveryFixtureInventory = $wrongVersionBundle.record
$wrongVersionPath = Join-Path $wrongVersionBundle.source $wrongVersionBundle.bundle_name
Copy-Item -LiteralPath (Join-Path $wrongVersionSource.source $wrongVersionSource.bundle_name) -Destination $wrongVersionPath -Force
$wrongVersionHash = (Get-FileHash -LiteralPath $wrongVersionPath -Algorithm SHA256).Hash
Expect-Blocked { Invoke-MIR42NineTargetLocalDelivery -RepoRoot $wrongVersionBundle.repo -SourceRoot $wrongVersionBundle.source -FrozenInventoryPath $wrongVersionBundle.inventory_path -ReleaseId 'wrong-version-bundle' } 'bundle-package'
if ((Get-FileHash -LiteralPath $wrongVersionPath -Algorithm SHA256).Hash -cne $wrongVersionHash) { throw 'Stale-version source bundle was overwritten.' }

# A correct member name with stale entry bytes is also refused, while a source
# package that no longer matches the inventory fails before bundle creation.
$wrongHashBundle = New-MIR4NineTargetLocalDeliveryFixture -Root $root -Name 'wrong-hash-bundle'
$global:MIR4LocalDeliveryFixtureInventory = $wrongHashBundle.record
$wrongHashPackage = $wrongHashBundle.packages[0]
$wrongHashPackagePath = Join-Path $wrongHashBundle.source $wrongHashPackage.path
$originalWrongHashPackageBytes = [IO.File]::ReadAllBytes($wrongHashPackagePath)
[IO.File]::WriteAllText($wrongHashPackagePath, 'forged package bytes', [Text.UTF8Encoding]::new($false))
Write-MIR4LocalDeliveryFixtureBundle -SourceRoot $wrongHashBundle.source -BundleName $wrongHashBundle.bundle_name -Packages $wrongHashBundle.packages
[IO.File]::WriteAllBytes($wrongHashPackagePath, $originalWrongHashPackageBytes)
$wrongHashBundlePath = Join-Path $wrongHashBundle.source $wrongHashBundle.bundle_name
$wrongHashBundleHash = (Get-FileHash -LiteralPath $wrongHashBundlePath -Algorithm SHA256).Hash
Expect-Blocked { Invoke-MIR42NineTargetLocalDelivery -RepoRoot $wrongHashBundle.repo -SourceRoot $wrongHashBundle.source -FrozenInventoryPath $wrongHashBundle.inventory_path -ReleaseId 'wrong-hash-bundle' } 'bundle-package'
if ((Get-FileHash -LiteralPath $wrongHashBundlePath -Algorithm SHA256).Hash -cne $wrongHashBundleHash) { throw 'Wrong-hash source bundle was overwritten.' }

$wrongPackageInput = New-MIR4NineTargetLocalDeliveryFixture -Root $root -Name 'wrong-package-input'
$global:MIR4LocalDeliveryFixtureInventory = $wrongPackageInput.record
$wrongPackagePath = Join-Path $wrongPackageInput.source $wrongPackageInput.packages[0].path
$wrongPackageBundlePath = Join-Path $wrongPackageInput.source $wrongPackageInput.bundle_name
$wrongPackageBundleHash = (Get-FileHash -LiteralPath $wrongPackageBundlePath -Algorithm SHA256).Hash
[IO.File]::WriteAllText($wrongPackagePath, 'source package no longer matches inventory', [Text.UTF8Encoding]::new($false))
Expect-Blocked { Get-MIR42NineTargetLocalDeliveryPlan -RepoRoot $wrongPackageInput.repo -SourceRoot $wrongPackageInput.source -FrozenInventoryPath $wrongPackageInput.inventory_path -ReleaseId 'wrong-package-input' } 'source-identity'
if ((Get-FileHash -LiteralPath $wrongPackageBundlePath -Algorithm SHA256).Hash -cne $wrongPackageBundleHash) { throw 'Bad package input triggered a bundle rewrite.' }

$firstRelease = New-MIR4NineTargetLocalDeliveryFixture -Root $root -Name 'sequential-first' -SourceVersion '4.4.2'
$global:MIR4LocalDeliveryFixtureInventory = $firstRelease.record
[void](Invoke-MIR42NineTargetLocalDelivery -RepoRoot $firstRelease.repo -SourceRoot $firstRelease.source -FrozenInventoryPath $firstRelease.inventory_path -ReleaseId 'sequential-first')
$oldPointerPath = Join-Path $firstRelease.repo 'dist/LATEST-MIR42-PUBLISHED.txt'
$oldPointerHashes = @{}
foreach ($pointerName in @('LATEST-MIR42-PUBLISHED.txt','LATEST-MIR42-FINAL-CANDIDATE.txt')) {
  $oldPointerHashes[$pointerName] = (Get-FileHash -LiteralPath (Join-Path $firstRelease.repo ('dist/' + $pointerName)) -Algorithm SHA256).Hash
}
$oldVersionedPackagePath = Join-Path $firstRelease.repo ('dist/4.4.2/' + $firstRelease.packages[0].public_name)
$oldVersionedPackageHash = (Get-FileHash -LiteralPath $oldVersionedPackagePath -Algorithm SHA256).Hash
$secondRelease = New-MIR4NineTargetLocalDeliveryFixture -Root $root -Name 'sequential-second' -SourceVersion '4.4.3' -ExistingRepo $firstRelease.repo
$global:MIR4LocalDeliveryFixtureInventory = $secondRelease.record
$secondResult = Invoke-MIR42NineTargetLocalDelivery -RepoRoot $secondRelease.repo -SourceRoot $secondRelease.source -FrozenInventoryPath $secondRelease.inventory_path -ReleaseId 'sequential-second'
if ($secondResult.status -cne 'delivered-and-verified') {
  throw 'Sequential delivery did not atomically select the new recognised release.'
}
foreach ($pointerName in $oldPointerHashes.Keys) {
  if ((Get-MIR42NineTargetLocalDeliveryPointerSelection -Path (Join-Path $secondRelease.repo ('dist/' + $pointerName))).source_version -cne '4.4.3' -or
      (Get-FileHash -LiteralPath (Join-Path $secondRelease.repo ('dist/4.4.3/previous-' + $pointerName)) -Algorithm SHA256).Hash -cne $oldPointerHashes[$pointerName]) {
    throw 'Sequential delivery did not atomically select and preserve each recognised current pointer.'
  }
}
if ((Get-FileHash -LiteralPath $oldVersionedPackagePath -Algorithm SHA256).Hash -cne $oldVersionedPackageHash) {
  throw 'Sequential delivery did not preserve prior versioned bytes and pointer identity.'
}

$replayFirst = New-MIR4NineTargetLocalDeliveryFixture -Root $root -Name 'replay-first' -SourceVersion '4.4.2'
$global:MIR4LocalDeliveryFixtureInventory = $replayFirst.record
[void](Invoke-MIR42NineTargetLocalDelivery -RepoRoot $replayFirst.repo -SourceRoot $replayFirst.source -FrozenInventoryPath $replayFirst.inventory_path -ReleaseId 'replay-first')
$replaySecond = New-MIR4NineTargetLocalDeliveryFixture -Root $root -Name 'replay-second' -SourceVersion '4.4.3' -ExistingRepo $replayFirst.repo
$global:MIR4LocalDeliveryFixtureInventory = $replaySecond.record
Expect-Blocked {
  Invoke-MIR42NineTargetLocalDelivery -RepoRoot $replaySecond.repo -SourceRoot $replaySecond.source -FrozenInventoryPath $replaySecond.inventory_path -ReleaseId 'replay-second' -AfterCopy {
    param($file)
    if ([string]$file.destination_path -ceq 'LATEST-MIR42-FINAL-CANDIDATE.txt') { throw 'simulated-final-pointer-interruption' }
  }
} 'simulated-final-pointer-interruption'
if (Test-Path -LiteralPath (Join-Path $replaySecond.repo 'build/delivery/replay-second/receipt.json')) { throw 'Interrupted recognised-pointer handoff wrote a completion receipt.' }
$replayResult = Invoke-MIR42NineTargetLocalDelivery -RepoRoot $replaySecond.repo -SourceRoot $replaySecond.source -FrozenInventoryPath $replaySecond.inventory_path -ReleaseId 'replay-second'
if ($replayResult.status -cne 'delivered-and-verified' -or
    (Get-MIR42NineTargetLocalDeliveryPointerSelection -Path (Join-Path $replaySecond.repo 'dist/LATEST-MIR42-PUBLISHED.txt')).source_version -cne '4.4.3' -or
    (Get-MIR42NineTargetLocalDeliveryPointerSelection -Path (Join-Path $replaySecond.repo 'dist/LATEST-MIR42-FINAL-CANDIDATE.txt')).source_version -cne '4.4.3') {
  throw 'Recognised-pointer handoff did not resume from its original journal binding.'
}
$replayReceipt = [IO.File]::ReadAllText((Join-Path $replaySecond.repo 'build/delivery/replay-second/receipt.json')) | ConvertFrom-Json
if ([string]$replayReceipt.source_version -cne '4.4.3' -or [string]$replayReceipt.frozen_inventory.record_sha256 -cne ('C' * 64)) {
  throw 'Recognised-pointer handoff did not persist enriched receipt facts after resume.'
}

$unknownPointer = New-MIR4NineTargetLocalDeliveryFixture -Root $root -Name 'unknown-pointer' -SourceVersion '4.4.3'
$global:MIR4LocalDeliveryFixtureInventory = $unknownPointer.record
$unknownPointerPath = Join-Path $unknownPointer.repo 'dist/LATEST-MIR42-PUBLISHED.txt'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $unknownPointerPath) | Out-Null
[IO.File]::WriteAllText($unknownPointerPath, 'maintainer-owned manual pointer', [Text.UTF8Encoding]::new($false))
Expect-Blocked { Invoke-MIR42NineTargetLocalDelivery -RepoRoot $unknownPointer.repo -SourceRoot $unknownPointer.source -FrozenInventoryPath $unknownPointer.inventory_path -ReleaseId 'unknown-pointer' } 'pointer-selector'
if ([IO.File]::ReadAllText($unknownPointerPath) -cne 'maintainer-owned manual pointer') { throw 'Unknown pointer was overwritten.' }

Write-Output 'Local delivery passed generic interruption/identity controls and exact nine-target inventory delivery controls for direct ZIPs, generated/preserved deterministic bundles, versioned assets, strict current pointers, and sequential recognised-pointer handoff.'
