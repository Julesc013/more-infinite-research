#!/usr/bin/env python3
"""Read-only incoming-pack conflict classifier. Does not copy or overwrite files."""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import unicodedata

HERE=Path(__file__).resolve().parent
module_spec=importlib.util.spec_from_file_location('mir_cutover_merge',HERE.parent/'cutover.py')
c=importlib.util.module_from_spec(module_spec);module_spec.loader.exec_module(c)

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def portable_target(root: Path, relative: str) -> Path:
    current=root
    for part in Path(relative).parts:
        if current.exists():
            if not current.is_dir(): raise c.CutoverError('Parent is not a directory')
            key=unicodedata.normalize('NFC',part).casefold()
            for entry in current.iterdir():
                if unicodedata.normalize('NFC',entry.name).casefold()==key and entry.name!=part:
                    raise c.CutoverError('Case/Unicode-equivalent target already exists: '+entry.name)
        current=current/part
        c.no_links(current)
    return current

def inspect(incoming: Path, target: Path) -> dict:
    c.no_links(incoming.absolute());c.no_links(target.absolute())
    incoming=incoming.resolve(strict=True);target=target.resolve(strict=True)
    if not target.is_dir():raise c.CutoverError('Target must be an existing directory')
    members=json.loads((incoming/'tools/mir5/adoption/pack_members.json').read_text())['files']
    baseline=json.loads((incoming/'tools/mir5/adoption/base_members.json').read_text())['files']
    if not isinstance(members,list) or len(set(members))!=len(members):raise c.CutoverError('Invalid member list')
    rows=[]
    for name in members:
        c.path_name(name)
        if name!='MIR5-PACK.md' and not any(name.startswith(r+'/mir5/') for r in c.ROOTS):
            raise c.CutoverError('Unexpected incoming root: '+name)
        src=incoming/name;c.no_links(src)
        if not src.is_file():raise c.CutoverError('Missing incoming file: '+name)
        new=sha(src)
        try:
            dst=portable_target(target,name)
            if not dst.exists():status='absent';old=None
            elif not dst.is_file():status='conflict';old=None
            else:
                old=sha(dst)
                status='identical' if old==new else ('predecessor_pack_update' if baseline.get(name)==old else 'conflict')
            row={'path':name,'status':status,'incoming_sha256':new,'target_sha256':old}
        except (OSError,c.CutoverError) as e:
            row={'path':name,'status':'conflict','reason':str(e),'incoming_sha256':new}
        rows.append(row)
    counts={k:sum(r['status']==k for r in rows) for k in ('absent','identical','predecessor_pack_update','conflict')}
    return {'kind':'read-only-merge-review-not-apply-authorization','counts':counts,'files':rows,'writes_performed':False}

def main()->int:
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--repo',type=Path,required=True)
    ap.add_argument('--incoming',type=Path,default=HERE.parents[2])
    ap.add_argument('--full',action='store_true')
    ns=ap.parse_args()
    try:
        result=inspect(ns.incoming,ns.repo)
        if not ns.full:result={**result,'files':[r for r in result['files'] if r['status']=='conflict']}
        print(json.dumps(result,indent=2))
        return 2 if result['counts']['conflict'] else 0
    except (OSError,ValueError,KeyError,TypeError,c.CutoverError) as e:
        print('Merge check refused: '+str(e),file=sys.stderr);return 2
if __name__=='__main__':raise SystemExit(main())
