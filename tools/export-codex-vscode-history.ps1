param(
  [string]$ExportRoot = (Join-Path $env:USERPROFILE 'Downloads\codex-vscode-exports')
)

$ErrorActionPreference = 'Stop'

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stage = Join-Path $ExportRoot "codex-vscode-history-export-$timestamp"
$raw = Join-Path $stage 'raw'
$derived = Join-Path $stage 'derived'
$logPath = Join-Path $stage 'STAGING_LOG.txt'

New-Item -ItemType Directory -Path $raw, $derived -Force | Out-Null

$sqliteCmd = (Get-Command sqlite3 -ErrorAction Stop).Source
$sevenZip = 'C:\Program Files\7-Zip\7z.exe'
$excludedSensitive = New-Object System.Collections.Generic.List[object]
$excludedLowValue = New-Object System.Collections.Generic.List[object]
$includedSources = New-Object System.Collections.Generic.List[object]
$notes = New-Object System.Collections.Generic.List[string]

function Add-Log([string]$Message) {
  $line = "$(Get-Date -Format o) $Message"
  Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
}

function Ensure-Dir([string]$Path) {
  if ($Path -and -not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function RelPath([string]$Base, [string]$Path) {
  return [System.IO.Path]::GetRelativePath($Base, $Path)
}

function Add-Included([string]$Source, [string]$Dest, [string]$Kind, [string]$Reason) {
  $script:includedSources.Add([pscustomobject]@{
    source = $Source
    archive_path = (RelPath $stage $Dest)
    kind = $Kind
    reason = $Reason
  }) | Out-Null
}

function Add-ExcludedSensitive([string]$Path, [string]$Reason) {
  $script:excludedSensitive.Add([pscustomobject]@{ path = $Path; reason = $Reason }) | Out-Null
}

function Add-ExcludedLowValue([string]$Path, [string]$Reason) {
  $script:excludedLowValue.Add([pscustomobject]@{ path = $Path; reason = $Reason }) | Out-Null
}

function Copy-FilePreserve([string]$Source, [string]$Dest, [string]$Reason) {
  Ensure-Dir (Split-Path -Parent $Dest)
  Copy-Item -LiteralPath $Source -Destination $Dest -Force
  try {
    (Get-Item -LiteralPath $Dest).LastWriteTime = (Get-Item -LiteralPath $Source).LastWriteTime
  } catch {}
  Add-Included $Source $Dest 'copy' $Reason
}

function Link-Or-Copy-File([string]$Source, [string]$Dest, [string]$Reason) {
  Ensure-Dir (Split-Path -Parent $Dest)
  if (Test-Path -LiteralPath $Dest) {
    Remove-Item -LiteralPath $Dest -Force
  }
  try {
    New-Item -ItemType HardLink -Path $Dest -Target $Source -Force | Out-Null
    Add-Included $Source $Dest 'hardlink' $Reason
  } catch {
    Copy-Item -LiteralPath $Source -Destination $Dest -Force
    try {
      (Get-Item -LiteralPath $Dest).LastWriteTime = (Get-Item -LiteralPath $Source).LastWriteTime
    } catch {}
    Add-Included $Source $Dest 'copy-fallback' $Reason
  }
}

function Link-Tree([string]$SourceRoot, [string]$DestRoot, [string]$Reason) {
  if (-not (Test-Path -LiteralPath $SourceRoot)) {
    return
  }
  $files = Get-ChildItem -LiteralPath $SourceRoot -Force -Recurse -File -ErrorAction SilentlyContinue
  foreach ($file in $files) {
    $rel = RelPath $SourceRoot $file.FullName
    Link-Or-Copy-File $file.FullName (Join-Path $DestRoot $rel) $Reason
  }
}

function Backup-Sqlite([string]$Source, [string]$Dest, [string]$Reason) {
  Ensure-Dir (Split-Path -Parent $Dest)
  $escaped = $Dest.Replace("'", "''")
  $out = & $script:sqliteCmd $Source ".timeout 10000" ".backup '$escaped'" 2>&1
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Dest)) {
    $script:notes.Add("sqlite backup failed for $Source; copied database file directly. sqlite output: $out") | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Dest -Force
    Add-Included $Source $Dest 'sqlite-copy-fallback' $Reason
  } else {
    Add-Included $Source $Dest 'sqlite-backup' $Reason
  }
}

