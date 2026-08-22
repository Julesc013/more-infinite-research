param([string]$RepoRoot='',[switch]$Check)
$ErrorActionPreference='Stop'
if(-not $RepoRoot){$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path}else{$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path}
. (Join-Path $RepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
$authorityPath=Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/MIR4-Package-Presentation-OverlayV1.json'
$text=Get-Content -Raw -LiteralPath $authorityPath
if(-not($text|Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/mir4-package-presentation-overlay.schema.json'))){throw '[mir4-presentation-authority-schema]'}
$authority=$text|ConvertFrom-Json -Depth 50
if(-not(Test-MIR4BootstrapRecordHash -Record $authority)){throw '[mir4-presentation-authority-hash]'}
if($authority.semantic_authority-or$authority.gameplay_difference_authorized-or$authority.public_output_authorized){throw '[mir4-presentation-boundary]'}
$outputRoot=[IO.Path]::GetFullPath((Join-Path $RepoRoot ([string]$authority.output_root)))
$outputRoot=Assert-MIR4DescendantPath -Root (Join-Path $RepoRoot 'build/mir4') -Path $outputRoot

function Get-PresentationReadme($row){
  $admission=if($row.role-eq'mandatory'){'mandatory release candidate; qualification required'}elseif($row.role-eq'conditional'){'conditional release candidate; independently admitted only when green'}else{'private experimental test candidate; no public support claim'}
  return @"
# More Infinite Research 4.0

This is the **$($row.target_key)** distribution for **Factorio $($row.factorio_line)**.

- Source version: `4.0.0`
- Distribution version: `$($row.distribution_version)`
- Direct semantic basis: MIR `$($row.predecessor)`
- Candidate role: $admission

## Player product

This candidate preserves the target-local technology IDs, settings, research behavior, migrations, runtime state, compatibility dispositions, and capability omissions of its named MIR 3 predecessor. MIR 4 qualification separately proves deterministic packaging, exact-engine load, direct upgrade where applicable, and reload/state continuity.

MIR handles a subject only when certified, otherwise it preserves the subject, requests an extension or review, omits it with evidence, or fails hard safety with a witness. New automatically inferred gameplay families remain diagnose-only in 4.0.

## Developer platform

API/SDK V0, MEP V0, the reference extension, Inspector, target-provider projections, normalized compiler shadow, runtime/state inventory, ProcessIR, and autonomous opportunity reports are separate GitHub preview assets. They are deliberately absent from this player ZIP and are not Mod Portal payloads.

## Support snapshot

When reporting a problem, include this distribution version, Factorio version, active mod list, startup settings, and a save or minimal reproduction where possible. Developer tooling can export a read-only MIR support snapshot.
"@
}

function Get-PresentationChangelog($row,[string]$existing){
  $bridge=if($row.target_key-eq'f018'){"`n    - Added a private 0.18 metadata bridge from the 0.17 terminal package; this is not a public compatibility or upgrade claim."}else{''}
  return @"
---------------------------------------------------------------------------------------------------
Version: $($row.distribution_version)
Date: 2026-08-18

  Major Features:

    - Established the MIR 4.0 source identity for the $($row.target_key) Factorio $($row.factorio_line) distribution.
    - Preserved the exact target-local gameplay semantics of predecessor $($row.predecessor).
    - Added target-aware player documentation while keeping all developer-preview and governance assets outside the mod package.$bridge

  Compatibility:

    - Preserved technology IDs, settings, migrations, research progress, and runtime state owned by the predecessor.
    - Kept newly inferred automatic support diagnose-only until subject and target proof exists.

$existing
"@
}

function Test-PresentationCandidate($row,[string]$InputPath,[string]$CandidatePath){
  $a=Get-MIR4ArchiveInventory -Path $InputPath;$b=Get-MIR4ArchiveInventory -Path $CandidatePath
  $aNames=@($a.entries.path);$bNames=@($b.entries.path)
  if(@(Compare-Object -ReferenceObject $aNames -DifferenceObject $bNames).Count-ne 0){throw "[mir4-presentation-surface] $($row.target_key)"}
  foreach($name in $aNames){if($name-in@('README.md','changelog.txt')){continue};$left=$a.entries|Where-Object path -eq $name;$right=$b.entries|Where-Object path -eq $name;if($left.sha256-cne$right.sha256){throw "[mir4-presentation-noninterference] $($row.target_key):$name"}}
  foreach($name in @('README.md','changelog.txt')){$left=$a.entries|Where-Object path -eq $name;$right=$b.entries|Where-Object path -eq $name;if($left.sha256-ceq$right.sha256){throw "[mir4-presentation-absent] $($row.target_key):$name"}}
  return $b
}

$manifestRows=@()
foreach($row in $authority.targets){
  $hashes=@();$inventory=$null
  foreach($letter in @('A','B','C')){
    $input=Join-Path $RepoRoot "$($row.input_root)/$letter/more-infinite-research_$($row.distribution_version).zip"
    $candidate=Join-Path $outputRoot "candidates/$($row.target_key)/$letter/more-infinite-research_$($row.distribution_version).zip"
    if(-not(Test-Path -LiteralPath $input -PathType Leaf)){throw "[mir4-presentation-input] $input"}
    if(-not $Check){
      $work=Join-Path $outputRoot "work/$($row.target_key)-$letter"
      Expand-MIR4SafeArchive -ArchivePath $input -Destination $work -OutputRoot $outputRoot
      $sourceRoot=Join-Path $work "more-infinite-research_$($row.distribution_version)"
      [IO.File]::WriteAllText((Join-Path $sourceRoot 'README.md'),(Get-PresentationReadme $row).Replace("`r`n","`n"),[Text.UTF8Encoding]::new($false))
      $existing=[IO.File]::ReadAllText((Join-Path $sourceRoot 'changelog.txt'))
      [IO.File]::WriteAllText((Join-Path $sourceRoot 'changelog.txt'),(Get-PresentationChangelog $row $existing).Replace("`r`n","`n"),[Text.UTF8Encoding]::new($false))
      Write-MIR4DeterministicArchive -SourceRoot $sourceRoot -EntryRoot "more-infinite-research_$($row.distribution_version)" -OutputPath $candidate -ContainmentRoot $outputRoot
      Remove-MIR4BuildTree -OutputRoot $outputRoot -Path $work
    }
    $inventory=Test-PresentationCandidate $row $input $candidate
    $hashes+=(Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash
  }
  if(@($hashes|Sort-Object -Unique).Count-ne 1){throw "[mir4-presentation-nondeterministic] $($row.target_key)"}
  $distribution=Join-Path $outputRoot "distributions/more-infinite-research_$($row.distribution_version).zip"
  if(-not $Check){New-Item -ItemType Directory -Force -Path (Split-Path $distribution -Parent)|Out-Null;Copy-Item -LiteralPath (Join-Path $outputRoot "candidates/$($row.target_key)/A/more-infinite-research_$($row.distribution_version).zip") -Destination $distribution -Force}
  if((Get-FileHash -LiteralPath $distribution -Algorithm SHA256).Hash-cne$hashes[0]){throw "[mir4-presentation-distribution] $($row.target_key)"}
  $manifestRows+=[ordered]@{target_key=[string]$row.target_key;factorio_line=[string]$row.factorio_line;role=[string]$row.role;version=[string]$row.distribution_version;predecessor=[string]$row.predecessor;sha256=$hashes[0];bytes=(Get-Item $distribution).Length;entries=$inventory.entry_count;status='built-unqualified-m4c01-candidate'}
}
$manifest=[pscustomobject][ordered]@{schema=1;kind='MIR4M4C01PlayerCandidateSetV1';source_version='4.0.0';candidate_wave='M4C01';status='built-unqualified';targets=$manifestRows;public_output_authorized=$false;record_sha256=''}
$manifest.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $manifest
$manifestPath=Join-Path $outputRoot 'candidate-set.json'
if($Check){$existing=Get-Content -Raw -LiteralPath $manifestPath|ConvertFrom-Json -Depth 50;if(-not(Test-MIR4BootstrapRecordHash -Record $existing)){throw '[mir4-presentation-manifest-hash]'};if((ConvertTo-MIR4BootstrapCanonicalJson $existing)-cne(ConvertTo-MIR4BootstrapCanonicalJson $manifest)){throw '[mir4-presentation-manifest-stale]'}}else{Write-MIR4BootstrapRecord -Path $manifestPath -Record $manifest}
$manifest|ConvertTo-Json -Depth 20
