function New-MIR4RuntimeStateInventory {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  $runtimeRoot = Join-Path $repo 'prototypes/mir/runtime'
  $runtimeFiles = @(Get-ChildItem -LiteralPath $runtimeRoot -Recurse -Filter '*.lua' -File | Sort-Object FullName)
  $runtimeFeatures = @(foreach ($file in $runtimeFiles) {
    $text = [IO.File]::ReadAllText($file.FullName)
    $required = @([regex]::Matches($text,'(?s)M\.requires_features\s*=\s*\{(?<body>.*?)\}') | ForEach-Object { [regex]::Matches($_.Groups['body'].Value,'["''](?<id>[a-z0-9_-]+)["'']') | ForEach-Object { $_.Groups['id'].Value } } | Sort-Object -Unique)
    $handlers = @([regex]::Matches($text,'function\s+M\.(?<id>(?:on_[a-z0-9_]+|register))\s*\(') | ForEach-Object { $_.Groups['id'].Value } | Sort-Object -Unique)
    $buckets = @([regex]::Matches($text,'runtime_state\.bucket\(["''](?<id>[a-z0-9_-]+)["'']\)') | ForEach-Object { $_.Groups['id'].Value } | Sort-Object -Unique)
    $events = @([regex]::Matches($text,'defines\.events\.(?<id>[a-z0-9_]+)') | ForEach-Object { $_.Groups['id'].Value } | Sort-Object -Unique)
    [ordered]@{ path=[IO.Path]::GetRelativePath($repo,$file.FullName).Replace('\','/'); sha256=(Get-MIR4PlatformFileSha256 $file.FullName); required_features=$required; handlers=$handlers; state_buckets=$buckets; events=$events }
  })
  $stateSpecs = @($runtimeFeatures | ForEach-Object { $owner=$_.path; foreach($bucket in $_.state_buckets){[ordered]@{id=$bucket;owner=$owner;namespace="storage.mir.$bucket"}} } | Sort-Object id,owner)
  $eventRows = @($runtimeFeatures | ForEach-Object { $owner=$_.path; foreach($event in $_.events){[ordered]@{id=$event;owner=$owner}} } | Sort-Object id,owner)
  $migrations = @(Get-ChildItem -LiteralPath (Join-Path $repo 'migrations') -File | Where-Object { $_.Extension -in @('.json','.lua') } | Sort-Object Name | ForEach-Object {
    $version = if ($_.BaseName -match '^more-infinite-research_(?<version>[0-9]+(?:\.[0-9]+)+)$') { $Matches.version } else { $null }
    [ordered]@{ path=('migrations/' + $_.Name); sha256=(Get-MIR4PlatformFileSha256 $_.FullName); format=$_.Extension.TrimStart('.'); activates_at=$version }
  })
  $record = [pscustomobject][ordered]@{
    kind='MIR4RuntimeStateInventoryV0'; schema=0; maturity='shadow'; authoritative=$false
    runtime_feature_specs=$runtimeFeatures; state_specs=$stateSpecs; migrations=$migrations
    event_registry=[ordered]@{ mode='generated-preview'; source='prototypes/mir/runtime'; owner='existing-runtime-entrypoint'; events=$eventRows }
    predecessor_map=[ordered]@{ f210='3.2.11';f200='2.5.11';f110='1.9.9';f100='1.8.9';authority='.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV5.json' }
    invariants=@('runtime-never-mutates-prototypes','state-owned-under-mir-namespace','migration-predecessor-explicit','preview-does-not-register-events')
    digest=''
  }
  return Add-MIR4PlatformDigest $record
}