function Write-Utf8([string]$Path, [string]$Content) {
  Ensure-Dir (Split-Path -Parent $Path)
  Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
}

function Export-Sqlite-Diagnostics([string]$DbPath, [string]$NamePrefix) {
  $schemaDir = Join-Path $derived 'sqlite-schema'
  Ensure-Dir $schemaDir
  $schema = & $script:sqliteCmd $DbPath ".schema" 2>&1
  Write-Utf8 (Join-Path $schemaDir "$NamePrefix.schema.sql") (($schema | Out-String).TrimEnd())
  $tables = & $script:sqliteCmd $DbPath "select name from sqlite_schema where type='table' and name not like 'sqlite_%' order by name;" 2>$null
  $rows = foreach ($table in $tables) {
    if ($table) {
      $quoted = '"' + $table.Replace('"', '""') + '"'
      $count = & $script:sqliteCmd $DbPath "select count(*) from $quoted;" 2>$null
      [pscustomobject]@{ database = $NamePrefix; table = $table; rows = $count }
    }
  }
  if ($rows) {
    $rows | Export-Csv -LiteralPath (Join-Path $schemaDir "$NamePrefix.table_counts.csv") -NoTypeInformation -Encoding UTF8
  }
}

Add-Log "Starting Codex/VS Code export staging at $stage"
Add-Log "sqlite=$sqliteCmd"
Add-Log "7zip=$sevenZip"

$codexHome = Join-Path $env:USERPROFILE '.codex'
if (Test-Path -LiteralPath $codexHome) {
  $codexDest = Join-Path $raw 'codex-home'
  Ensure-Dir $codexDest

  $sensitiveNames = @('auth.json', 'cap_sid', 'installation_id')
  foreach ($name in $sensitiveNames) {
    $p = Join-Path $codexHome $name
    if (Test-Path -LiteralPath $p) {
      Add-ExcludedSensitive $p 'credential/session identifier not needed for behavioral analysis'
    }
  }
  $sandboxSecrets = Join-Path $codexHome '.sandbox-secrets'
  if (Test-Path -LiteralPath $sandboxSecrets) {
    Add-ExcludedSensitive $sandboxSecrets 'sandbox secret material'
  }

  foreach ($name in @('.sandbox-bin', '.tmp', 'tmp')) {
    $p = Join-Path $codexHome $name
    if (Test-Path -LiteralPath $p) {
      Add-ExcludedLowValue $p 'runtime/temp payload, not chat/history metadata'
    }
  }

  foreach ($dirName in @('sessions', 'attachments', 'memories', 'plugins', 'skills', '.sandbox', 'sqlite', 'cache', 'vendor_imports')) {
    $src = Join-Path $codexHome $dirName
    if (Test-Path -LiteralPath $src) {
      Link-Tree $src (Join-Path $codexDest $dirName) '.codex analysis/history subtree'
    }
  }

  Get-ChildItem -LiteralPath $codexHome -Force -File -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Name -in $sensitiveNames) {
      return
    }
    if ($_.Name -like '*.sqlite') {
      return
    }
    if ($_.Name -like '*.sqlite-wal' -or $_.Name -like '*.sqlite-shm') {
      Add-ExcludedLowValue $_.FullName 'raw sqlite WAL/SHM skipped; consistent sqlite backup is included'
      return
    }
    Copy-FilePreserve $_.FullName (Join-Path $codexDest $_.Name) '.codex root metadata/config file'
  }

  Get-ChildItem -LiteralPath $codexHome -Force -File -Filter '*.sqlite' -ErrorAction SilentlyContinue | ForEach-Object {
    $dest = Join-Path $codexDest $_.Name
    Backup-Sqlite $_.FullName $dest '.codex sqlite database backup including committed WAL state'
    Export-Sqlite-Diagnostics $dest ("codex_" + $_.BaseName)
  }
}

