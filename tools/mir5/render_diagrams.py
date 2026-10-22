#!/usr/bin/env python3
"""Render developer diagrams, never game data. Python 3.10+ and Graphviz dot.

One JSON graph catalogue produces editable Mermaid and equivalent SVG/PNG.
This does not execute a Mermaid renderer or claim native Factorio validation.
Only explicitly named generated outputs in --output are written; no deletion.
"""
from __future__ import annotations
import argparse
import html
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROLES = {
    'process': ('#FFFFFF','#52657D','#182B45'),
    'data': ('#EEF4FD','#5B7CA7','#17365A'),
    'engine': ('#EAF3FC','#3974A9','#163F64'),
    'generator': ('#E1F3EE','#16856F','#0C5649'),
    'optional': ('#FFF4DF','#B2822B','#73541B'),
    'api': ('#F0EAFB','#8063B0','#4E3977'),
    'error': ('#FCEEEF','#B95762','#7A2A37'),
    'success': ('#E5F3EA','#4E8A63','#2D563A'),
    'decision': ('#F5F1E8','#9F8965','#584A34'),
}
class DiagramError(ValueError):
    pass

def validate_catalog(value: object) -> list[dict]:
    if not isinstance(value,dict) or value.get('format') != 1:
        raise DiagramError('Expected diagram catalogue format 1')
    diagrams=value.get('diagrams')
    if not isinstance(diagrams,list) or not diagrams:
        raise DiagramError('A nonempty diagram array is required')
    seen=set()
    for d in diagrams:
        if not isinstance(d,dict): raise DiagramError('Diagram must be an object')
        did=d.get('id','')
        if not re.fullmatch(r'[0-9]{2}_[a-z0-9_]+',did) or did in seen:
            raise DiagramError('Unsafe or duplicate diagram ID')
        seen.add(did)
        if d.get('direction') not in ('TB','LR'): raise DiagramError('Unsupported direction')
        for key in ('title','question','summary','status'):
            if not isinstance(d.get(key),str) or not d[key].strip(): raise DiagramError('Missing '+key)
        groups=d.get('groups',[]);gids={g.get('id') for g in groups}
        if len(gids)!=len(groups): raise DiagramError('Duplicate group')
        nodes=d.get('nodes',[]);nids=set()
        for n in nodes:
            if not re.fullmatch('[A-Za-z][A-Za-z0-9_]*',n.get('id','')) or n['id'] in nids:
                raise DiagramError('Unsafe or duplicate node')
            nids.add(n['id'])
            if n.get('group') and n['group'] not in gids: raise DiagramError('Unknown group')
            if n.get('role') not in ROLES: raise DiagramError('Unknown node role')
            if n.get('shape','box') not in ('box','diamond'): raise DiagramError('Unknown node shape')
            if not isinstance(n.get('label'),str) or not n['label']: raise DiagramError('Missing label')
        if not nodes: raise DiagramError('No nodes')
        for e in d.get('edges',[]):
            if e.get('from') not in nids or e.get('to') not in nids: raise DiagramError('Unknown edge endpoint')
            if e.get('style') not in ('solid','dashed'): raise DiagramError('Unknown edge style')
            if not isinstance(e.get('label'),str): raise DiagramError('Edge label must be text')
    return diagrams

def quote(text: str) -> str:
    return json.dumps(text,ensure_ascii=False)

def dot_source(d: dict) -> str:
    lines=['digraph MIR {',
      f'graph [rankdir={d["direction"]}, bgcolor="white", pad="0.30", nodesep="0.32", ranksep="0.48", splines=polyline, fontname="DejaVu Sans", fontsize=20, fontcolor="#15324F", labelloc=t, label={quote(d["title"]+chr(10)+"PROPOSED DESIGN  /  NOT NATIVE-VERIFIED")}, compound=true];',
      'node [shape=box, style="rounded,filled", fontname="DejaVu Sans", fontsize=11, margin="0.16,0.12", penwidth=1.25];',
      'edge [fontname="DejaVu Sans", fontsize=9, color="#667B92", fontcolor="#44576E", arrowsize=0.72, penwidth=1.1];']
    def node(n):
        fill,stroke,text=ROLES[n['role']]
        return f'{n["id"]} [label={quote(n["label"])}, shape={n.get("shape","box")}, fillcolor="{fill}", color="{stroke}", fontcolor="{text}"];'
    for g in d['groups']:
        lines += [f'subgraph cluster_{g["id"]} {{',f'label={quote(g["label"])}; fontsize=12; fontcolor="#53687E"; style="rounded,filled"; color="#CCD7E2"; fillcolor="#F7F9FC"; margin=18;']
        lines += [node(n) for n in d['nodes'] if n.get('group')==g['id']]
        lines.append('}')
    lines += [node(n) for n in d['nodes'] if not n.get('group')]
    for e in d['edges']:
        lines.append(f'{e["from"]} -> {e["to"]} [label={quote(e["label"])}, style={e["style"]}];')
    return '\n'.join(lines+['}'])+'\n'

