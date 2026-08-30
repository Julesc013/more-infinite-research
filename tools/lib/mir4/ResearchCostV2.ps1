Set-StrictMode -Version Latest

$script:MIR4ResearchCostV2Schema = 2
$script:MIR4ResearchCostV2Abi = 'mir-research-cost-v2-preview'
$script:MIR4ResearchCostV2Rounding = 'round-half-up-positive-final-v1'

function ConvertTo-MIR4BigInteger {
  param(
    [Parameter(Mandatory)]$Value,
    [string]$Field = 'integer'
  )

  $text = [string]$Value
  if ($text -notmatch '^(0|[1-9][0-9]{0,127})$') {
    throw "research_cost_v2_invalid_${Field}:$text"
  }
  return [System.Numerics.BigInteger]::Parse(
    $text,
    [Globalization.CultureInfo]::InvariantCulture
  )
}

function Get-MIR4BigIntegerGcd {
  param(
    [Parameter(Mandatory)][System.Numerics.BigInteger]$Left,
    [Parameter(Mandatory)][System.Numerics.BigInteger]$Right
  )

  while ($Right -ne [System.Numerics.BigInteger]::Zero) {
    $remainder = [System.Numerics.BigInteger]::Remainder($Left, $Right)
    $Left = $Right
    $Right = $remainder
  }
  return $Left
}

function New-MIR4Rational {
  param(
    [Parameter(Mandatory)]$Numerator,
    $Denominator = '1'
  )

  $n = ConvertTo-MIR4BigInteger -Value $Numerator -Field numerator
  $d = ConvertTo-MIR4BigInteger -Value $Denominator -Field denominator
  if ($d -eq [System.Numerics.BigInteger]::Zero) {
    throw 'research_cost_v2_zero_denominator'
  }
  $gcd = Get-MIR4BigIntegerGcd -Left $n -Right $d
  return [pscustomobject][ordered]@{
    numerator = ([System.Numerics.BigInteger]::Divide($n, $gcd)).ToString()
    denominator = ([System.Numerics.BigInteger]::Divide($d, $gcd)).ToString()
  }
}

function ConvertTo-MIR4Rational {
  param(
    [Parameter(Mandatory)]$Value,
    [string]$Field = 'rational'
  )

  if ($Value -is [string] -and $Value -match '^(0|[1-9][0-9]{0,127})/([1-9][0-9]{0,127})$') {
    return New-MIR4Rational -Numerator $Matches[1] -Denominator $Matches[2]
  }
  if ($Value -is [string] -or $Value -is [int] -or $Value -is [long] -or
      $Value -is [System.Numerics.BigInteger]) {
    return New-MIR4Rational -Numerator $Value
  }
  if ($null -ne $Value -and $null -ne $Value.PSObject.Properties['numerator'] -and
      $null -ne $Value.PSObject.Properties['denominator']) {
    return New-MIR4Rational -Numerator $Value.numerator -Denominator $Value.denominator
  }
  throw "research_cost_v2_invalid_${Field}"
}

function Add-MIR4Rational {
  param([Parameter(Mandatory)]$Left, [Parameter(Mandatory)]$Right)

  $a = ConvertTo-MIR4Rational $Left
  $b = ConvertTo-MIR4Rational $Right
  $an = ConvertTo-MIR4BigInteger $a.numerator
  $ad = ConvertTo-MIR4BigInteger $a.denominator
  $bn = ConvertTo-MIR4BigInteger $b.numerator
  $bd = ConvertTo-MIR4BigInteger $b.denominator
  return New-MIR4Rational -Numerator (($an * $bd) + ($bn * $ad)) -Denominator ($ad * $bd)
}

function Multiply-MIR4Rational {
  param([Parameter(Mandatory)]$Left, [Parameter(Mandatory)]$Right)

  $a = ConvertTo-MIR4Rational $Left
  $b = ConvertTo-MIR4Rational $Right
  return New-MIR4Rational `
    -Numerator ((ConvertTo-MIR4BigInteger $a.numerator) * (ConvertTo-MIR4BigInteger $b.numerator)) `
    -Denominator ((ConvertTo-MIR4BigInteger $a.denominator) * (ConvertTo-MIR4BigInteger $b.denominator))
}

