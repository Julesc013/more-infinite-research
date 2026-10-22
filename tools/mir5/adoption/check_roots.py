#!/usr/bin/env python3
"""Check root patch preimages without writing to the repository. Python 3.10+."""
from pathlib import Path
import argparse, json, subprocess, sys

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--repo', type=Path, required=True)
    args = p.parse_args()
    expected = json.loads(Path(__file__).with_name('expected-blobs.json').read_text(encoding='utf-8'))
    bad = False
    for name, wanted in expected['files'].items():
        path = args.repo / name
        if not path.is_file() or path.is_symlink():
            print(f'REFUSED: missing or symbolic {name}', file=sys.stderr); bad = True; continue
        result = subprocess.run(['git', '-C', str(args.repo), 'hash-object', '--', name], capture_output=True, text=True)
        actual = result.stdout.strip()
        if result.returncode or actual != wanted:
            print(f'REFUSED: {name} changed: expected {wanted}, observed {actual or "unavailable"}', file=sys.stderr)
            bad = True
    if bad:
        print('Reconcile a new patch; do not force the old routing edit.', file=sys.stderr)
        return 2
    print('Observed root preimages match. Review the patch and run git apply --check; no files changed.')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
