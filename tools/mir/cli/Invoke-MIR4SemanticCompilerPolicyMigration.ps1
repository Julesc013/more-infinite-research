param(
  [ValidateSet('generate','check','show')][string]$Command='check',
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$OutputPath=''
)

$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../application/compiler/SemanticCompilerPolicyMigration.ps1')

$receipt=if($Command-eq'generate'){
  Invoke-MIR4SemanticCompilerPolicyMigrationProjectionV1 -RepoRoot $RepoRoot
}elseif($Command-eq'check'){
  Invoke-MIR4SemanticCompilerPolicyMigrationProjectionV1 -RepoRoot $RepoRoot -Check
}else{
  Get-MIR4RepositoryJsonV1 -RepoRoot $RepoRoot -Path $script:MIR4SemanticCompilerPolicyMigrationReceiptPath
}
$result=[ordered]@{
  schema=1;kind='MIR4SemanticCompilerPolicyMigrationResultV1';migration_id=[string]$receipt.migration_id;state=[string]$receipt.state
  predecessor_receipt=[string]$receipt.predecessor_receipt.path;predecessor_sha256=[string]$receipt.predecessor_receipt.sha256
  receipt=$script:MIR4SemanticCompilerPolicyMigrationReceiptPath;digest=[string]$receipt.digest
  package_source_sha256=[string]$receipt.package_source_sha256;package_visible_delta=@($receipt.package_visible_delta);release_transition_authority=$false
}
$json=($result|ConvertTo-Json -Depth 20)+[char]10
if(-not[string]::IsNullOrWhiteSpace($OutputPath)){
  $path=if([IO.Path]::IsPathRooted($OutputPath)){$OutputPath}else{Join-Path $RepoRoot $OutputPath}
  New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent)|Out-Null
  [IO.File]::WriteAllText($path,$json,[Text.UTF8Encoding]::new($false))
}
$json
