#!/usr/bin/env python3
"""Validate this documentation/diagram/tool pack, not MIR gameplay. Python 3.10+."""
from pathlib import Path
import importlib.util
import json
import re
import struct
import sys
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[2]
def module(name,path):
    s=importlib.util.spec_from_file_location(name,path)
    m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
c=module('mir_pack_layout',Path(__file__).with_name('cutover.py'))
r=module('mir_pack_diagrams',Path(__file__).with_name('render_diagrams.py'))

def main():
    errors=[];counts={'markdown':0,'json':0,'python':0,'links':0,'diagrams':0,'svg':0,'png':0};truths=set();requirements=set()
    selected=[ROOT/'MIR5-PACK.md']
    for directory in c.ROOTS:
        selected += [p for p in (ROOT/directory/'mir5').rglob('*') if p.is_file() and '__pycache__' not in p.parts]
    for p in selected:
        rel=p.relative_to(ROOT).as_posix()
        try:
            c.no_links(p)
            if p.suffix=='.json':
                json.loads(p.read_text(encoding='utf-8'),object_pairs_hook=c.strict_object,parse_constant=c.reject_constant);counts['json']+=1
            elif p.suffix=='.py':
                compile(p.read_bytes(),str(p),'exec');counts['python']+=1
            elif p.suffix=='.md':
                text=p.read_text(encoding='utf-8');counts['markdown']+=1
                if rel.startswith('spec/'):
                    for req in re.findall(r'^`([A-Z]+-[0-9]+)`\s*[—-]',text,re.M):
                        if req in requirements:raise ValueError('Duplicate requirement ID '+req)
                        requirements.add(req)
                if rel.startswith('docs/') or rel.startswith('spec/'):
                    if not text.startswith('---\n'):raise ValueError('Missing front matter')
                    front=text.split('---',2)[1]
                    for key in ('title:','status:','applies_to:','audience:','doc_type:','owner:','last_reviewed:','source_of_truth_for:'):
                        if key not in front:raise ValueError('Missing front matter '+key)
                    token=re.search(r'source_of_truth_for:\s*\n\s*-\s*(\S+)',front)
                    if not token or token.group(1) in truths:raise ValueError('Duplicate/missing source_of_truth_for')
                    truths.add(token.group(1))
                if '/adoption/canonical/' in rel:continue
                def verify(href):
                    found=c.local_target(rel,href)
                    if found:
                        target,_=found
                        if not (ROOT/target).is_file():raise ValueError('Missing local file link: '+target)
                        counts['links']+=1
                    return href
                c.markdown_links(text,verify)
            elif p.suffix=='.svg':
                text=p.read_text();ET.fromstring(text)
                if re.search(r'<script\b',text,re.I):raise ValueError('SVG script not permitted')
                counts['svg']+=1
            elif p.suffix=='.png':
                b=p.read_bytes()
                if b[:8]!=b'\x89PNG\r\n\x1a\n':raise ValueError('Invalid PNG signature')
                w,h=struct.unpack('>II',b[16:24])
                if not (100<w<16000 and 100<h<16000):raise ValueError('Implausible PNG dimensions')
                counts['png']+=1
            elif p.suffix=='.html':
                text=p.read_text()
                if re.search(r'<script\b|(?:src|href)=["\']https?://',text,re.I):raise ValueError('Atlas must be offline and script-free')
        except Exception as e:errors.append(f'{rel}: {e}')
    for base in ('docs/mir5/diagrams','tools/mir5/adoption/diagrams'):
        directory=ROOT/base
        try:
            ds=r.validate_catalog(json.loads((directory/'catalog.json').read_text()))
            for d in ds:
                if (directory/(d['id']+'.mmd')).read_text()!=r.mermaid_source(d):raise ValueError('Stale Mermaid '+d['id'])
                for suffix in ('.svg','.png'):
                    if not (directory/(d['id']+suffix)).is_file():raise ValueError('Missing render '+d['id']+suffix)
            if (directory/'index.html').read_text()!=r.atlas(ds,directory):raise ValueError('Stale atlas')
            counts['diagrams']+=len(ds)
        except Exception as e:errors.append(base+': '+str(e))
    cases=json.loads((ROOT/'tests/mir5/cases.json').read_text())['cases']
    ids=[x['id'] for x in cases]
    if len(set(ids))!=len(ids):errors.append('Duplicate acceptance case ID')
    for case in cases:
        if case['status']!='not_run' or case['implementation_command'] is not None:errors.append('Pack must not invent executed product acceptance: '+case['id'])
        if case['requirement'] not in requirements:errors.append('Unknown requirement '+case['requirement'])
    members=ROOT/'tools/mir5/adoption/pack_members.json'
    if members.exists():
        names=json.loads(members.read_text())['files']
        actual={p.relative_to(ROOT).as_posix() for p in selected}
        if set(names)!=actual or len(names)!=len(set(names)):errors.append('Pack membership differs from enumerated payload')
    if errors:
        print('\n'.join(errors),file=sys.stderr);return 1
    print(json.dumps({'status':'pass','scope':'document-diagram-tool-pack-not-native-product','checked':counts,
       'normative_requirement_ids':len(requirements),'product_acceptance_cases':len(cases),'native_tests_run':False,
       'mermaid_renderer_executed':False,'rendered_via':'Graphviz from the same graph records'},indent=2));return 0
if __name__=='__main__':raise SystemExit(main())
