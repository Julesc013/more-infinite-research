Set-StrictMode -Version Latest

function Assert-MIRLoopbackRcon([bool]$Condition,[string]$Message) {
  if(-not$Condition){throw "[mir-loopback-rcon] $Message"}
}
function Get-MIRLoopbackRconSha256([byte[]]$Bytes) {
  $sha=[Security.Cryptography.SHA256]::Create()
  try{return -join($sha.ComputeHash($Bytes)|ForEach-Object {$_.ToString('X2')})}finally{$sha.Dispose()}
}
function Get-MIRLoopbackRconUtf8Bytes([string]$Value,[string]$Label,[int]$MaximumBytes,[switch]$OneLine) {
  Assert-MIRLoopbackRcon (-not[string]::IsNullOrEmpty($Value)) "$Label is empty"
  Assert-MIRLoopbackRcon ($Value.IndexOf([char]0)-lt0) "$Label contains NUL"
  if($OneLine){Assert-MIRLoopbackRcon ($Value.IndexOfAny([char[]]@("`r","`n"))-lt0) "$Label is not one line"}
  try{$bytes=[Text.UTF8Encoding]::new($false,$true).GetBytes($Value)}catch{throw "[mir-loopback-rcon] $Label is not strict UTF-8"}
  Assert-MIRLoopbackRcon ($bytes.Length-le$MaximumBytes) "$Label exceeds byte bound"
  return ,$bytes
}
function Write-MIRLoopbackRconInt32([IO.Stream]$Stream,[int]$Value) {
  $bytes=[BitConverter]::GetBytes($Value)
  if(-not[BitConverter]::IsLittleEndian){[Array]::Reverse($bytes)}
  $Stream.Write($bytes,0,$bytes.Length)
}
function Read-MIRLoopbackRconExact([IO.Stream]$Stream,[int]$Count) {
  Assert-MIRLoopbackRcon ($Count-ge0-and$Count-le65536) 'packet read length is invalid'
  $bytes=[byte[]]::new($Count);$offset=0
  while($offset-lt$Count){
    $read=$Stream.Read($bytes,$offset,$Count-$offset)
    Assert-MIRLoopbackRcon ($read-gt0) 'connection closed during packet read'
    $offset+=$read
  }
  return ,$bytes
}
function ConvertFrom-MIRLoopbackRconInt32([byte[]]$Bytes) {
  Assert-MIRLoopbackRcon ($Bytes.Length-eq4) 'integer encoding is invalid'
  if([BitConverter]::IsLittleEndian){return [BitConverter]::ToInt32($Bytes,0)}
  $copy=[byte[]]$Bytes.Clone();[Array]::Reverse($copy);return [BitConverter]::ToInt32($copy,0)
}
function Write-MIRLoopbackRconPacket([IO.Stream]$Stream,[int]$Id,[int]$Type,[string]$Payload,[string]$Label='payload',[switch]$OneLine) {
  [byte[]]$body=Get-MIRLoopbackRconUtf8Bytes -Value $Payload -Label $Label -MaximumBytes 65526 -OneLine:$OneLine
  Write-MIRLoopbackRconInt32 $Stream (10+$body.Length)
  Write-MIRLoopbackRconInt32 $Stream $Id
  Write-MIRLoopbackRconInt32 $Stream $Type
  $Stream.Write($body,0,$body.Length);$Stream.WriteByte(0);$Stream.WriteByte(0);$Stream.Flush()
}
function Read-MIRLoopbackRconPacket([IO.Stream]$Stream) {
  $length=ConvertFrom-MIRLoopbackRconInt32 (Read-MIRLoopbackRconExact $Stream 4)
  Assert-MIRLoopbackRcon ($length-ge10-and$length-le65536) 'packet length is invalid'
  [byte[]]$packet=Read-MIRLoopbackRconExact $Stream $length
  Assert-MIRLoopbackRcon ($packet[$length-2]-eq0-and$packet[$length-1]-eq0) 'packet terminators are invalid'
  if($length-eq10){$payload=[byte[]]::new(0)}else{$payload=[byte[]]$packet[8..($length-3)]}
  Assert-MIRLoopbackRcon (-not($payload-contains[byte]0)) 'response payload contains interior NUL'
  try{$text=[Text.UTF8Encoding]::new($false,$true).GetString($payload)}catch{throw '[mir-loopback-rcon] response payload is not strict UTF-8'}
  return [pscustomobject][ordered]@{id=(ConvertFrom-MIRLoopbackRconInt32 ([byte[]]$packet[0..3]));type=(ConvertFrom-MIRLoopbackRconInt32 ([byte[]]$packet[4..7]));payload_base64=[Convert]::ToBase64String($payload);payload_byte_length=$payload.Length;payload_text=$text;payload_sha256=(Get-MIRLoopbackRconSha256 $payload)}
}
function Get-MIRLoopbackRconElapsedMilliseconds([Diagnostics.Stopwatch]$Timer) {
  return [Math]::Round([double]$Timer.Elapsed.TotalMilliseconds,3)
}
function Open-MIRLoopbackRconSession {
  param(
    [ValidateRange(1,65535)][int]$Port,
    [Parameter(Mandatory)][string]$Password,
    [ValidateRange(1,30000)][int]$ConnectTimeoutMilliseconds=5000,
    [ValidateRange(1,30000)][int]$IoTimeoutMilliseconds=5000,
    [int]$AuthenticationRequestId=43101
  )
  Assert-MIRLoopbackRcon ($AuthenticationRequestId-ge1-and$AuthenticationRequestId-le2147483645) 'authentication request id is invalid'
  [byte[]]$null=Get-MIRLoopbackRconUtf8Bytes -Value $Password -Label 'password' -MaximumBytes 65526
  $tcp=[Net.Sockets.TcpClient]::new([Net.Sockets.AddressFamily]::InterNetwork);$stream=$null;$timer=[Diagnostics.Stopwatch]::StartNew()
  try {
    $tcp.SendTimeout=$IoTimeoutMilliseconds;$tcp.ReceiveTimeout=$IoTimeoutMilliseconds
    $connect=$tcp.ConnectAsync([Net.IPAddress]::Loopback,$Port)
    Assert-MIRLoopbackRcon ($connect.Wait($ConnectTimeoutMilliseconds)) 'loopback connection timed out'
    $null=$connect.GetAwaiter().GetResult();$stream=$tcp.GetStream();$stream.ReadTimeout=$IoTimeoutMilliseconds;$stream.WriteTimeout=$IoTimeoutMilliseconds
    Write-MIRLoopbackRconPacket -Stream $stream -Id $AuthenticationRequestId -Type 3 -Payload $Password -Label 'password'
    $authFrames=[Collections.Generic.List[object]]::new();$authenticated=$false
    foreach($order in 1..2){
      $packet=Read-MIRLoopbackRconPacket $stream
      [void]$authFrames.Add([pscustomobject][ordered]@{order=$order;id=$packet.id;type=$packet.type;received_monotonic_milliseconds=(Get-MIRLoopbackRconElapsedMilliseconds $timer)})
      if($packet.type-eq2-and$packet.id-eq$AuthenticationRequestId){$authenticated=$true;break}
      Assert-MIRLoopbackRcon ($order-eq1-and$packet.type-eq0-and$packet.id-eq$AuthenticationRequestId) 'authentication response differs'
    }
    Assert-MIRLoopbackRcon $authenticated 'authentication failed'
    return [pscustomobject]@{tcp=$tcp;stream=$stream;timer=$timer;authentication_request_id=$AuthenticationRequestId;auth_frames=@($authFrames.ToArray());commands=[Collections.Generic.List[object]]::new();closed=$false}
  } catch {
    $openFailure=$_.Exception
    $cleanupFacts=[Collections.Generic.List[object]]::new()
    foreach($row in @(
      [ordered]@{step='stream-dispose';value=$stream},
      [ordered]@{step='tcp-dispose';value=$tcp}
    )){
      $fact=[ordered]@{step=$row.step;attempted=($null-ne$row.value);succeeded=$true;error=$null}
      if($fact.attempted){try{$row.value.Dispose()}catch{$fact.succeeded=$false;$fact.error=$_.Exception.Message}}
      [void]$cleanupFacts.Add([pscustomobject]$fact)
    }
    $openFailure.Data['mir_loopback_rcon_cleanup_facts']=@($cleanupFacts.ToArray())
    throw $openFailure
  }
}
function Send-MIRLoopbackRconCommand {
  param([Parameter(Mandatory)]$Session,[Parameter(Mandatory)][string]$Command,[int]$RequestId)
  Assert-MIRLoopbackRcon (-not$Session.closed) 'session is closed'
  Assert-MIRLoopbackRcon ($Session.commands.Count-lt2) 'command bound exceeded'
  [byte[]]$commandBytes=Get-MIRLoopbackRconUtf8Bytes -Value $Command -Label 'command' -MaximumBytes 16384 -OneLine
  if(-not$PSBoundParameters.ContainsKey('RequestId')){$RequestId=$Session.authentication_request_id+$Session.commands.Count+1}
  Assert-MIRLoopbackRcon ($RequestId-ge1) 'command request id is invalid'
  $row=[pscustomobject][ordered]@{order=($Session.commands.Count+1);request_id=$RequestId;command_sha256=(Get-MIRLoopbackRconSha256 $commandBytes);command_bytes=$commandBytes.Length;write_monotonic_milliseconds=$null;response_monotonic_milliseconds=$null;complete=$false;response=$null}
  [void]$Session.commands.Add($row)
  Write-MIRLoopbackRconPacket -Stream $Session.stream -Id $RequestId -Type 2 -Payload $Command -Label 'command' -OneLine
  $row.write_monotonic_milliseconds=Get-MIRLoopbackRconElapsedMilliseconds $Session.timer
  $response=Read-MIRLoopbackRconPacket $Session.stream
  $row.response_monotonic_milliseconds=Get-MIRLoopbackRconElapsedMilliseconds $Session.timer
  $row.response=[ordered]@{id=$response.id;type=$response.type;payload_base64=$response.payload_base64;payload_byte_length=$response.payload_byte_length;payload_text=$response.payload_text;payload_sha256=$response.payload_sha256}
  Assert-MIRLoopbackRcon ($response.id-eq$RequestId-and$response.type-eq0) 'command response differs'
  $row.complete=$true
  return $row
}
function Close-MIRLoopbackRconSession {
  param([Parameter(Mandatory)]$Session)
  if($Session.closed){return @()}
  $facts=[Collections.Generic.List[object]]::new()
  foreach($row in @(
    [ordered]@{step='stream-dispose';value=$Session.stream},
    [ordered]@{step='tcp-dispose';value=$Session.tcp}
  )){
    $fact=[ordered]@{step=$row.step;attempted=($null-ne$row.value);succeeded=$true;error=$null}
    if($fact.attempted){try{$row.value.Dispose()}catch{$fact.succeeded=$false;$fact.error=$_.Exception.Message}}
    [void]$facts.Add([pscustomobject]$fact)
  }
  $Session.closed=$true
  return @($facts.ToArray())
}
function Get-MIRLoopbackRconReceipt($Session,[int]$Port,[int]$AuthenticationRequestId,[object[]]$CleanupFacts=@()) {
  return [pscustomobject][ordered]@{loopback_only=$true;port=$Port;authentication_request_id=$AuthenticationRequestId;auth_frames=@($Session.auth_frames);commands=@($Session.commands.ToArray());command_attempts=$Session.commands.Count;closed=[bool]$Session.closed;cleanup_facts=@($CleanupFacts)}
}
function Invoke-MIRLoopbackRconCommands {
  param(
    [ValidateRange(1,65535)][int]$Port,
    [Parameter(Mandatory)][string]$Password,
    [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Commands,
    [int]$AuthenticationRequestId=43101,
    [int]$FirstCommandRequestId=43102,
    [ValidateRange(1,30000)][int]$ConnectTimeoutMilliseconds=5000,
    [ValidateRange(1,30000)][int]$IoTimeoutMilliseconds=5000
  )
  Assert-MIRLoopbackRcon ($Commands.Count-ge1-and$Commands.Count-le2) 'command count is invalid'
  Assert-MIRLoopbackRcon ($FirstCommandRequestId-ge1-and([int64]$FirstCommandRequestId+$Commands.Count-1)-le[int]::MaxValue) 'command request id is invalid'
  foreach($command in $Commands){$null=Get-MIRLoopbackRconUtf8Bytes -Value $command -Label 'command' -MaximumBytes 16384 -OneLine}
  $session=$null;$primaryFailure=$null;$result=$null
  try {
    $opened=@(Open-MIRLoopbackRconSession -Port $Port -Password $Password -AuthenticationRequestId $AuthenticationRequestId -ConnectTimeoutMilliseconds $ConnectTimeoutMilliseconds -IoTimeoutMilliseconds $IoTimeoutMilliseconds)
    Assert-MIRLoopbackRcon ($opened.Count-eq1) 'open emitted an invalid session shape'
    $session=$opened[0]
    for($index=0;$index-lt$Commands.Count;$index++){$null=Send-MIRLoopbackRconCommand -Session $session -Command $Commands[$index] -RequestId ($FirstCommandRequestId+$index)}
    $result=Get-MIRLoopbackRconReceipt -Session $session -Port $Port -AuthenticationRequestId $AuthenticationRequestId
  } catch {$primaryFailure=$_}
  $inheritedCleanupFacts=@()
  if($null-ne$primaryFailure-and$primaryFailure.Exception.Data.Contains('mir_loopback_rcon_cleanup_facts')){
    $inheritedCleanupFacts=@($primaryFailure.Exception.Data['mir_loopback_rcon_cleanup_facts'])
  }
  $cleanupFacts=if($null-ne$session){@(Close-MIRLoopbackRconSession -Session $session)}else{$inheritedCleanupFacts}
  if($null-ne$session){$result=Get-MIRLoopbackRconReceipt -Session $session -Port $Port -AuthenticationRequestId $AuthenticationRequestId -CleanupFacts $cleanupFacts}
  $cleanupFailed=@($cleanupFacts|Where-Object {-not $_.succeeded})
  if($null-ne$primaryFailure){
    $primaryFailure.Exception.Data['mir_loopback_rcon_cleanup_facts']=$cleanupFacts
    if($null-ne$result){$primaryFailure.Exception.Data['mir_loopback_rcon_receipt']=$result}
    throw $primaryFailure
  }
  if($cleanupFailed.Count-gt0){
      $cleanupFailure=[InvalidOperationException]::new('[mir-loopback-rcon] cleanup failed')
      $cleanupFailure.Data['mir_loopback_rcon_cleanup_facts']=$cleanupFacts
      if($null-ne$result){$cleanupFailure.Data['mir_loopback_rcon_receipt']=$result}
      throw $cleanupFailure
  }
  return $result
}
