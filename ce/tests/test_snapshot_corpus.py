"""Snapshot corpus schema and FFRS reference checks (031B)."""
import json
from pathlib import Path
import unittest

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / 'ce/tests/fixtures/corpus/snapshots'
SCHEMA = json.loads((ROOT / 'schemas/evidence-snapshot.schema.json').read_text(encoding='utf-8'))


class SnapshotCorpusTests(unittest.TestCase):
    def test_all_valid_snapshots_match_schema(self):
        validator = Draft202012Validator(SCHEMA)
        files = sorted(p for p in CORPUS.glob('*.json'))
        self.assertEqual(len(files), 25)
        for path in files:
            with self.subTest(path=path.name):
                validator.validate(json.loads(path.read_text(encoding='utf-8')))

    def test_ffrs_reference_is_minimized_and_unresolved(self):
        snap = json.loads((CORPUS / 'ffrs-reference.json').read_text(encoding='utf-8'))
        self.assertEqual(len(snap['candidates']), 31)
        self.assertEqual(snap['coverage']['discovery']['entities_discovered'], 52)
        self.assertEqual(snap['coverage']['discovery']['candidates'], 31)
        self.assertEqual(snap['coverage']['validation']['validated'], 0)
        self.assertEqual(snap['coverage']['validation']['status'], 'unavailable')
        self.assertIn('LaunchUEInfoScanner', [u['name'] for u in snap['unresolved']])
        blob = json.dumps(snap).lower()
        for word in ['c:\\\\users', '/home/', 'temp\\\\']:
            self.assertNotIn(word, blob)

    def test_corruption_fixtures_are_present_and_invalid(self):
        corrupt = CORPUS / 'corrupt'
        names = {p.name for p in corrupt.glob('*.json')}
        self.assertEqual(names, {'invalid-json.json', 'truncated-json.json',
                                 'wrong-version.json', 'missing-field.json',
                                 'wrong-type.json', 'extra-property.json',
                                 'oversized.json'})
        self.assertGreater((corrupt / 'oversized.json').stat().st_size, 8 * 1024 * 1024)
        validator = Draft202012Validator(SCHEMA)
        for name in ['invalid-json.json', 'truncated-json.json', 'wrong-version.json',
                     'missing-field.json', 'wrong-type.json', 'extra-property.json']:
            with self.subTest(name=name):
                with self.assertRaises(Exception):
                    validator.validate(json.loads((corrupt / name).read_text(encoding='utf-8')))


if __name__ == '__main__':
    unittest.main()