function Get-MIR4RationalPower {
  param(
    [Parameter(Mandatory)]$Value,
    [Parameter(Mandatory)][ValidateRange(0, 1000)][int]$Exponent
  )

  $result = New-MIR4Rational 1
  $factor = ConvertTo-MIR4Rational $Value
  for ($index = 0; $index -lt $Exponent; $index++) {
    $result = Multiply-MIR4Rational $result $factor
  }
  return $result
}

function Compare-MIR4Rational {
  param([Parameter(Mandatory)]$Left, [Parameter(Mandatory)]$Right)

  $a = ConvertTo-MIR4Rational $Left
  $b = ConvertTo-MIR4Rational $Right
  $crossLeft = (ConvertTo-MIR4BigInteger $a.numerator) * (ConvertTo-MIR4BigInteger $b.denominator)
  $crossRight = (ConvertTo-MIR4BigInteger $b.numerator) * (ConvertTo-MIR4BigInteger $a.denominator)
  return $crossLeft.CompareTo($crossRight)
}

function ConvertTo-MIR4RoundedInteger {
  param([Parameter(Mandatory)]$Value)

  $rational = ConvertTo-MIR4Rational $Value
  $n = ConvertTo-MIR4BigInteger $rational.numerator
  $d = ConvertTo-MIR4BigInteger $rational.denominator
  $quotient = [System.Numerics.BigInteger]::Divide($n, $d)
  $remainder = [System.Numerics.BigInteger]::Remainder($n, $d)
  if (($remainder * 2) -ge $d) { $quotient += [System.Numerics.BigInteger]::One }
  return $quotient.ToString()
}

function Get-MIR4ResearchCostV2TextSha256 {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
    return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '')
  } finally {
    $sha.Dispose()
  }
}

function Get-MIR4ResearchCostNodeMap {
  param([Parameter(Mandatory)]$Snapshot)

  $map = @{}
  foreach ($node in @($Snapshot.nodes)) {
    $id = [string]$node.id
    if ($id -notmatch '^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$') {
      throw "research_cost_v2_invalid_node_id:$id"
    }
    if ($map.ContainsKey($id)) { throw "research_cost_v2_duplicate_node:$id" }
    $map[$id] = $node
  }
  return $map
}

