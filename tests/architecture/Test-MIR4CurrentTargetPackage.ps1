param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/CurrentTargetPackage.ps1')

foreach ($target in @('f210','f200','f110','f100')) {
  $context = New-MIR4CurrentTargetPackageContext -RepoRoot $repo -Target $target
  if ($context.outputs.Count -eq 0 -or $context.package_source_sha256 -notmatch '^[A-F0-9]{64}$') {
    throw "[mir4-current-target-package-empty] $target"
  }
  foreach ($required in @('info.json','settings.lua','data.lua','data-updates.lua','data-final-fixes.lua','control.lua')) {
    $path = Resolve-MIR4CurrentTargetPackageOutputPath -Context $context -RelativePath $required
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or -not $path.StartsWith((Join-Path $repo 'source'), [StringComparison]::OrdinalIgnoreCase)) {
      throw "[mir4-current-target-package-source-boundary] $target $required"
    }
  }
  if ($null -ne (Resolve-MIR4CurrentTargetPackageOutputPath -Context $context -RelativePath 'prototypes/mir/not-declared.lua' -AllowMissing)) {
    throw "[mir4-current-target-package-root-fallback] $target"
  }
}

# Angel Smelting performs supported F200 Bob/Angel recipe rewrites in its
# data-final-fixes stage. The hidden optional edge is therefore a package-load
# ordering contract, not a user-facing required/recommended dependency. Keep
# the edge target-specific until an independent F210 case establishes it.
$f200Context = New-MIR4CurrentTargetPackageContext -RepoRoot $repo -Target 'f200'
$f200Info = Get-MIR4CurrentTargetPackageOutputText -Context $f200Context -RelativePath 'info.json' | ConvertFrom-Json
$f210Context = New-MIR4CurrentTargetPackageContext -RepoRoot $repo -Target 'f210'
$f210Info = Get-MIR4CurrentTargetPackageOutputText -Context $f210Context -RelativePath 'info.json' | ConvertFrom-Json
if (@($f200Info.dependencies | Where-Object { [string]$_ -ceq '(?) angelssmelting' }).Count -ne 1) {
  throw '[mir4-current-target-package-f200-angelssmelting-ordering]'
}
if (@($f210Info.dependencies | Where-Object { [string]$_ -ceq '(?) angelssmelting' }).Count -ne 0) {
  throw '[mir4-current-target-package-f210-unsupported-angelssmelting-ordering]'
}

# The former repository-root player projection has no current source or test
# authority.  Package-shaped paths belong only to source plus a selected
# composition (or to pinned historical Git/archive readers outside this test).
foreach ($retiredRoot in @(
  'info.json', 'changelog.txt', 'thumbnail.png',
  'settings.lua', 'data.lua', 'data-updates.lua', 'data-final-fixes.lua', 'control.lua',
  'prototypes', 'locale', 'migrations'
)) {
  if (Test-Path -LiteralPath (Join-Path $repo $retiredRoot)) {
    throw "[mir4-current-target-package-retired-root-present] $retiredRoot"
  }
}

# Current validation is allowed to inspect the repository's governance and
# tooling, but must obtain every player-package path through the explicit
# target context.  Scan all executable current-tool surfaces by default: a
# hand-maintained list would let a new reader restore the retired root
# projection unnoticed.  The two exceptions below deliberately operate on an
# immutable historical reconstruction, never this checkout; each is tagged at
# the read site and must retain its named proof mechanism.
$historicalReaderExceptions = @{
  'scripts/Invoke-MIRBackportQualification.ps1' = [pscustomobject]@{
    marker = 'MIR4-ROOT-PROJECTION-HISTORICAL-EXCEPTION: backport-source-historical-root-v1'
    proof = 'Assert-MIRBackportHistoricalSourceRoot'
  }
  'tools/commands/release/Invoke-MIR4BootstrapCapsule.ps1' = [pscustomobject]@{
    marker = 'MIR4-ROOT-PROJECTION-HISTORICAL-EXCEPTION: bootstrap-capsule-historical-root-v1'
    proof = 'Assert-MIR4GitSourceProof'
  }
}

function Get-MIR4RootReaderVariableName {
  param($Ast)
  if ($Ast -is [System.Management.Automation.Language.VariableExpressionAst]) {
    return $Ast.VariablePath.UserPath.ToLowerInvariant()
  }
  return $null
}

