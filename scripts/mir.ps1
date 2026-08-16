# MIR-L5-LEGACY-CLI-WRAPPER: retained for historical command compatibility only.
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Args
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
& (Join-Path $repo "tools/mir.ps1") @Args
exit $LASTEXITCODE