def mermaid_source(d: dict) -> str:
    def label(s):return html.escape(s,quote=True).replace('\n','<br/>')
    def node(n):
        a,b=('{','}') if n.get('shape')=='diamond' else ('[',']')
        return f'    {n["id"]}{a}"{label(n["label"])}"{b}:::{n["role"]}'
    lines=['%% Generated from the diagram catalogue; design, not an execution trace.',f'flowchart {d["direction"]}',f'  accTitle: {d["title"]}',f'  accDescr: {d["summary"]}']
    for g in d['groups']:
        lines.append(f'  subgraph group_{g["id"]}["{label(g["label"])}"]')
        lines += [node(n) for n in d['nodes'] if n.get('group')==g['id']]
        lines.append('  end')
    lines += [node(n) for n in d['nodes'] if not n.get('group')]
    for e in d['edges']:
        arrow='-.->' if e['style']=='dashed' else '-->'
        edge_label=f'|"{label(e["label"])}"|' if e['label'] else ''
        lines.append(f'  {e["from"]} {arrow}{edge_label} {e["to"]}')
    for name,(fill,stroke,text) in ROLES.items():
        lines.append(f'  classDef {name} fill:{fill},stroke:{stroke},color:{text},stroke-width:1.3px')
    return '\n'.join(lines)+'\n'

def inline_svg(svg: str, prefix: str) -> str:
    svg=svg[svg.index('<svg'):]
    svg=re.sub(r'id="([^"]+)"',lambda m:f'id="{prefix}_{m[1]}"',svg)
    svg=re.sub(r'(href|xlink:href)="#([^"]+)"',lambda m:f'{m[1]}="#{prefix}_{m[2]}"',svg)
    svg=re.sub(r'url\(#([^)]+)\)',lambda m:f'url(#{prefix}_{m[1]})',svg)
    return svg

