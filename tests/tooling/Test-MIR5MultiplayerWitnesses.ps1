# MIR5-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$path=Join-Path $RepoRoot 'tools/mir5/Invoke-MultiplayerSession.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors){throw ($errors|Out-String)}
# Load only the real pure log-reader boundary, without executing the native
# session entry point or duplicating the acceptance implementation.
foreach($name in @('Assert-Session','Get-StageMarker')) {
  $function=@($ast.FindAll({param($node) $node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-ceq$name},$true))
  if($function.Count-ne1){throw 'Expected one session witness function'}
  . ([scriptblock]::Create($function[0].Extent.Text))
}
$assertions=0
function Assert-Witness([bool]$Condition,[string]$Message){if(-not$Condition){throw $Message};$script:assertions++}
function Marker($Witness,[string]$Case,[string]$Stage) {
  '['+$markerPrefix+'] RESULT '+([ordered]@{case=$Case;stage=$Stage;status='passed';witnesses=$Witness}|ConvertTo-Json -Compress)
}
$fixtureCase='scripted-effects-multiplayer';$markerPrefix='MIR5_SCRIPTED_EFFECTS_MULTIPLAYER'
foreach($phase in @(@('ready',0),@('rejoin-ready',2),@('restart-ready',4),@('completed',6))) {
  $stage=[string]$phase[0];$joins=[int]$phase[1];$observed=$stage-cne'ready'
  $witness=[ordered]@{actual_join_events=$joins;two_connected_clients_required=$true;runtime_owned_state_checked=$observed;physical_rates_checked=$observed;foreign_offsets_preserved=$observed}
  $line=Marker $witness $fixtureCase $stage
  Assert-Witness ($null-ne(Get-StageMarker $line $stage $joins)) "Valid $stage was rejected"
  if($observed){
    foreach($field in @('runtime_owned_state_checked','physical_rates_checked','foreign_offsets_preserved')) {
      $witness[$field]=$false;$rejected=$false
      try{Get-StageMarker (Marker $witness $fixtureCase $stage) $stage $joins|Out-Null}catch{$rejected=$true}
      Assert-Witness $rejected "$stage accepted a false $field"
      $witness[$field]=$true
    }
  }
}
$witness.actual_join_events=5;$rejected=$false
try{Get-StageMarker (Marker $witness $fixtureCase 'completed') 'completed' 6|Out-Null}catch{$rejected=$true}
Assert-Witness $rejected 'Wrong real-client join count was accepted'
$witness.actual_join_events=6;$witness.Remove('physical_rates_checked');$rejected=$false
try{Get-StageMarker (Marker $witness $fixtureCase 'completed') 'completed' 6|Out-Null}catch{$rejected=$true}
Assert-Witness $rejected 'Missing physical witness was accepted'
$fixtureCase='library-multiplayer';$markerPrefix='MIR5_LIBRARY_MULTIPLAYER'
$witness=[ordered]@{actual_join_events=2;two_connected_clients_required=$true;distinct_personal_query_and_selection=$true;native_research_queue_and_effects_unchanged=$true}
$line=Marker $witness $fixtureCase 'rejoin-ready'
Assert-Witness ($null-ne(Get-StageMarker $line 'rejoin-ready' 2)) 'Existing Library witness was rejected'
$witness.distinct_personal_query_and_selection=$false;$rejected=$false
try{Get-StageMarker (Marker $witness $fixtureCase 'rejoin-ready') 'rejoin-ready' 2|Out-Null}catch{$rejected=$true}
Assert-Witness $rejected 'Library personal-view witness was weakened'
$rejected=$false
try{Get-StageMarker ($line+"`n"+$line) 'rejoin-ready' 2|Out-Null}catch{$rejected=$true}
Assert-Witness $rejected 'Duplicate native stage witness was accepted'
[pscustomobject]@{status='passed';assertions=$assertions;native_factorio=$false;scope='Actual log-reader acceptance for the two declared multiplayer cases'}|ConvertTo-Json -Compress
