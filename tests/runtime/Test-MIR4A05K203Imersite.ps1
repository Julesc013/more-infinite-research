# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [Parameter(Mandatory)][string]$FactorioBin,
  [Parameter(Mandatory)][string]$CandidateZip,
  [string]$RepoRoot = ''
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path }
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot 'tools/lib/compatibility/FactorioRunner.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/FactorioProcess.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/ImmutableInputStaging.ps1')

function Assert-A05 { param([bool]$Condition,[string]$Code) if (-not $Condition) { throw "[mir4-a05-k2-03] $Code" } }
function Get-A05Sha256 { param([string]$Path) (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant() }
function Get-A05Relative { param([string]$Path)
  $full = [IO.Path]::GetFullPath($Path)
  $prefix = $RepoRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  Assert-A05 ($full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) 'private-path'
  $full.Substring($prefix.Length).Replace('\','/')
}
function Get-A05Artifact { param([string]$Path)
  $item = Get-Item -LiteralPath $Path
  [pscustomobject][ordered]@{ path=Get-A05Relative $item.FullName; bytes=[long]$item.Length; raw_sha256=Get-A05Sha256 $item.FullName }
}
function ConvertFrom-A05Fields { param([string]$Payload)
  $fields = [ordered]@{}
  foreach ($part in @($Payload -split ';')) {
    $separator = $part.IndexOf('=')
    Assert-A05 ($separator -gt 0) "field:$part"
    $fields[$part.Substring(0,$separator)] = $part.Substring($separator + 1)
  }
  [pscustomobject]$fields
}
function ConvertFrom-A05Csv { param([string]$Value)
  if ([string]::IsNullOrEmpty($Value)) { return }
  $Value -split ','
}
function Assert-A05Sequence { param([object[]]$Actual,[string[]]$Expected,[string]$Code)
  Assert-A05 ((@($Actual | ForEach-Object { [string]$_ }) -join '|') -ceq (@($Expected) -join '|')) $Code
}

$engine = (Resolve-Path -LiteralPath $FactorioBin).Path
$candidate = (Resolve-Path -LiteralPath $CandidateZip).Path
Assert-A05 ((Get-A05Sha256 $engine) -ceq '710B0278D3049564B122DAFB3CD3D0338D0BDE1CEC3B7417AE1FC3FB37AB85A8') 'engine-sha256'
Assert-A05 ((Get-Item -LiteralPath $engine).VersionInfo.ProductVersion -ceq '2.1.17') 'engine-version'
Assert-A05 ((Get-A05Sha256 $candidate) -ceq '99C020CBA2800179FF2D76EE35F58B27A97CF2A7D89993CFFE06403DC140090E') 'candidate-sha256'
$expectedCandidate = Join-Path $RepoRoot 'build/packages/development-contracts/849fc8c0a1294b3faf7445de82da1127/f210/DEVELOPMENT-A/more-infinite-research_4.2.21000.zip'
Assert-A05 ($candidate -ceq (Resolve-Path -LiteralPath $expectedCandidate).Path) 'candidate-path'

$lockedSource = Join-Path $RepoRoot 'build/synthesis-20260906/k2-engine-candidate/runs/u-ad28370088e7/mods'
$currentSource = Join-Path $RepoRoot 'build/compat-mod-cache'
$outputRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot 'build/mir4/a05-k2-materials/k2-03-runtime'))
[IO.Directory]::CreateDirectory($outputRoot) | Out-Null
$common = @(
  [pscustomobject]@{name='flib_0.17.2.zip';sha256='0A48C15DC0FC6C13BB3FE8293BA6CB35A07F3B0F37D37ACB50AB30E32E8E019D'},
  [pscustomobject]@{name='k2so-assets_1.0.7.zip';sha256='C3E11214407B08120B2EE717405D3B0398F533647695AB2E6EF6DF9267D62017'},
  [pscustomobject]@{name='Krastorio2_2.1.2.zip';sha256='89989E60784EA3E94345289E063C64ABFCE5F35693DB7B9A69D656A163620F43'},
  [pscustomobject]@{name='Krastorio2Assets_2.1.0.zip';sha256='39EF950EC8B21A40357DD0240EF8389501EE75CCA82717F2773B98554DA46E29'},
  [pscustomobject]@{name='Krastorio2MenuSimulations_2.1.0.zip';sha256='3A485B449B356DC4B3EB4233DE4E803B3A001259FBC251BDC9F9D9120B3C53A7'},
  [pscustomobject]@{name='mir-validation-settings-overrides_0.1.0.zip';sha256='0A6AAA9E8D89DDCC9E421F8AB065124554531588C4E4F91EC5E4D52EC0E10E26'}
)

