"""Read-only merge-review tests; no live repository access."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[2]
s=importlib.util.spec_from_file_location('merge_under_test',ROOT/'tools/mir5/adoption/check_merge.py')
m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
class AdoptionTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
        self.src=self.root/'incoming';self.target=self.root/'target';self.target.mkdir()
        self.name='docs/mir5/example.md';self.write(self.src,self.name,'new')
        meta=self.src/'tools/mir5/adoption';meta.mkdir(parents=True)
        (meta/'pack_members.json').write_text(json.dumps({'files':[self.name]}))
        (meta/'base_members.json').write_text(json.dumps({'files':{self.name:hashlib.sha256(b'old').hexdigest()}}))
    def tearDown(self):self.temp.cleanup()
    def write(self,root,path,text):
        f=root/path;f.parent.mkdir(parents=True,exist_ok=True);f.write_text(text)
    def status(self):return m.inspect(self.src,self.target)['files'][0]['status']
    def test_absent(self):self.assertEqual(self.status(),'absent')
    def test_identical(self):
        self.write(self.target,self.name,'new');self.assertEqual(self.status(),'identical')
    def test_predecessor_update(self):
        self.write(self.target,self.name,'old');self.assertEqual(self.status(),'predecessor_pack_update')
    def test_local_changes_conflict(self):
        self.write(self.target,self.name,'local work');self.assertEqual(self.status(),'conflict')
        self.assertEqual((self.target/self.name).read_text(),'local work')
    def test_parent_file_conflict(self):
        (self.target/'docs').write_text('keep me');self.assertEqual(self.status(),'conflict')
    def test_case_collision(self):
        (self.target/'DOCS').mkdir();self.assertEqual(self.status(),'conflict')
    def test_symlink_conflict(self):
        external=self.root/'external';external.mkdir()
        try:(self.target/'docs').symlink_to(external,target_is_directory=True)
        except OSError:self.skipTest('Host disallows symlinks')
        self.assertEqual(self.status(),'conflict');self.assertEqual(list(external.iterdir()),[])
    def test_no_target_writes(self):
        self.write(self.target,'unrelated.txt','preserve')
        before={p.relative_to(self.target):p.read_bytes() for p in self.target.rglob('*') if p.is_file()}
        result=m.inspect(self.src,self.target)
        after={p.relative_to(self.target):p.read_bytes() for p in self.target.rglob('*') if p.is_file()}
        self.assertEqual(before,after);self.assertFalse(result['writes_performed'])
if __name__=='__main__':unittest.main()