$codeUser = Join-Path $env:APPDATA 'Code\User'
if (Test-Path -LiteralPath $codeUser) {
  $userDest = Join-Path $raw 'vscode-code-user'
  foreach ($name in @('settings.json', 'keybindings.json')) {
    $src = Join-Path $codeUser $name
    if (Test-Path -LiteralPath $src) {
      Copy-FilePreserve $src (Join-Path $userDest $name) 'VS Code user configuration relevant to extension behavior'
    }
  }
  $snippets = Join-Path $codeUser 'snippets'
  if (Test-Path -LiteralPath $snippets) {
    Link-Tree $snippets (Join-Path $userDest 'snippets') 'VS Code snippets for behavior/context analysis'
  }

  $global = Join-Path $codeUser 'globalStorage'
  if (Test-Path -LiteralPath $global) {
    $globalDest = Join-Path $userDest 'globalStorage'
    $globalDb = Join-Path $global 'state.vscdb'
    if (Test-Path -LiteralPath $globalDb) {
      $destDb = Join-Path $globalDest 'state.vscdb'
      Backup-Sqlite $globalDb $destDb 'VS Code global state database'
      Export-Sqlite-Diagnostics $destDb 'vscode_global_state'
      $matching = & $sqliteCmd -json $destDb "select key, value from ItemTable where lower(key) like '%openai%' or lower(key) like '%chatgpt%' or lower(key) like '%codex%' order by key;" 2>$null
      Write-Utf8 (Join-Path $derived 'vscode-global-openai-codex-keys.json') (($matching | Out-String).TrimEnd())
    }
    foreach ($name in @('storage.json', 'state.vscdb.backup')) {
      $src = Join-Path $global $name
      if (Test-Path -LiteralPath $src) {
        Copy-FilePreserve $src (Join-Path $globalDest $name) 'VS Code global storage companion file'
      }
    }
  }

  $workspaceRoot = Join-Path $codeUser 'workspaceStorage'
  $workspaceIndex = New-Object System.Collections.Generic.List[object]
  if (Test-Path -LiteralPath $workspaceRoot) {
    foreach ($dir in Get-ChildItem -LiteralPath $workspaceRoot -Directory -Force -ErrorAction SilentlyContinue) {
      $db = Join-Path $dir.FullName 'state.vscdb'
      if (-not (Test-Path -LiteralPath $db)) {
        continue
      }
      $keys = & $sqliteCmd $db "select key from ItemTable where lower(key) like '%openai%' or lower(key) like '%chatgpt%' or lower(key) like '%codex%' order by key;" 2>$null
      if (-not $keys) {
        continue
      }
      $destDir = Join-Path (Join-Path $userDest 'workspaceStorage') $dir.Name
      Ensure-Dir $destDir
      $workspaceJson = Join-Path $dir.FullName 'workspace.json'
      $workspaceText = $null
      if (Test-Path -LiteralPath $workspaceJson) {
        Copy-FilePreserve $workspaceJson (Join-Path $destDir 'workspace.json') 'VS Code workspace mapping for Codex/OpenAI state'
        $workspaceText = Get-Content -LiteralPath $workspaceJson -Raw
      }
      $destDb = Join-Path $destDir 'state.vscdb'
      Backup-Sqlite $db $destDb 'VS Code workspace state database with Codex/OpenAI keys'
      Export-Sqlite-Diagnostics $destDb ("vscode_workspace_" + $dir.Name)
      $matching = & $sqliteCmd -json $destDb "select key, value from ItemTable where lower(key) like '%openai%' or lower(key) like '%chatgpt%' or lower(key) like '%codex%' order by key;" 2>$null
      Write-Utf8 (Join-Path $destDir 'openai-codex-keys.json') (($matching | Out-String).TrimEnd())
      $workspaceIndex.Add([pscustomobject]@{
        storage_id = $dir.Name
        source = $dir.FullName
        workspace_json = $workspaceText
        keys = @($keys)
        last_write_time = $dir.LastWriteTime
      }) | Out-Null
    }
  }
  $workspaceIndex | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $derived 'vscode-workspace-codex-index.json') -Encoding UTF8
}

$logRoot = Join-Path $env:APPDATA 'Code\logs'
if (Test-Path -LiteralPath $logRoot) {
  $logFiles = Get-ChildItem -LiteralPath $logRoot -Force -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match 'openai\.chatgpt|chatgpt|codex|openai' }
  foreach ($file in $logFiles) {
    $rel = RelPath $logRoot $file.FullName
    Link-Or-Copy-File $file.FullName (Join-Path (Join-Path $raw 'vscode-logs') $rel) 'VS Code/OpenAI/Codex extension log'
  }
}