function Get-A05Observation { param([string]$LogPath,[string]$CaseId,[string]$ExpectedPhaseStatus)
  $log = [IO.File]::ReadAllText($LogPath)
  $ownerMatches = [regex]::Matches($log,'\[MIR4_A05_OWNER\]\s+([^\r\n]+)')
  $scienceMatches = [regex]::Matches($log,'\[MIR4_A05_SCIENCE\]\s+([^\r\n]+)')
  $effectMatches = [regex]::Matches($log,'\[MIR4_A05_EFFECT_OWNER\]\s+([^\r\n]+)')
  $routeMatches = [regex]::Matches($log,'\[MIR4_A05_ROUTE\]\s+([^\r\n]+)')
  Assert-A05 ($ownerMatches.Count -eq 1 -and $scienceMatches.Count -eq 1 -and $effectMatches.Count -eq 2 -and $routeMatches.Count -eq 19) "$CaseId-marker-counts"
  $owner = ConvertFrom-A05Fields $ownerMatches[0].Groups[1].Value
  Assert-A05 ($owner.native -ceq 'kr-imersite-productivity' -and [int]$owner.native_effects -eq 7 -and [double]$owner.native_crystal -eq 0.1) "$CaseId-native-owner"
  Assert-A05 ($owner.mir -ceq 'recipe-prod-research_material_imersite-1' -and [int]$owner.mir_effects -eq 1 -and [double]$owner.mir_powder -eq 0.02 -and [int]$owner.exact_owners -eq 2) "$CaseId-mir-owner"
  $effectOwners = @($effectMatches | ForEach-Object { ConvertFrom-A05Fields $_.Groups[1].Value } | Sort-Object recipe)
  Assert-A05 ((@($effectOwners | ForEach-Object { "$($_.recipe)|$($_.technology)|$($_.change)" }) -join ';') -ceq 'kr-imersite-crystal|kr-imersite-productivity|0.1;kr-imersite-powder|recipe-prod-research_material_imersite-1|0.02') "$CaseId-effect-owners"
  $science = ConvertFrom-A05Fields $scienceMatches[0].Groups[1].Value
  Assert-A05Sequence (ConvertFrom-A05Csv $science.native) @('electromagnetic-science-pack','kr-advanced-tech-card','kr-matter-tech-card','kr-singularity-tech-card','production-science-pack','space-science-pack') "$CaseId-native-science"
  Assert-A05Sequence (ConvertFrom-A05Csv $science.mir) @('automation-science-pack','chemical-science-pack','logistic-science-pack','production-science-pack') "$CaseId-mir-science"
  Assert-A05Sequence (ConvertFrom-A05Csv $science.labs) @('biolab','kr-advanced-lab','kr-singularity-lab','lab') "$CaseId-compatible-labs"

  $auditPattern = 'audit schema=1 kind=coverage_recipe category=(?<category>\S+) key=(?<key>\S+) owners=(?<owners>.*?) productivity_eligible=(?<eligible>\S+) reason=(?<reason>\S+) recipe=(?<recipe>\S+) status=(?<status>\S+) visible=(?<visible>\S+)'
  $auditRows = @([regex]::Matches($log,$auditPattern) | ForEach-Object { [pscustomobject][ordered]@{category=$_.Groups['category'].Value;key=$_.Groups['key'].Value;owners=$_.Groups['owners'].Value;productivity_eligible=[bool]::Parse($_.Groups['eligible'].Value);reason=$_.Groups['reason'].Value;recipe=$_.Groups['recipe'].Value;status=$_.Groups['status'].Value;visible=[bool]::Parse($_.Groups['visible'].Value)} })
  $routes = @($routeMatches | ForEach-Object {
    $fields = ConvertFrom-A05Fields $_.Groups[1].Value
    $audit = @($auditRows | Where-Object recipe -CEQ $fields.name)
    Assert-A05 ($audit.Count -eq 1) "$CaseId-route-audit:$($fields.name)"
    [pscustomobject][ordered]@{name=$fields.name;hidden=[bool]::Parse($fields.hidden);allow_productivity=[bool]::Parse($fields.allow);ingredients=@(ConvertFrom-A05Csv $fields.ingredients);results=@(ConvertFrom-A05Csv $fields.results);disposition=$audit[0]}
  } | Sort-Object name)
  Assert-A05 (@($routes | Where-Object {$_.disposition.category -ceq 'external_exact_owner'}).Count -eq 1) "$CaseId-external-count"
  Assert-A05 (@($routes | Where-Object {$_.disposition.category -ceq 'generated_family_covered'}).Count -eq 1) "$CaseId-generated-count"
  Assert-A05 (@($routes | Where-Object {$_.disposition.category -ceq 'safe_skip'}).Count -eq 17) "$CaseId-safe-skip-count"
  $crystal = @($routes | Where-Object name -CEQ 'kr-imersite-crystal')[0]
  $powder = @($routes | Where-Object name -CEQ 'kr-imersite-powder')[0]
  $return = @($routes | Where-Object name -CEQ 'kr-crush-kr-imersite-crystal')[0]
  Assert-A05 ($crystal.allow_productivity -and $crystal.disposition.owners -ceq 'kr-imersite-productivity' -and $crystal.disposition.reason -ceq 'existing_recipe_productivity_effect') "$CaseId-crystal-disposition"
  Assert-A05 ($powder.allow_productivity -and $powder.disposition.owners -ceq 'recipe-prod-research_material_imersite-1' -and $powder.disposition.reason -ceq 'fixed_stream_coverage') "$CaseId-powder-disposition"
  Assert-A05 ($return.hidden -and -not $return.allow_productivity -and $return.disposition.reason -ceq 'hidden_recipe') "$CaseId-return-disposition"
  Assert-A05 ([regex]::Matches($log,'Material route omitted recipe=kr-imersite-crystal reason=potential-return-path:kr-imersite-powder').Count -eq 1) "$CaseId-return-omission"
  Assert-A05 ([regex]::Matches($log,'Registered technology recipe-prod-research_material_imersite-1').Count -eq 1) "$CaseId-single-registration"
  $streamPattern = 'audit schema=1 kind=stream effects=1 .* key=research_material_imersite lab_status=full .* reason=recipe_productivity science=automation-science-pack,logistic-science-pack,chemical-science-pack,production-science-pack science_phase_policy_id=K2SciencePhasePolicyV1 science_phase_policy_status=(?<phase>\S+)'
  $stream = [regex]::Match($log,$streamPattern)
  Assert-A05 ($stream.Success -and $stream.Groups['phase'].Value -ceq $ExpectedPhaseStatus) "$CaseId-stream-audit"
  Assert-A05 ($log.Contains('audit schema=2 kind=decision confidence=identity=exact,family=exact,tier=exact,owner=exact,science=exact,lab=exact,loop_safety=exact,total=1 decision=generate_stream effects=1 emitted=true family=explicit_stream key=recipe-prod-research_material_imersite-1 labs=biolab,kr-advanced-lab,kr-singularity-lab,lab')) "$CaseId-generation-decision"
  [pscustomobject][ordered]@{owner=$owner;effect_owners=$effectOwners;science=[pscustomobject][ordered]@{native=@(ConvertFrom-A05Csv $science.native);mir=@(ConvertFrom-A05Csv $science.mir);compatible_labs=@(ConvertFrom-A05Csv $science.labs);lab_status='full';science_phase_policy_status=$ExpectedPhaseStatus};routes=$routes;route_counts=[pscustomobject][ordered]@{total=19;external_exact_owner=1;generated_family_covered=1;safe_skip=17};return_path_omission='potential-return-path:kr-imersite-powder'}
}

