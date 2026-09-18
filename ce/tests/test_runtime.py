import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

from jsonschema import Draft202012Validator, ValidationError

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('build_ce', ROOT / 'tools/build_ce.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class RuntimeContractTests(unittest.TestCase):
    def setUp(self):
        self.schema = json.loads((ROOT / 'schemas/runtime-report.schema.json').read_text())
        self.validator = Draft202012Validator(self.schema)

    def test_schema_and_real_lua_serialization(self):
        Draft202012Validator.check_schema(self.schema)
        for name in ['generated-report.json', 'generated-observed.json']:
            report = json.loads((ROOT / 'ce/tests' / name).read_text(encoding='utf-8'))
            self.validator.validate(report)

    def test_reject_false_uniqueness_and_scope_changes(self):
        report = json.loads((ROOT / 'ce/tests/generated-observed.json').read_text())
        self.validator.validate(report)
        for field, value in [('match_count', 2), ('status', 'error'), ('scope', 'process'),
                             ('cross_build_robustness', 'verified')]:
            changed = copy.deepcopy(report)
            changed['aobs'][0][field] = value
            with self.assertRaises(ValidationError):
                self.validator.validate(changed)

    def test_package_is_deterministic_and_self_contained(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            builder.build(output)
            for name in ['CESuite_Core.CT', 'CESuite_Core.lua']:
                self.assertEqual((output / name).read_bytes(), (ROOT / 'releases' / name).read_bytes())
            root = ET.parse(output / 'CESuite_Core.CT').getroot()
            self.assertEqual(len(root.find('CheatEntries')), 0)
            self.assertEqual(root.findtext('LuaScript'), builder.bundle())

    def test_runtime_has_no_target_write_or_network_calls(self):
        # Defense-in-depth allowlist regression, not a formal security proof.
        import re
        source = builder.bundle()
        for forbidden in ['autoAssemble', 'autoAssembleCheck', 'writeBytes', 'writeInteger',
                          'allocateMemory', 'deAlloc', 'openProcess', 'getInternet',
                          'getAddress', 'getAddressSafe', 'loadstring', 'shellExecute']:
            self.assertIsNone(re.search(r'\b' + forbidden + r'\s*\(', source), forbidden)


if __name__ == '__main__':
    unittest.main()