function Get-MIR4RootReaderExpressionValues {
  param($Ast,[hashtable]$Facts)
  $values = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  # Resolve only a constant expression or a plain variable/alias expression.
  # Recursively collecting every literal below a command incorrectly treats
  # an argument such as `-RelativePath 'info.json'` as the command's return
  # value, then taints unrelated variables with the same name in other
  # functions. Member access and interpolated values likewise describe data,
  # not a literal repository-relative package path.
  try {
    $constant = $Ast.SafeGetValue()
    foreach ($value in @($constant)) {
      if ($value -is [string]) { [void]$values.Add([string]$value) }
    }
  } catch {}
  $hasNonAliasExpression = $null -ne $Ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.CommandAst] -or
      $node -is [System.Management.Automation.Language.MemberExpressionAst] -or
      $node -is [System.Management.Automation.Language.ExpandableStringExpressionAst]
  }, $true)
  if (-not $hasNonAliasExpression) {
    foreach ($literal in @($Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true))) {
      [void]$values.Add([string]$literal.Value)
    }
    foreach ($variable in @($Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.VariableExpressionAst] }, $true))) {
      $name = Get-MIR4RootReaderVariableName -Ast $variable
      if ($name -and $Facts.ContainsKey($name)) {
        foreach ($value in @($Facts[$name])) { [void]$values.Add([string]$value) }
      }
    }
  }
  return @($values)
}

