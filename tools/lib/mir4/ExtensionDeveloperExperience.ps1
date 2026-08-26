. (Join-Path $PSScriptRoot 'ModuleEcosystem.ps1')

function Get-MIR4ExtensionDeveloperRepoRoot {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return (Resolve-Path -LiteralPath $RepoRoot).Path
}

function Copy-MIR4ExtensionDeveloperValue {
  param([AllowNull()]$Value)
  if ($null -eq $Value) { return $null }
  return (($Value | ConvertTo-Json -Depth 100 -Compress) | ConvertFrom-Json -Depth 100)
}

function New-MIR4ExtensionTemplateV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][ValidatePattern('^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+$')][string]$ExtensionId,
    [ValidateSet('minimal','all-fragments','unavailable')][string]$Template='minimal'
  )
  $repo = Get-MIR4ExtensionDeveloperRepoRoot $RepoRoot
  if ($Template -eq 'all-fragments') {
    $record = New-MIR4ReferenceExtensionV1 -RepoRoot $repo
    $record.extension_id = $ExtensionId
    $record.namespace = $ExtensionId
    $record.extension_version = '0.1.0-preview'
    foreach ($fragment in @($record.fragments)) {
      $fragment.id = $fragment.id.Replace('org.more-infinite-research.reference',$ExtensionId)
    }
    $record.fragments[5].data.extension_id = 'org.more-infinite-research.platform'
    $record.digest = ''
    $record.digest = Get-MIR4ModuleDigest $record
    return $record
  }

  $target = if ($Template -eq 'unavailable') { 'f012' } else { 'f210' }
  $fragments = @(
    [ordered]@{
      id="$ExtensionId.compatibility";kind='CompatibilityFragment'
      data=[ordered]@{subject_refs=@('replace-with-a-stable-subject-id');disposition='request-review'}
    },
    [ordered]@{
      id="$ExtensionId.presentation";kind='PresentationFragment'
      data=[ordered]@{title='First MIR extension';summary='A minimal data-only MIR Extension Protocol V1 preview.'}
    },
    [ordered]@{
      id="$ExtensionId.dependency";kind='ExtensionDependency'
      data=[ordered]@{extension_id='org.more-infinite-research.platform';constraint='0.5.0-preview'}
    },
    [ordered]@{
      id="$ExtensionId.finalization";kind='FinalizationRequirement'
      data=[ordered]@{phase='after-normalization';writes_allowed=$false}
    }
  )
  if ($Template -eq 'unavailable') {
    $fragments += [ordered]@{
      id="$ExtensionId.process";kind='ProcessClassificationFragment'
      data=[ordered]@{certificate_ref=$null;status='unavailable';reason='This example deliberately records unavailable target evidence.'}
    }
  }
  $record = [pscustomobject][ordered]@{
    kind='MIR4ExtensionEnvelopeV1';schema=1;extension_id=$ExtensionId;extension_version='0.1.0-preview'
    namespace=$ExtensionId;targets=@($target);fragments=@($fragments);canonicalization='mir-canonical-json/1';digest=''
  }
  $record.digest = Get-MIR4ModuleDigest $record
  Test-MIR4MepV1Envelope -Envelope $record -RepoRoot $repo | Out-Null
  return $record
}

