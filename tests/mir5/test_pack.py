"""Graph/contract packaging tests. These do not test the MIR implementation."""
import copy
import importlib.util
import json
from pathlib import Path
import re
import unittest
ROOT=Path(__file__).resolve().parents[2]
s=importlib.util.spec_from_file_location('render_under_test',ROOT/'tools/mir5/render_diagrams.py')
r=importlib.util.module_from_spec(s);s.loader.exec_module(r)

class PackTests(unittest.TestCase):
    def setUp(self):
        self.data=json.loads((ROOT/'docs/mir5/diagrams/catalog.json').read_text())

    def test_permanent_graphs_have_unique_nodes_and_valid_edges(self):
        self.assertEqual(len(r.validate_catalog(self.data)),12)

    def test_duplicate_node_rejected(self):
        self.data['diagrams'][0]['nodes'].append(copy.deepcopy(self.data['diagrams'][0]['nodes'][0]))
        with self.assertRaises(r.DiagramError):r.validate_catalog(self.data)

    def test_unknown_endpoint_rejected(self):
        self.data['diagrams'][0]['edges'][0]['to']='not_defined'
        with self.assertRaises(r.DiagramError):r.validate_catalog(self.data)

    def test_unsafe_diagram_path_rejected(self):
        self.data['diagrams'][0]['id']='../escape'
        with self.assertRaises(r.DiagramError):r.validate_catalog(self.data)

    def test_mermaid_files_match_single_source(self):
        for d in self.data['diagrams']:
            self.assertEqual((ROOT/'docs/mir5/diagrams'/f'{d["id"]}.mmd').read_text(),r.mermaid_source(d))

    def test_dot_generation_is_deterministic(self):
        for d in self.data['diagrams']:self.assertEqual(r.dot_source(d),r.dot_source(copy.deepcopy(d)))

    def test_permanent_diagrams_have_no_staging_prefix(self):
        for d in self.data['diagrams']:
            self.assertNotRegex(json.dumps(d),r'(?:source|spec|docs|tools|sdk|tests|targets)/mir5/')
            self.assertFalse(d['transition_only'])

    def test_transition_diagram_is_separate(self):
        data=json.loads((ROOT/'tools/mir5/adoption/diagrams/catalog.json').read_text())
        self.assertEqual(len(data['diagrams']),1)
        self.assertTrue(data['diagrams'][0]['transition_only'])

    def test_product_cases_remain_unexecuted(self):
        for row in json.loads((ROOT/'tests/mir5/cases.json').read_text())['cases']:
            self.assertEqual(row['status'],'not_run');self.assertIsNone(row['implementation_command'])

    def test_api_examples_share_versioned_names(self):
        for p in (ROOT/'sdk/mir5/examples').rglob('*.lua'):
            text=p.read_text()
            self.assertNotIn('__more-infinite-research__/api/data',text)
            self.assertNotIn('remote.call("more-infinite-research",',text)
        text=(ROOT/'sdk/mir5/examples/required/data-final-fixes.lua').read_text()
        self.assertIn('__more-infinite-research__.api.v1.data',text)

    def test_atlas_has_no_network_dependency(self):
        text=(ROOT/'docs/mir5/diagrams/index.html').read_text()
        self.assertNotRegex(text,r'<script\b')
        self.assertNotRegex(text,r'(?:href|src)=["\']https?://')
        self.assertEqual(len(re.findall(r'<section id=',text)),12)

    def test_private_slice_does_not_claim_release_qualification(self):
        info=json.loads((ROOT/'source/mir5/info.json').read_text())
        self.assertEqual(info['name'],'more-infinite-research')
        self.assertIn('Incomplete',info['description'])
        self.assertIn('disposable test worlds',(ROOT/'source/mir5/README.md').read_text())

if __name__=='__main__':unittest.main()
