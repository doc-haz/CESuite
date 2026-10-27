"""Validate the 032A Advisor prototype output against the v1 schema."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

from jsonschema import Draft202012Validator, ValidationError

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from run_lua_tests import run  # noqa: E402

LIBRARY = Path('C:/Program Files/Cheat Engine/lua53-64.dll')
SCHEMA = json.loads((ROOT / 'schemas/evidence-advisor.schema.json').read_text(encoding='utf-8'))


class AdvisorSchemaTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='advisor schema ')
        self.out = Path(self.tmp.name)
        run(LIBRARY, 'ce/tests/advisor_spec.lua', output_path=self.out)
        self.report = json.loads((self.out / 'advisor-report.json').read_text(encoding='utf-8'))

    def tearDown(self):
        self.tmp.cleanup()

    def test_report_is_schema_valid(self):
        Draft202012Validator(SCHEMA).validate(self.report)

    def test_truncation_flags_and_bounds(self):
        self.assertIs(self.report['truncated'], False)
        self.assertEqual(set(self.report['truncation']), {'findings_capped', 'fields_capped', 'limitations_capped'})
        self.assertLessEqual(len(self.report['findings']), 64)
        for finding in self.report['findings']:
            for step in finding['suggested_next_steps']:
                self.assertEqual(step['action'], step['action'].upper())

    def test_findings_and_refs_are_bounded(self):
        self.assertLessEqual(len(self.report['findings']), 64)
        for finding in self.report['findings']:
            self.assertTrue(finding['evidence_refs'])
            self.assertTrue(finding['do_not_assume'])
            self.assertIn(finding['confidence'], {'exact', 'strong', 'weak', 'unknown'})

    def test_no_repair_actions_or_local_paths(self):
        text = json.dumps(self.report).lower()
        for term in ('replace_aob', 'patch_memory', 'rewrite_table', 'autoassemble',
                     'loadstring', 'c:\\users', 'appdata', 'doc_haz'):
            self.assertNotIn(term, text)
        for finding in self.report['findings']:
            for step in finding['suggested_next_steps']:
                self.assertNotIn(step['action'], {'replace_aob', 'patch_memory', 'rewrite_table'})

    def test_extra_property_is_rejected(self):
        for mutate in (
            lambda r: r.__setitem__('unexpected', True),
            lambda r: r['truncation'].__setitem__('extra', True),
            lambda r: r['input'].__setitem__('extra', True),
            lambda r: r['findings'][0]['evidence_refs'][0].__setitem__('id', 42),
        ):
            mutated = json.loads(json.dumps(self.report))
            mutate(mutated)
            with self.assertRaises(ValidationError):
                Draft202012Validator(SCHEMA).validate(mutated)

    def test_deterministic_identity(self):
        first = self.report['advisor_report_id']
        run(LIBRARY, 'ce/tests/advisor_spec.lua', output_path=self.out)
        second = json.loads((self.out / 'advisor-report.json').read_text(encoding='utf-8'))['advisor_report_id']
        self.assertEqual(first, second)


if __name__ == '__main__':
    unittest.main()