$extRoot = Join-Path $env:USERPROFILE '.vscode\extensions'
$extensionIndex = New-Object System.Collections.Generic.List[object]
if (Test-Path -LiteralPath $extRoot) {
  $official = Get-ChildItem -LiteralPath $extRoot -Directory -Filter 'openai.chatgpt-*' -ErrorAction SilentlyContinue
  foreach ($dir in $official) {
    $destDir = Join-Path (Join-Path $raw 'vscode-extensions') $dir.Name
    foreach ($name in @('package.json', 'readme.md', 'README.md', 'LICENSE.md', '.vsixmanifest')) {
      $src = Join-Path $dir.FullName $name
      if (Test-Path -LiteralPath $src) {
        Copy-FilePreserve $src (Join-Path $destDir $name) 'OpenAI Codex VS Code extension manifest/docs'
      }
    }
    foreach ($sub in @('out', 'webview', 'resources', 'syntaxes')) {
      $src = Join-Path $dir.FullName $sub
      if (Test-Path -LiteralPath $src) {
        Link-Tree $src (Join-Path $destDir $sub) 'OpenAI Codex VS Code extension source-like/runtime assets'
      }
    }
    $bin = Join-Path $dir.FullName 'bin'
    if (Test-Path -LiteralPath $bin) {
      foreach ($pkg in Get-ChildItem -LiteralPath $bin -Recurse -File -Filter 'codex-package.json' -ErrorAction SilentlyContinue) {
        $rel = RelPath $dir.FullName $pkg.FullName
        Copy-FilePreserve $pkg.FullName (Join-Path $destDir $rel) 'Codex bundled binary package metadata'
      }
      Add-ExcludedLowValue $bin 'large bundled platform runtime binaries; package metadata copied separately'
    }
    $pkgPath = Join-Path $dir.FullName 'package.json'
    $pkgObj = $null
    if (Test-Path -LiteralPath $pkgPath) {
      $pkgObj = Get-Content -LiteralPath $pkgPath -Raw | ConvertFrom-Json
    }
    $extensionIndex.Add([pscustomobject]@{
      source = $dir.FullName
      included_archive_path = (RelPath $stage $destDir)
      name = $pkgObj.name
      publisher = $pkgObj.publisher
      display_name = $pkgObj.displayName
      version = $pkgObj.version
      excluded_bin = $bin
    }) | Out-Null
  }

  $legacy = Get-ChildItem -LiteralPath $extRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'openaicodex|codex|chatgpt|openai' -and $_.Name -notlike 'openai.chatgpt-*' }
  foreach ($dir in $legacy) {
    $legacyDest = Join-Path (Join-Path $raw 'vscode-extensions') $dir.Name
    Link-Tree $dir.FullName $legacyDest 'legacy Codex/OpenAI-named VS Code extension files'
    $extensionIndex.Add([pscustomobject]@{
      source = $dir.FullName
      included_archive_path = (RelPath $stage $legacyDest)
      name = $dir.Name
      publisher = $null
      display_name = $null
      version = $null
      excluded_bin = $null
    }) | Out-Null
  }
}
$extensionIndex | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $derived 'vscode-extension-index.json') -Encoding UTF8

$sourceInventory = New-Object System.Collections.Generic.List[object]
foreach ($src in @($codexHome, $codeUser, (Join-Path $env:APPDATA 'Code\logs'), $extRoot)) {
  if ($src -and (Test-Path -LiteralPath $src)) {
    $m = Get-ChildItem -LiteralPath $src -Force -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
    $sourceInventory.Add([pscustomobject]@{
      source_root = $src
      file_count = $m.Count
      bytes = $m.Sum
      mib = [math]::Round($m.Sum / 1MB, 2)
    }) | Out-Null
  }
}
$sourceInventory | Export-Csv -LiteralPath (Join-Path $derived 'source-root-size-inventory.csv') -NoTypeInformation -Encoding UTF8
$includedSources | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $derived 'included-sources.json') -Encoding UTF8
$excludedSensitive | Export-Csv -LiteralPath (Join-Path $stage 'EXCLUDED_SENSITIVE_PATHS.csv') -NoTypeInformation -Encoding UTF8
$excludedLowValue | Export-Csv -LiteralPath (Join-Path $stage 'EXCLUDED_LOW_VALUE_OR_RUNTIME_PATHS.csv') -NoTypeInformation -Encoding UTF8

