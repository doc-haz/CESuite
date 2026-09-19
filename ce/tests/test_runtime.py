import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile
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
        for name in ['generated-report.json', 'generated-observed.json', 'generated-dependencies.json']:
            report = json.loads((ROOT / 'ce/tests' / name).read_text(encoding='utf-8'))
            self.validator.validate(report)

    def test_reject_false_uniqueness_and_scope_changes(self):
        report = json.loads((ROOT / 'ce/tests/generated-observed.json').read_text())
        self.validator.validate(report)
        legacy = copy.deepcopy(report)
        legacy['core_version'] = '0.1.0'
        self.validator.validate(legacy)
        for field, value in [('match_count', 2), ('status', 'error'), ('scope', 'process'),
                             ('cross_build_robustness', 'verified')]:
            changed = copy.deepcopy(report)
            changed['aobs'][0][field] = value
            with self.assertRaises(ValidationError):
                self.validator.validate(changed)

    def test_dependencies_are_required_only_for_new_core_and_remain_unverified(self):
        report = json.loads((ROOT / 'ce/tests/generated-dependencies.json').read_text())
        self.validator.validate(report)
        self.assertGreater(len(report['dependencies']), 0)
        missing = copy.deepcopy(report)
        del missing['dependencies']
        with self.assertRaises(ValidationError):
            self.validator.validate(missing)
        for version in ['0.1.0', '0.1.1', '0.1.2', '0.1.3']:
            missing['core_version'] = version
            self.validator.validate(missing)
        for field, value in [('status', 'verified'), ('source', 'runtime'),
                             ('relation', 'resolved'), ('line', 0), ('extra', True)]:
            changed = copy.deepcopy(report)
            changed['dependencies'][0][field] = value
            with self.assertRaises(ValidationError):
                self.validator.validate(changed)

    def test_lua_dependency_provenance_contract(self):
        report = json.loads((ROOT / 'ce/tests/generated-dependencies.json').read_text())
        rows = [d for d in report['dependencies'] if d['source'] == 'lua_lexical']
        self.assertEqual([(d['name'], d['relation']) for d in rows],
                         [('DWG_HC_PLAYER', 'requires'), ('DWG_HC_GODMODE', 'provides')])
        for row in rows:
            self.assertEqual(row['status'], 'unverified')
            self.assertEqual(row['section'], 'enable')
            for field, value in [('status', 'verified'), ('source', 'lexical'),
                                 ('kind', 'symbol'), ('name', 'OTHER_GLOBAL'),
                                 ('command', 'alloc'), ('relation', 'resolved')]:
                changed = copy.deepcopy(report)
                index = report['dependencies'].index(row)
                changed['dependencies'][index][field] = value
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
        source = builder.bundle() + '\n'.join(builder.autorun_files().values())
        for forbidden in ['autoAssemble', 'autoAssembleCheck', 'writeBytes', 'writeInteger',
                          'allocateMemory', 'deAlloc', 'openProcess', 'getInternet',
                          'getAddress', 'getAddressSafe', 'loadstring', 'shellExecute']:
            self.assertIsNone(re.search(r'\b' + forbidden + r'\s*\(', source), forbidden)

    def test_autorun_structure_content_and_reproducibility(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            builder.build(output)
            name = f'CESuite_Autorun_v{builder.version()}.zip'
            original = (output / name).read_bytes()
            builder.build(output)
            self.assertEqual(original, (output / name).read_bytes())
            expected = {'CESuite_Autorun.lua', 'cesuite/core.lua', 'cesuite/bootstrap.lua'}
            expected.update('cesuite/' + p.name for p in (ROOT / 'ce/modules').glob('*.lua'))
            with zipfile.ZipFile(output / name) as archive:
                self.assertEqual(set(archive.namelist()), expected)
                self.assertEqual(len(archive.namelist()), len(expected))
                for path, source in builder.autorun_files().items():
                    self.assertEqual(archive.read(path).decode('utf-8'), source)
                    self.assertNotIn('@VERSION@', source)
            self.assertEqual((output / 'CESuite_Core.CT').read_bytes(),
                             (output / f'CESuite_Core_v{builder.version()}.CT').read_bytes())


if __name__ == '__main__':
    unittest.main()
