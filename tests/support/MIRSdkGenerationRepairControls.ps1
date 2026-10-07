function Test-MIRSdkGenerationRepairControls {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)
  $workflowPath=Join-Path $RepoRoot '.github/workflows/validate.yml'
  $workflow=Get-Content -LiteralPath $workflowPath -Raw
  $step=[regex]::Match($workflow,'(?ms)^      - name: Preserve source-bound SDK generation repair after a stale projection failure\r?\n(?<step>.*?)(?=^      - |\z)')
  Assert-MIRDevelopmentCISelection $step.Success 'SDK generation repair step is missing'
  $stepText=$step.Value
  Assert-MIRDevelopmentCISelection ($stepText.Contains("failure() && steps.verification-instance.outcome == 'failure' && matrix.test_id == 'static.mir4-platform-preview'")) 'SDK recovery is not restricted to the failed exact preview worker'
  Assert-MIRDevelopmentCISelection (-not $stepText.Contains('continue-on-error:')) 'SDK recovery waived a failed verification step'
  $bodyMatch=[regex]::Match($stepText,'(?ms)^        run: \|\r?\n(?<body>.*)\z')
  Assert-MIRDevelopmentCISelection $bodyMatch.Success 'SDK recovery worker has no executable body'
  $body=$bodyMatch.Groups['body'].Value -replace '(?m)^          ',''
  $tokens=$null;$errors=$null
  $null=[Management.Automation.Language.Parser]::ParseInput($body,[ref]$tokens,[ref]$errors)
  Assert-MIRDevelopmentCISelection ($errors.Count -eq 0) 'SDK recovery workflow body does not parse'
  $run=[scriptblock]::Create($body)
  $platformPath=Join-Path $RepoRoot 'tools/lib/mir4/PlatformPreview.ps1'
  $platformAst=[Management.Automation.Language.Parser]::ParseFile($platformPath,[ref]$tokens,[ref]$errors)
  Assert-MIRDevelopmentCISelection ($errors.Count -eq 0) 'Canonical SDK generator does not parse'
  $writer=@($platformAst.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in @('Get-MIR4PlatformRepoRoot','Invoke-MIR4PlatformGenerate')},$false))
  Assert-MIRDevelopmentCISelection ($writer.Count -eq 2) 'Cannot consume the canonical fixed-point writer'
  $fixtureParent=Join-Path $RepoRoot 'build/tests/sdk-generation-repair-controls'
  $root=Join-Path $fixtureParent ([guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $root -Force | Out-Null
  $environmentNames=@('MIR_SDK_REPAIR_EVIDENCE','MIR_SDK_REPAIR_HEAD','MIR_SDK_REPAIR_FINGERPRINT','GITHUB_SHA','GITHUB_RUN_ID','GITHUB_RUN_ATTEMPT','GITHUB_WORKFLOW','GITHUB_OUTPUT')
  $previous=@{}
  foreach($name in $environmentNames){$previous[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
  $cases=[Collections.Generic.List[object]]::new()
  try {
    foreach($mode in @('unrelated-failure','fixed-point','dirty-checkout','changed-player-source','unowned-diff')){
      $caseRoot=Join-Path $root $mode
      New-Item -ItemType Directory -Path (Join-Path $caseRoot 'tools/lib/mir4'),(Join-Path $caseRoot 'tools/mir/application/package'),(Join-Path $caseRoot 'sdk/preview/mir4/reference'),(Join-Path $caseRoot 'evidence') -Force | Out-Null
      [IO.File]::WriteAllText((Join-Path $caseRoot 'evidence/stdout.txt'),$(if($mode -eq 'unrelated-failure'){'a different failure'}else{'[mir4-platform-stale] sdk/preview/mir4/reference/a.json'}))
      [IO.File]::WriteAllText((Join-Path $caseRoot 'evidence/stderr.txt'),'')
      [IO.File]::WriteAllText((Join-Path $caseRoot 'sdk/preview/mir4/reference/a.json'),'old-a')
      [IO.File]::WriteAllText((Join-Path $caseRoot 'sdk/preview/mir4/reference/b.json'),'old-b')
      [IO.File]::WriteAllText((Join-Path $caseRoot 'player.txt'),'player-source')
      $fixtureGenerator=@'
function Get-MIR4PlatformGeneratedFiles {
  param([string]$RepoRoot)
  $state.generation_calls++
  if($state.mode -eq 'changed-player-source'){[IO.File]::WriteAllText((Join-Path $RepoRoot 'player.txt'),'changed-player-source')}
  return [ordered]@{
    'sdk/preview/mir4/reference/a.json'='correct-a'
    'sdk/preview/mir4/reference/b.json'=[IO.File]::ReadAllText((Join-Path $RepoRoot 'sdk/preview/mir4/reference/a.json'))
  }
}
'@
      [IO.File]::WriteAllText((Join-Path $caseRoot 'tools/lib/mir4/PlatformPreview.ps1'),(($writer.Extent.Text -join "`n")+"`n"+$fixtureGenerator))
      [IO.File]::WriteAllText((Join-Path $caseRoot 'tools/mir/application/package/TargetMaterializer.ps1'),"function Get-MIR4CanonicalPackageSourceFingerprint {param([string]`$RepoRoot) (Get-FileHash -LiteralPath (Join-Path `$RepoRoot 'player.txt')).Hash}")
      $state=@{mode=$mode;generation_calls=0;commit=('a'*40);tree=('b'*40)}
      # Only Git metadata is controlled here; generation uses the real writer
      # over two tiny dependent projections. No clone, mod archive or engine.
      function git {
        $global:LASTEXITCODE=0
        switch($args[0]){
          'rev-parse'{if($args[1] -eq 'HEAD'){$state.commit}else{$state.tree}}
          'status'{if($state.mode -eq 'dirty-checkout'){' M player.txt'}}
          'diff'{
            'sdk/preview/mir4/reference/a.json'
            'sdk/preview/mir4/reference/b.json'
            if($state.mode -eq 'unowned-diff'){'player.txt'}
          }
          'ls-files'{}
          default{throw 'Unexpected Git command in bounded SDK controls'}
        }
      }
      [Environment]::SetEnvironmentVariable('MIR_SDK_REPAIR_EVIDENCE',(Join-Path $caseRoot 'evidence'),'Process')
      [Environment]::SetEnvironmentVariable('MIR_SDK_REPAIR_HEAD',('c'*40),'Process')
      [Environment]::SetEnvironmentVariable('MIR_SDK_REPAIR_FINGERPRINT',('D'*64),'Process')
      [Environment]::SetEnvironmentVariable('GITHUB_SHA',$state.commit,'Process')
      [Environment]::SetEnvironmentVariable('GITHUB_RUN_ID','123','Process')
      [Environment]::SetEnvironmentVariable('GITHUB_RUN_ATTEMPT','1','Process')
      [Environment]::SetEnvironmentVariable('GITHUB_WORKFLOW','MIR Validation','Process')
      [Environment]::SetEnvironmentVariable('GITHUB_OUTPUT',(Join-Path $caseRoot 'github-output.txt'),'Process')
      $message=$null;$failureStack=$null
      Push-Location -LiteralPath $caseRoot
      try{& $run}catch{$message=$_.Exception.Message;$failureStack=$_.ScriptStackTrace}finally{Pop-Location}
      $repairPath=Join-Path $caseRoot 'build/results/mir4-sdk-generation-repair/repair.json'
      if($mode -eq 'fixed-point'){
        Assert-MIRDevelopmentCISelection ($null -eq $message) "Canonical SDK recovery failed: $message $failureStack"
        $record=Get-Content -LiteralPath $repairPath -Raw | ConvertFrom-Json -Depth 20
        Assert-MIRDevelopmentCISelection ($state.generation_calls -eq 3) 'Recovery did not run the complete two-pass dependent fixed point'
        Assert-MIRDevelopmentCISelection ($record.fixed_point_completed -and $record.files.Count -eq 2) 'Recovered projections do not cover the fixed point'
        Assert-MIRDevelopmentCISelection ($record.source.checkout_commit -ceq $state.commit -and $record.source.checkout_tree -ceq $state.tree -and $record.source.head_commit -ceq ('c'*40)) 'SDK recovery changed its exact source identities'
        Assert-MIRDevelopmentCISelection ($record.original_verification_outcome -ceq 'failure' -and -not $record.accepted_evidence -and -not $record.native_qualification -and -not $record.publication_authorized) 'Generated repair gained accepted verification or release authority'
        foreach($row in $record.files){
          $payload=Join-Path (Split-Path -Parent $repairPath) ('files/'+$row.path)
          Assert-MIRDevelopmentCISelection ((Get-FileHash -LiteralPath $payload).Hash -ceq $row.sha256 -and [IO.File]::ReadAllText($payload) -ceq 'correct-a') 'Exported generated bytes do not match the verified fixed point'
        }
        Assert-MIRDevelopmentCISelection ((Get-Content -LiteralPath $env:GITHUB_OUTPUT -Raw).Trim() -ceq 'artifact_ready=true') 'Ready artifact was not explicitly identified'
      }elseif($mode -eq 'unrelated-failure'){
        Assert-MIRDevelopmentCISelection ($null -eq $message -and $state.generation_calls -eq 0 -and -not(Test-Path -LiteralPath $repairPath)) 'Unrelated stdout/stderr failure triggered SDK regeneration'
      }else{
        $expected=switch($mode){'dirty-checkout'{'exact clean hosted checkout'};'changed-player-source'{'changed player source'};'unowned-diff'{'Unexpected SDK repair path'}}
        Assert-MIRDevelopmentCISelection ($null -ne $message -and $message.Contains($expected) -and -not(Test-Path -LiteralPath $repairPath)) "Recovery did not refuse $mode before publishing: $message"
        if($mode -eq 'dirty-checkout'){Assert-MIRDevelopmentCISelection ($state.generation_calls -eq 0) 'Dirty checkout was regenerated'}
      }
      $cases.Add([ordered]@{case=$mode;passed=$true;generator_calls=$state.generation_calls;expected_refusal=$message;artifact_published=($mode -eq 'fixed-point')})
    }
    $record=[ordered]@{schema=1;kind='MIRSdkGenerationRepairControlResult';status='passed';workflow_sha256=(Get-FileHash -LiteralPath $workflowPath).Hash;canonical_writer_sha256=(Get-FileHash -LiteralPath $platformPath).Hash;cases=$cases.ToArray();factorio_processes=0;dependency_archives_staged=0;dependency_archive_payload_bytes_copied=0;full_sdk_generation=$false;native_qualification=$false}
    [IO.File]::WriteAllText((Join-Path $root 'result.json'),(($record|ConvertTo-Json -Depth 20)+[char]10),[Text.UTF8Encoding]::new($false))
    Write-Host "[ok] SDK generation repair workflow controls passed: $root/result.json"
  }finally{
    foreach($name in $environmentNames){[Environment]::SetEnvironmentVariable($name,$previous[$name],'Process')}
  }
}
