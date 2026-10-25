"""Regression corpus manifest contract and file integrity (030D)."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / 'ce/tests/fixtures/corpus'
MANIFEST = CORPUS / 'manifest.json'

REQUIRED = ['id', 'title', 'category', 'source_kind', 'purpose', 'origin',
            'files', 'expected_behavior', 'invariants', 'runtime_required',
            'dependencies', 'known_unknowns']


class CorpusManifestTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = json.loads(MANIFEST.read_text(encoding='utf-8'))
        cls.spec = (ROOT / 'ce/tests/corpus_spec.lua').read_text(encoding='utf-8')

    def test_manifest_is_complete_and_unique(self):
        self.assertEqual(self.manifest['version'], '1.0')
        categories = set(self.manifest['categories'])
        self.assertIn('dynamic', categories)
        fixtures = self.manifest['fixtures']
        ids = [f['id'] for f in fixtures]
        self.assertEqual(len(ids), len(set(ids)))
        for fixture in fixtures:
            for field in REQUIRED:
                self.assertIn(field, fixture)
            self.assertIn(fixture['category'], categories)
            self.assertIn(fixture['runtime_required'], (True, False))
            self.assertIsInstance(fixture['files'], list)
            self.assertTrue(fixture['files'])
            self.assertIsInstance(fixture['invariants'], dict)
            self.assertNotIn('C:\\\\', json.dumps(fixture))
            for rel in fixture['files']:
                path = ROOT / rel
                self.assertTrue(path.is_file(), f'missing fixture file: {rel}')
                self.assertNotIn('..', Path(rel).parts)

    def test_every_fixture_has_a_corpus_test(self):
        for fixture in self.manifest['fixtures']:
            marker = "test('%s'" % fixture['id']
            self.assertIn(marker, self.spec, f'missing corpus test for {fixture["id"]}')

    def test_clean_room_and_runtime_declaration(self):
        for fixture in self.manifest['fixtures']:
            self.assertNotIn('Users', json.dumps(fixture))
            if fixture['runtime_required']:
                self.assertIn('runtime-replay', fixture['category'])
            else:
                self.assertNotEqual(fixture['category'], 'runtime-replay')


if __name__ == '__main__':
    unittest.main()
