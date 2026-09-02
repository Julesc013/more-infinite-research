function ConvertTo-MIR4CommandInventoryJsonV1 {
  param([Parameter(Mandatory)]$Value)
  return $Value | ConvertTo-Json -Depth 100 -Compress
}

function Get-MIR4CommandInventoryDigestV1 {
  param([Parameter(Mandatory)]$Value)
  $json = ConvertTo-MIR4CommandInventoryJsonV1 -Value $Value
  $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
  return 'sha256:' + [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Get-MIR4CommandImplementationClassificationV1 {
  param([Parameter(Mandatory)][string]$RelativePath,[Parameter(Mandatory)][string]$Text)
  if ($RelativePath -ceq 'tools/mir.ps1') { return 'canonical-public' }
  if ($RelativePath -ceq 'scripts/mir.ps1') { return 'compatibility-wrapper' }
  if ($Text -match 'MIR-[A-Z0-9-]+-LEGACY-.*WRAPPER|COMPATIBILITY-(?:COMMAND|TEST|LIBRARY)') { return 'compatibility-wrapper' }
  if ($RelativePath -match '(?i)(?:^|/)(?:New|Import)-MIR3|(?:^|/)Update-MIR4.*Authority\.ps1$') { return 'migration-only' }
  if ($RelativePath -match '(?i)historical|terminal|museum') { return 'historical' }
  return 'canonical-internal'
}

function Get-MIR4CommandInventoryV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $routerRelative = 'tools/mir/cli/Invoke-MIRCommandRouter.ps1'
  $routerPath = Join-Path $repo $routerRelative
  $routerText = Get-Content -Raw -LiteralPath $routerPath
  $commandLines = @($routerText -split ([string][char]10) | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\.\\tools\\mir\.ps1\s+' })
  $commands = @{}
  foreach ($line in $commandLines) {
    $tail = ($line -replace '^\.\\tools\\mir\.ps1\s+','').Trim()
    $tokens = @($tail -split '\s+' | Where-Object { $_ })
    if ($tokens.Count -lt 1) { continue }
    $keyTokens = @($tokens[0])
    if ($tokens.Count -gt 1 -and $tokens[1] -notmatch '^[<\[]') { $keyTokens += $tokens[1] }
    if ($keyTokens[0] -ceq 'mir4' -and $keyTokens.Count -lt 2) { throw '[mir4-command-inventory-mir4-key]' }
    $key = $keyTokens -join ' '
    if (-not $commands.ContainsKey($key)) {
      $commands[$key] = [pscustomobject][ordered]@{
        key = $key
        public_syntax = $line
        public_entrypoint = 'tools/mir.ps1'
        router = $routerRelative
        classification = 'canonical-public-command'
        implementation_count = 1
      }
    }
  }
  $commandRows = @($commands.Values | Sort-Object key)
  if (@($commandRows | Group-Object key | Where-Object Count -gt 1).Count -ne 0) { throw '[mir4-command-inventory-duplicate-key]' }
  if (@($commandRows | Where-Object key -eq 'mir4 release-engine').Count -ne 1) { throw '[mir4-command-inventory-release-engine]' }

  $files = @()
  $roots = @('tools/mir.ps1','tools/mir','tools/commands','tools/lib','scripts')
  foreach ($root in $roots) {
    $path = Join-Path $repo $root
    $items = if (Test-Path -LiteralPath $path -PathType Leaf) { @(Get-Item -LiteralPath $path) } else { @(Get-ChildItem -LiteralPath $path -Recurse -File -Filter '*.ps1') }
    foreach ($item in $items) {
      $relative = [IO.Path]::GetRelativePath($repo,$item.FullName).Replace('\','/')
      $text = Get-Content -Raw -LiteralPath $item.FullName
      $files += [pscustomobject][ordered]@{
        path = $relative
        classification = Get-MIR4CommandImplementationClassificationV1 -RelativePath $relative -Text $text
        sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
        lines = ($text -split ([string][char]10)).Count
        package_visible = $false
      }
    }
  }
  $files = @($files | Sort-Object path -Unique)
  $groups = @{}
  foreach ($classification in @('canonical-public','canonical-internal','compatibility-wrapper','migration-only','historical','obsolete','unknown')) {
    $groups[$classification] = @($files | Where-Object classification -eq $classification).Count
  }
  if ([int]$groups['canonical-public'] -ne 1 -or [int]$groups['unknown'] -ne 0) { throw '[mir4-command-inventory-authority-count]' }
  $record = [ordered]@{
    schema = 1
    kind = 'MIR4CommandInventoryV1'
    state = 'M42-01-CANONICAL'
    public_entrypoint = 'tools/mir.ps1'
    router = $routerRelative
    command_count = $commandRows.Count
    commands = $commandRows
    implementation_files = $files
    summary = [ordered]@{
      canonical_public = [int]$groups['canonical-public']
      canonical_internal = [int]$groups['canonical-internal']
      compatibility_wrapper = [int]$groups['compatibility-wrapper']
      migration_only = [int]$groups['migration-only']
      historical = [int]$groups['historical']
      obsolete = [int]$groups['obsolete']
      unknown = [int]$groups['unknown']
      duplicate_command_keys = 0
    }
    transition_gate = [ordered]@{
      version_allocation=$false;tagging=$false;signing=$false;sealing=$false;publication=$false
    }
    digest = ''
  }
  $digestMaterial = [ordered]@{}
  foreach ($property in $record.GetEnumerator()) {
    if ([string]$property.Key -cne 'digest') { $digestMaterial[$property.Key] = $property.Value }
  }
  $record.digest = Get-MIR4CommandInventoryDigestV1 -Value $digestMaterial
  return [pscustomobject]$record
}

function Update-MIR4CommandInventoryV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Check)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $path = Join-Path $repo 'governance/automation/mir4-command-inventory-v1.json'
  $schema = Join-Path $repo 'contracts/repository/mir4-command-inventory-v1.schema.json'
  $record = Get-MIR4CommandInventoryV1 -RepoRoot $repo
  $json = (($record | ConvertTo-Json -Depth 100) + [string][char]10).
    Replace(([string][char]13 + [char]10),[string][char]10).
    Replace([string][char]13,[string][char]10)
  if ($Check) {
    $actual = if (Test-Path -LiteralPath $path -PathType Leaf) { (Get-Content -Raw -LiteralPath $path).Replace(([string][char]13+[char]10),[string][char]10) } else { '' }
    if ($actual -cne $json) { throw '[mir4-command-inventory-stale]' }
    if (-not ((Get-Content -Raw -LiteralPath $path) | Test-Json -SchemaFile $schema)) { throw '[mir4-command-inventory-schema]' }
  } else {
    [IO.File]::WriteAllText($path,$json,[Text.UTF8Encoding]::new($false))
  }
  return $record
}
