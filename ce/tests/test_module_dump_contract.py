"""Validate real serialized sidecars; CE memory and UI remain mocked."""
import copy
import ctypes.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from run_lua_tests import run
try:
    from jsonschema import Draft202012Validator
except ImportError:
    Draft202012Validator = None

class ModuleDumpContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix='CESuite dump contract ')
        cls.addClassCleanup(cls.directory.cleanup)
        library = os.environ.get('CESUITE_LUA_LIBRARY') or ctypes.util.find_library('lua5.3')
        run(Path(library or 'C:/Program Files/Cheat Engine/lua53-64.dll'),
            'ce/tests/module_dump_spec.lua', output_path=Path(cls.directory.name).as_posix())
        cls.reports = [json.loads(p.read_text()) for p in sorted(Path(cls.directory.name).glob('dump-*.json'))]
        cls.schema = json.loads((ROOT / 'schemas/module-dump.schema.json').read_text())

    def test_real_sidecar_values_and_previous_files(self):
        self.assertGreaterEqual(len(self.reports), 8)
        self.assertEqual({r['status'] for r in self.reports}, {'complete', 'partial'})
        self.assertTrue(any(r.get('cancelled') for r in self.reports))
        previous = [r for r in self.reports if r.get('previous_files')]
        self.assertEqual(len(previous), 2)
        self.assertTrue(any(b['backup'].endswith('.previous.1') for r in previous for b in r['previous_files']))
        for r in self.reports:
            self.assertLessEqual(r['bytes_written'], r['size'])
            self.assertEqual(r['atomic_snapshot'], False)
            if r['status'] == 'complete': self.assertEqual(r['bytes_written'], r['size'])
            for b in r.get('previous_files', []):
                self.assertTrue(b['backup'].startswith(b['original']+'.previous'))

    @unittest.skipIf(Draft202012Validator is None, 'jsonschema unavailable; no packages installed')
    def test_schema_accepts_real_sidecars_and_rejects_invalid_claims(self):
        Draft202012Validator.check_schema(self.schema)
        validator = Draft202012Validator(self.schema, format_checker=Draft202012Validator.FORMAT_CHECKER)
        for report in self.reports: validator.validate(report)
        complete = next(r for r in self.reports if r['status']=='complete')
        for field, value in [('status','cancelled'), ('pid',0), ('atomic_snapshot',True),
                             ('binary_fingerprint','invented'), ('cancelled',True),
                             ('previous_files',[{'original':'x','backup':'x'}])]:
            changed = copy.deepcopy(complete);changed[field]=value
            self.assertTrue(list(validator.iter_errors(changed)), field)
