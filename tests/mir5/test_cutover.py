"""Filesystem/exporter tests only. These do not execute Factorio or the MIR API."""
from pathlib import Path
import copy
import importlib.util
import json
import os
import subprocess
import tempfile
import unittest

PACK = Path(__file__).resolve().parents[2]
_spec = importlib.util.spec_from_file_location('mir_layout_export', PACK / 'tools/mir5/cutover.py')
c = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(c)

class CutoverTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.repo = self.base / 'repo'
        self.repo.mkdir()
        self.run_git('init', '-q')
        self.run_git('config', 'user.email', 'fixture@example.invalid')
        self.run_git('config', 'user.name', 'Layout fixture')
        self.run_git('config', 'core.autocrlf', 'false')
        self.write('spec/mir5/README.md', '# Contract\n\n[Guide](../../docs/mir5/README.md)\n')
        self.write('docs/mir5/README.md', '# Guide\n\n[Contract](../../spec/mir5/README.md#contract)\n')
        self.write('source/mir5/data.lua', 'return {name="unchanged-historical-id"}\n')
        self.write('source/old.lua', '-- former product\n')
        self.write('LICENSE', 'Preserved copyright\n')
        self.commit()

    def tearDown(self):
        self.temp.cleanup()

    def run_git(self, *args):
        p = subprocess.run(['git', '-C', str(self.repo), *args], capture_output=True, text=True)
        if p.returncode:
            raise AssertionError(p.stderr)
        return p.stdout.strip()

    def write(self, path, text):
        p = self.repo / path
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding='utf-8', newline='\n')

    def commit(self):
        self.run_git('add', '.')
        self.run_git('commit', '-qm', 'Fixture state')

    def approved(self):
        p = c.make_plan(self.repo)
        p['review'] = {'inventory_reviewed': True, 'root_replacements_reviewed': True,
                       'historical_custody_reference': 'synthetic-test-custody',
                       'preservation_review_reference': 'synthetic-layout-only-not-native'}
        for r in p['entries']:
            if r['action'] == 'review':
                r['action'] = 'keep' if r['source'] == 'LICENSE' else 'retire'
                r['destination'] = r['source'] if r['action'] == 'keep' else None
                r['reason'] = 'Explicit synthetic fixture disposition'
        return p

    def row(self, p, name):
        return next(r for r in p['entries'] if r['source'] == name)

    def test_plan_requires_review(self):
        with self.assertRaises(c.CutoverError): c.validate_plan(self.repo, c.make_plan(self.repo))

    def test_unknown_disposition_refused(self):
        p = self.approved(); self.row(p, 'LICENSE')['action'] = 'review'
        with self.assertRaises(c.CutoverError): c.validate_plan(self.repo, p)

    def test_missing_review_reference(self):
        p = self.approved(); p['review']['historical_custody_reference'] = ''
        with self.assertRaises(c.CutoverError): c.validate_plan(self.repo, p)

    def test_export_links_bytes_and_source_unchanged(self):
        p = self.approved(); before = c.tracked(self.repo)
        out = self.base / 'output'; report = c.export_tree(self.repo, p, out)
        self.assertEqual(c.tracked(self.repo), before)
        self.assertTrue((self.repo / 'source/old.lua').exists())
        self.assertFalse((out / 'source/old.lua').exists())
        self.assertEqual((out/'source/data.lua').read_bytes(), (self.repo/'source/mir5/data.lua').read_bytes())
        self.assertIn('../spec/README.md#contract', (out/'docs/README.md').read_text())
        self.assertEqual(len(report['local_link_edits']), 2)
        self.assertFalse((out/'.incomplete-layout-export').exists())

    def test_destination_collision(self):
        p=self.approved(); self.row(p,'docs/mir5/README.md')['destination']='spec/README.md'
        with self.assertRaises(c.CutoverError): c.validate_plan(self.repo,p)

    def test_casefold_collision(self):
        p=self.approved(); self.row(p,'docs/mir5/README.md')['destination']='SPEC/readme.MD'
        with self.assertRaises(c.CutoverError): c.validate_plan(self.repo,p)

    def test_file_directory_collision(self):
        p=self.approved(); self.row(p,'docs/mir5/README.md')['destination']='spec'
        with self.assertRaises(c.CutoverError): c.validate_plan(self.repo,p)

    def test_path_traversal(self):
        p=self.approved(); self.row(p,'source/mir5/data.lua')['destination']='../escape.lua'
        with self.assertRaises(c.CutoverError): c.validate_plan(self.repo,p)

    def test_absolute_and_windows_paths(self):
        for value in ('/tmp/escape','C:/escape','a\\b','.git/config','.Git/config','a/../b','CON.txt'):
            with self.subTest(value=value), self.assertRaises(c.CutoverError): c.path_name(value)

    def test_dirty_source_refused(self):
        p=self.approved(); self.write('LICENSE','Changed\n')
        with self.assertRaises(c.CutoverError): c.validate_plan(self.repo,p)

    def test_nonignored_untracked_refused(self):
        self.write('local-save.txt','Preserve me\n')
        with self.assertRaises(c.CutoverError): c.make_plan(self.repo)

    def test_ignored_file_not_deleted(self):
        self.write('.gitignore','local/\n'); self.commit()
        self.write('local/save.zip','Not a real save; retained\n')
        p=self.approved(); out=self.base/'out'
        c.export_tree(self.repo,p,out)
        self.assertTrue((self.repo/'local/save.zip').exists())
        self.assertFalse((out/'local/save.zip').exists())

    def test_stale_commit_refused(self):
        p=self.approved(); self.write('LICENSE','New committed state\n'); self.commit()
        with self.assertRaises(c.CutoverError): c.validate_plan(self.repo,p)

    def test_tampered_hash_refused(self):
        p=self.approved(); self.row(p,'LICENSE')['sha256']='0'*64
        with self.assertRaises(c.CutoverError): c.validate_plan(self.repo,p)

    def test_missing_row_refused(self):
        p=self.approved(); p['entries'].pop()
        with self.assertRaises(c.CutoverError): c.validate_plan(self.repo,p)

    def test_duplicate_source_refused(self):
        p=self.approved(); p['entries'].append(copy.deepcopy(p['entries'][0]))
        with self.assertRaises(c.CutoverError): c.validate_plan(self.repo,p)

    def test_versioned_directory_refused(self):
        p=self.approved(); self.row(p,'source/mir5/data.lua')['destination']='source/mir5/data.lua'
        with self.assertRaises(c.CutoverError): c.validate_plan(self.repo,p)

    def test_output_inside_repo_refused(self):
        with self.assertRaises(c.CutoverError): c.export_tree(self.repo,self.approved(),self.repo/'out')

    def test_existing_output_refused(self):
        out=self.base/'out'; out.mkdir(); (out/'keep').write_text('keep')
        with self.assertRaises(c.CutoverError): c.export_tree(self.repo,self.approved(),out)
        self.assertEqual((out/'keep').read_text(),'keep')

    def test_symbolic_source_refused(self):
        target=self.base/'foreign'; target.write_text('outside')
        try: (self.repo/'linked').symlink_to(target)
        except OSError: self.skipTest('Host disallows symlinks')
        self.commit()
        with self.assertRaises(c.CutoverError): c.make_plan(self.repo)

    def test_symbolic_output_parent_refused(self):
        target=self.base/'real'; target.mkdir(); link=self.base/'linked'
        try: link.symlink_to(target, target_is_directory=True)
        except OSError: self.skipTest('Host disallows symlinks')
        with self.assertRaises(c.CutoverError): c.export_tree(self.repo,self.approved(),link/'out')

    def test_retired_markdown_target_refused(self):
        p=self.approved(); r=self.row(p,'spec/mir5/README.md'); r['action']='retire';r['destination']=None
        with self.assertRaises(c.CutoverError): c.render(self.repo,c.validate_plan(self.repo,p)[1])

    def test_missing_link_target_refused(self):
        self.write('docs/mir5/README.md','# Guide\n\n[Missing](missing.md)\n');self.commit()
        with self.assertRaises(c.CutoverError): c.render(self.repo,c.validate_plan(self.repo,self.approved())[1])

    def test_fenced_code_links_unchanged(self):
        text='```lua\n-- [x](missing.md)\n```\n'
        self.assertEqual(c.markdown_links(text,lambda _: 'wrong'),text)

    def test_external_links_unchanged(self):
        self.assertIsNone(c.local_target('docs/a.md','https://example.invalid/mir4/item#old'))
        self.assertIsNone(c.local_target('docs/a.md','#anchor'))

    def test_unsupported_markdown_refused(self):
        with self.assertRaises(c.CutoverError): c.markdown_links('[x]: local.md\n',lambda x:x)

    def test_canonical_root_template(self):
        self.write('AGENTS.md','Historical root\n')
        self.write('tools/mir5/adoption/canonical/AGENTS.md','# Current\n\n[Contract](spec/README.md)\n')
        self.commit(); p=self.approved(); out=self.base/'out';c.export_tree(self.repo,p,out)
        self.assertEqual((out/'AGENTS.md').read_text(),'# Current\n\n[Contract](spec/README.md)\n')
        self.assertFalse((out/'tools/mir5').exists())

    def test_binary_and_executable_bytes(self):
        p=self.repo/'source/mir5/icon.png';p.write_bytes(bytes(range(256)))
        sh=self.repo/'tools/mir5/real_tool.py';sh.parent.mkdir(parents=True,exist_ok=True);sh.write_text('print("ok")\n');sh.chmod(0o755)
        self.commit();out=self.base/'out';c.export_tree(self.repo,self.approved(),out)
        self.assertEqual((out/'source/icon.png').read_bytes(),bytes(range(256)))
        if os.name!='nt': self.assertTrue((out/'tools/real_tool.py').stat().st_mode & 0o111)

    def test_duplicate_ids_in_plan_do_not_create_output(self):
        p=self.approved();p['entries'].append(copy.deepcopy(p['entries'][0]));out=self.base/'out'
        with self.assertRaises(c.CutoverError): c.export_tree(self.repo,p,out)
        self.assertFalse(out.exists())

    def test_reserved_marker_refused(self):
        p=self.approved(); self.row(p,'source/mir5/data.lua')['destination']='.incomplete-layout-export'
        with self.assertRaises(c.CutoverError): c.validate_plan(self.repo,p)

    def test_link_escaping_root_refused(self):
        with self.assertRaises(c.CutoverError): c.local_target('docs/a.md','../../escape.md')

    def test_crlf_markdown_retained_except_link(self):
        p=self.repo/'docs/mir5/README.md';p.write_bytes(b'# Guide\r\n\r\n[Contract](../../spec/mir5/README.md)\r\n');self.commit()
        out=self.base/'out';c.export_tree(self.repo,self.approved(),out)
        self.assertEqual((out/'docs/README.md').read_bytes(),b'# Guide\r\n\r\n[Contract](../spec/README.md)\r\n')

    def test_portable_path_forbidden_characters(self):
        for value in ('a/b?.lua','a/b*.lua','a/b|.lua','a/b<.lua','a/b>.lua','a/b".lua','a/b\t.lua','a/b\x1f.lua','a/b\x7f.lua'):
            with self.subTest(value=value), self.assertRaises(c.CutoverError): c.path_name(value)

    def test_duplicate_json_key_refused(self):
        p=self.base/'duplicate.json';p.write_text('{"format":1,"format":1}')
        with self.assertRaises(c.CutoverError): c.load_plan(p)

    def test_nonfinite_json_refused(self):
        p=self.base/'nonfinite.json';p.write_text('{"format":1,"number":NaN}')
        with self.assertRaises(c.CutoverError): c.load_plan(p)

    def test_review_wrong_type_refused(self):
        p=self.approved();p['review']=[]
        with self.assertRaises(c.CutoverError):c.validate_plan(self.repo,p)

    def test_api_major_directory_is_not_product_staging(self):
        self.assertEqual(c.final_path('source/api/v1/data.lua'),'source/api/v1/data.lua')

    def test_all_seven_staging_roots_are_flattened(self):
        for root in c.ROOTS:
            a,d,_,_=c.default_action(root+'/mir5/example.txt')
            self.assertEqual((a,d),('move',root+'/example.txt'))

    def test_transition_diagnostics_retire(self):
        a,d,_,_=c.default_action('tools/mir5/adoption/diagrams/13_cutover.svg')
        self.assertEqual((a,d),('retire',None))

    def test_wrong_plan_type_refused(self):
        with self.assertRaises(c.CutoverError):c.validate_plan(self.repo,[])

if __name__=='__main__': unittest.main()
