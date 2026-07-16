param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Args
)

$ErrorActionPreference = "Stop"
$repo = Resolve-Path (Join-Path $PSScriptRoot "..\..")
& (Join-Path $repo "scripts\Invoke-MIRAssurance.ps1") @Args
exit $LASTEXITCODE