def atlas(diagrams: list[dict], output: Path) -> str:
    nav=''.join(f'<a href="#{d["id"]}">{d["id"][:2]} · {html.escape(d["title"])}</a>' for d in diagrams)
    cards=[]
    for d in diagrams:
        svg=inline_svg((output/(d['id']+'.svg')).read_text(),d['id'])
        mmd=html.escape((output/(d['id']+'.mmd')).read_text())
        cards.append(f'''<section id="{d['id']}" class="card"><div class="eyebrow">{d['id'][:2]} / {html.escape(d['question'])}</div><h2>{html.escape(d['title'])}</h2><p>{html.escape(d['summary'])}</p><div class="figure">{svg}</div><div class="foot">Contracts: {html.escape(', '.join(d['contracts']))}. Proposed design; product acceptance remains unexecuted.</div><details><summary>Editable Mermaid source</summary><pre>{mmd}</pre></details></section>''')
    return '''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>MIR architecture atlas</title><style>
:root{--ink:#16324d;--muted:#52657a;--line:#dce4ec}*{box-sizing:border-box}body{margin:0;background:#edf2f7;color:var(--ink);font:16px/1.6 system-ui,-apple-system,Segoe UI,sans-serif}header{background:#102b46;color:#fff;padding:52px max(28px,calc((100vw - 1180px)/2)) 38px}header p{max-width:850px;color:#dce8f4}h1{font-size:38px;line-height:1.18;margin:8px 0 18px;letter-spacing:-.8px}.kicker{font-size:12px;letter-spacing:2px;font-weight:700;color:#acd9d1}.badge{display:inline-block;padding:5px 11px;border:1px solid #7790a6;border-radius:20px;font-size:12px}main{max-width:1240px;margin:30px auto;padding:0 24px}nav{display:grid;grid-template-columns:repeat(auto-fit,minmax(290px,1fr));gap:8px;margin:24px 0 32px}nav a{padding:10px 14px;background:white;border:1px solid var(--line);border-radius:8px;color:var(--ink);text-decoration:none;font-size:13px}nav a:hover{border-color:#16856f}.card{background:white;border:1px solid var(--line);border-radius:14px;padding:30px;margin:0 0 26px;box-shadow:0 5px 20px #16324d08;scroll-margin-top:16px}.eyebrow{font-size:12px;letter-spacing:.7px;text-transform:uppercase;color:#176d61;font-weight:750}h2{font-size:25px;line-height:1.3;margin:8px 0 12px}p{max-width:1000px}.figure{overflow:auto;margin:20px 0;padding:8px;border:1px solid #e6ecf2;border-radius:8px}.figure svg{display:block;margin:auto;max-width:100%;height:auto}.foot{font-size:12px;color:var(--muted);border-top:1px solid var(--line);padding-top:13px}details{margin-top:14px;color:var(--muted)}summary{cursor:pointer;font-size:13px}pre{overflow:auto;background:#f4f7fa;padding:20px;border-radius:7px;font:12px/1.5 ui-monospace,Consolas,monospace}.legend{display:flex;gap:10px;flex-wrap:wrap;font-size:12px}.legend span{border:1px solid var(--line);border-radius:5px;padding:4px 9px;background:white}.note{padding:16px 20px;border-left:4px solid #16856f;background:#e6f3ef;font-size:14px}footer{font-size:12px;color:var(--muted);padding:18px 0 40px}@media print{body{background:white}header{background:white;color:#16324d;padding:20px}header p{color:#52657a}nav,details{display:none}main{padding:0}.card{box-shadow:none;break-before:page;break-inside:avoid;border:0;padding:12px}.figure{overflow:visible;border:0}.figure svg{max-height:230mm}h1{font-size:28px}}@media(max-width:700px){header{padding:30px 20px}h1{font-size:29px}main{padding:0 12px}.card{padding:18px}.figure svg{min-width:650px}}
</style></head><body><header><div class="kicker">MORE INFINITE RESEARCH / ARCHITECTURE ATLAS</div><h1>Explicit research.<br>Deterministic construction.<br>Native execution.</h1><p>Start with the whole-mod view, then trace one boundary at a time. The Generator creates native research during prototype loading. It does not run during gameplay, infer arbitrary research or manage saved worlds.</p><span class="badge">DESIGN REVISION 2 · NOT AN IMPLEMENTED MOD</span></header><main><div class="note">These diagrams explain the proposed contracts. They do not prove Factorio behavior, save safety or a speedup. Every image and its editable Mermaid text comes from the same developer-only graph record. This page is self-contained and needs no network or JavaScript.</div><nav>'''+nav+'''</nav><div class="legend"><span>Blue: engine / native state</span><span>Green: Generator / accepted result</span><span>Amber: optional work</span><span>Purple: API / presentation</span><span>Red: rejection / forbidden boundary</span></div>'''+''.join(cards)+'''<footer>Normative authority remains the focused specification files. Timing is measured separately from semantic determinism. Graphviz renders the included SVG/PNG; Mermaid sources are generated for editing and supported by the documented flowchart subset, but a Mermaid renderer was not executed for this pack.</footer></main></body></html>'''

def render(catalog: Path, output: Path) -> int:
    diagrams=validate_catalog(json.loads(catalog.read_text(encoding='utf-8')))
    if not shutil.which('dot'): raise DiagramError('Graphviz dot is required for SVG/PNG; not a player dependency')
    output.mkdir(parents=True,exist_ok=True)
    for d in diagrams:
        text=dot_source(d)
        (output/(d['id']+'.mmd')).write_text(mermaid_source(d),encoding='utf-8',newline='\n')
        for ext in ('svg','png'):
            cmd=['dot','-T'+ext]
            if ext=='png':cmd+=['-Gdpi=155']
            cmd+=['-o',str(output/(d['id']+'.'+ext))]
            p=subprocess.run(cmd,input=text.encode(),capture_output=True,timeout=40)
            if p.returncode:raise DiagramError(p.stderr.decode('utf-8','replace'))
    (output/'index.html').write_text(atlas(diagrams,output),encoding='utf-8',newline='\n')
    return len(diagrams)

def main() -> int:
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--catalog',type=Path,required=True)
    ap.add_argument('--output',type=Path)
    ap.add_argument('--check',action='store_true')
    args=ap.parse_args()
    try:
        if args.check:
            ds=validate_catalog(json.loads(args.catalog.read_text(encoding='utf-8')))
            print(f'Graph record checks passed: {len(ds)} diagrams; not a Mermaid/native execution test')
        else:
            if args.output is None:ap.error('--output is required for rendering')
            print(f'Rendered {render(args.catalog,args.output)} diagrams and offline HTML atlas')
        return 0
    except (OSError,ValueError,subprocess.SubprocessError) as e:
        print(f'Diagram operation refused: {e}',file=sys.stderr);return 2
if __name__=='__main__':raise SystemExit(main())