function Get-MIR4ExtensionDoctorV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[AllowNull()]$Envelope=$null)
  $repo = Get-MIR4ExtensionDeveloperRepoRoot $RepoRoot
  $authority = Get-MIR4ModuleEcosystemAuthority -RepoRoot $repo
  $checks = @()
  $checks += [ordered]@{id='powershell-7';status=$(if($PSVersionTable.PSVersion.Major-ge7){'passed'}else{'failed'});observed=[string]$PSVersionTable.PSVersion}
  $checks += [ordered]@{id='json-schema';status=$(if(Get-Command Test-Json -ErrorAction SilentlyContinue){'passed'}else{'failed'});observed='Test-Json'}
  $checks += [ordered]@{id='mep-schema';status=$(if(Test-Path -LiteralPath (Join-Path $repo 'spec/schemas/preview/mir4-mep-v1.schema.json')-PathType Leaf){'passed'}else{'failed'});observed='spec/schemas/preview/mir4-mep-v1.schema.json'}
  $safe = -not(
    [bool]$authority.semantic_authority -or [bool]$authority.player_package_mutation_authorized -or
    [bool]$authority.prototype_write_authorized -or [bool]$authority.runtime_state_mutation_authorized -or
    [bool]$authority.migration_execution_authorized -or [bool]$authority.safety_kernel_override_authorized -or
    [bool]$authority.public_support_authorized -or [bool]$authority.signing_or_sealing_authorized -or
    [bool]$authority.publication_authorized
  )
  $checks += [ordered]@{id='authority-firewall';status=$(if($safe){'passed'}else{'failed'});observed='all-player-and-release-authority-denied'}
  $expectedCommands = @('ci-init','diff','discover','doctor','explain','init','lock','migrate','package','test','validate')
  $actualCommands = @($authority.builder_commands | ForEach-Object {[string]$_} | Sort-Object)
  $checks += [ordered]@{id='command-surface';status=$(if(($actualCommands-join'|')-ceq($expectedCommands-join'|')){'passed'}else{'failed'});observed=$actualCommands}
  $discoveryFiles = @(
    '.mir/releases/waves/mir4-r0/MIR4-F210-MEP-Discovery-ContractV1.json',
    'spec/schemas/preview/mir4-f210-mod-data-snapshot-v1.schema.json',
    'spec/schemas/preview/mir4-f210-mep-discovery-result-v1.schema.json',
    'tools/lib/mir4/MepDiscovery.ps1'
  )
  $discoveryReady = @($discoveryFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $repo $_) -PathType Leaf) }).Count -eq 0
  $checks += [ordered]@{id='f210-read-only-discovery';status=$(if($discoveryReady){'passed'}else{'failed'});observed='extension-owned-mod-data-read-only'}
  if ($null -ne $Envelope) {
    try {
      Test-MIR4MepV1Envelope -Envelope $Envelope -RepoRoot $repo | Out-Null
      $checks += [ordered]@{id='extension-envelope';status='passed';observed=[string]$Envelope.extension_id}
    } catch {
      $checks += [ordered]@{id='extension-envelope';status='failed';observed=$_.Exception.Message}
    }
  }
  $status = if (@($checks | Where-Object status -ne 'passed').Count) { 'failed' } else { 'passed' }
  $record = [pscustomobject][ordered]@{
    kind='MIR4ExtensionDoctorV1';schema=1;status=$status;maturity='developer-preview';checks=$checks
    commands=$actualCommands;offline_capable=$true;package_visible=$false;player_mutation_authorized=$false
    prototype_write_authorized=$false;release_authority=$false;digest=''
  }
  $record.digest = Get-MIR4ModuleDigest $record
  return $record
}