function Test-MIR4RetiredPackagePathValue {
  param([string]$Value)
  $portable = $Value.Replace('\', '/').TrimStart('/')
  return $portable -in @('info.json','changelog.txt','thumbnail.png','settings.lua','data.lua','data-updates.lua','data-final-fixes.lua','control.lua') -or
    $portable.StartsWith('prototypes/', [StringComparison]::OrdinalIgnoreCase) -or
    $portable.StartsWith('locale/', [StringComparison]::OrdinalIgnoreCase) -or
    $portable.StartsWith('migrations/', [StringComparison]::OrdinalIgnoreCase)
}

function Get-MIR4RootReaderJoinPathValues {
  param($CommandAst,[string[]]$RootVariables,[hashtable]$Facts)
  $elements = @($CommandAst.CommandElements)
  if ($elements.Count -lt 3 -or [string]$elements[0].Extent.Text -notmatch '^(?i:Join-Path)$') { return @() }
  for ($index = 1; $index -lt $elements.Count; $index++) {
    $name = Get-MIR4RootReaderVariableName -Ast $elements[$index]
    if ($name -notin $RootVariables) { continue }
    for ($childIndex = $index + 1; $childIndex -lt $elements.Count; $childIndex++) {
      if ($elements[$childIndex] -is [System.Management.Automation.Language.CommandParameterAst]) { continue }
      return @(Get-MIR4RootReaderExpressionValues -Ast $elements[$childIndex] -Facts $Facts)
    }
  }
  return @()
}

function Get-MIR4RootReaderScopeKey {
  param([Parameter(Mandatory)]$Ast)
  $cursor = $Ast
  while ($null -ne $cursor) {
    if ($cursor -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
      return "function:$($cursor.Name):$($cursor.Extent.StartOffset)"
    }
    $cursor = $cursor.Parent
  }
  return 'script'
}

function Get-MIR4RetiredRootReaderViolations {
  param([Parameter(Mandatory)][string]$ScriptPath)
  $tokens = $null
  $parseErrors = $null
  $ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$parseErrors)
  if (@($parseErrors).Count -ne 0) { throw "[mir4-current-target-package-reader-parse] $ScriptPath" }
  $assignments = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true))
  $assignmentData = @(
    foreach ($assignment in $assignments) {
      [pscustomobject]@{
        ast = $assignment
        scope = Get-MIR4RootReaderScopeKey -Ast $assignment
        name = Get-MIR4RootReaderVariableName -Ast $assignment.Left
        literals = @(Get-MIR4RootReaderExpressionValues -Ast $assignment.Right -Facts @{})
        references = @(
          $assignment.Right.FindAll({ param($node) $node -is [System.Management.Automation.Language.VariableExpressionAst] }, $true) |
            ForEach-Object { Get-MIR4RootReaderVariableName -Ast $_ } |
            Where-Object { $_ } |
            Sort-Object -Unique
        )
      }
    }
  )
  $scopeKeys = @(
    @($assignmentData | ForEach-Object { [string]$_.scope }) +
    @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -or $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -or $node -is [System.Management.Automation.Language.ForEachStatementAst] }, $true) |
      ForEach-Object { Get-MIR4RootReaderScopeKey -Ast $_ }) |
      Sort-Object -Unique
  )
  $factsByScope = @{}
  $rootVariablesByScope = @{}
  $taintedPathVariablesByScope = @{}
  foreach ($scope in $scopeKeys) {
    $scopeAssignments = @($assignmentData | Where-Object scope -ceq $scope)
    $facts = @{}
    foreach ($entry in $scopeAssignments) {
      if (-not $entry.name) { continue }
      $facts[$entry.name] = @(@($facts[$entry.name]) + $entry.literals | Sort-Object -Unique)
    }
    for ($iteration = 0; $iteration -lt 4; $iteration++) {
      $changed = $false
      foreach ($entry in $scopeAssignments) {
        if (-not $entry.name) { continue }
        $next = @(@($facts[$entry.name]) + $entry.literals + @($entry.references | ForEach-Object { @($facts[$_]) }) | Sort-Object -Unique)
        if ((@($facts[$entry.name]) -join "`n") -cne ($next -join "`n")) { $facts[$entry.name] = $next; $changed = $true }
      }
      foreach ($foreachAst in @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.ForEachStatementAst] }, $true) | Where-Object { (Get-MIR4RootReaderScopeKey -Ast $_) -ceq $scope })) {
        $name = Get-MIR4RootReaderVariableName -Ast $foreachAst.Variable
        if (-not $name) { continue }
        $next = @(@($facts[$name]) + @(Get-MIR4RootReaderExpressionValues -Ast $foreachAst.Condition -Facts $facts) | Sort-Object -Unique)
        if ((@($facts[$name]) -join "`n") -cne ($next -join "`n")) { $facts[$name] = $next; $changed = $true }
      }
      if (-not $changed) { break }
    }
    $rootVariables = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($name in @('repo','repoRoot','repository','root','workspace')) { [void]$rootVariables.Add($name) }
    for ($iteration = 0; $iteration -lt 4; $iteration++) {
      $changed = $false
      foreach ($entry in $scopeAssignments) {
        $hasCommand = $null -ne $entry.ast.Right.Find({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
        if ($entry.name -and -not $hasCommand -and $entry.literals.Count -eq 0 -and $entry.references.Count -eq 1 -and $rootVariables.Contains($entry.references[0])) {
          $changed = $rootVariables.Add($entry.name) -or $changed
        }
      }
      if (-not $changed) { break }
    }
    $factsByScope[$scope] = $facts
    $rootVariablesByScope[$scope] = @($rootVariables)
    $taintedPathVariablesByScope[$scope] = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  }
  foreach ($assignment in $assignments) {
    $scope = Get-MIR4RootReaderScopeKey -Ast $assignment
    $facts = $factsByScope[$scope]
    $rootVariableArray = $rootVariablesByScope[$scope]
    $taintedPathVariables = $taintedPathVariablesByScope[$scope]
    $name = Get-MIR4RootReaderVariableName -Ast $assignment.Left
    if (-not $name) { continue }
    foreach ($join in @($assignment.Right.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))) {
      if (@(Get-MIR4RootReaderJoinPathValues -CommandAst $join -RootVariables $rootVariableArray -Facts $facts | Where-Object { Test-MIR4RetiredPackagePathValue $_ }).Count -gt 0) {
        [void]$taintedPathVariables.Add($name)
      }
    }
  }
  $readerCommands = @('get-content','get-item','import-powershelldatafile','copy-item','move-item','remove-item','set-content','add-content','out-file')
  $violations = [Collections.Generic.List[string]]::new()
  foreach ($reader in @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))) {
    if ([string]$reader.GetCommandName() -notin $readerCommands) { continue }
    $scope = Get-MIR4RootReaderScopeKey -Ast $reader
    $facts = $factsByScope[$scope]
    $rootVariableArray = $rootVariablesByScope[$scope]
    $taintedPathVariables = $taintedPathVariablesByScope[$scope]
    $directValues = @(
      $reader.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) |
        ForEach-Object { Get-MIR4RootReaderJoinPathValues -CommandAst $_ -RootVariables $rootVariableArray -Facts $facts }
    )
    $variableValues = @(
      $reader.CommandElements |
        ForEach-Object { Get-MIR4RootReaderVariableName -Ast $_ } |
        Where-Object { $_ -and $taintedPathVariables.Contains($_) }
    )
    if (@($directValues | Where-Object { Test-MIR4RetiredPackagePathValue $_ }).Count -gt 0 -or $variableValues.Count -gt 0) {
      $violations.Add("$($reader.Extent.StartLineNumber):$($reader.Extent.Text)")
    }
  }
  foreach ($reader in @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] }, $true))) {
    $member = [string]$reader.Member.Extent.Text
    if ($member -notin @('ReadAllText','ReadAllBytes','OpenRead','Open')) { continue }
    $scope = Get-MIR4RootReaderScopeKey -Ast $reader
    $facts = $factsByScope[$scope]
    $rootVariableArray = $rootVariablesByScope[$scope]
    $taintedPathVariables = $taintedPathVariablesByScope[$scope]
    $directValues = @(
      $reader.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) |
        ForEach-Object { Get-MIR4RootReaderJoinPathValues -CommandAst $_ -RootVariables $rootVariableArray -Facts $facts }
    )
    $variableValues = @($reader.Arguments | ForEach-Object { Get-MIR4RootReaderVariableName -Ast $_ } | Where-Object { $_ -and $taintedPathVariables.Contains($_) })
    if (@($directValues | Where-Object { Test-MIR4RetiredPackagePathValue $_ }).Count -gt 0 -or $variableValues.Count -gt 0) {
      $violations.Add("$($reader.Extent.StartLineNumber):$($reader.Extent.Text)")
    }
  }
  return @($violations | Sort-Object -Unique)
}

