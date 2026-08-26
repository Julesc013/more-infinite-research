if (-not (Get-Command New-MIR4InspectionBundleV1 -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'CompatibilityIndex.ps1')
}

function Get-MIR4InspectorV1Html {
  return @'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; connect-src 'none'; font-src 'none'; object-src 'none'; frame-src 'none'; form-action 'none'; base-uri 'none'">
  <title>MIR 4 Inspector V1 Preview</title>
  <style>
    :root{color-scheme:light dark;font:16px/1.5 system-ui,sans-serif}body{max-width:1200px;margin:auto;padding:1rem}a.skip{position:absolute;left:-9999px}a.skip:focus{left:1rem;top:1rem;background:Canvas;padding:.5rem;z-index:2}.toolbar{display:flex;flex-wrap:wrap;gap:.75rem;align-items:end}.badge{border:1px solid currentColor;border-radius:1rem;padding:.15rem .55rem}.panel{border:1px solid color-mix(in srgb,CanvasText 25%,transparent);border-radius:.5rem;padding:1rem;margin:1rem 0;overflow:auto}label{display:block;font-weight:650}input,button{font:inherit;padding:.45rem}.pager{display:flex;gap:.5rem;align-items:center;margin:.5rem 0}button:focus-visible,input:focus-visible,a:focus-visible{outline:3px solid #2f80ed;outline-offset:2px}table{width:100%;border-collapse:collapse}caption{text-align:left;font-weight:700;margin:.5rem 0}th,td{text-align:left;vertical-align:top;border-bottom:1px solid color-mix(in srgb,CanvasText 20%,transparent);padding:.45rem;overflow-wrap:anywhere}.error{color:#b42318;font-weight:650}[hidden]{display:none!important}
  </style>
</head>
<body>
  <a class="skip" href="#workbench" data-i18n="skip">Skip to workbench</a>
  <header><h1 data-i18n="title">MIR 4 Inspector</h1><span class="badge" data-i18n="badge">V1 preview · local · read only</span></header>
  <p data-i18n="intro">Open a bounded MIR4InspectionBundleV1 from a local file. The workbench has no network or upload path and never mutates Factorio data.</p>
  <div class="toolbar" aria-label="Inspector controls">
    <div><label for="bundle" data-i18n="open">Inspection bundle</label><input id="bundle" type="file" accept="application/json,.json"></div>
    <div><label for="filter" data-i18n="filter">Filter current section</label><input id="filter" type="search" disabled autocomplete="off"></div>
    <button id="export" type="button" disabled data-i18n="export">Export bounded snapshot</button>
  </div>
  <p id="status" role="status" aria-live="polite">No inspection bundle loaded.</p>
  <p id="error" class="error" role="alert" aria-live="assertive" hidden></p>
  <main id="workbench" tabindex="-1"></main>
  <script>
  'use strict';
  const LIMITS=Object.freeze({sections:11,items:100,page:25,depth:8,string:4096});
  const FORBIDDEN=new Set(['callback','callbacks','compiler_context','CompilerContext','data_raw','executor','executors','function','functions','operation','operations','prototype','prototypes','prototype_write','safety_kernel','secret','secrets','modpack_supported']);
  const MESSAGES=Object.freeze({en:{skip:'Skip to workbench',title:'MIR 4 Inspector',badge:'V1 preview · local · read only',intro:'Open a bounded MIR4InspectionBundleV1 from a local file. The workbench has no network or upload path and never mutates Factorio data.',open:'Inspection bundle',filter:'Filter current section',export:'Export bounded snapshot',previous:'Previous page',next:'Next page',empty:'No bounded rows.',loaded:'Inspection bundle loaded.',invalid:'The file is not a valid bounded MIR4InspectionBundleV1.'}});
  const t=k=>(MESSAGES[document.documentElement.lang]||MESSAGES.en)[k]||k;
  document.querySelectorAll('[data-i18n]').forEach(node=>{node.textContent=t(node.dataset.i18n)});
  let bundle=null;
  const state=new Map();
  const status=document.getElementById('status'),error=document.getElementById('error'),workbench=document.getElementById('workbench'),filter=document.getElementById('filter'),exportButton=document.getElementById('export');
  function reject(value,depth=0){if(depth>LIMITS.depth)throw new Error('depth');if(value===null||typeof value!=='object')return;if(Array.isArray(value)){if(value.length>LIMITS.items)throw new Error('items');value.forEach(item=>reject(item,depth+1));return}for(const [key,item] of Object.entries(value)){if(FORBIDDEN.has(key))throw new Error('forbidden:'+key);if(typeof item==='string'&&item.length>LIMITS.string)throw new Error('string');reject(item,depth+1)}}
  function validate(value){reject(value);if(!value||value.kind!=='MIR4InspectionBundleV1'||value.schema!==1||!Array.isArray(value.sections)||value.sections.length!==LIMITS.sections)throw new Error('kind');for(const section of value.sections){if(!section||typeof section.id!=='string'||typeof section.label!=='string'||!Array.isArray(section.items)||section.items.length>LIMITS.items)throw new Error('section')}return value}
  function text(value){if(value===null||value===undefined)return '';if(typeof value==='string')return value.slice(0,LIMITS.string);if(typeof value==='number'||typeof value==='boolean')return String(value);return JSON.stringify(value,null,2).slice(0,LIMITS.string)}
  function render(){workbench.replaceChildren();if(!bundle)return;const needle=filter.value.trim().toLocaleLowerCase();for(const section of bundle.sections){const all=section.items.filter(item=>text(item).toLocaleLowerCase().includes(needle));const current=Math.min(state.get(section.id)||0,Math.max(0,Math.ceil(all.length/LIMITS.page)-1));state.set(section.id,current);const start=current*LIMITS.page,rows=all.slice(start,start+LIMITS.page);const region=document.createElement('section');region.className='panel';region.setAttribute('aria-labelledby','heading-'+section.id);const heading=document.createElement('h2');heading.id='heading-'+section.id;heading.textContent=section.label;region.append(heading);const table=document.createElement('table'),caption=document.createElement('caption');caption.textContent=section.label+' — '+all.length+' bounded row(s)';table.append(caption);const head=document.createElement('thead'),headRow=document.createElement('tr'),numberHead=document.createElement('th'),valueHead=document.createElement('th');numberHead.scope='col';numberHead.textContent='#';valueHead.scope='col';valueHead.textContent='Summary';headRow.append(numberHead,valueHead);head.append(headRow);table.append(head);const body=document.createElement('tbody');if(rows.length===0){const row=document.createElement('tr'),cell=document.createElement('td');cell.colSpan=2;cell.textContent=t('empty');row.append(cell);body.append(row)}else{rows.forEach((item,index)=>{const row=document.createElement('tr'),number=document.createElement('th'),value=document.createElement('td');number.scope='row';number.textContent=String(start+index+1);value.textContent=text(item);row.append(number,value);body.append(row)})}table.append(body);region.append(table);const pager=document.createElement('div');pager.className='pager';pager.setAttribute('aria-label',section.label+' pagination');const previous=document.createElement('button'),position=document.createElement('span'),next=document.createElement('button');previous.type='button';previous.textContent=t('previous');previous.disabled=current===0;previous.onclick=()=>{state.set(section.id,current-1);render()};next.type='button';next.textContent=t('next');next.disabled=start+rows.length>=all.length;next.onclick=()=>{state.set(section.id,current+1);render()};position.textContent='Page '+(current+1)+' of '+Math.max(1,Math.ceil(all.length/LIMITS.page));position.setAttribute('aria-live','polite');pager.append(previous,position,next);region.append(pager);workbench.append(region)}}
  function fail(message){bundle=null;state.clear();workbench.replaceChildren();filter.disabled=true;exportButton.disabled=true;error.hidden=false;error.textContent=t('invalid')+' '+String(message).slice(0,256);status.textContent='No inspection bundle loaded.'}
  document.getElementById('bundle').addEventListener('change',async event=>{try{const file=event.target.files&&event.target.files[0];if(!file)throw new Error('missing file');bundle=validate(JSON.parse(await file.text()));state.clear();error.hidden=true;error.textContent='';filter.disabled=false;exportButton.disabled=false;status.textContent=t('loaded');render();workbench.focus()}catch(problem){fail(problem)}});
  filter.addEventListener('input',()=>{state.clear();render()});
  exportButton.addEventListener('click',()=>{if(!bundle)return;const bounded=validate(bundle),blob=new Blob([JSON.stringify(bounded,null,2)+'\n'],{type:'application/json'}),link=document.createElement('a');link.href=URL.createObjectURL(blob);link.download='mir4-inspection-bundle-v1.json';link.click();URL.revokeObjectURL(link.href)});
  </script>
</body>
</html>
'@
}

function Get-MIR4InspectorV1ExporterPowerShell {
  return @'
param([Parameter(Mandatory)][string]$InputPath,[Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference='Stop'
$record=Get-Content -Raw -LiteralPath $InputPath|ConvertFrom-Json -Depth 100
if([int]$record.schema-ne 1-or[string]$record.kind-cne'MIR4InspectionBundleV1'-or@($record.sections).Count-ne 11){throw '[mir4-inspector-v1-bundle]'}
if(@($record.sections|Where-Object{@($_.items).Count-gt 100}).Count){throw '[mir4-inspector-v1-bound]'}
$json=$record|ConvertTo-Json -Depth 100
[IO.File]::WriteAllText($OutputPath,$json+"`n",[Text.UTF8Encoding]::new($false))
[pscustomobject]@{status='exported-bounded-read-only';path=$OutputPath;upload=$false;mutation=$false}|ConvertTo-Json
'@
}

function Get-MIR4InspectorV1Readme {
  return @'
# MIR 4 Inspector V1

Open `index.html` locally and select a generated `MIR4InspectionBundleV1` JSON file. The workbench uses the local File API only, renders eleven bounded sections, supports keyboard paging/filtering and screen-reader labels, and never uploads or mutates data.

This is a package-excluded developer preview. It is not a public compatibility claim or release proof.
'@
}

function Test-MIR4InspectorHtmlV1 {
  param([Parameter(Mandatory)][string]$Html)
  foreach ($required in @(
    'MIR 4 Inspector V1 Preview','MIR4InspectionBundleV1','Content-Security-Policy','connect-src ''none''',
    'role="status"','role="alert"','aria-live="polite"','aria-live="assertive"','focus-visible','createElement(''caption'')',
    'scope=''col''','scope=''row''','data-i18n','MESSAGES','LIMITS','local file','textContent','replaceChildren',
    'Previous page','Next page','Export bounded snapshot'
  )) { if (-not $Html.Contains($required)) { throw "[mir4-w07-inspector-required] $required" } }
  foreach ($forbidden in @('innerHTML','fetch(','XMLHttpRequest','WebSocket','sendBeacon','setInterval','setTimeout','requestAnimationFrame','<form','http://','https://')) {
    if ($Html.Contains($forbidden)) { throw "[mir4-w07-inspector-local-only] $forbidden" }
  }
  return $true
}

function New-MIR4InspectorWorkbenchResultV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Ledger,[Parameter(Mandatory)]$FactoryPlan,
    [Parameter(Mandatory)]$FactoryPackage,[AllowNull()]$SourceIdentity=$null,[AllowNull()]$ProcessIRComparison=$null
  )
  $repo = Get-MIR4W07RepoRoot $RepoRoot
  Import-MIR4W07CanonicalSupport -RepoRoot $repo
  $authority = Get-MIR4InspectorCompatibilityAuthority -RepoRoot $repo
  $exactComparison=Resolve-MIR4W07ProcessIRComparison -RepoRoot $repo -Comparison $ProcessIRComparison
  $bundle = New-MIR4InspectionBundleV1 -RepoRoot $repo -Ledger $Ledger -SourceIdentity $SourceIdentity -ProcessIRComparison $(if($null-ne$exactComparison){$exactComparison.value}else{$null})
  Test-MIR4InspectionBundleV1 -Bundle $bundle -RepoRoot $repo | Out-Null
  $html = Get-MIR4InspectorV1Html
  Test-MIR4InspectorHtmlV1 -Html $html | Out-Null
  $htmlBytes = [Text.UTF8Encoding]::new($false).GetBytes($html.Replace("`r`n","`n"))
  $sha = [Security.Cryptography.SHA256]::Create(); try { $htmlSha = ([BitConverter]::ToString($sha.ComputeHash($htmlBytes)).Replace('-','').ToLowerInvariant()) } finally { $sha.Dispose() }
  $blocked = @($Ledger.subjects | Where-Object { [string]$_.proof.state -eq 'review-required/no-governed-exact-archive-closure' } | ForEach-Object { [string]$_.subject_id } | Sort-Object)
  $record = [pscustomobject][ordered]@{
    schema=1;kind='MIR4InspectorWorkbenchResultV1';programme_id=[string]$authority.programme_id;source_identity=$SourceIdentity;maturity='developer-preview'
    authority='W07-read-only-inspector-and-data-bundle-factory';input_digests=[ordered]@{inspection_bundle=[string]$bundle.digest;subject_ledger=[string]$Ledger.digest;factory_plan=[string]$FactoryPlan.digest}
    workbench=[ordered]@{root='sdk/preview/mir4/inspector-v1';html_sha256=$htmlSha;section_count=11;sections=@($authority.inspector_sections);bounded_lists=$true;page_limit=25;raw_mutable_compiler_objects=$false}
    offline=[ordered]@{local_file_api_only=$true;network_calls=0;upload_paths=0;external_assets=0;idle_runtime_work=$false}
    accessibility=[ordered]@{keyboard_paging=$true;keyboard_filter=$true;focus_visible=$true;screen_reader_labels=$true;table_captions_and_headers=$true;live_status_and_error_regions=$true}
    localization=[ordered]@{catalogue='inline-local-preview-catalogue';ui_text_separated_from_render_logic=$true;default_locale='en'}
    compatibility_factory=[ordered]@{pipeline=@($authority.factory_pipeline);subject_count=[int]$FactoryPlan.subject_inventory_count;plan_digest=[string]$FactoryPlan.digest;package=$FactoryPackage;arbitrary_code=$false;executable_content=$false;validation='passed'}
    blockers=[ordered]@{subjects=$blocked;ir4='BLOCKED-INDEPENDENT-PRODUCTION-CONSUMER';process_ir=$(if($null-ne$exactComparison){'CAPTURED-EXACT-TARGET-PROCESSIR-PREVIEW'}else{'BLOCKED-EXACT-TARGET-PROCESSIR-SNAPSHOT'})}
    passed=$true;package_visible=$false;public_release_proof=$false;player_mutation_authorized=$false;public_support_authorized=$false;publication_authorized=$false;digest=''
  }
  Add-MIR4ModuleDigest $record | Out-Null
  return [ordered]@{result=$record;inspection_bundle=$bundle;html=$html;exporter=(Get-MIR4InspectorV1ExporterPowerShell);readme=(Get-MIR4InspectorV1Readme)}
}