function New-MIR4ExtensionLockV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)]$Envelope,
    [string]$Target=''
  )
  $repo = Get-MIR4ExtensionDeveloperRepoRoot $RepoRoot
  Test-MIR4MepV1Envelope -Envelope $Envelope -RepoRoot $repo | Out-Null
  if ([string]::IsNullOrWhiteSpace($Target)) { $Target = [string]@($Envelope.targets | Sort-Object)[-1] }
  if ($Target -notmatch '^f[0-9]{3}$') { throw "[mir4-extension-lock-target] $Target" }
  if ($Target -notin @($Envelope.targets)) { throw "[mir4-extension-lock-target-not-declared] $Target" }
  $closure = Resolve-MIR4ExtensionClosureV1 -RepoRoot $repo -Extensions @($Envelope) -Target $Target
  $authority = Get-MIR4ModuleEcosystemAuthority -RepoRoot $repo
  $transport = @($authority.transports | Where-Object target -eq $Target)
  if ($transport.Count -ne 1) { throw "[mir4-extension-lock-transport] $Target" }
  $transportAvailable = [string]$transport[0].transport -cne 'unavailable'
  $admissionReady = [string]$transport[0].admission -in @('preview','build-materializer-local-preview')
  $status = if (-not $transportAvailable) { 'unavailable' } elseif (-not [bool]$closure.complete -or -not $admissionReady) { 'review-required' } else { 'preview-ready' }
  $closureRows=@($closure.extensions)
  $requiredCapabilities=@($closureRows|ForEach-Object{if($_-is[Collections.IDictionary]){@($_['required_capabilities'])}else{@($_.required_capabilities)}}|Sort-Object -Unique)
  $missingCapabilities=@($closureRows|ForEach-Object{if($_-is[Collections.IDictionary]){@($_['missing_capabilities'])}else{@($_.missing_capabilities)}}|Sort-Object -Unique)
  $record = [pscustomobject][ordered]@{
    kind='MIR4ExtensionLockV1';schema=1;maturity='developer-preview';extension=[ordered]@{
      id=[string]$Envelope.extension_id;version=[string]$Envelope.extension_version;digest=[string]$Envelope.digest
    }
    target=$Target;host=$closure.host;closure_digest=[string]$closure.digest
    required_capabilities=$requiredCapabilities
    missing_capabilities=$missingCapabilities
    dependencies=@($Envelope.fragments | Where-Object kind -eq 'ExtensionDependency' | ForEach-Object {[string]$_.data.extension_id} | Sort-Object -Unique)
    conflicts=@($Envelope.fragments | Where-Object kind -eq 'ExtensionConflict' | ForEach-Object {@($_.data.extension_ids)} | Sort-Object -Unique)
    transport=[ordered]@{name=[string]$transport[0].transport;admission=[string]$transport[0].admission;maturity=[string]$transport[0].maturity;available=$transportAvailable}
    status=$status;canonicalization='mir-canonical-json/1';portable=$true;package_visible=$false
    player_mutation_authorized=$false;prototype_write_authorized=$false;release_authority=$false;digest=''
  }
  $record.digest = Get-MIR4ModuleDigest $record
  return $record
}

function Add-MIR4ExtensionDiffLeafV1 {
  param([AllowNull()]$Value,[Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][Collections.IDictionary]$Output)
  if ($null -eq $Value -or $Value -is [string] -or $Value -is [bool] -or $Value -is [ValueType]) {
    $Output[$Path] = $Value
    return
  }
  if ($Value -is [pscustomobject]) {
    foreach ($property in @($Value.PSObject.Properties | Sort-Object Name -CaseSensitive)) {
      Add-MIR4ExtensionDiffLeafV1 -Value $property.Value -Path "$Path.$($property.Name)" -Output $Output
    }
    return
  }
  if ($Value -is [Collections.IDictionary]) {
    foreach ($key in @($Value.Keys | ForEach-Object {[string]$_} | Sort-Object -CaseSensitive)) {
      Add-MIR4ExtensionDiffLeafV1 -Value $Value[$key] -Path "$Path.$key" -Output $Output
    }
    return
  }
  if ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
    $items = @($Value)
    if ($items.Count -eq 0) { $Output[$Path] = @(); return }
    for ($i=0;$i-lt$items.Count;$i++) { Add-MIR4ExtensionDiffLeafV1 -Value $items[$i] -Path "$Path[$i]" -Output $Output }
    return
  }
  $Output[$Path] = $Value
}

