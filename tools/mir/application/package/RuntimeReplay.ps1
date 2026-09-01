function Write-MIR4RuntimeReplayJson {
  param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)][string]$Path)
  $parent = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 100) + "`n"), [Text.UTF8Encoding]::new($false))
}

function Get-MIR4RuntimeReplayTreeUsage {
  param([Parameter(Mandatory)][string]$Path)
  [int64]$bytes = 0
  $files = 0
  if (Test-Path -LiteralPath $Path -PathType Container) {
    foreach ($item in @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue)) { $files++; $bytes += [int64]$item.Length }
  }
  return [pscustomobject][ordered]@{files=$files;bytes=$bytes}
}

function Test-MIR4RuntimeReplayContained {
  param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$Path,[switch]$AllowEqual)
  $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\','/')
  $candidate = [IO.Path]::GetFullPath($Path).TrimEnd('\','/')
  if ($AllowEqual -and $candidate.Equals($rootPath,[StringComparison]::OrdinalIgnoreCase)) { return $true }
  return $candidate.StartsWith(($rootPath + [IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)
}

function Remove-MIR4RuntimeReplayWorkRoot {
  param([Parameter(Mandatory)][string]$WorkRoot)
  $root = [IO.Path]::GetFullPath($WorkRoot)
  if (-not (Test-Path -LiteralPath $root -PathType Container)) { return }
  foreach ($child in @(Get-ChildItem -LiteralPath $root -Force)) {
    if (-not (Test-MIR4RuntimeReplayContained -Root $root -Path $child.FullName)) { throw "Unsafe F2D cleanup target: $($child.FullName)" }
    Remove-Item -LiteralPath $child.FullName -Recurse -Force
  }
  if (@(Get-ChildItem -LiteralPath $root -Force).Count -ne 0) { throw "F2D work root is not empty after contained cleanup." }
  Remove-Item -LiteralPath $root -Force
}

function ConvertTo-MIR4RuntimeReplayRedactedText {
  param([Parameter(Mandatory)][string]$Text,[Parameter(Mandatory)][string[]]$Paths)
  $value = $Text
  foreach ($path in @($Paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object Length -Descending -Unique)) {
    $token = if ($path -match '(?i)factorio\.exe$') { '<factorio-binary>' } elseif ($path -match '(?i)Factorio$') { '<factorio-install>' } elseif (Test-Path -LiteralPath (Join-Path $path '.git')) { '<repository-root>' } else { '<work-root>' }
    foreach ($form in @($path,$path.Replace('\','/'),$path.Replace('\','\\'))) { $value = $value.Replace($form,$token) }
  }
  return $value
}

function Invoke-MIR4RuntimeReplayChild {
  param([Parameter(Mandatory)][string[]]$Arguments,[Parameter(Mandatory)][string]$Label)
  $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
  & $pwsh @Arguments
  if ($LASTEXITCODE -ne 0) { throw "$Label failed with exit code $LASTEXITCODE." }
}

function Invoke-MIR4TargetRuntimeReplay {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][ValidateSet('f210','f200','f110','f100')][string]$Target,
    [Parameter(Mandatory)][string]$FactorioBin,
    [Parameter(Mandatory)][string]$WorkRoot,
    [Parameter(Mandatory)][string]$EvidenceRoot,
    [Parameter(Mandatory)][ValidatePattern('^[A-Z0-9][A-Z0-9.-]*$')][string]$CandidateId,
    [ValidateSet('OnFailure','Always','Never')][string]$Retention='OnFailure'
  )
  $ErrorActionPreference = 'Stop'
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  if (-not [IO.Path]::IsPathRooted($WorkRoot) -or -not [IO.Path]::IsPathRooted($EvidenceRoot)) { throw 'F2D work and evidence roots must be absolute.' }
  $work = [IO.Path]::GetFullPath($WorkRoot).TrimEnd('\','/')
  $evidence = [IO.Path]::GetFullPath($EvidenceRoot).TrimEnd('\','/')
  if ((Test-MIR4RuntimeReplayContained -Root $repo -Path $work -AllowEqual) -or (Test-MIR4RuntimeReplayContained -Root $repo -Path $evidence -AllowEqual)) { throw 'F2D work and evidence roots must be external to the repository.' }
  if ((Test-MIR4RuntimeReplayContained -Root $work -Path $evidence -AllowEqual) -or (Test-MIR4RuntimeReplayContained -Root $evidence -Path $work -AllowEqual)) { throw 'F2D work and evidence roots must be separate.' }
  foreach ($path in @($work,$evidence)) {
    if (Test-Path -LiteralPath $path) { if (@(Get-ChildItem -LiteralPath $path -Force).Count -gt 0) { throw "F2D root is not empty: $path" } }
    else { New-Item -ItemType Directory -Force -Path $path | Out-Null }
  }
  $factorio = (Resolve-Path -LiteralPath $FactorioBin).Path
  $factorioItem = Get-Item -LiteralPath $factorio
  $factorioVersion = [string]$factorioItem.VersionInfo.ProductVersion
  if ($factorioVersion -match '^([0-9]+\.[0-9]+\.[0-9]+)') { $factorioVersion = [string]$Matches[1] }
  $factorioInstall = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $factorio))
  $started = [DateTime]::UtcNow
  $startFree = (Get-PSDrive -Name ([IO.Path]::GetPathRoot($work).Substring(0,1))).Free
  $minimumFree = 54GB
  if ([int64]$startFree -lt $minimumFree) { throw "F2D admission requires at least 54 GiB free on the work volume." }
  $completed = $false
  try {
    . (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
    . (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
    . (Join-Path $repo 'tools/lib/validation/FactorioVersionPolicy.ps1')
    $golden = Get-Content -Raw -LiteralPath (Join-Path $repo 'spec/distribution/mir4-golden-four-target-baseline-v1.json') | ConvertFrom-Json
    $baseline = @($golden.targets | Where-Object target -eq $Target)
    if ($baseline.Count -ne 1) { throw "F2D target baseline is not unique: $Target" }
    $profile = Get-Content -Raw -LiteralPath (Join-Path $repo "validation/profiles/factorio-$([string]$baseline[0].factorio_line).json") | ConvertFrom-Json
    $effectiveProfile = Resolve-MIR4FactorioQualificationProfile -Profile $profile -FactorioBin $factorio -RepoRoot $repo
    if ([string]$effectiveProfile.qualification_factorio_version -ne $factorioVersion) { throw 'Selected Factorio version does not match the effective qualification profile.' }
    if ($Target -eq 'f210') {
      $channelReview = Get-MIR4Factorio21ChannelReview -FactorioBin $factorio -RepoRoot $repo
      if ([string]$channelReview.status -eq 'invalid-engine-channel-input') { throw 'Installed Factorio is outside the governed 2.1 experimental channel.' }
      Write-MIR4RuntimeReplayJson -Value $channelReview -Path (Join-Path $evidence 'engine-channel-review.json')
    }
    $packageRoot = Join-Path $work 'packages'
    $materialization = New-MIR4TargetPackage -RepoRoot $repo -Target $Target -CandidateId $CandidateId -OutputRoot $packageRoot
    if ([string]$materialization.content_sha256 -ne [string]$baseline[0].archive.content_sha256 -or [int]$materialization.entry_count -ne [int]$baseline[0].archive.entry_count) { throw 'F2D materialized target does not match the accepted content identity.' }
    $candidate = [string]$materialization.archive_path
    $predecessor = Join-Path $repo "dist/more-infinite-research_$([string]$baseline[0].predecessor).zip"
    if (-not (Test-Path -LiteralPath $predecessor -PathType Leaf)) { throw "F2D predecessor is missing: $predecessor" }
    $redactionPaths = @($work,$factorio,$factorioInstall,$repo)
    $freshRoot = Join-Path $work 'fresh-load-userdata'
    $freshSummaryRoot = Join-Path $work 'fresh-load-summaries'
    New-Item -ItemType Directory -Force -Path $freshSummaryRoot | Out-Null
    $runtimeRegistry = Get-Content -Raw -LiteralPath (Join-Path $repo 'validation/scenarios/runtime.json') | ConvertFrom-Json -Depth 100
    $profileProperty = $runtimeRegistry.profiles.PSObject.Properties[[string]$baseline[0].factorio_line]
    if ($null -eq $profileProperty) { throw 'F2D runtime.exact-zip profile is missing from the scenario registry.' }
    $freshDeclarations = @($profileProperty.Value | Where-Object { $_.kind -ne 'gate' -and $_.tags -contains 'smoke' } | Sort-Object name)
    if ($freshDeclarations.Count -eq 0) { throw 'F2D runtime.exact-zip selected no smoke scenarios.' }
    $freshRows = [Collections.Generic.List[object]]::new()
    foreach ($declaration in $freshDeclarations) {
      $scenarioName = [string]$declaration.name
      $scenarioSlug = $scenarioName -replace '[^A-Za-z0-9._-]','-'
      $workerRoot = Join-Path $freshRoot $scenarioSlug
      $workerResult = Join-Path $freshSummaryRoot "$scenarioSlug.json"
      Invoke-MIR4RuntimeReplayChild -Label "runtime.exact-zip/$scenarioName" -Arguments @('-NoProfile','-File',(Join-Path $repo 'scripts/Invoke-MIRValidation.ps1'),'-ScenarioWorker','-Scenario',$scenarioName,'-FactorioBin',$factorio,'-UserDataDir',$workerRoot,'-CandidateZip',$candidate,'-MaxParallel','1','-ValidationSummaryPath',$workerResult)
      $workerText = ConvertTo-MIR4RuntimeReplayRedactedText -Text (Get-Content -Raw -LiteralPath $workerResult) -Paths $redactionPaths
      [IO.File]::WriteAllText($workerResult,$workerText,[Text.UTF8Encoding]::new($false))
      $workerFresh = $workerText | ConvertFrom-Json
      if ([string]$workerFresh.status -ne 'passed' -or
          [string]$workerFresh.validation_package_sha256 -ne [string]$materialization.archive_sha256 -or
          [string]$workerFresh.validation_package_content_sha256 -ne [string]$materialization.content_sha256 -or
          @($workerFresh.scenarios).Count -ne 1) {
        throw "F2D exact-package scenario did not produce exact passing evidence: $scenarioName"
      }
      $freshRows.Add([ordered]@{name=$scenarioName;kind=[string]$declaration.kind;group=[string]$declaration.group;surface=[string]$declaration.surface;status='passed';assertions_executed=[int]$workerFresh.assertions_executed;duration_seconds=[double]$workerFresh.duration_seconds;worker_result_sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($workerText)))})
    }
    $freshResult = Join-Path $evidence 'fresh-load-result.json'
    $fresh = [ordered]@{schema=1;kind='MIR4F2DExactZipFreshLoadMatrixV1';status='passed';target=$Target;factorio_version=$factorioVersion;factorio_binary_sha256=(Get-FileHash -LiteralPath $factorio -Algorithm SHA256).Hash;validation_package_sha256=[string]$materialization.archive_sha256;validation_package_content_sha256=[string]$materialization.content_sha256;scenarios=@($freshRows | ForEach-Object name);rows=@($freshRows);factorio_process_concurrency=1}
    Write-MIR4RuntimeReplayJson -Value $fresh -Path $freshResult
    $freshLogs = @(Get-ChildItem -LiteralPath $freshRoot -Recurse -File -Filter 'factorio-current.log' -ErrorAction SilentlyContinue | Sort-Object FullName)
    if ($freshLogs.Count -ne $freshDeclarations.Count) { throw 'F2D fresh-load log cardinality does not match the exact-zip scenario matrix.' }
    $logSections = [Collections.Generic.List[string]]::new()
    foreach ($freshLog in $freshLogs) {
      $logSections.Add((ConvertTo-MIR4RuntimeReplayRedactedText -Text (Get-Content -Raw -LiteralPath $freshLog.FullName) -Paths $redactionPaths))
    }
    [IO.File]::WriteAllText((Join-Path $evidence 'fresh-load-factorio.log'),(($logSections -join "`n") + "`n"),[Text.UTF8Encoding]::new($false))
    $upgradeOutput = Join-Path $evidence 'upgrade-matrix.json'
    Invoke-MIR4RuntimeReplayChild -Label 'upgrade matrix' -Arguments @('-NoProfile','-File',(Join-Path $repo 'validation/tests/runtime/Test-MIRUpgradeMatrix.ps1'),'-RepoRoot',$repo,'-FactorioBin',$factorio,'-FromZip',$predecessor,'-ToZip',$candidate,'-FromVersion',([string]$baseline[0].predecessor),'-ToVersion',([string]$baseline[0].distribution_version),'-FixtureName',([string]$profile.upgrade.fixture),'-OutputPath',$upgradeOutput,'-WorkRoot',(Join-Path $work 'upgrade-rows'),'-Retention',$Retention)
    $upgrade = Get-Content -Raw -LiteralPath $upgradeOutput | ConvertFrom-Json
    if ([string]$upgrade.status -ne 'passed') { throw 'F2D upgrade matrix did not pass.' }
    $head = (& git -C $repo rev-parse HEAD).Trim()
    $tree = (& git -C $repo rev-parse 'HEAD^{tree}').Trim()
    $targetCode = ([string]$Target).Substring(1)
    $proof = [ordered]@{
      schema=1;kind='MIR4F2DTargetRuntimeReplayProofV1';status="M41-F2D-$targetCode-PASSED-NO-CUTOVER";target=$Target;candidate_id=$CandidateId
      source=[ordered]@{commit=$head;tree=$tree;manifest_sha256=[string]$materialization.source_manifest_sha256;overlay_sha256=[string]$materialization.target_overlay_sha256}
      engine=[ordered]@{selection=if($Target-eq'f210'){'latest-installed-official-2.1-experimental'}else{'exact-profile'};version=$factorioVersion;file_version=[string]$factorioItem.VersionInfo.FileVersion;binary_sha256=(Get-FileHash -LiteralPath $factorio -Algorithm SHA256).Hash}
      package=[ordered]@{distribution_version=[string]$materialization.distribution_version;archive_sha256=[string]$materialization.archive_sha256;content_sha256=[string]$materialization.content_sha256;entry_count=[int]$materialization.entry_count;expected_content_sha256=[string]$baseline[0].archive.content_sha256;expected_entry_count=[int]$baseline[0].archive.entry_count}
      predecessor=[ordered]@{version=[string]$baseline[0].predecessor;archive_sha256=(Get-FileHash -LiteralPath $predecessor -Algorithm SHA256).Hash}
      runtime=[ordered]@{fresh_load='passed';scenario_count=@($fresh.scenarios).Count;upgrade='passed';required_archetypes=@($upgrade.required_archetypes);first_reload=$true;second_reload=$true}
      governed_comparisons=@('technologies-and-stable-ids','settings-and-defaults','science-and-prerequisites','effects-costs-owners-and-maxima','locale','migrations','runtime-registrations','state-namespace-and-watermark','current-research','completed-levels','fractional-progress','research-queue','target-omissions','available-performance-telemetry')
      transition_gates=[ordered]@{package_cutover=$false;old_writer_retirement=$false;version_allocation=$false;tagging=$false;signing=$false;sealing=$false;publication=$false}
    }
    $evidenceSchema = Join-Path $repo 'spec/schemas/mir4-f2d-runtime-replay-evidence-v1.schema.json'
    if (-not (($proof | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile $evidenceSchema)) { throw 'F2D target proof violates its evidence schema.' }
    Write-MIR4RuntimeReplayJson -Value $proof -Path (Join-Path $evidence 'target-proof.json')
    $preCustodyRows = @(Get-ChildItem -LiteralPath $evidence -File | Where-Object Name -notin @('custody-precleanup.json','custody-manifest.json','independent-verification.json','resource-receipt.json') | Sort-Object Name | ForEach-Object {[ordered]@{path=$_.Name;bytes=[int64]$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}})
    $preCustody = [ordered]@{schema=1;kind='MIR4F2DExternalCustodyManifestV1';status='verified-before-cleanup';target=$Target;source_commit=$head;files=$preCustodyRows;transition_gates=$proof.transition_gates}
    if (-not (($preCustody | ConvertTo-Json -Depth 20) | Test-Json -SchemaFile $evidenceSchema)) { throw 'F2D pre-cleanup custody violates its evidence schema.' }
    Write-MIR4RuntimeReplayJson -Value $preCustody -Path (Join-Path $evidence 'custody-precleanup.json')
    Invoke-MIR4RuntimeReplayChild -Label 'independent F2D verifier' -Arguments @('-NoProfile','-File',(Join-Path $repo 'tools/mir/application/package/RuntimeReplayVerifier.ps1'),'-RepoRoot',$repo,'-Target',$Target,'-EvidenceRoot',$evidence,'-OutputPath',(Join-Path $evidence 'independent-verification.json'))
    $usage = Get-MIR4RuntimeReplayTreeUsage -Path $work
    $shouldRemove = $Retention -ne 'Always'
    if ($shouldRemove) { Remove-MIR4RuntimeReplayWorkRoot -WorkRoot $work }
    $endFree = (Get-PSDrive -Name ([IO.Path]::GetPathRoot($work).Substring(0,1))).Free
    $resource = [ordered]@{schema=1;kind='MIR4F2DResourceReceiptV1';target=$Target;retention=$Retention;work_root_status=if($shouldRemove){'removed'}else{'retained'};expanded_files=[int]$usage.files;expanded_bytes=[int64]$usage.bytes;free_bytes_before=[int64]$startFree;free_bytes_after=[int64]$endFree;duration_seconds=[Math]::Round(([DateTime]::UtcNow-$started).TotalSeconds,3);factorio_process_concurrency=1;materialization_concurrency=1}
    if (-not (($resource | ConvertTo-Json -Depth 20) | Test-Json -SchemaFile $evidenceSchema)) { throw 'F2D resource receipt violates its evidence schema.' }
    Write-MIR4RuntimeReplayJson -Value $resource -Path (Join-Path $evidence 'resource-receipt.json')
    $custodyRows = @(Get-ChildItem -LiteralPath $evidence -File | Where-Object Name -ne 'custody-manifest.json' | Sort-Object Name | ForEach-Object {[ordered]@{path=$_.Name;bytes=[int64]$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}})
    $custody = [ordered]@{schema=1;kind='MIR4F2DExternalCustodyManifestV1';status='verified';target=$Target;source_commit=$head;files=$custodyRows;transition_gates=$proof.transition_gates}
    if (-not (($custody | ConvertTo-Json -Depth 20) | Test-Json -SchemaFile $evidenceSchema)) { throw 'F2D custody manifest violates its evidence schema.' }
    $custodyPath = Join-Path $evidence 'custody-manifest.json'
    Write-MIR4RuntimeReplayJson -Value $custody -Path $custodyPath
    $persistedCustody = Get-Content -Raw -LiteralPath $custodyPath | ConvertFrom-Json
    if (-not (($persistedCustody | ConvertTo-Json -Depth 20) | Test-Json -SchemaFile $evidenceSchema)) { throw 'Persisted F2D custody manifest violates its evidence schema.' }
    foreach ($row in @($persistedCustody.files)) {
      $custodiedPath = Join-Path $evidence ([string]$row.path)
      if (-not (Test-Path -LiteralPath $custodiedPath -PathType Leaf) -or
          (Get-FileHash -LiteralPath $custodiedPath -Algorithm SHA256).Hash -ne [string]$row.sha256 -or
          (Get-Item -LiteralPath $custodiedPath).Length -ne [int64]$row.bytes) {
        throw "Persisted F2D custody verification failed: $([string]$row.path)"
      }
    }
    $completed = $true
    return [pscustomobject]$proof
  } finally {
    if (-not $completed -and $Retention -eq 'Never' -and (Test-Path -LiteralPath $work -PathType Container)) { Remove-MIR4RuntimeReplayWorkRoot -WorkRoot $work }
  }
}
