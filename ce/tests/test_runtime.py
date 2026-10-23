import copy
import os
import sys
import ctypes.util
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
    @classmethod
    def setUpClass(cls):
        sys.path.insert(0, str(ROOT / 'tools'))
        from run_lua_tests import run
        library = os.environ.get('CESUITE_LUA_LIBRARY') or ctypes.util.find_library('lua5.3')
        library = library or 'C:/Program Files/Cheat Engine/lua53-64.dll'
        cls.generated_directory = tempfile.TemporaryDirectory(prefix='CESuite contract ')
        cls.addClassCleanup(cls.generated_directory.cleanup)
        cls.generated = Path(cls.generated_directory.name)
        run(Path(library), output_path=cls.generated.as_posix())

    def setUp(self):
        self.schema = json.loads((ROOT / 'schemas/runtime-report.schema.json').read_text(encoding='utf-8'))
        self.validator = Draft202012Validator(self.schema)

    def test_unknown_section_provenance_contract(self):
        report = self.profile_report()
        for key in ('resources', 'aobs', 'dependencies'):
            for row in report[key]: row['section'] = 'unknown'
        for group in report['dependency_summary']:
            group['sections'] = ['unknown']
            for location in group['locations']: location['section'] = 'unknown'
        self.validator.validate(report)
        report['resources'][0]['section'] = 'invented'
        with self.assertRaises(ValidationError): self.validator.validate(report)

    def test_legacy_014_report_needs_no_migration(self):
        report = json.loads((ROOT / 'fixtures/runtime-v0.1.4.json').read_text(encoding='utf-8'))
        self.assertEqual(report['core_version'], '0.1.4')
        self.assertNotIn('dependency_summary', report)
        self.validator.validate(report)
        del report['dependencies']
        with self.assertRaises(ValidationError):
            self.validator.validate(report)

    def profile_report(self):
        return json.loads((self.generated / 'generated-dependencies.json').read_text(encoding='utf-8'))

    def test_profile_optional_for_legacy_and_current_reports(self):
        report = self.profile_report()
        del report['semantics_profile']
        for version in ['0.1.0', '0.1.1', '0.1.2', '0.1.3', '0.1.4', '0.1.5', '0.1.6', '0.1.7', '0.1.8', '0.1.9']:
            report['core_version'] = version
            self.validator.validate(report)

    def test_generated_profile_evidence_contract(self):
        report = self.profile_report()
        self.validator.validate(report)
        profile = report['semantics_profile']
        self.assertEqual(profile['source_runtime_equivalence'], 'unverified')
        runtime = profile['runtime_profile']
        self.assertEqual(runtime['api_version'], report['ce_version'])
        self.assertEqual(runtime['declared_version_basis'], 'not_available')
        for key in ['declared_version', 'file_version', 'binary_sha256']:
            self.assertIsNone(runtime[key])
        notes = profile['known_post_source_changes']
        self.assertEqual(len(notes), 6)
        self.assertEqual(len({n['id'] for n in notes}), len(notes))
        for note in notes:
            self.assertEqual(note['evidence_kind'], 'release_note_evidence')
            self.assertEqual(note['runtime_validation'], 'not_performed')
            self.assertEqual(note['evidence_ref'], 'user-chronology/' + note['version'])

    def test_profile_rejects_unsupported_states_and_evidence(self):
        for path, value in [
            (['source_runtime_equivalence'], 'equivalent'),
            (['source_runtime_equivalence'], 'known_differences'),
            (['profile_version'], '2'),
            (['runtime_profile', 'declared_version'], '7.7.1'),
            (['runtime_profile', 'declared_version_basis'], 'runtime'),
            (['known_post_source_changes', 0, 'evidence_kind'], 'source_verified'),
            (['known_post_source_changes', 0, 'runtime_validation'], 'verified'),
            (['known_post_source_changes', 0, 'evidence_ref'], 'https://invented.invalid'),
        ]:
            with self.subTest(path=path):
                report = self.profile_report()
                target = report['semantics_profile']
                for key in path[:-1]:
                    target = target[key]
                target[path[-1]] = value
                with self.assertRaises(ValidationError):
                    self.validator.validate(report)

    def test_profile_requires_exact_source_commit(self):
        for value in [None, '', 'ec45d5f', 'g' * 40, '0' * 40]:
            report = self.profile_report()
            report['semantics_profile']['source_profile']['commit'] = value
            with self.assertRaises(ValidationError):
                self.validator.validate(report)
        report = self.profile_report()
        del report['semantics_profile']['source_profile']['commit']
        with self.assertRaises(ValidationError):
            self.validator.validate(report)

    def test_profile_cannot_upgrade_dependency_status(self):
        report = self.profile_report()
        self.assertTrue(report['dependencies'])
        self.assertTrue(all(d['status'] == 'unverified' for d in report['dependencies']))
        report['dependencies'][0]['status'] = 'source_verified'
        with self.assertRaises(ValidationError):
            self.validator.validate(report)

    def test_summary_indices_counts_and_identity_match_original_occurrences(self):
        for name in ['generated-report.json', 'generated-observed.json', 'generated-dependencies.json']:
            report = json.loads((self.generated / name).read_text(encoding='utf-8'))
            self.assertEqual(report['core_version'], '0.1.9')
            self.validator.validate(report)
            visited, identities = [], set()
            for group in report['dependency_summary']:
                fields = ('name', 'kind', 'source', 'relation')
                identity = tuple(group[f] for f in fields)
                self.assertNotIn(identity, identities)
                identities.add(identity)
                self.assertEqual(group['location_count'], len(group['locations']))
                self.assertEqual(group['occurrence_count'], sum(x['occurrence_count'] for x in group['locations']))
                self.assertEqual(group['script_ids'], list(dict.fromkeys(x['script_id'] for x in group['locations'])))
                self.assertEqual(group['sections'], list(dict.fromkeys(x['section'] for x in group['locations'])))
                for location in group['locations']:
                    self.assertEqual(location['occurrence_count'], len(location['occurrence_indices']))
                    for index in location['occurrence_indices']:
                        original = report['dependencies'][index - 1]
                        self.assertEqual(identity, tuple(original[f] for f in fields))
                        for field in ('script_id', 'section', 'line', 'command'):
                            self.assertEqual(location[field], original[field])
                        visited.append(index)
            self.assertEqual(sorted(visited), list(range(1, len(report['dependencies']) + 1)))

    def test_summary_contract_rejects_missing_invalid_and_verified_evidence(self):
        report = json.loads((self.generated / 'generated-dependencies.json').read_text(encoding='utf-8'))
        missing = copy.deepcopy(report)
        del missing['dependency_summary']
        with self.assertRaises(ValidationError):
            self.validator.validate(missing)
        missing['core_version'] = '0.1.4'
        self.validator.validate(missing)
        for field, value in [('status', 'verified'), ('occurrence_count', 0),
                             ('location_count', 0), ('locations', []), ('script_ids', []),
                             ('sections', ['enable', 'enable']), ('source', 'runtime')]:
            changed = copy.deepcopy(report)
            changed['dependency_summary'][0][field] = value
            with self.assertRaises(ValidationError):
                self.validator.validate(changed)
        for value in [[0], [1, 1], []]:
            changed = copy.deepcopy(report)
            changed['dependency_summary'][0]['locations'][0]['occurrence_indices'] = value
            with self.assertRaises(ValidationError):
                self.validator.validate(changed)

    def test_schema_and_real_lua_serialization(self):
        Draft202012Validator.check_schema(self.schema)
        for name in ['generated-report.json', 'generated-observed.json', 'generated-dependencies.json']:
            report = json.loads((self.generated / name).read_text(encoding='utf-8'))
            self.validator.validate(report)

    def test_reject_false_uniqueness_and_scope_changes(self):
        report = json.loads((self.generated / 'generated-observed.json').read_text(encoding='utf-8'))
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
        report = json.loads((self.generated / 'generated-dependencies.json').read_text(encoding='utf-8'))
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
        report = json.loads((self.generated / 'generated-dependencies.json').read_text(encoding='utf-8'))
        rows = [d for d in report['dependencies'] if d['source'] == 'lua_lexical']
        self.assertEqual([(d['name'], d['relation']) for d in rows],
                         [('MOD_PLAYER', 'requires'), ('MOD_GODMODE', 'provides')])
        for row in rows:
            self.assertEqual(row['status'], 'unverified')
            self.assertEqual(row['section'], 'enable')
            for field, value in [('status', 'verified'), ('source', 'lexical'),
                                 ('kind', 'symbol'), ('name', 'invalid-name'),
                                 ('command', 'alloc'), ('relation', 'resolved')]:
                changed = copy.deepcopy(report)
                index = report['dependencies'].index(row)
                changed['dependencies'][index][field] = value
                with self.assertRaises(ValidationError):
                    self.validator.validate(changed)

    def test_lua_schema_accepts_generic_names_in_occurrences_and_summary(self):
        report = json.loads((self.generated / 'generated-dependencies.json').read_text(encoding='utf-8'))
        for name in ['GAME_STATE', 'modPlayer', '_privateFlag', 'customHelper']:
            changed = copy.deepcopy(report)
            for row in changed['dependencies'] + changed['dependency_summary']:
                if row['source'] == 'lua_lexical':
                    row['name'] = name
            self.validator.validate(changed)
        for field in ['dependencies', 'dependency_summary']:
            for name in ['bad-name', '0bad', '', 'object.field']:
                changed = copy.deepcopy(report)
                next(row for row in changed[field] if row['source'] == 'lua_lexical')['name'] = name
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