function New-MIR4ExtensionDiffV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Base,[Parameter(Mandatory)]$Candidate)
  $repo = Get-MIR4ExtensionDeveloperRepoRoot $RepoRoot
  Test-MIR4MepV1Envelope -Envelope $Base -RepoRoot $repo | Out-Null
  Test-MIR4MepV1Envelope -Envelope $Candidate -RepoRoot $repo | Out-Null
  $left=[ordered]@{};$right=[ordered]@{}
  Add-MIR4ExtensionDiffLeafV1 -Value $Base -Path '$' -Output $left
  Add-MIR4ExtensionDiffLeafV1 -Value $Candidate -Path '$' -Output $right
  $changes = @(
    foreach ($path in @(@($left.Keys)+@($right.Keys) | Sort-Object -Unique -CaseSensitive)) {
      $hasLeft=$left.Contains($path);$hasRight=$right.Contains($path)
      if ($hasLeft -and $hasRight) {
        $a=ConvertTo-MIR4ModuleCanonicalJson $left[$path];$b=ConvertTo-MIR4ModuleCanonicalJson $right[$path]
        if ($a-cne$b) { [ordered]@{path=$path;change='changed';before=$left[$path];after=$right[$path]} }
      } elseif ($hasLeft) { [ordered]@{path=$path;change='removed';before=$left[$path];after=$null} }
      else { [ordered]@{path=$path;change='added';before=$null;after=$right[$path]} }
    }
  )
  $record=[pscustomobject][ordered]@{
    kind='MIR4ExtensionDiffV1';schema=1;base=[ordered]@{id=[string]$Base.extension_id;version=[string]$Base.extension_version;digest=[string]$Base.digest}
    candidate=[ordered]@{id=[string]$Candidate.extension_id;version=[string]$Candidate.extension_version;digest=[string]$Candidate.digest}
    status=$(if($changes.Count){'changed'}else{'identical'});change_count=$changes.Count;changes=$changes
    package_visible=$false;player_mutation_authorized=$false;release_authority=$false;digest=''
  }
  $record.digest=Get-MIR4ModuleDigest $record
  return $record
}

function New-MIR4ExtensionShadowPlanV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Envelope,[string]$Target='')
  $repo=Get-MIR4ExtensionDeveloperRepoRoot $RepoRoot
  if([string]::IsNullOrWhiteSpace($Target)){$Target=[string]@($Envelope.targets|Sort-Object)[-1]}
  $lock=New-MIR4ExtensionLockV1 -RepoRoot $repo -Envelope $Envelope -Target $Target
  $contributions=@(
    foreach($fragment in @($Envelope.fragments|Sort-Object id)){
      $availability=if([string]$fragment.kind-in@('ProcessClassificationFragment','ExternalEffectChannelDeclaration')-and[string]$fragment.data.status-eq'unavailable'){'unavailable'}else{'available'}
      [ordered]@{fragment_id=[string]$fragment.id;fragment_kind=[string]$fragment.kind;operation='data-only-shadow';availability=$availability;authoritative=$false;mutation_authorized=$false}
    }
  )
  $record=[pscustomobject][ordered]@{
    kind='MIR4ExtensionShadowPlanV1';schema=1;maturity='developer-preview';extension_lock_digest=[string]$lock.digest
    target=$Target;contributions=$contributions;result=$(if([string]$lock.status-eq'unavailable'){'unavailable'}else{'shadow-complete'})
    authoritative_output=$false;player_mutation_authorized=$false;prototype_write_authorized=$false;public_support_claim=$false;digest=''
  }
  $record.digest=Get-MIR4ModuleDigest $record
  return $record
}

