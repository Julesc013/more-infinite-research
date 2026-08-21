$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
. (Join-Path $repo 'tools\lib\mir4\BootstrapMaterialization.ps1')
$root='.mir/releases/waves/mir4-r0'
$records=@(
  @{path="$root/MIR4-Target-RegistryV5.json";schema='spec/schemas/mir4-hybrid-platform-authority.schema.json'},
  @{path="$root/MIR4-Platform-Maturity-and-Publication-ContractV1.json";schema='spec/schemas/mir4-hybrid-platform-authority.schema.json'},
  @{path="$root/MIR4-Candidate-Wave-ProgrammeV1.json";schema='spec/schemas/mir4-hybrid-platform-authority.schema.json'},
  @{path="$root/MIR4-M4C01-Implementation-AuthorizationV1.json";schema='spec/schemas/mir4-m4c01-implementation-authorization.schema.json'}
)
foreach($item in $records){
  $path=Join-Path $repo $item.path;$text=Get-Content -Raw -LiteralPath $path
  if(-not($text|Test-Json -SchemaFile (Join-Path $repo $item.schema))){throw "[mir4-hybrid-schema] $($item.path)"}
  $record=$text|ConvertFrom-Json -Depth 100 -DateKind String
  if(-not(Test-MIR4BootstrapRecordHash -Record $record)){throw "[mir4-hybrid-self-hash] $($item.path)"}
}
$authority=Get-Content -Raw -LiteralPath (Join-Path $repo "$root/MIR4-M4C01-Implementation-AuthorizationV1.json")|ConvertFrom-Json -DateKind String
foreach($forbidden in @('production-key-create-or-use','main-promotion','legacy-promotion','v4-tags','github-release-publication','mod-portal-mir4-upload','production-seal','cleanup-or-deletion')){if($forbidden -notin @($authority.not_authorized)){throw "[mir4-hybrid-boundary] Missing $forbidden"}}
$registry=Get-Content -Raw -LiteralPath (Join-Path $repo "$root/MIR4-Target-RegistryV5.json")|ConvertFrom-Json -DateKind String
if(@($registry.payload.targets).Count-ne 17){throw '[mir4-hybrid-target-count] Expected 17 targets.'}
if(($registry.payload.targets|Where-Object id -eq 'factorio-2.1').mir3_predecessor-cne'3.2.11'){throw '[mir4-hybrid-f210-predecessor]'}
if(($registry.payload.targets|Where-Object id -eq 'factorio-2.0').mir3_predecessor-cne'2.5.11'){throw '[mir4-hybrid-f200-predecessor]'}
$presentationPath=Join-Path $repo "$root/MIR4-Package-Presentation-OverlayV1.json"
$presentationText=Get-Content -Raw -LiteralPath $presentationPath
if(-not($presentationText|Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-package-presentation-overlay.schema.json'))){throw '[mir4-presentation-schema]'}
$presentation=$presentationText|ConvertFrom-Json -Depth 100 -DateKind String
if(-not(Test-MIR4BootstrapRecordHash -Record $presentation)-or$presentation.semantic_authority-or$presentation.gameplay_difference_authorized-or$presentation.public_output_authorized){throw '[mir4-presentation-boundary]'}
Write-Host 'MIR 4 hybrid platform authority validation passed.'
