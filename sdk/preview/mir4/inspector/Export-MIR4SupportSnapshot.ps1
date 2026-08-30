param([Parameter(Mandatory)][string]$InputPath,[string]$OutputPath='')
$record=Get-Content -Raw -LiteralPath $InputPath|ConvertFrom-Json
$view=[ordered]@{kind=$record.kind;schema=$record.schema;maturity=$record.maturity;target=$record.target;capabilities=$record.capabilities;payload=$record.payload;diagnostics=$record.diagnostics;digest=$record.digest}
$json=$view|ConvertTo-Json -Depth 100
if($OutputPath){[IO.File]::WriteAllText($OutputPath,$json+"`n",[Text.UTF8Encoding]::new($false))}else{$json}