$privacyNote = @'
# Privacy and Security Note

This export is intended for behavioral and workflow analysis. It contains chat/session transcripts, logs, local memories, tool/plugin metadata, attachments, and VS Code extension state. Those files can still contain private source snippets, personal data, paths, prompts, secrets that were pasted into chats, and other sensitive context.

Obvious credential containers were not copied into the archive. See `EXCLUDED_SENSITIVE_PATHS.csv` for the exact withheld paths.

Runtime binaries, temp folders, and raw SQLite WAL/SHM companions were also skipped where a consistent database backup or package metadata was included instead. See `EXCLUDED_LOW_VALUE_OR_RUNTIME_PATHS.csv`.
'@
Write-Utf8 (Join-Path $stage 'PRIVACY_SECURITY_NOTE.md') $privacyNote

$manifest = [pscustomobject]@{
  export_name = (Split-Path -Leaf $stage)
  created_at = (Get-Date).ToString('o')
  host = $env:COMPUTERNAME
  user = $env:USERNAME
  staging_path = $stage
  compression_target = (Join-Path $ExportRoot ((Split-Path -Leaf $stage) + '.zip'))
  compression = @{
    format = 'zip'
    method = 'deflate'
    requested_level = '7-Zip mx=9 mfb=258 mpass=15'
  }
  included_high_value_roots = @(
    '.codex selected history/state/memory/skill/plugin/attachment data',
    'VS Code User global state and matching Codex/OpenAI workspace state',
    'VS Code OpenAI/Codex extension logs',
    'OpenAI Codex VS Code extension manifests and source-like assets'
  )
  excluded_sensitive_count = $excludedSensitive.Count
  excluded_low_value_count = $excludedLowValue.Count
  notes = @($notes)
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $stage 'export_manifest.json') -Encoding UTF8

$readme = @"
# Codex VS Code History Export

Created: $((Get-Date).ToString('o'))

Main entry points:

- raw/codex-home/sessions/ - Codex session JSONL transcripts.
- raw/codex-home/logs_2.sqlite - consistent backup of the Codex logs database.
- raw/codex-home/state_5.sqlite - consistent backup of Codex state, threads, jobs, dynamic tools, and related metadata.
- raw/codex-home/memories/, skills/, plugins/, attachments/ - local memory, skills, plugins, and attachments.
- raw/vscode-code-user/globalStorage/state.vscdb - VS Code global state backup.
- raw/vscode-code-user/workspaceStorage/*/ - workspaces with Codex/OpenAI-related state keys.
- raw/vscode-logs/ - OpenAI/Codex VS Code extension logs.
- raw/vscode-extensions/ - extension manifests and source-like assets, excluding large bundled runtime binaries.
- derived/ - schemas, table counts, extension/workspace indexes, and source inventory.

Read PRIVACY_SECURITY_NOTE.md before uploading this archive to any cloud service.
"@
Write-Utf8 (Join-Path $stage 'README.md') $readme

$inventoryRows = Get-ChildItem -LiteralPath $stage -Force -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
  [pscustomobject]@{
    archive_path = (RelPath $stage $_.FullName)
    bytes = $_.Length
    last_write_time = $_.LastWriteTime
  }
}
$inventoryRows | Export-Csv -LiteralPath (Join-Path $stage 'ARCHIVE_FILE_INVENTORY.csv') -NoTypeInformation -Encoding UTF8

$m = Get-ChildItem -LiteralPath $stage -Force -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
Add-Log "Finished staging. files=$($m.Count) logical_bytes=$($m.Sum) logical_mib=$([math]::Round($m.Sum / 1MB, 2))"

[pscustomobject]@{
  stage = $stage
  zip = Join-Path $ExportRoot ((Split-Path -Leaf $stage) + '.zip')
  files = $m.Count
  logical_mib = [math]::Round($m.Sum / 1MB, 2)
  excluded_sensitive = $excludedSensitive.Count
  excluded_low_value = $excludedLowValue.Count
} | ConvertTo-Json -Depth 4
