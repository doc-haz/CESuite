"""Validate the evidence snapshot v1 draft schema against pure-model output."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from run_lua_tests import run


class EvidenceSnapshotSchemaTests(unittest.TestCase):
    def test_capture_and_diff_validate_against_draft_schema(self):
        schema = json.loads((ROOT / 'schemas/evidence-snapshot.schema.json').read_text(encoding='utf-8'))
        validator = Draft202012Validator(schema)
        library = 'C:/Program Files/Cheat Engine/lua53-64.dll'
        with tempfile.TemporaryDirectory(prefix='CESuite snapshot ') as directory:
            run(Path(library), str(ROOT / 'ce/tests/snapshot_spec.lua'), output_path=Path(directory))
            a = json.loads((Path(directory) / 'snapshot_a.json').read_text(encoding='utf-8'))
            b = json.loads((Path(directory) / 'snapshot_b.json').read_text(encoding='utf-8'))
            diff = json.loads((Path(directory) / 'diff.json').read_text(encoding='utf-8'))
            validator.validate(a)
            validator.validate(b)
            self.assertEqual(a['snapshot_version'], 1)
            self.assertEqual(a['source']['kind'], 'runtime_report')
            self.assertEqual(a['candidates'][0]['pattern'], '48895c24')
            self.assertEqual(b['candidates'][0]['pattern'], '48895c25')
            self.assertEqual(diff['comparability']['status'], 'comparable')
            self.assertEqual(diff['candidates']['changed'][0]['fields'][0]['field'], 'pattern')
            self.assertEqual(diff['coverage']['validation']['changed'], True)
            text = json.dumps(diff, ensure_ascii=False).lower()
            for word in ['fixed', 'broken', 'regressed', 'compatible', 'incompatible']:
                self.assertNotIn(word, text)


if __name__ == '__main__':
    unittest.main()
