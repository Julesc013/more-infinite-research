# Load only in the bounded Windows PowerShell actor owned by the direct-library
# responsive-menu runner.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-MIRMenuFileSha256 {
  param([Parameter(Mandatory)][string]$Path)
  # The Desktop helper inherits the Core host's module path. Use the .NET
  # primitive rather than depending on Get-FileHash module autoload there.
  $stream=[IO.File]::OpenRead([IO.Path]::GetFullPath($Path))
  $algorithm=[Security.Cryptography.SHA256]::Create()
  try{([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-','')}
  finally{$algorithm.Dispose();$stream.Dispose()}
}

function Initialize-MIRMenuOcr {
  Add-Type -AssemblyName System.Runtime.WindowsRuntime
  $null=[Windows.Globalization.Language,Windows.Foundation,ContentType=WindowsRuntime]
  $null=[Windows.Media.Ocr.OcrEngine,Windows.Foundation,ContentType=WindowsRuntime]
  $null=[Windows.Media.Ocr.OcrResult,Windows.Foundation,ContentType=WindowsRuntime]
  $null=[Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime]
  $null=[Windows.Storage.FileAccessMode,Windows.Storage,ContentType=WindowsRuntime]
  $null=[Windows.Storage.Streams.IRandomAccessStream,Windows.Storage.Streams,ContentType=WindowsRuntime]
  $null=[Windows.Graphics.Imaging.BitmapDecoder,Windows.Graphics.Imaging,ContentType=WindowsRuntime]
  $null=[Windows.Graphics.Imaging.SoftwareBitmap,Windows.Graphics.Imaging,ContentType=WindowsRuntime]
  $null=[Windows.Graphics.Imaging.BitmapPixelFormat,Windows.Graphics.Imaging,ContentType=WindowsRuntime]
  $null=[Windows.Graphics.Imaging.BitmapAlphaMode,Windows.Graphics.Imaging,ContentType=WindowsRuntime]
  $engine=[Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage((New-Object Windows.Globalization.Language('en-GB')))
  if($null-eq$engine){throw '[mir-menu-observer-english-ocr-unavailable]'}
  $methods=@([System.WindowsRuntimeSystemExtensions].GetMethods()|Where-Object {
    $_.Name-eq'AsTask'-and$_.IsGenericMethodDefinition-and$_.GetGenericArguments().Count-eq1-and$_.GetParameters().Count-eq1-and$_.GetParameters()[0].ParameterType.Name-eq'IAsyncOperation`1'
  })
  if($methods.Count-ne1){throw '[mir-menu-observer-async-adapter]'}
  [pscustomobject]@{engine=$engine;as_task=$methods[0];language=$engine.RecognizerLanguage.LanguageTag;maximum_dimension=[Windows.Media.Ocr.OcrEngine]::MaxImageDimension}
}

function Wait-MIRMenuOperation {
  param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Operation,[Parameter(Mandatory)][type]$ResultType,[ValidateRange(1,5000)][int]$TimeoutMilliseconds=2000)
  $task=$Context.as_task.MakeGenericMethod($ResultType).Invoke($null,@($Operation))
  if(-not$task.Wait($TimeoutMilliseconds)){throw '[mir-menu-observer-operation-timeout]'}
  $task.GetAwaiter().GetResult()
}

function ConvertTo-MIRMenuText {
  param([AllowEmptyString()][string]$Text)
  ([regex]::Replace($Text.ToLowerInvariant(),'[^\p{L}\p{N}]+',' ')).Trim()
}

function Read-MIRMenuImage {
  param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$ImagePath)
  $file=Wait-MIRMenuOperation $Context ([Windows.Storage.StorageFile]::GetFileFromPathAsync([IO.Path]::GetFullPath($ImagePath))) ([Windows.Storage.StorageFile])
  $stream=$null;$bitmap=$null
  try{
    $stream=Wait-MIRMenuOperation $Context ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
    $decoder=Wait-MIRMenuOperation $Context ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
    if($decoder.PixelWidth-gt4096-or$decoder.PixelHeight-gt4096-or$decoder.PixelWidth-lt1-or$decoder.PixelHeight-lt1){throw '[mir-menu-observer-image-bounds]'}
    $bitmap=Wait-MIRMenuOperation $Context ($decoder.GetSoftwareBitmapAsync([Windows.Graphics.Imaging.BitmapPixelFormat]::Bgra8,[Windows.Graphics.Imaging.BitmapAlphaMode]::Premultiplied)) ([Windows.Graphics.Imaging.SoftwareBitmap])
    $result=Wait-MIRMenuOperation $Context ($Context.engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
    $lines=@()
    foreach($line in $result.Lines){
      $words=@($line.Words)
      if($words.Count-eq0){continue}
      $left=($words|ForEach-Object {$_.BoundingRect.X}|Measure-Object -Minimum).Minimum
      $top=($words|ForEach-Object {$_.BoundingRect.Y}|Measure-Object -Minimum).Minimum
      $right=($words|ForEach-Object {$_.BoundingRect.X+$_.BoundingRect.Width}|Measure-Object -Maximum).Maximum
      $bottom=($words|ForEach-Object {$_.BoundingRect.Y+$_.BoundingRect.Height}|Measure-Object -Maximum).Maximum
      $lines+=,[pscustomobject]@{text=$line.Text;normalized=(ConvertTo-MIRMenuText $line.Text);left=[double]$left;top=[double]$top;width=[double]($right-$left);height=[double]($bottom-$top)}
    }
    [pscustomobject]@{text=$result.Text;lines=$lines;width=[int]$decoder.PixelWidth;height=[int]$decoder.PixelHeight;language=$Context.language}
  }finally{if($null-ne$bitmap){$bitmap.Dispose()};if($null-ne$stream){$stream.Dispose()}}
}

function Get-MIRMenuState {
  param([Parameter(Mandatory)]$Observation)
  $lines=@($Observation.lines|ForEach-Object {$_.normalized})
  $blocked=@($lines|Where-Object {$_-match '(^| )(error|notice|failed to load|loading mods|loading sprites)( |$)'})
  if($blocked.Count){return 'blocked-or-loading'}
  $main=@('single player','multiplayer','settings')
  $options=@('graphics','controls','interface')
  if(@($main|Where-Object {$_-notin$lines}).Count-eq0 -and ('main menu'-in$lines -or 'mods'-in$lines)){return 'main-menu'}
  if(@($options|Where-Object {$_-notin$lines}).Count-eq0 -and ('sounds'-in$lines -or 'mod settings'-in$lines) -and -not('single player'-in$lines)){return 'settings-menu'}
  return 'unrecognized'
}

function Get-MIRMenuSettingsTarget {
  param([Parameter(Mandatory)]$Observation)
  if((Get-MIRMenuState $Observation)-cne'main-menu'){throw '[mir-menu-observer-main-menu-required]'}
  $matches=@($Observation.lines|Where-Object normalized -CEQ 'settings')
  if($matches.Count-ne1){throw '[mir-menu-observer-ambiguous-settings-target]'}
  $line=$matches[0]
  $x=[int][Math]::Round($line.left+$line.width/2)
  $y=[int][Math]::Round($line.top+$line.height/2)
  if($x-lt0-or$y-lt0-or$x-ge$Observation.width-or$y-ge$Observation.height){throw '[mir-menu-observer-target-bounds]'}
  [pscustomobject]@{x=$x;y=$y}
}
