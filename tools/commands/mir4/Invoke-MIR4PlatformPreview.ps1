param(
  [Parameter(Mandatory)][ValidateSet('generate','check','conformance','package','compile')][string]$Command,
  [string]$RepoRoot='',
  [string]$Target='',
  [string]$ExtensionPath='',
  [string]$OutputPath=''
)
$ErrorActionPreference='Stop'
if(-not $RepoRoot){$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path}
. (Join-Path $RepoRoot 'tools\lib\mir4\PlatformPreview.ps1')
switch($Command){
  'generate'{Invoke-MIR4PlatformGenerate -RepoRoot $RepoRoot|Out-Null}
  'check'{Invoke-MIR4PlatformGenerate -RepoRoot $RepoRoot -Check|Out-Null}
  'conformance'{Test-MIR4PlatformConformance -RepoRoot $RepoRoot|Out-Null}
  'package'{New-MIR4PlatformPreviewPackages -RepoRoot $RepoRoot|ConvertTo-Json -Depth 20}
  'compile'{
    if(-not$Target-or-not$ExtensionPath-or-not$OutputPath){throw 'MIR 4 shadow compile requires target, extension and output paths.'}
    Invoke-MIR4ShadowExtensionCompilation -RepoRoot $RepoRoot -TargetId $Target -ExtensionPath $ExtensionPath -OutputPath $OutputPath|ConvertTo-Json -Depth 100
  }
}
Write-Host "MIR 4 platform $Command passed."