function Invoke-A05Case { param([string]$CaseId,[string]$K2SOPath,[string]$K2SOHash,[bool]$IncludeXy,[bool]$Reload,[string]$PhaseStatus)
  $inputLease = $null
  try {
    $caseRoot = [IO.Path]::GetFullPath((Join-Path $outputRoot $CaseId))
    $prefix = $outputRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    Assert-A05 ($caseRoot.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) "$CaseId-root"
    if (Test-Path -LiteralPath $caseRoot) { Remove-Item -LiteralPath $caseRoot -Recurse -Force }
    $mods = Join-Path $caseRoot 'mods'
    [IO.Directory]::CreateDirectory($mods) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $caseRoot 'saves')) | Out-Null
    $inputRecords = @()
    foreach ($entry in $common) {
      $source = Join-Path $lockedSource $entry.name
      Assert-A05 ((Get-A05Sha256 $source) -ceq $entry.sha256) "$CaseId-archive:$($entry.name)"
      $inputRecords += [ordered]@{source_path=$source;file_name=$entry.name;expected_sha256=$entry.sha256;role='dependency-mod';identity=[ordered]@{archive=$entry.name;sha256=$entry.sha256};provenance=[ordered]@{kind='locked-k2-archive';archive_root=$lockedSource};immutable=$true}
    }
    Assert-A05 ((Get-A05Sha256 $K2SOPath) -ceq $K2SOHash) "$CaseId-k2so-hash"
    $inputRecords += [ordered]@{source_path=$K2SOPath;file_name=(Split-Path -Leaf $K2SOPath);expected_sha256=$K2SOHash;role='dependency-mod';identity=[ordered]@{archive=(Split-Path -Leaf $K2SOPath);sha256=$K2SOHash};provenance=[ordered]@{kind=if($K2SOPath.StartsWith($lockedSource,[StringComparison]::OrdinalIgnoreCase)){'locked-k2so-archive'}else{'current-k2so-cache'};archive_root=(Split-Path -Parent $K2SOPath)};immutable=$true}
    if ($IncludeXy) {
      $xy = Join-Path $lockedSource 'xy-k2so-enhancements-nulls-fork_0.8.3.zip'
      $xyHash = '930F43B96B04012FEF090C40D8B16A6B3F259D1713C86CF59DFF3E9A5A97E2BE'
      Assert-A05 ((Get-A05Sha256 $xy) -ceq $xyHash) "$CaseId-xy-hash"
      $inputRecords += [ordered]@{source_path=$xy;file_name=(Split-Path -Leaf $xy);expected_sha256=$xyHash;role='dependency-mod';identity=[ordered]@{archive=(Split-Path -Leaf $xy);sha256=$xyHash};provenance=[ordered]@{kind='locked-k2so-enhancement-archive';archive_root=$lockedSource};immutable=$true}
    }
    $candidateHash = '99C020CBA2800179FF2D76EE35F58B27A97CF2A7D89993CFFE06403DC140090E'
    $inputRecords += [ordered]@{source_path=$candidate;file_name=(Split-Path -Leaf $candidate);expected_sha256=$candidateHash;role='candidate';identity=[ordered]@{target='f210';sha256=$candidateHash};provenance=[ordered]@{kind='locked-development-contract-candidate';path=$expectedCandidate};immutable=$true}
    $inputLease = New-MIRImmutableInputLease -RunRoot $caseRoot -StageDirectory $mods -Inputs $inputRecords
    $fixtureArchive = Publish-MIRModDirectoryArchive -Source (Join-Path $RepoRoot 'fixtures/assert-k2-03-imersite') -Name 'mir-fixture-assert-k2-03-imersite' -Version '0.1.0' -ModsDir $mods
    $enabled = @('base','elevated-rails','quality','recycler','space-age','flib','k2so-assets','Krastorio2','Krastorio2-spaced-out','Krastorio2Assets','Krastorio2MenuSimulations','mir-validation-settings-overrides','more-infinite-research')
    if ($IncludeXy) { $enabled += 'xy-k2so-enhancements-nulls-fork' }
    $enabled += 'mir-fixture-assert-k2-03-imersite'
    $modList = [pscustomobject][ordered]@{mods=@($enabled | ForEach-Object {[pscustomobject][ordered]@{name=$_;enabled=$true}})}
    [IO.File]::WriteAllText((Join-Path $mods 'mod-list.json'),(($modList|ConvertTo-Json -Depth 10)+"`n"),[Text.UTF8Encoding]::new($false))
    $settings = Join-Path $lockedSource 'mod-settings.dat'
    Assert-A05 ((Get-A05Sha256 $settings) -ceq '6AF4D7F55D19D9F105BCD540FFCA61267613843BC7AFEB457241BFB3703977A4') "$CaseId-settings-hash"
    Copy-Item -LiteralPath $settings -Destination (Join-Path $mods 'mod-settings.dat')
    $load = Invoke-MIRFactorioLoadCheck -FactorioBin $engine -UserDataDir $caseRoot -ScenarioName $CaseId -ScenarioTimeoutSeconds 300
    Assert-A05 ($load.passed -and -not $load.timed_out -and $load.exit_code -eq 0) "$CaseId-load"
    Assert-A05 ($load.stderr_sha256 -ceq 'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855') "$CaseId-stderr"
    $observation = Get-A05Observation -LogPath $load.factorio_log -CaseId $CaseId -ExpectedPhaseStatus $PhaseStatus
    $reloadResult = $null
    if ($Reload) {
      $reloadResult = Invoke-MIRFactorioReloadContract -FactorioBin $engine -UserDataDir $caseRoot -ScenarioName $CaseId -SavePath $load.save -RequiredReloadCount 2 -MaxReloadDurationSeconds 300 -RequiredLogFragments '[MIR4_A05_K2_03_IMERSITE_PROGRESS] technology=recipe-prod-research_material_imersite-1 progress=0.42'
      Assert-A05 ([bool]$reloadResult.passed) "$CaseId-reloads"
    }
    $inputStaging = Get-MIRImmutableInputLeaseReceipt -Lease $inputLease
    $archives = @($inputStaging.inputs | Where-Object { $_.role -ceq 'dependency-mod' } | ForEach-Object { Get-A05Artifact $_.stage_path })
    $candidateInput = @($inputStaging.inputs | Where-Object { $_.role -ceq 'candidate' })
    Assert-A05 ($candidateInput.Count -eq 1) "$CaseId-candidate-input-count"
    $caseResult = [pscustomobject][ordered]@{case_id=$CaseId;k2so=[pscustomobject][ordered]@{version=if($K2SOPath -match '_([0-9]+\.[0-9]+\.[0-9]+)[.]zip$'){$matches[1]}else{''};archive_sha256=$K2SOHash};xy_enabled=$IncludeXy;fresh_load=[pscustomobject][ordered]@{passed=$true;duration_seconds=$load.duration_seconds;save=Get-A05Artifact $load.save;stdout=Get-A05Artifact $load.stdout;stderr=Get-A05Artifact $load.stderr;factorio_log=Get-A05Artifact $load.factorio_log};reloads=$reloadResult;mod_closure=[pscustomobject][ordered]@{enabled_mods=$enabled;archives=@($archives|Sort-Object path);fixture=Get-A05Artifact $fixtureArchive;candidate=Get-A05Artifact $candidateInput[0].stage_path;mod_list=Get-A05Artifact (Join-Path $mods 'mod-list.json');mod_settings=Get-A05Artifact (Join-Path $mods 'mod-settings.dat');input_staging=$inputStaging};observation=$observation}
    Complete-MIRImmutableInputLease -Lease $inputLease | Out-Null
    $inputLease = $null
    return $caseResult
  } catch {
    $failure = $_
    if ($null -ne $inputLease -and -not $inputLease.closed) { try { Complete-MIRImmutableInputLease -Lease $inputLease -Outcome failed | Out-Null } catch {} }
    throw $failure
  }
}

