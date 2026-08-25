function Get-MIR4DiagnosticRegistryV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $path = Join-Path $repo 'spec/api/mir4-v1/diagnostics.json'
  $registry = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100
  if ([string]$registry.kind -cne 'MIR4DiagnosticRegistryV1' -or [int]$registry.schema -ne 1) {
    throw '[mir4-diagnostic-registry]'
  }
  $codes = @($registry.diagnostics | ForEach-Object { [string]$_.code })
  if (@($codes | Sort-Object -Unique).Count -ne $codes.Count) { throw '[mir4-diagnostic-code-reuse]' }
  $orders = @($registry.diagnostics | ForEach-Object { [int]$_.order })
  if (@($orders | Sort-Object -Unique).Count -ne $orders.Count) { throw '[mir4-diagnostic-order-reuse]' }
  if (($codes -join '|') -cne (@($codes | Sort-Object -CaseSensitive) -join '|')) { throw '[mir4-diagnostic-registry-order]' }
  return $registry
}

function Get-MIR4DiagnosticDefinitionV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Code)
  $registry = Get-MIR4DiagnosticRegistryV1 -RepoRoot $RepoRoot
  $match = @($registry.diagnostics | Where-Object { [string]$_.code -ceq $Code })
  if ($match.Count -ne 1) { throw "[mir4-diagnostic-unknown] $Code" }
  return $match[0]
}

function New-MIR4DiagnosticV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Code,
    [string]$Path = '$',
    [Collections.IDictionary]$Context = [ordered]@{}
  )
  $definition = Get-MIR4DiagnosticDefinitionV1 -RepoRoot $RepoRoot -Code $Code
  if ($Path.Length -gt 512) { throw '[mir4-diagnostic-path]' }
  if ($Context.Count -gt 32) { throw '[mir4-diagnostic-context]' }
  return [pscustomobject][ordered]@{
    kind = 'MIR4DiagnosticV1'
    schema = 1
    code = [string]$definition.code
    severity = [string]$definition.severity
    order = [int]$definition.order
    path = $Path
    message = [string]$definition.message
    context = $Context
  }
}

function Sort-MIR4DiagnosticsV1 {
  param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Diagnostics)
  return @($Diagnostics | Sort-Object @{Expression={ switch ([string]$_.severity) { 'error' { 0 }; 'warning' { 1 }; 'info' { 2 }; default { 3 } }}}, @{Expression={ [int]$_.order }}, @{Expression={ [string]$_.code }}, @{Expression={ [string]$_.path }})
}

function Format-MIR4DiagnosticV1 {
  param([Parameter(Mandatory)]$Diagnostic)
  $location = if ([string]$Diagnostic.path -ceq '$') { '' } else { " $($Diagnostic.path)" }
  return "[$([string]$Diagnostic.code)] $([string]$Diagnostic.severity)$($location): $([string]$Diagnostic.message)"
}
