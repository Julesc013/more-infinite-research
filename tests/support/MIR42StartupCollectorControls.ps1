function Invoke-MIR42StartupCollectorControls {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Root)
  $scriptPath=Join-Path $RepoRoot 'scripts/Collect-MIRPlayerReport.ps1'
  $userData=Join-Path $Root 'userdata'
  $mods=Join-Path $userData 'mods'
  [void][IO.Directory]::CreateDirectory($mods)
  $controls=@(
    @{id='basic';text='Authorization: Basic MIR421_COLLECTOR_BASIC';private='MIR421_COLLECTOR_BASIC'},
    @{id='proxy-basic';text='Proxy-Authorization: Basic MIR421_COLLECTOR_PROXY';private='MIR421_COLLECTOR_PROXY'},
    @{id='bearer';text='Authorization: Bearer MIR421_COLLECTOR_BEARER';private='MIR421_COLLECTOR_BEARER'},
    @{id='bare-bearer';text='Bearer MIR421_COLLECTOR_BARE';private='MIR421_COLLECTOR_BARE'},
    @{id='json-token';text='{"token": "MIR421_COLLECTOR_JSON"}';private='MIR421_COLLECTOR_JSON'},
    @{id='access-token';text='{"access_token": "MIR421_COLLECTOR_ACCESS"}';private='MIR421_COLLECTOR_ACCESS'},
    @{id='quoted-password';text='password="MIR421 collector private suffix"';private='private suffix'},
    @{id='escaped-token';text='{"token": "MIR421 collector\"escaped value"}';private='escaped value'},
    @{id='single-secret';text="secret='MIR421 collector private words'";private='private words'},
    @{id='api-key';text='api-key=MIR421_COLLECTOR_API';private='MIR421_COLLECTOR_API'},
    @{id='legacy-prefixed-password';text='server_password=MIR421_COLLECTOR_PREFIX';private='MIR421_COLLECTOR_PREFIX'},
    @{id='legacy-joined-token';text='backupToken=MIR421_COLLECTOR_JOINED';private='MIR421_COLLECTOR_JOINED'},
    @{id='placeholder-suffix';text='token="<REDACTED>MIR421_COLLECTOR_SUFFIX"';private='MIR421_COLLECTOR_SUFFIX'},
    @{id='windows-home';text='C:\Users\MIR421-collector-user\Factorio\factorio-current.log';private='MIR421-collector-user'},
    @{id='legacy-windows-home';text='C:\Documents and Settings\MIR421-old-user\Factorio\factorio-current.log';private='MIR421-old-user'},
    @{id='unix-home';text='/home/MIR421-private-user/Factorio/factorio-current.log';private='MIR421-private-user'},
    @{id='email';text='contact mir421.collector@example.invalid';private='mir421.collector@example.invalid'},
    @{id='selected-userdata';text=$userData;private=$userData}
  )
  $diagnostic='Error __more-infinite-research__/data.lua:421: synthetic startup failure'
  $log=$diagnostic+"`n"+(@($controls|ForEach-Object{$_.text})-join"`n")+"`n"
  $utf8=[Text.UTF8Encoding]::new($false)
  foreach($name in @('factorio-current.log','factorio-previous.log')){[IO.File]::WriteAllText((Join-Path $userData $name),$log,$utf8)}
  [IO.File]::WriteAllText((Join-Path $mods 'mod-list.json'),'{"mods":[{"name":"base","enabled":true}],"token":"MIR421_COLLECTOR_MODLIST"}',$utf8)
  [IO.File]::WriteAllText((Join-Path $mods 'mod-settings.dat'),'MIR421_SYNTHETIC_BINARY_SETTINGS',$utf8)
  [IO.File]::WriteAllText((Join-Path $mods 'more-infinite-research_4.2.21001.zip'),'synthetic identity input, not a player package',$utf8)
  [void][IO.Directory]::CreateDirectory((Join-Path $userData 'saves'))
  [IO.File]::WriteAllText((Join-Path $userData 'saves/original.zip'),'MIR421_SYNTHETIC_SAVE_EXCLUDED',$utf8)
  $inputs=@(Get-ChildItem -LiteralPath $userData -Recurse -File|ForEach-Object{[pscustomobject]@{path=$_.FullName;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}})
  $hosts=@((Get-Command pwsh -ErrorAction Stop).Source)
  if($IsWindows){
    $windowsHost=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
    if(-not(Test-Path -LiteralPath $windowsHost -PathType Leaf)){throw '[mir421-collector-windows-host-missing]'}
    $hosts+=$windowsHost
  }
  $hostVersions=@()
  foreach($hostPath in $hosts){
    $version=(& $hostPath -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'|Out-String).Trim()
    if($LASTEXITCODE-ne0-or$version-notmatch'^\d+\.\d+\.\d+') {throw '[mir421-collector-host-version]'}
    if($IsWindows-and$hostPath-ceq$windowsHost-and$version-notmatch'^5\.1\.') {throw '[mir421-collector-windows-5-1-required]'}
    $hostVersions+=$version
  }
  $assertions=0
  foreach($hostPath in $hosts){
    $output=Join-Path $Root ('reports-'+$assertions)
    $messages=(& $hostPath -NoProfile -File $scriptPath -FactorioUserData $userData -OutputDirectory $output 2>&1|Out-String)
    if($LASTEXITCODE-ne0){throw "[mir421-collector-execution] $messages"}
    $reports=@(Get-ChildItem -LiteralPath $output -File -Filter '*.zip')
    if($reports.Count-ne1){throw '[mir421-collector-report-count]'}
    $assertions++
    $stream=[IO.File]::OpenRead($reports[0].FullName)
    try{
      $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Read,$true)
      try{
        $entries=@($zip.Entries|ForEach-Object{$_.FullName}|Sort-Object)
        $expected=@('logs/factorio-current.log','logs/factorio-previous.log','mods/mod-list.json','README.txt','manifest.json'|Sort-Object)
        if(($entries-join'|')-cne($expected-join'|')){throw '[mir421-collector-excluded-material]'}
        $assertions++
        $texts=@{}
        foreach($entry in $zip.Entries){
          $reader=[IO.StreamReader]::new($entry.Open(),[Text.Encoding]::UTF8)
          try{$texts[$entry.FullName]=$reader.ReadToEnd()}finally{$reader.Dispose()}
        }
        foreach($name in @('logs/factorio-current.log','logs/factorio-previous.log')){
          if(-not$texts[$name].Contains($diagnostic)){throw '[mir421-collector-diagnostic-retained]'}
          $assertions++
          foreach($control in $controls){if($texts[$name].Contains([string]$control.private)){throw "[mir421-collector-private-log] $($control.id)"};$assertions++}
          foreach($line in @($texts[$name]-split"`n"|Where-Object{$_-like'{*'})){[void]($line|ConvertFrom-Json);$assertions++}
        }
        $modList=$texts['mods/mod-list.json']|ConvertFrom-Json
        if($texts['mods/mod-list.json'].Contains('MIR421_COLLECTOR_MODLIST')-or$modList.mods[0].name-cne'base'-or-not$modList.mods[0].enabled){throw '[mir421-collector-private-mod-list]'}
        $assertions++
        $manifest=$texts['manifest.json']|ConvertFrom-Json
        if($manifest.kind-cne'MIRPlayerStartupReportV1'-or$manifest.logs.Count-ne2-or$manifest.mod_settings.included-or$manifest.mir_archives.Count-ne1-or-not$manifest.mod_list.redacted-or$manifest.mod_list.bytes-ne(Get-Item -LiteralPath (Join-Path $mods 'mod-list.json')).Length){throw '[mir421-collector-manifest-boundary]'}
        $assertions++
        foreach($row in $manifest.logs){
          $actual=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes($texts['logs/'+$row.name])))
          if($row.captured_sha256-cne$actual-or$row.tail_truncated){throw '[mir421-collector-log-hash]'}
          $assertions++
        }
        $actual=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes($texts['mods/mod-list.json'])))
        if($manifest.mod_list.captured_sha256-cne$actual){throw '[mir421-collector-mod-list-hash]'}
        $assertions++
      }finally{$zip.Dispose()}
    }finally{$stream.Dispose()}
  }
  foreach($input in $inputs){if((Get-FileHash -LiteralPath $input.path -Algorithm SHA256).Hash-cne$input.sha256){throw '[mir421-collector-original-input-mutated]'};$assertions++}

  # Exercise the established byte limits with owned synthetic files. A long
  # first line crosses the tail boundary; only complete trailing diagnostics
  # should survive. The oversized mod list is omitted rather than parsed.
  $boundedData=Join-Path $Root 'bounded-userdata'
  [void][IO.Directory]::CreateDirectory((Join-Path $boundedData 'mods'))
  $boundedLog=Join-Path $boundedData 'factorio-current.log'
  $file=[IO.File]::Create($boundedLog)
  try{
    $chunk=$utf8.GetBytes(('x' * 1MB))
    for($index=0;$index-lt8;$index++){$file.Write($chunk,0,$chunk.Length)}
    $tail=$utf8.GetBytes("`nMIR421_COMPLETE_TAIL`nAuthorization: Basic MIR421_BOUNDED_PRIVATE`n")
    $file.Write($tail,0,$tail.Length)
  }finally{$file.Dispose()}
  $oversizedList=Join-Path $boundedData 'mods/mod-list.json'
  $file=[IO.File]::Create($oversizedList)
  try{$file.SetLength(2MB+1)}finally{$file.Dispose()}
  foreach($hostPath in $hosts){
    $output=Join-Path $Root ('bounded-reports-'+$assertions)
    $messages=(& $hostPath -NoProfile -File $scriptPath -FactorioUserData $boundedData -OutputDirectory $output 2>&1|Out-String)
    if($LASTEXITCODE-ne0){throw "[mir421-collector-bounded-execution] $messages"}
    $reports=@(Get-ChildItem -LiteralPath $output -File -Filter '*.zip')
    if($reports.Count-ne1){throw '[mir421-collector-bounded-report-count]'}
    $stream=[IO.File]::OpenRead($reports[0].FullName)
    try{
      $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Read,$true)
      try{
        if($null-ne$zip.GetEntry('mods/mod-list.json')-or$zip.Entries.Count-ne3){throw '[mir421-collector-oversized-list-excluded]'}
        $reader=[IO.StreamReader]::new($zip.GetEntry('logs/factorio-current.log').Open(),[Text.Encoding]::UTF8)
        try{$safeTail=$reader.ReadToEnd()}finally{$reader.Dispose()}
        if($safeTail.Length-gt8MB-or-not$safeTail.Contains('MIR421_COMPLETE_TAIL')-or$safeTail.Contains('MIR421_BOUNDED_PRIVATE')-or$safeTail.Contains('xxxx')){throw '[mir421-collector-tail-boundary]'}
        $reader=[IO.StreamReader]::new($zip.GetEntry('manifest.json').Open(),[Text.Encoding]::UTF8)
        try{$manifest=$reader.ReadToEnd()|ConvertFrom-Json}finally{$reader.Dispose()}
        if($manifest.logs.Count-ne1-or-not$manifest.logs[0].tail_truncated-or$manifest.logs[0].source_bytes-le8MB-or$null-ne$manifest.mod_list-or-not(@($manifest.notes)-contains'mod-list.json exceeded 2 MiB and was omitted.')){throw '[mir421-collector-bounded-manifest]'}
        $assertions+=3
      }finally{$zip.Dispose()}
    }finally{$stream.Dispose()}
  }

  $tokens=$null;$errors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile($scriptPath,[ref]$tokens,[ref]$errors)
  $definitions=@($ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-ceq'Protect-MIRLogText'},$true))
  if($errors.Count-or$definitions.Count-ne1){throw '[mir421-collector-redactor-authority]'}
  $redactor=[scriptblock]::Create($definitions[0].Extent.Text)
  foreach($control in $controls){
    & {
      param($Definition,$InputText,$UserDataPath)
      $userData=$UserDataPath
      . $Definition
      $first=Protect-MIRLogText -Value $InputText
      if((Protect-MIRLogText -Value $first)-cne$first){throw '[mir421-collector-redaction-fixed-point]'}
    } $redactor $control.text $userData
    $assertions++
  }
  & {
    param($Definition,$UserDataPath)
    $userData=$UserDataPath
    . $Definition
    $safe='__more-infinite-research__/data.lua:421 recipe lab-api; count=16 token_count=3'
    if((Protect-MIRLogText -Value $safe)-cne$safe-or(Protect-MIRLogText -Value '')-cne''){throw '[mir421-collector-safe-text]'}
  } $redactor $userData
  $assertions+=2
  return [pscustomobject]@{assertions=$assertions;hosts=$hosts.Count;host_versions=$hostVersions;windows_powershell_5_1=$IsWindows;native_factorio=$false;original_inputs_unchanged=$true}
}