$dynamicRootCounterexamples = @(@'
$candidatePath = 'info.json'
$readPath = Join-Path $repo $candidatePath
Get-Content -LiteralPath $readPath
'@, @'
$readPath = Join-Path $repo 'prototypes\mir\obsolete.lua'
[IO.File]::ReadAllText($readPath)
'@)
foreach ($dynamicRootCounterexample in $dynamicRootCounterexamples) {
  $dynamicRootTokens = $null
  $dynamicRootErrors = $null
  $dynamicRootAst = [System.Management.Automation.Language.Parser]::ParseInput($dynamicRootCounterexample, [ref]$dynamicRootTokens, [ref]$dynamicRootErrors)
  if (@($dynamicRootErrors).Count -ne 0) { throw '[mir4-current-target-package-dynamic-root-reader-guard-invalid]' }
  $dynamicRootPath = Join-Path ([IO.Path]::GetTempPath()) ("mir4-current-target-package-guard-$([Guid]::NewGuid().ToString('N')).ps1")
  try {
    [IO.File]::WriteAllText($dynamicRootPath, $dynamicRootCounterexample, [Text.UTF8Encoding]::new($false))
    if (@(Get-MIR4RetiredRootReaderViolations -ScriptPath $dynamicRootPath).Count -ne 1) {
      throw '[mir4-current-target-package-dynamic-root-reader-guard-invalid]'
    }
  } finally {
    if (Test-Path -LiteralPath $dynamicRootPath) { Remove-Item -LiteralPath $dynamicRootPath -Force }
  }
}
$toolRoots = @('scripts', 'tests', 'tools')
foreach ($toolRoot in $toolRoots) {
  $toolPath = Join-Path $repo $toolRoot
  if (-not (Test-Path -LiteralPath $toolPath -PathType Container)) { continue }
  Get-ChildItem -LiteralPath $toolPath -Recurse -File -Filter '*.ps1' | ForEach-Object {
    $relative = [IO.Path]::GetRelativePath($repo, $_.FullName).Replace('\', '/')
    $text = Get-Content -Raw -LiteralPath $_.FullName
    if ($text -notmatch '(?i)(?:info|changelog|thumbnail|settings|data(?:-updates|-final-fixes)?|control|prototypes|locale|migrations)') { return }
    $violations = @(Get-MIR4RetiredRootReaderViolations -ScriptPath $_.FullName)
    if ($violations.Count -eq 0) { return }
    $exception = $historicalReaderExceptions[$relative]
    if ($null -eq $exception) {
      throw "[mir4-current-target-package-raw-root-reader] $relative :: $($violations -join '; ')"
    }
    if ($text -notmatch [regex]::Escape([string]$exception.marker) -or
        $text -notmatch [regex]::Escape([string]$exception.proof)) {
      throw "[mir4-current-target-package-historical-reader-ungoverned] $relative"
    }
  }
}

Write-Host '[ok] current validators resolve every player package path through source/composition target authority.'