function Find-MIR4ResearchCostCycleVisit {
  param(
    [Parameter(Mandatory)][string]$Id,
    [Parameter(Mandatory)][hashtable]$Map,
    [Parameter(Mandatory)][hashtable]$State,
    [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[string]]$Stack,
    [Parameter(Mandatory)][hashtable]$StackIndex
  )

  if ($State[$Id] -eq 1) {
    $cycle = @()
    for ($index = [int]$StackIndex[$Id]; $index -lt $Stack.Count; $index++) {
      $cycle += $Stack[$index]
    }
    $cycle += $Id
    return ,$cycle
  }
  if ($State[$Id] -eq 2) { return $null }
  if (-not $Map.ContainsKey($Id)) { throw "research_cost_v2_missing_node:$Id" }

  $State[$Id] = 1
  $StackIndex[$Id] = $Stack.Count
  $Stack.Add($Id)
  foreach ($prerequisite in @($Map[$Id].prerequisites) | ForEach-Object { [string]$_ } | Sort-Object -Unique) {
    $witness = Find-MIR4ResearchCostCycleVisit -Id $prerequisite -Map $Map `
      -State $State -Stack $Stack -StackIndex $StackIndex
    if ($null -ne $witness) { return ,@($witness) }
  }
  $Stack.RemoveAt($Stack.Count - 1)
  $StackIndex.Remove($Id)
  $State[$Id] = 2
  return $null
}

function Find-MIR4ResearchCostCycle {
  param([Parameter(Mandatory)][string]$TargetId, [Parameter(Mandatory)][hashtable]$Map)

  $state = @{}
  $stack = [Collections.Generic.List[string]]::new()
  $stackIndex = @{}
  $witness = Find-MIR4ResearchCostCycleVisit -Id $TargetId -Map $Map `
    -State $state -Stack $stack -StackIndex $stackIndex
  if ($null -eq $witness) { return $null }
  return ,@($witness)
}

function Resolve-MIR4ResearchCostAnchorV2 {
  param(
    [Parameter(Mandatory)][ValidateSet('absolute', 'previous-series-level', 'direct-prerequisite-sum', 'transitive-prerequisite-closure', 'profile-defined')][string]$BaseSource,
    [Parameter(Mandatory)][string]$TargetId,
    $Snapshot,
    $AbsoluteBase,
    $ProfileBase,
    [string]$PreviousSeriesId = ''
  )

  if ($BaseSource -eq 'absolute') {
    $anchor = ConvertTo-MIR4Rational -Value $AbsoluteBase -Field absolute_base
    return [pscustomobject][ordered]@{base_source=$BaseSource; anchor=$anchor; contributors=@(); cycle_witness=@()}
  }
  if ($BaseSource -eq 'profile-defined') {
    $anchor = ConvertTo-MIR4Rational -Value $ProfileBase -Field profile_base
    return [pscustomobject][ordered]@{base_source=$BaseSource; anchor=$anchor; contributors=@(); cycle_witness=@()}
  }

  $map = Get-MIR4ResearchCostNodeMap -Snapshot $Snapshot
  if (-not $map.ContainsKey($TargetId)) { throw "research_cost_v2_missing_target:$TargetId" }
  $cycle = Find-MIR4ResearchCostCycle -TargetId $TargetId -Map $map
  if ($null -ne $cycle) {
    throw ('research_cost_v2_graph_cycle:' + (@($cycle) -join '>'))
  }

  $contributorIds = @()
  if ($BaseSource -eq 'previous-series-level') {
    if ([string]::IsNullOrWhiteSpace($PreviousSeriesId) -or -not $map.ContainsKey($PreviousSeriesId)) {
      throw "research_cost_v2_missing_previous_series:$PreviousSeriesId"
    }
    $contributorIds = @($PreviousSeriesId)
  } elseif ($BaseSource -eq 'direct-prerequisite-sum') {
    $contributorIds = @($map[$TargetId].prerequisites | ForEach-Object { [string]$_ } | Sort-Object -Unique)
  } else {
    $seen = @{}
    $pending = [Collections.Generic.Queue[string]]::new()
    foreach ($id in @($map[$TargetId].prerequisites | ForEach-Object { [string]$_ } | Sort-Object -Unique)) {
      $pending.Enqueue($id)
    }
    while ($pending.Count -gt 0) {
      $id = $pending.Dequeue()
      if ($seen.ContainsKey($id)) { continue }
      if (-not $map.ContainsKey($id)) { throw "research_cost_v2_missing_node:$id" }
      $seen[$id] = $true
      foreach ($next in @($map[$id].prerequisites | ForEach-Object { [string]$_ } | Sort-Object -Unique)) {
        $pending.Enqueue($next)
      }
    }
    $contributorIds = @($seen.Keys | Sort-Object)
  }

  $contributors = @()
  $anchor = New-MIR4Rational 0
  foreach ($id in @($contributorIds | Sort-Object -Unique)) {
    if ($id -eq $TargetId) { throw "research_cost_v2_self_contributor:$TargetId" }
    $node = $map[$id]
    if ($node.generated_continuation -eq $true) { continue }
    $cost = ConvertTo-MIR4Rational -Value $node.realized_cost -Field "realized_cost_$id"
    $anchor = Add-MIR4Rational $anchor $cost
    $contributors += [pscustomobject][ordered]@{id=$id; realized_cost=$cost}
  }
  if ((Compare-MIR4Rational $anchor (New-MIR4Rational 1)) -lt 0) {
    throw 'research_cost_v2_anchor_below_one'
  }
  return [pscustomobject][ordered]@{
    base_source = $BaseSource
    anchor = $anchor
    contributors = @($contributors)
    cycle_witness = @()
  }
}

function New-MIR4ResearchCostModelV2 {
  param(
    [Parameter(Mandatory)]$AnchorResolution,
    [Parameter(Mandatory)][ValidateRange(1, 1000000)][int]$AnchorLevel,
    [Parameter(Mandatory)]$BaseMultiplier,
    [Parameter(Mandatory)]$LinearRatio,
    $AbsoluteLinearIncrement = '0',
    $GrowthFactor = '1',
    [hashtable]$Provenance = @{}
  )

  $anchor = ConvertTo-MIR4Rational $AnchorResolution.anchor
  $baseMultiplierValue = ConvertTo-MIR4Rational -Value $BaseMultiplier -Field base_multiplier
  $linearRatioValue = ConvertTo-MIR4Rational -Value $LinearRatio -Field linear_ratio
  $absoluteIncrementValue = ConvertTo-MIR4Rational -Value $AbsoluteLinearIncrement -Field absolute_linear_increment
  $growthValue = ConvertTo-MIR4Rational -Value $GrowthFactor -Field growth_factor
  if ((Compare-MIR4Rational $baseMultiplierValue (New-MIR4Rational 1)) -lt 0 -or
      (Compare-MIR4Rational $growthValue (New-MIR4Rational 1)) -lt 0) {
    throw 'research_cost_v2_requires_base_multiplier_and_growth_at_least_one'
  }

  $semantic = [ordered]@{
    schema = $script:MIR4ResearchCostV2Schema
    formula_abi = $script:MIR4ResearchCostV2Abi
    maturity = 'experimental-package-excluded'
    anchor_level = $AnchorLevel
    base_source = [string]$AnchorResolution.base_source
    prerequisite_anchor = $anchor
    base_multiplier = $baseMultiplierValue
    linear_ratio = $linearRatioValue
    absolute_linear_increment = $absoluteIncrementValue
    growth_factor = $growthValue
    rounding_law = $script:MIR4ResearchCostV2Rounding
    contributors = @($AnchorResolution.contributors)
  }
  $semanticJson = $semantic | ConvertTo-Json -Depth 100 -Compress
  $model = [ordered]@{}
  foreach ($key in $semantic.Keys) { $model[$key] = $semantic[$key] }
  $model.provenance = [pscustomobject]$Provenance
  $model.semantic_digest = 'sha256:' + (Get-MIR4ResearchCostV2TextSha256 $semanticJson).ToLowerInvariant()
  return [pscustomobject]$model
}

function Get-MIR4ResearchCostV2 {
  param(
    [Parameter(Mandatory)]$Model,
    [Parameter(Mandatory)][ValidateRange(1, 1000000)][int]$Level
  )

  if ([int]$Model.schema -ne $script:MIR4ResearchCostV2Schema -or
      [string]$Model.formula_abi -ne $script:MIR4ResearchCostV2Abi -or
      [string]$Model.rounding_law -ne $script:MIR4ResearchCostV2Rounding) {
    throw 'research_cost_v2_model_abi_mismatch'
  }
  $offset = $Level - [int]$Model.anchor_level
  if ($offset -lt 0 -or $offset -gt 1000) { throw 'research_cost_v2_level_out_of_range' }
  $anchor = ConvertTo-MIR4Rational $Model.prerequisite_anchor
  $base = Multiply-MIR4Rational $anchor $Model.base_multiplier
  $relativeLinear = Multiply-MIR4Rational `
    (Multiply-MIR4Rational $anchor $Model.linear_ratio) `
    (New-MIR4Rational $offset)
  $absoluteLinear = Multiply-MIR4Rational $Model.absolute_linear_increment (New-MIR4Rational $offset)
  $affine = Add-MIR4Rational (Add-MIR4Rational $base $relativeLinear) $absoluteLinear
  $grown = Multiply-MIR4Rational $affine (Get-MIR4RationalPower $Model.growth_factor $offset)
  return ConvertTo-MIR4RoundedInteger $grown
}

function Test-MIR4ResearchCostSelectorMatch {
  param([Parameter(Mandatory)]$Selector, [Parameter(Mandatory)]$Subject)

  $kind = [string]$Selector.kind
  $value = [string]$Selector.value
  switch ($kind) {
    'all' { return $true }
    'target' { return [string]$Subject.target -eq $value }
    'owner' { return [string]$Subject.owner -eq $value }
    'source-mod' { return [string]$Subject.source_mod -eq $value }
    'effect-channel' { return [string]$Subject.effect_channel -eq $value }
    'family' { return [string]$Subject.family -eq $value }
    'stream' { return [string]$Subject.stream -eq $value }
    'technology' { return [string]$Subject.technology -eq $value }
    default { throw "research_cost_v2_unknown_selector:$kind" }
  }
}

function Resolve-MIR4ResearchCostProfileV1 {
  param([Parameter(Mandatory)]$Subject, [Parameter(Mandatory)][object[]]$Layers)

  $layerRank = @{'safe-default'=10; target=20; ecosystem=30; modpack=40; user=50; explicit=60; 'hard-safety'=70}
  $specificity = @{all=0; target=10; owner=20; 'source-mod'=30; 'effect-channel'=40; family=50; stream=60; technology=70}
  $allowedFields = @('base_source','base_multiplier','linear_ratio','absolute_linear_increment','growth_factor','previous_series_id')
  $matched = @()
  foreach ($layer in $Layers) {
    $layerId = [string]$layer.id
    $layerKind = [string]$layer.kind
    if (-not $layerRank.ContainsKey($layerKind)) { throw "research_cost_v2_unknown_profile_layer:$layerKind" }
    foreach ($rule in @($layer.rules)) {
      $selectorKind = [string]$rule.selector.kind
      if (-not $specificity.ContainsKey($selectorKind)) { throw "research_cost_v2_unknown_selector:$selectorKind" }
      if (Test-MIR4ResearchCostSelectorMatch -Selector $rule.selector -Subject $Subject) {
        $matched += [pscustomobject]@{
          id = [string]$rule.id
          layer_id = $layerId
          layer_kind = $layerKind
          layer_rank = [int]$layerRank[$layerKind]
          specificity = [int]$specificity[$selectorKind]
          priority = if ($null -ne $rule.PSObject.Properties['priority']) { [int]$rule.priority } else { 0 }
          values = $rule.values
        }
      }
    }
  }
  $ordered = @($matched | Sort-Object layer_rank, specificity, priority, id)
  $effective = [ordered]@{}
  $fieldSources = [ordered]@{}
  foreach ($row in $ordered) {
    foreach ($property in @($row.values.PSObject.Properties | Sort-Object Name)) {
      if ($property.Name -notin $allowedFields) {
        throw "research_cost_v2_unknown_profile_field:$($property.Name)"
      }
      $effective[$property.Name] = $property.Value
      $fieldSources[$property.Name] = [pscustomobject][ordered]@{
        rule_id=$row.id; layer_id=$row.layer_id; layer_kind=$row.layer_kind
      }
    }
  }
  return [pscustomobject][ordered]@{
    schema = 1
    policy_id = 'mir-research-cost-profile-rules-v1-preview'
    maturity = 'experimental-package-excluded'
    effective = [pscustomobject]$effective
    field_sources = [pscustomobject]$fieldSources
    applied_rule_ids = @($ordered.id)
  }
}

function Convert-MIR4ResearchProgressV2 {
  param(
    [Parameter(Mandatory)]$Fraction,
    [Parameter(Mandatory)]$PreviousModel,
    [Parameter(Mandatory)]$CurrentModel,
    [Parameter(Mandatory)][ValidateRange(1, 1000000)][int]$Level
  )

  $fractionValue = ConvertTo-MIR4Rational -Value $Fraction -Field research_fraction
  if ((Compare-MIR4Rational $fractionValue (New-MIR4Rational 1)) -gt 0) {
    throw 'research_cost_v2_fraction_above_one'
  }
  $previousCost = Get-MIR4ResearchCostV2 -Model $PreviousModel -Level $Level
  $currentCost = Get-MIR4ResearchCostV2 -Model $CurrentModel -Level $Level
  $converted = Multiply-MIR4Rational $fractionValue (New-MIR4Rational $previousCost $currentCost)
  if ((Compare-MIR4Rational $converted (New-MIR4Rational 1)) -gt 0) {
    $converted = New-MIR4Rational 1
  }
  return [pscustomobject][ordered]@{
    schema = 1
    abi = 'mir-research-cost-v2-progress-transition-preview'
    level = $Level
    previous_cost = $previousCost
    current_cost = $currentCost
    converted_fraction = $converted
    application = 'analytical-once-only-factorio-runtime-not-admitted'
  }
}

function Get-MIR4ResearchCostV2TargetDispositions {
  return [ordered]@{
    f210 = 'preview-only-runtime-projection-not-admitted'
    f200 = 'preview-only-target-local-runtime-proof-required'
    f110 = 'schema-preserved-no-runtime-projection'
    f100 = 'schema-preserved-no-runtime-projection'
    f018_to_f013 = 'private-target-omitted'
  }
}