function New-MIR4ExtensionClosureShadowPlanV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)]$Envelope,
    [Parameter(Mandatory)]$Closure
  )
  $repo=Get-MIR4ExtensionDeveloperRepoRoot $RepoRoot
  Test-MIR4MepV1Envelope -Envelope $Envelope -RepoRoot $repo|Out-Null
  if([string]$Closure.kind-cne'MIR4ExtensionClosureV1'-or-not[bool]$Closure.complete){throw '[mir4-extension-shadow-closure]'}
  $row=@($Closure.extensions|Where-Object extension_id -eq ([string]$Envelope.extension_id))
  if($row.Count-ne1-or[string]$row[0].digest-cne[string]$Envelope.digest){throw '[mir4-extension-shadow-closure-member]'}
  $contributions=@(
    foreach($fragment in @($Envelope.fragments|Sort-Object id)){
      $availability=if([string]$fragment.kind-in@('ProcessClassificationFragment','ExternalEffectChannelDeclaration')-and[string]$fragment.data.status-eq'unavailable'){'unavailable'}else{'available'}
      [ordered]@{fragment_id=[string]$fragment.id;fragment_kind=[string]$fragment.kind;operation='data-only-shadow';availability=$availability;authoritative=$false;mutation_authorized=$false}
    }
  )
  $record=[pscustomobject][ordered]@{
    kind='MIR4ExtensionClosureShadowPlanV1';schema=1;maturity='developer-preview'
    extension=[ordered]@{id=[string]$Envelope.extension_id;version=[string]$Envelope.extension_version;digest=[string]$Envelope.digest}
    target=[string]$Closure.target;extension_closure_digest=[string]$Closure.digest;contributions=$contributions;result='shadow-complete'
    authoritative_output=$false;player_mutation_authorized=$false;prototype_write_authorized=$false;public_support_claim=$false;digest=''
  }
  $record.digest=Get-MIR4ModuleDigest $record
  return $record
}

function Write-MIR4ExtensionCiScaffoldV1 {
  param([Parameter(Mandatory)][string]$OutputRoot,[string]$ExtensionPath='extension.json')
  New-Item -ItemType Directory -Force -Path (Join-Path $OutputRoot '.github/workflows') | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $OutputRoot 'tools') | Out-Null
  $workflow=@'
name: MIR4 extension conformance
on:
  push:
  pull_request:
permissions:
  contents: read
jobs:
  conformance:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262
      - name: Validate vendored MIR4 extension
        shell: pwsh
        run: ./tools/Invoke-MIR4ExtensionCI.ps1
'@
  $runner=@'
param(
  [string]$SdkRoot='vendor/mir4-mep-v1-preview',
  [string]$ExtensionPath='__EXTENSION_PATH__'
)
$ErrorActionPreference='Stop'
$sdk=(Resolve-Path -LiteralPath $SdkRoot).Path
$extension=(Resolve-Path -LiteralPath $ExtensionPath).Path
& (Join-Path $sdk 'tools/commands/mir4/Invoke-MIR4Extension.ps1') -Command doctor -RepoRoot $sdk -ExtensionPath $extension | Out-Null
& (Join-Path $sdk 'tools/commands/mir4/Invoke-MIR4Extension.ps1') -Command validate -RepoRoot $sdk -ExtensionPath $extension | Out-Null
& (Join-Path $sdk 'tools/commands/mir4/Invoke-MIR4Extension.ps1') -Command test -RepoRoot $sdk -ExtensionPath $extension | Out-Null
'@
  $runner=$runner.Replace('__EXTENSION_PATH__',$ExtensionPath.Replace("'","''"))
  $utf8=[Text.UTF8Encoding]::new($false)
  $lf=([char]10).ToString()
  [IO.File]::WriteAllText((Join-Path $OutputRoot '.github/workflows/mir4-extension.yml'),$workflow.Replace([Environment]::NewLine,$lf).TrimEnd()+$lf,$utf8)
  [IO.File]::WriteAllText((Join-Path $OutputRoot 'tools/Invoke-MIR4ExtensionCI.ps1'),$runner.Replace([Environment]::NewLine,$lf).TrimEnd()+$lf,$utf8)
  $record=[pscustomobject][ordered]@{
    kind='MIR4ExtensionCiScaffoldV1';schema=1;status='initialized'
    files=@('.github/workflows/mir4-extension.yml','tools/Invoke-MIR4ExtensionCI.ps1')
    sdk_layout='vendored-offline-preview';network_required_for_validation=$false
    package_visible=$false;player_mutation_authorized=$false;release_authority=$false;digest=''
  }
  $record.digest=Get-MIR4ModuleDigest $record
  return $record
}
