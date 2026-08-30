param([Parameter(Mandatory)][string]$InputPath,[Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference='Stop'
$record=Get-Content -Raw -LiteralPath $InputPath|ConvertFrom-Json -Depth 100
if([int]$record.schema-ne 1-or[string]$record.kind-cne'MIR4InspectionBundleV1'-or@($record.sections).Count-ne 11){throw '[mir4-inspector-v1-bundle]'}
if(@($record.sections|Where-Object{@($_.items).Count-gt 100}).Count){throw '[mir4-inspector-v1-bound]'}
$json=$record|ConvertTo-Json -Depth 100
[IO.File]::WriteAllText($OutputPath,$json+"`n",[Text.UTF8Encoding]::new($false))
[pscustomobject]@{status='exported-bounded-read-only';path=$OutputPath;upload=$false;mutation=$false}|ConvertTo-Json