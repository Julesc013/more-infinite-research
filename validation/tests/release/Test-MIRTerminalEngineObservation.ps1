param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path }
. (Join-Path $RepoRoot "tools\lib\terminal\TerminalEngineObservation.ps1")

$dataRaw = [pscustomobject][ordered]@{
  technology = [pscustomobject][ordered]@{
    "mir-tech-b" = [pscustomobject][ordered]@{name="mir-tech-b";enabled=$true;max_level="infinite";prerequisites=@("a");unit=[pscustomobject][ordered]@{count_formula="100*L";time=30;ingredients=@(@("automation-science-pack",1))};effects=@([pscustomobject][ordered]@{type="laboratory-speed";modifier=0.1})}
    "mir-tech-a" = [pscustomobject][ordered]@{name="mir-tech-a";enabled=$false;hidden=$true;effects=@()}
  }
  "bool-setting" = [pscustomobject][ordered]@{
    "not-mir" = [pscustomobject][ordered]@{setting_type="startup";default_value=$false}
    "mir-enabled" = [pscustomobject][ordered]@{setting_type="startup";default_value=$true}
  }
  "int-setting" = [pscustomobject][ordered]@{
    "mir-count" = [pscustomobject][ordered]@{setting_type="startup";default_value=7;minimum_value=1;maximum_value=9}
  }
}
$first = Get-MIRTerminalEngineInventory -DataRaw $dataRaw -Release "3.2.5" -Target "2.1" -DeclaredTechnologyNames @("missing", "mir-tech-b", "mir-tech-a") -EvidencePath ".mir/evidence/example.json"
$second = Get-MIRTerminalEngineInventory -DataRaw $dataRaw -Release "3.2.5" -Target "2.1" -DeclaredTechnologyNames @("mir-tech-a", "mir-tech-b", "missing") -EvidencePath ".mir/evidence/example.json"
$firstJson = $first | ConvertTo-Json -Depth 100
$secondJson = $second | ConvertTo-Json -Depth 100
if ($firstJson -ne $secondJson -or @($first.technologies).Count -ne 2 -or @($first.effects_and_owners).Count -ne 1 -or @($first.settings).Count -ne 2) {
  throw "Terminal engine inventory normalization is not deterministic or complete."
}
if ((@($first.technologies.stable_id) -join "|") -ne "mir-tech-a|mir-tech-b" -or
    (@($first.settings.stable_id) -join "|") -ne "mir-count|mir-enabled" -or
    [string]$first.effects_and_owners[0].stable_id -ne "mir-tech-b#effect-001") {
  throw "Terminal engine inventory ordering or MIR filtering failed."
}
$logInventory = Get-MIRTerminalEngineInventoryFromLog -Lines @(
  "  1.0 MIR_TERMINAL_SETTING`tbool-setting`tmir-enabled`tstartup`ttrue`t<nil>`t<nil>`t`tfalse`ta",
  "  1.1 MIR_TERMINAL_TECH`tmir-tech-b`ttrue`tfalse`tfalse`tinfinite`ta`t{count_formula=`"100*L`"}`t1",
  "  1.2 MIR_TERMINAL_EFFECT`tmir-tech-b`t1`tlaboratory-speed`t0.1`t{modifier=0.1,type=`"laboratory-speed`"}",
  "  1.3 MIR_TERMINAL_SETTINGS_COMPLETE`t1",
  "  1.4 MIR_TERMINAL_DATA_COMPLETE`t1`t1"
) -Release "3.2.5" -Target "2.1" -EvidencePath ".mir/evidence/example.json"
if (-not $logInventory.data_complete -or -not $logInventory.settings_complete -or
    @($logInventory.technologies).Count -ne 1 -or @($logInventory.effects_and_owners).Count -ne 1 -or @($logInventory.settings).Count -ne 1) {
  throw "Terminal observer line protocol did not parse its completed inventories."
}
Write-Host "[ok] terminal exact-engine observation normalization is deterministic"
