# Read the consumed parameter and default-path expressions without executing a
# sweep, acquiring archives, changing power settings or launching Factorio.
function Test-MIRNativeEntryDefaults {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $count = 0
  $repo = $RepoRoot
  foreach ($relative in @('scripts/Invoke-MIRExtendedTests.ps1','scripts/Start-MIROvernightLocalSweep.ps1')) {
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $RepoRoot $relative),[ref]$tokens,[ref]$errors)
    if ($errors.Count -or $null -eq $ast.ParamBlock) { throw "[mir-native-entry-parse] $relative" }
    $parameters=[scriptblock]::Create($ast.ParamBlock.Extent.Text + "`nreturn `$LinkMode")
    if ((& $parameters) -cne 'Hardlink') { throw "[mir-native-entry-link-default] $relative" }
    $count++
    foreach ($mode in @('Copy','Symlink')) {
      $refused=$false
      try { & $parameters -LinkMode $mode | Out-Null }
      catch { $refused=$_.FullyQualifiedErrorId -like 'ParameterArgumentValidationError*' }
      if (-not $refused) { throw "[mir-native-entry-link-mode] $relative/$mode" }
      $count++
    }
  }
  foreach ($entry in @(
    @{path='scripts/Start-MIROvernightLocalSweep.ps1';variable='$LocalModDir'},
    @{path='scripts/Invoke-MIRReleaseTargetedGate.ps1';variable='$LocalModDir'},
    @{path='scripts/Invoke-MIRPerformanceQualification.ps1';variable='$LocalModZipDir'},
    @{path='tools/lib/assurance/Core.ps1';variable='$defaultMods'}
  )) {
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $RepoRoot $entry.path),[ref]$tokens,[ref]$errors)
    if ($errors.Count) { throw "[mir-native-entry-parse] $($entry.path)" }
    $assignments=@($ast.FindAll({param($node)
      $node -is [Management.Automation.Language.AssignmentStatementAst] -and
      $node.Left.Extent.Text -ceq $entry.variable -and
      $node.Right.Extent.Text -match '^Join-Path \(Split-Path -Parent'
    },$true))
    if ($assignments.Count -ne 1) { throw "[mir-native-entry-library-definition] $($entry.path)" }
    foreach ($FactorioLine in @('2.0','2.1')) {
      $target=$FactorioLine
      $actual=& ([scriptblock]::Create($assignments[0].Extent.Text + "`nreturn " + $entry.variable))
      $expected=Join-Path (Split-Path -Parent $RepoRoot) "testmods/$FactorioLine"
      if ($actual -cne $expected) { throw "[mir-native-entry-library-default] $($entry.path)/$FactorioLine" }
      $count++
    }
    $text=[IO.File]::ReadAllText((Join-Path $RepoRoot $entry.path))
    if ($text -match 'testmods_\$(?:FactorioLine|target)') { throw "[mir-native-entry-retired-library-fallback] $($entry.path)" }
    $count++
  }
  $tokens=$null; $errors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $RepoRoot 'scripts/Measure-MIRPerformanceRegression.ps1'),[ref]$tokens,[ref]$errors)
  if ($errors.Count -or $null -eq $ast.ParamBlock) { throw '[mir-native-entry-performance-parse]' }
  $parameters=[scriptblock]::Create($ast.ParamBlock.Extent.Text + "`nreturn `$LocalModZipDir")
  if (-not [string]::IsNullOrWhiteSpace((& $parameters -RepoRoot $RepoRoot -ExpectedSourceCommit ('1' * 40)))) {
    throw '[mir-native-entry-performance-library-parameter]'
  }
  $count++
  $defaults=@($ast.FindAll({param($node)
    $node -is [Management.Automation.Language.IfStatementAst] -and
    $node.Clauses[0].Item1.Extent.Text -ceq '[string]::IsNullOrWhiteSpace($LocalModZipDir)'
  },$true))
  if ($defaults.Count -ne 1) { throw '[mir-native-entry-performance-library-definition]' }
  foreach ($line in @('2.0','2.1')) {
    $campaign=[pscustomobject]@{factorio_line=$line}
    $LocalModZipDir=''
    $actual=& ([scriptblock]::Create($defaults[0].Extent.Text + "`nreturn `$LocalModZipDir"))
    $expected=Join-Path (Split-Path -Parent $RepoRoot) "testmods/$line"
    if ($actual -cne $expected) { throw "[mir-native-entry-performance-library-default] $line" }
    $count++
    $LocalModZipDir=Join-Path $RepoRoot 'build/private-library-control'
    $actual=& ([scriptblock]::Create($defaults[0].Extent.Text + "`nreturn `$LocalModZipDir"))
    if ($actual -cne $LocalModZipDir) { throw "[mir-native-entry-performance-library-override] $line" }
    $count++
  }
  $tokens=$null; $errors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $RepoRoot 'scripts/Start-MIROvernightLocalSweep.ps1'),[ref]$tokens,[ref]$errors)
  $definitions=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Resolve-MIRFactorioBinary'},$true))
  if ($definitions.Count -ne 1) { throw '[mir-native-entry-engine-definition]' }
  . ([scriptblock]::Create($definitions[0].Extent.Text))
  $expectedEngines=@{
    '2.0'='D:\Programs\Factorio\2.0\bin\x64\factorio.exe'
    '2.1'='C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe'
  }
  # Both controlled paths exist, so accidentally selecting Steam for F200
  # fails independently of which engines are installed on this test host.
  function Test-Path { param([string]$LiteralPath) return $LiteralPath -cin @($expectedEngines.Values) }
  function Resolve-Path { param([string]$LiteralPath) return [pscustomobject]@{Path=$LiteralPath} }
  foreach ($FactorioLine in @('2.0','2.1')) {
    if ((Resolve-MIRFactorioBinary -Path '') -cne $expectedEngines[$FactorioLine]) { throw "[mir-native-entry-engine-default] $FactorioLine" }
    $count++
  }
  [pscustomobject]@{status='passed-native-entry-defaults';assertions=$count;factorio_processes=0;profiles_created=0;dependency_archive_payload_bytes_copied=0;engine_resolution='controlled-paths-only'}
}