$locked = Invoke-A05Case -CaseId 'locked-2.0.13' -K2SOPath (Join-Path $lockedSource 'Krastorio2-spaced-out_2.0.13.zip') -K2SOHash 'A2EEB2E5A6119C4117BD3653979D40D305D17539E184BFA6F4ED53EF12A5F242' -IncludeXy $true -Reload $true -PhaseStatus 'already-normalized'
$current = Invoke-A05Case -CaseId 'current-2.0.17' -K2SOPath (Join-Path $currentSource 'Krastorio2-spaced-out_2.0.17.zip') -K2SOHash '0D48E22858FB4D1259413B65FFA7E5A0C5B5C2439A4918D58BDACC9411FA9284' -IncludeXy $false -Reload $false -PhaseStatus 'not-applicable'
Assert-A05 ((ConvertTo-Json $locked.observation.effect_owners -Depth 20 -Compress) -ceq (ConvertTo-Json $current.observation.effect_owners -Depth 20 -Compress)) 'version-owner-parity'
Assert-A05 ((ConvertTo-Json $locked.observation.routes -Depth 20 -Compress) -ceq (ConvertTo-Json $current.observation.routes -Depth 20 -Compress)) 'version-route-parity'
$result = [pscustomobject][ordered]@{schema=1;kind='MIR4A05K203ImersiteRuntimeResultV1';generated_at=(Get-Date).ToUniversalTime().ToString('o');engine=[pscustomobject][ordered]@{version='2.1.17';executable_sha256=Get-A05Sha256 $engine};candidate=[pscustomobject][ordered]@{archive_sha256=Get-A05Sha256 $candidate;path=Get-A05Relative $candidate};test=Get-A05Artifact $PSCommandPath;fixture=@(Get-A05Artifact (Join-Path $RepoRoot 'fixtures/assert-k2-03-imersite/info.json');Get-A05Artifact (Join-Path $RepoRoot 'fixtures/assert-k2-03-imersite/data-final-fixes.lua');Get-A05Artifact (Join-Path $RepoRoot 'fixtures/assert-k2-03-imersite/control.lua'));locked_2_0_13=$locked;current_2_0_17_fresh_load_only=$current;version_parity=[pscustomobject][ordered]@{owner_effects=$true;route_matrix=$true};non_claims=@('Current K2SO 2.0.17 evidence is a fresh-load observation without xy enhancement; no current-version reload or continuity claim.','No infinite continuation, broader K2 support, player mutation, release, signing, or publication claim.')}
$resultPath = Join-Path $outputRoot 'result.json'
[IO.File]::WriteAllText($resultPath,(ConvertTo-Json $result -Depth 100 -Compress),[Text.UTF8Encoding]::new($false))
Write-Host "[MIR4_A05_RUNTIME] $(Get-A05Relative $resultPath)"
